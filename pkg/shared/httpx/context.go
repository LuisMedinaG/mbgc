// Package httpx provides HTTP middleware and context utilities for mbgc services.
package httpx

import "context"

type contextKey int

const (
	ctxRequestID contextKey = iota
	ctxUserID
	ctxUsername
	ctxIsAdmin
)

// SetGatewayUser stores the user identity injected by the gateway into ctx.
// Internal services call this inside TrustGatewayHeaders middleware.
func SetGatewayUser(ctx context.Context, userID, username string, isAdmin bool) context.Context {
	ctx = context.WithValue(ctx, ctxUserID, userID)
	ctx = context.WithValue(ctx, ctxUsername, username)
	ctx = context.WithValue(ctx, ctxIsAdmin, isAdmin)
	return ctx
}

// UserIDFromContext returns the Supabase user UUID injected by the gateway.
// Returns ("", false) if not set — use this to guard authenticated handlers.
func UserIDFromContext(ctx context.Context) (string, bool) {
	v, ok := ctx.Value(ctxUserID).(string)
	return v, ok && v != ""
}

// UsernameFromContext returns the username injected by the gateway.
func UsernameFromContext(ctx context.Context) string {
	v, _ := ctx.Value(ctxUsername).(string)
	return v
}

// IsAdminFromContext reports whether the gateway flagged the user as admin.
func IsAdminFromContext(ctx context.Context) bool {
	v, _ := ctx.Value(ctxIsAdmin).(bool)
	return v
}

func withRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, ctxRequestID, id)
}

// RequestIDFromContext returns the request ID for the current request.
func RequestIDFromContext(ctx context.Context) string {
	v, _ := ctx.Value(ctxRequestID).(string)
	return v
}
