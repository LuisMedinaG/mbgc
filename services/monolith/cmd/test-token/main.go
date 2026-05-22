// Command test-token generates a JWT token for a test user.
//
// Usage:
//
//	go run ./cmd/test-token
//
// Environment variables:
//
//	TEST_USER — username of test user (default: "testuser")
//	TEST_PASSWORD — password of test user (default: "testpass123")
//	SESSION_SECRET — JWT secret (same as main app)
//
// If TEST_USER is set, the command will authenticate as that user.
// Otherwise, it creates a token for user ID 1 (assuming a test user exists).
package main

import (
	"fmt"
	"log"
	"os"

	"github.com/LuisMedinaG/mbgc/services/monolith/services/auth"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/db"
	"github.com/LuisMedinaG/mbgc/services/monolith/shared/httpx"
)

func main() {
	// Load .env if present
	if _, err := os.Stat(".env"); err == nil {
		// We can't use godotenv here since it's not imported, so we'll rely on env vars
	}

	dbPath := "games.db"
	if p := os.Getenv("DB_PATH"); p != "" {
		dbPath = p
	}
	jwtSecret := os.Getenv("SESSION_SECRET")
	if jwtSecret == "" {
		jwtSecret = "dev-secret-change-me-in-production"
	}

	sqlDB, err := db.Open(dbPath)
	if err != nil {
		log.Fatalf("database init failed: %v", err)
	}
	defer sqlDB.Close()

	authStore := auth.NewStore(sqlDB)

	testUser := os.Getenv("TEST_USER")
	if testUser == "" {
		testUser = "testuser"
	}
	testPass := os.Getenv("TEST_PASSWORD")
	if testPass == "" {
		testPass = "testpass123"
	}

	// Try to authenticate
	userID, err := authStore.AuthenticateUser(testUser, testPass)
	if err != nil {
		log.Fatalf("failed to authenticate test user %q: %v", testUser, err)
	}

	// Get user info
	_, isAdmin, err := authStore.GetUserInfo(userID)
	if err != nil {
		log.Fatalf("failed to get user info: %v", err)
	}

	// Generate token
	accessToken, err := httpx.GenerateAccessToken(userID, testUser, isAdmin, jwtSecret)
	if err != nil {
		log.Fatalf("failed to generate token: %v", err)
	}

	fmt.Printf("TEST_TOKEN=%s\n", accessToken)
}
