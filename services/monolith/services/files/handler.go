// Package files handles player aid uploads/deletes and rules URL management.
package files

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/LuisMedinaG/mbgc/services/monolith/internal/model"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"
)

const maxPlayerAidUploadBytes = 10 << 20 // 10 MB

// GameStore is the subset of the game store the files handler needs.
type GameStore interface {
	GetGame(id, userID int64) (model.Game, error)
	UpdateGameRulesURL(id int64, rulesURL string, userID int64) error
	GetPlayerAids(gameID int64) ([]model.PlayerAid, error)
	GetPlayerAid(id int64) (model.PlayerAid, error)
	CreatePlayerAid(gameID int64, filename, label string) (int64, error)
	DeletePlayerAid(id int64) error
}

// Handler serves player aid and rules URL API routes.
type Handler struct {
	store   GameStore
	dataDir string
}

// NewHandler creates a new files handler.
func NewHandler(store GameStore, dataDir string) *Handler {
	return &Handler{store: store, dataDir: dataDir}
}

// UpdateRulesURL sets the rules URL for a game.
//
// PUT /api/v1/games/{id}/rules-url
func (h *Handler) UpdateRulesURL(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	id, ok := requireID(w, r)
	if !ok {
		return
	}

	var body struct {
		RulesURL string `json:"rules_url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := validateRulesURL(body.RulesURL); err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}

	if _, err := h.store.GetGame(id, userID); err != nil {
		writeError(w, http.StatusNotFound, "game not found")
		return
	}

	if err := h.store.UpdateGameRulesURL(id, body.RulesURL, userID); err != nil {
		slog.Error("files.UpdateRulesURL", "gameID", id, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusOK, map[string]any{
		"game_id":   id,
		"rules_url": body.RulesURL,
	})
}

// UploadPlayerAid uploads a player aid image for a game.
//
// POST /api/v1/games/{id}/player-aids
func (h *Handler) UploadPlayerAid(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	id, ok := requireID(w, r)
	if !ok {
		return
	}

	if _, err := h.store.GetGame(id, userID); err != nil {
		writeError(w, http.StatusNotFound, "game not found")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxPlayerAidUploadBytes)
	if err := r.ParseMultipartForm(maxPlayerAidUploadBytes); err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			writeError(w, http.StatusRequestEntityTooLarge, "file too large")
			return
		}
		writeError(w, http.StatusBadRequest, "invalid multipart form")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "missing file")
		return
	}
	defer file.Close()

	contentType := header.Header.Get("Content-Type")
	ext, ok := allowedImageExt(contentType)
	if !ok {
		writeError(w, http.StatusBadRequest, "unsupported file type (png, jpg, gif, webp only)")
		return
	}

	filename, err := randomFilename(ext)
	if err != nil {
		slog.Error("files.UploadPlayerAid: randomFilename", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	dest := filepath.Join(h.dataDir, "uploads", filename)
	f, err := os.Create(dest)
	if err != nil {
		slog.Error("files.UploadPlayerAid: create file", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if _, err := io.Copy(f, file); err != nil {
		f.Close()
		_ = os.Remove(dest)
		slog.Error("files.UploadPlayerAid: copy file", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	f.Close()

	label := sanitizeLabel(r.FormValue("label"), header.Filename)

	aidID, err := h.store.CreatePlayerAid(id, filename, label)
	if err != nil {
		_ = os.Remove(dest)
		slog.Error("files.UploadPlayerAid: CreatePlayerAid", "gameID", id, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeData(w, http.StatusCreated, map[string]any{
		"id": aidID, "game_id": id, "filename": filename, "label": label,
	})
}

// DeletePlayerAid removes a player aid.
//
// DELETE /api/v1/games/{id}/player-aids/{aid_id}
func (h *Handler) DeletePlayerAid(w http.ResponseWriter, r *http.Request) {
	userID, ok := requireUserID(w, r)
	if !ok {
		return
	}
	id, ok := requireID(w, r)
	if !ok {
		return
	}

	aidID, err := strconv.ParseInt(r.PathValue("aid_id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid aid_id")
		return
	}

	if _, err := h.store.GetGame(id, userID); err != nil {
		writeError(w, http.StatusNotFound, "game not found")
		return
	}

	aid, err := h.store.GetPlayerAid(aidID)
	if err != nil || aid.GameID != id {
		writeError(w, http.StatusNotFound, "player aid not found")
		return
	}

	_ = os.Remove(filepath.Join(h.dataDir, "uploads", aid.Filename))

	if err := h.store.DeletePlayerAid(aidID); err != nil {
		slog.Error("files.DeletePlayerAid", "aidID", aidID, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func validateRulesURL(raw string) error {
	if raw == "" {
		return nil
	}
	u, err := url.Parse(raw)
	if err != nil {
		return errors.New("invalid rules URL")
	}
	if !strings.EqualFold(u.Scheme, "https") {
		return errors.New("rules URL must use https")
	}
	host := strings.ToLower(u.Host)
	if host != "drive.google.com" && host != "docs.google.com" {
		return errors.New("rules URL must point to Google Drive")
	}
	return nil
}

func allowedImageExt(contentType string) (string, bool) {
	switch contentType {
	case "image/png":
		return ".png", true
	case "image/jpeg":
		return ".jpg", true
	case "image/gif":
		return ".gif", true
	case "image/webp":
		return ".webp", true
	default:
		return "", false
	}
}

func randomFilename(ext string) (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b) + ext, nil
}

func sanitizeLabel(label, fallback string) string {
	label = strings.TrimSpace(label)
	if label == "" {
		label = strings.TrimSpace(fallback)
	}
	// Strip file extension from fallback name.
	if ext := filepath.Ext(label); ext != "" {
		label = label[:len(label)-len(ext)]
	}
	if len(label) > 100 {
		label = label[:100]
	}
	return label
}

// ── Request / response helpers ────────────────────────────────────────────────

func requireID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

func requireUserID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, ok := httpx.UserIDFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return 0, false
	}
	return id, true
}

func writeData(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]any{"data": v})
}

func writeError(w http.ResponseWriter, status int, msg string) {
	httpx.WriteJSONError(w, status, msg)
}

