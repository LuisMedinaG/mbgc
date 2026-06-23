# AGENTS.md — MBGC iOS

iOS SwiftUI app for MBGC backend. Swift 6.2 / iOS 17+ / SwiftData / URLSession.

## Stack
- SwiftUI + SwiftData + @Observable
- Native URLSession async/await for networking
- XcodeGen for project generation
- Bun for all npm/node operations
- Supabase Auth via hosted webview

## Directory
- `ios/MBGC/` — all Swift source
- `ios/project.yml` — XcodeGen config
- `ios/AGENTS.md` — this file
- `docs/ios-plan.md` — full plan reference

## Build Commands
- MCP `build_sim` / `test_sim` — primary
- Fallback: `xcodebuild -scheme MBGC -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`
- Project generation: `xcodegen generate` in `ios/` directory

## Critical Rules

**NEVER modify .pbxproj or .xcodeproj/ directory contents.**
To add a new Swift file: add it to the filesystem, then run `xcodegen generate` in the `ios/` directory. The human runs xcodegen; the agent never hand-edits .pbxproj.

**Always use @Observable** (iOS 17+). Never ObservableObject, @StateObject, or Combine.

**Keychain for secrets.** JWT stored in Keychain via Security framework. Never UserDefaults, never localStorage.

**SwiftData for persistence.** Read from SwiftData always. Write locally first, sync to API asynchronously.

**bun for all npm operations.** Never `npm install` — use `bun add` or `bunx`.

## API Contract
Base URL: `${MBGC_API_BASE_URL}` (env var, default `http://localhost:8080`)
Auth: `Authorization: Bearer <JWT>` on all /api/v1/* routes.

## Bundle ID
`app.lumedina.mbgc`

## Skills Available
- `wshobson/agents@mobile-ios-design` — iOS UI/HIG design
- `firebase/agent-skills@xcode-project-setup` — Xcode project setup

## Hooks
- `.claude/hooks/prevent-pbxproj` — blocks any attempt to write .pbxproj files
