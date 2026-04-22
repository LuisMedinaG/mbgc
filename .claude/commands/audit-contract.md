---
description: Run the contract-auditor across every service to flag response-envelope, pagination, and sentinel-error drift.
---

Delegate to the `contract-auditor` subagent (read-only). It will scan every populated service in this workspace and report violations of the shared conventions from `mbgc-shared`:

- response envelope — `{ "data": ... }` / `{ "error": "..." }`
- list pagination — top-level `total`, `page`, `per_page`
- sentinel errors only — no raw DB errors leaked to clients
- shared middleware used, not duplicated
- cross-service types imported from shared, not redeclared

Relay the auditor's report verbatim, then offer to route each group of findings to the relevant service expert for a fix. Do not start fixes in this invocation.
