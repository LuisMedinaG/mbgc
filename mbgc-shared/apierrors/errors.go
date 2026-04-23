package apierrors

import "errors"

var (
	ErrNotFound          = errors.New("not found")
	ErrUnauthorized      = errors.New("unauthorized")
	ErrForbidden         = errors.New("forbidden")
	ErrBadRequest        = errors.New("bad request")
	ErrConflict          = errors.New("conflict")
	ErrInternalServer    = errors.New("internal server error")
	ErrGameNotFound      = errors.New("game not found")
	ErrCollectionEntry   = errors.New("collection entry not found")
	ErrPlayerAidNotFound = errors.New("player aid not found")
	ErrProfileNotFound   = errors.New("profile not found")
	ErrQuotaExceeded     = errors.New("quota exceeded")
	ErrImportInProgress  = errors.New("import already in progress")
)
