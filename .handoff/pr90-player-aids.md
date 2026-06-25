# Handoff: PR #90 — Player Aid Storage + Catalog Filter Fix

## Backend Changes (merged to dev)

### 1. Player Aid Upload — API Contract Change

**`POST /api/v1/games/{id}/player-aids`**
- **Body type changed:** `application/json` → `multipart/form-data`
- **Fields:**
  - `file` (required) — the aid file, max **5 MB**
  - `label` (optional) — display name, max 255 chars
- **Response:** `201 Created` → `Envelope<PlayerAid>`

```swift
// Expected DTO to add
struct PlayerAidDTO: Decodable, Identifiable {
    let id: Int
    let gameId: Int
    let filename: String   // server-generated UUID + ext, e.g. "a1b2c3d4.png"
    let label: String?
    let createdAt: String  // ISO8601
}
```

**`DELETE /api/v1/games/{id}/player-aids/{aidID}`**
- Unchanged signature — still returns `204 NoContent`
- Backend now deletes from Supabase Storage automatically (best-effort, logged on failure)

### 2. iOS Work Required

**`APIClient.swift`**
- Current `send()` hardcodes `Content-Type: application/json` and takes `Data?` body.
- Needs a **new multipart upload method**. `// ponytail:` URLSession does not natively build multipart bodies; use a small helper to construct the boundary + body `Data` manually rather than pulling in Alamofire.

```swift
// Suggested minimal helper (to add in APIClient.swift or separate file)
func uploadPlayerAid(gameID: Int, fileData: Data, filename: String, label: String?) async throws -> PlayerAidDTO {
    let boundary = UUID().uuidString
    var body = Data()
    // build multipart body with boundary, fileData, optional label
    // then POST /api/v1/games/\(gameID)/player-aids
    // Content-Type: multipart/form-data; boundary=\(boundary)
}
```

**`GameDTO` / `Game` model**
- Add `playerAids: [PlayerAidDTO]?` to `GameDTO` when backend exposes it on game fetch.
- PR #90 did **not** add player aids to the game list response. Aids are only returned from the create endpoint currently. Verify if `GET /api/v1/games/{id}` includes `player_aids` before modeling.

**`LibraryView` / Game detail**
- Add UI for upload (Photos picker or Files picker → `Data`)
- Add UI for listing/deleting aids. Wait for backend to expose aids on game detail, or add a dedicated `listPlayerAids(gameID:)` call if an endpoint exists.

### 3. Security / Behavior Notes

- **Filename safety:** The original filename is discarded; the server generates a UUID and keeps only the original extension. No need to sanitize on the client.
- **Auth:** Same `Authorization: Bearer <JWT>` header. No changes.
- **Size limit:** 5 MB hard limit. Rejected with `400 BadRequest` if exceeded.
- **Cleanup:** On upload, if DB insert fails after storage succeeds, backend auto-deletes the orphan file. On delete, storage deletion is fire-and-forget; client should treat `204` as success even if the file lingers briefly in Supabase.

### 4. Catalog Filter Fix (no iOS impact)

- Player count filters (`1`, `2`, `3`, `4`, `2only`, `5plus`) now correctly constrain both `min_players` and `max_players`.
- No iOS changes needed; query params remain identical.

## Files Touched in PR #90

- `services/api/internal/catalog/handler.go` — multipart parsing, storage upload/remove
- `services/api/internal/catalog/store.go` — `GetPlayerAid`, filter predicate fixes
- `services/api/internal/supabase/client.go` — `Upload()`, `Remove()`
- `services/api/internal/catalog/handler_test.go` — new tests for multipart flows
- `services/api/internal/catalog/filter_test.go` — filter correctness tests
- `services/api/cmd/server/main.go` — wires storage client into catalog handler

## Open Questions for iOS Implementation

1. Does `GET /api/v1/games/{id}` already return `player_aids` array? If not, a backend follow-up is needed before the detail view can display aids.
2. Preferred UX: inline in game detail, or separate "Player Aids" tab?
3. File source: Photos (UIImage → JPEG/PNG Data) or Files (PDF)? The API accepts any Content-Type.
