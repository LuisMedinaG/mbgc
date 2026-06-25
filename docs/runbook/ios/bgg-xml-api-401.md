# BGG XML API 401 Without Auth

## Symptoms
- `BGG returned status 401`
- `curl -A 'app.lumedina.mbgc/1.0' 'https://boardgamegeek.com/xmlapi2/thing?id=13&stats=1'` returns `401`

## Root cause
BGG XML API requests require BGG API auth; a User-Agent alone is not enough.

## Fix
- Do not bundle a BGG token in iOS.
- Use a user-provided token stored in Keychain, or proxy through the authenticated Go importer.

## Prevention
- Keep BGG auth decisions explicit in specs before implementing direct iOS import.

## Related
- `ios/MBGC/Networking/BGGClient.swift`
- `services/api/internal/importer/bgg.go`
