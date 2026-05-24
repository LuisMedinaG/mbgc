---
name: managing-file-uploads
description: Adds or modifies a multipart file-upload endpoint in this Go service, covering size limits, MIME validation, random filename generation, disk storage under dataDir/uploads, and cleanup on store errors. Use when the user asks to add a file upload, accept image/PDF uploads, change upload size limits, validate uploaded MIME types, or fix upload-related bugs.
---

# Managing multipart file uploads

The canonical reference is `UploadPlayerAid` in `services/files/handler.go`. Copy its shape — the ordering matters (MaxBytesReader before ParseMultipartForm, `os.Remove(dest)` on any post-write error, DB insert last).

## Required touch points

```
- [ ] 1. Define a per-endpoint size limit constant
- [ ] 2. Wrap r.Body with http.MaxBytesReader BEFORE ParseMultipartForm
- [ ] 3. Type-assert http.MaxBytesError for 413 responses
- [ ] 4. Validate Content-Type via an allowlist helper
- [ ] 5. Generate filename with crypto/rand hex + ext
- [ ] 6. Write to filepath.Join(dataDir, "uploads", filename)
- [ ] 7. On any error AFTER the write, os.Remove(dest) before returning
- [ ] 8. Create the DB row LAST, remove file if that fails
- [ ] 9. Serve via /uploads/ static route in main.go (already wired)
```

## Size limit

Define at the top of the service file:

```go
const maxPlayerAidUploadBytes = 10 << 20 // 10 MB
```

Pick the smallest limit the feature needs. Large limits cost memory (Go buffers multipart in RAM up to `maxMemory`, then spills to temp files).

## Parse safely

```go
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
```

`MaxBytesReader` must wrap `r.Body` **before** `ParseMultipartForm` — otherwise the caller can stream an unbounded body. The `errors.As` check is how you distinguish "too large" (413) from a malformed form (400).

## MIME validation

Always allowlist Content-Types. Don't trust file extensions on the client side. Pattern from `allowedImageExt`:

```go
func allowedImageExt(contentType string) (string, bool) {
    switch contentType {
    case "image/png":  return ".png", true
    case "image/jpeg": return ".jpg", true
    case "image/gif":  return ".gif", true
    case "image/webp": return ".webp", true
    default: return "", false
    }
}
```

Read `header.Header.Get("Content-Type")` from `FormFile`, not `r.Header` (that's the multipart wrapper). Return 400 on unsupported type.

## Random filename

Never use the client-supplied filename for the on-disk path — path traversal risk and collision risk. Use `crypto/rand`:

```go
func randomFilename(ext string) (string, error) {
    b := make([]byte, 16)
    if _, err := rand.Read(b); err != nil { return "", err }
    return hex.EncodeToString(b) + ext, nil
}
```

Keep the original filename only as the user-visible `label`, run through `sanitizeLabel` (strip ext, trim, cap length).

## Disk layout

All uploads go under `filepath.Join(h.dataDir, "uploads", filename)`. The `files.Handler` is constructed with `dataDir` injected; new handlers that upload should take `dataDir` the same way. Don't hard-code paths; `dataDir` is set from env (`DATA_DIR`) and defaults differ between dev and Fly.

Create the file with `os.Create` (truncates) and `io.Copy` from the multipart reader. Don't forget `f.Close()` — deferring is fine, but explicitly closing before `os.Remove` on the error path is clearer.

## Cleanup ordering

**Golden rule:** if the DB insert fails after the file was written, remove the file. If the file write fails after `os.Create`, remove the partial file. Any other order leaks disk.

```go
f, err := os.Create(dest)
if err != nil { /* 500, no remove needed */ return }
if _, err := io.Copy(f, file); err != nil {
    f.Close()
    _ = os.Remove(dest)   // cleanup
    /* 500 */ return
}
f.Close()

// DB insert LAST
aidID, err := h.store.CreatePlayerAid(id, filename, label)
if err != nil {
    _ = os.Remove(dest)   // cleanup
    /* 500 */ return
}
```

On delete, remove the disk file before the DB row (`DeletePlayerAid` pattern). The `_ =` on `os.Remove` is intentional — a missing file is fine.

## Serving uploads

`main.go` already wires `GET /uploads/` through `http.StripPrefix` + `http.FileServer` with an `X-Content-Type-Options: nosniff` header. New upload endpoints don't need to add a serve route — just store under `dataDir/uploads/` and the filename is immediately reachable at `/uploads/<filename>`.

## Auth and ownership

Upload endpoints must be protected. Call `requireUserID(w, r)` then verify ownership of any parent resource (`h.store.GetGame(id, userID)`) **before** accepting the upload — don't spend bandwidth on files the user isn't allowed to attach.

## Verification

```sh
make test
# Manual:
TOKEN=$(...)
curl -X POST localhost:8080/api/v1/games/1/player-aids \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@test.png" -F "label=round 1"
# Confirm disk write + row:
ls data/uploads/
sqlite3 data/app.db "SELECT * FROM player_aids ORDER BY id DESC LIMIT 1"
```
