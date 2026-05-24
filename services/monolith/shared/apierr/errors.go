package apierr

import "errors"

// Sentinel errors shared across services.
var (
	ErrDuplicate        = errors.New("already exists")
	ErrWrongPassword    = errors.New("current password is incorrect")
	ErrForeignOwnership = errors.New("one or more ids are not owned by the user")
)

// IsDuplicate reports whether err is a SQLite UNIQUE constraint violation.
func IsDuplicate(err error) bool {
	if err == nil {
		return false
	}
	// SQLite driver surfaces constraint violations as error strings.
	msg := err.Error()
	return containsAny(msg, "UNIQUE", "unique")
}

// IsOwnership reports whether err signals a cross-user ownership violation.
func IsOwnership(err error) bool {
	return errors.Is(err, ErrForeignOwnership)
}

func containsAny(s string, subs ...string) bool {
	for _, sub := range subs {
		for i := 0; i+len(sub) <= len(s); i++ {
			if s[i:i+len(sub)] == sub {
				return true
			}
		}
	}
	return false
}
