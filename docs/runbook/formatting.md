Formatting & Code Style

Purpose
- Keep Go code consistent and reviewable. CI enforces `gofmt` and `golangci-lint` (see `.github/workflows/pipeline.yml`).

What CI enforces
- `gofmt` (check-only): CI fails if files are not `gofmt`-ed.
- `golangci-lint`: runs a conservative baseline (`.golangci.yml`).

Local developer workflow
- Check formatting only:

  gofmt -l .

- Auto-format in-place:

  gofmt -s -w .

- Fix imports (recommended):

  go install golang.org/x/tools/cmd/goimports@latest
  goimports -w .

Editor recommendations (VS Code)
- Install the `Go` extension (golang.go).
- Enable format on save in `settings.json`:

  "editor.formatOnSave": true

- Configure `gopls` to format and organise imports automatically (default in extension).

Pre-commit / Git hooks (optional)
- Add a `pre-commit` hook that runs `gofmt -s -w .` and `goimports -w .` to reduce CI failures.
- Example (in `.git/hooks/pre-commit`, make executable):

  #!/bin/sh
  gofmt -s -w .
  command -v goimports >/dev/null 2>&1 && goimports -w . || true
  git add -A

Why we fail CI rather than auto-commit
- Failing CI prevents accidental or unexpected commits from bots and preserves author intent. It ensures formatting is present at commit-time and keeps the commit history clean.

If you want automation
- If you prefer automatic PRs with formatting fixes, we can add a GitHub Action that opens a formatting PR (non-destructive). Ask me to add it and I'll implement a minimal action.

Questions or changes
- If any `golangci-lint` rules are noisy, open an issue or request a relaxed rule; we can tune `.golangci.yml`.
