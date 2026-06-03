// Package seed handles first-run provisioning (admin user).
// Safe to call on every boot — it is fully idempotent.
package seed

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/LuisMedinaG/mbgc/services/api/internal/config"
)

// AdminUser creates a Supabase Auth user + admin profile row if neither exists.
// Requires SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD, and SUPABASE_SERVICE_ROLE_KEY.
func AdminUser(ctx context.Context, cfg config.Config, db *pgxpool.Pool) error {
	if cfg.ServiceRoleKey == "" {
		return fmt.Errorf("SUPABASE_SERVICE_ROLE_KEY not set — skipping seed")
	}

	userID, err := ensureAuthUser(ctx, cfg)
	if err != nil {
		return fmt.Errorf("auth user: %w", err)
	}

	// ref: profile.ADMIN.2 — is_admin must be in app_metadata for JWT inclusion
	if err := ensureAdminAppMetadata(ctx, cfg, userID); err != nil {
		return fmt.Errorf("app_metadata: %w", err)
	}

	if err := ensureAdminProfile(ctx, db, userID); err != nil {
		return fmt.Errorf("admin profile: %w", err)
	}

	slog.Info("admin user ready", "email", cfg.SeedAdminEmail)
	return nil
}

// ensureAuthUser creates the Supabase Auth user via the Admin API.
// Returns the existing user's ID if the email is already registered.
func ensureAuthUser(ctx context.Context, cfg config.Config) (string, error) {
	baseURL := strings.TrimSuffix(cfg.SupabaseURL, "/")

	payload := map[string]interface{}{
		"email":         cfg.SeedAdminEmail,
		"password":      cfg.SeedAdminPassword,
		"email_confirm": true,
	}
	if cfg.SeedAdminUsername != "" {
		payload["user_metadata"] = map[string]string{"username": cfg.SeedAdminUsername}
	}

	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx,
		http.MethodPost,
		baseURL+"/auth/v1/admin/users",
		bytes.NewReader(body),
	)
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apikey", cfg.ServiceRoleKey)
	req.Header.Set("Authorization", "Bearer "+cfg.ServiceRoleKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		ID  string `json:"id"`
		Msg string `json:"msg"` // present on conflict
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", fmt.Errorf("decode response (status %d): %w", resp.StatusCode, err)
	}

	if resp.StatusCode == http.StatusUnprocessableEntity && strings.Contains(result.Msg, "already") {
		id, err := lookupAuthUserByEmail(ctx, cfg)
		if err != nil {
			return "", fmt.Errorf("user exists but lookup failed: %w", err)
		}
		return id, nil
	}

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated {
		return "", fmt.Errorf("admin API returned %d: %s", resp.StatusCode, result.Msg)
	}

	return result.ID, nil
}

// ensureAdminAppMetadata sets app_metadata.is_admin = true (and optionally
// user_metadata.username) so the flag is present in every JWT the user receives.
func ensureAdminAppMetadata(ctx context.Context, cfg config.Config, userID string) error {
	baseURL := strings.TrimSuffix(cfg.SupabaseURL, "/")

	update := map[string]interface{}{
		"app_metadata": map[string]bool{"is_admin": true},
	}
	if cfg.SeedAdminUsername != "" {
		update["user_metadata"] = map[string]string{"username": cfg.SeedAdminUsername}
	}

	body, _ := json.Marshal(update)
	req, err := http.NewRequestWithContext(ctx,
		http.MethodPut,
		baseURL+"/auth/v1/admin/users/"+userID,
		bytes.NewReader(body),
	)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("apikey", cfg.ServiceRoleKey)
	req.Header.Set("Authorization", "Bearer "+cfg.ServiceRoleKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		var result struct{ Msg string `json:"msg"` }
		json.NewDecoder(resp.Body).Decode(&result)
		return fmt.Errorf("admin API returned %d: %s", resp.StatusCode, result.Msg)
	}
	return nil
}

func lookupAuthUserByEmail(ctx context.Context, cfg config.Config) (string, error) {
	baseURL := strings.TrimSuffix(cfg.SupabaseURL, "/")
	req, err := http.NewRequestWithContext(ctx,
		http.MethodGet,
		baseURL+"/auth/v1/admin/users?per_page=1000",
		nil,
	)
	if err != nil {
		return "", err
	}
	req.Header.Set("apikey", cfg.ServiceRoleKey)
	req.Header.Set("Authorization", "Bearer "+cfg.ServiceRoleKey)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var result struct {
		Users []struct {
			ID    string `json:"id"`
			Email string `json:"email"`
		} `json:"users"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return "", err
	}
	for _, u := range result.Users {
		if strings.EqualFold(u.Email, cfg.SeedAdminEmail) {
			return u.ID, nil
		}
	}
	return "", fmt.Errorf("user %q not found", cfg.SeedAdminEmail)
}

func ensureAdminProfile(ctx context.Context, db *pgxpool.Pool, userID string) error {
	_, err := db.Exec(ctx, `
		INSERT INTO profile.users (id, is_admin)
		VALUES ($1, true)
		ON CONFLICT (id) DO UPDATE SET is_admin = true
	`, userID)
	return err
}
