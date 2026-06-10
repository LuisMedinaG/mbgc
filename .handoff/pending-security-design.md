# Pending Security Work — High-Level Design

Three items remain from the original 7-point security assessment. This doc covers the
*why*, the *design shape*, and the *constraints* for each. It deliberately omits
implementation detail — those decisions belong to whoever picks up each item.

Status reference: items map to the backlog in `security-hardening-2025-06-07.md`.

---

## 1. Monitoring & Alerting (transcript point #2)

### Why it's needed
Today the API emits structured `slog` logs to stdout, which Cloud Run captures — but
nothing *watches* them. Mean-time-to-detect for a silent failure or an active breach is
effectively infinite: nobody is paged, no error is aggregated, no anomaly is surfaced.
The transcript's own framing — *"if you do get hacked, this will save you so much time"* —
is about incident response, not prevention. Without this layer, every other fix we made
is invisible in production: we can't tell if the rate limiter is firing, if auth is being
probed, or if panics are spiking.

### Design shape
An error-and-event sink that sits downstream of the existing logging boundary. The two
existing choke points — the `Recover` middleware (panics) and `WriteError`'s internal-error
branch — already centralize every server-side failure. The design routes those same events
to an external aggregator with alerting rules layered on top. Request-ID correlation already
exists and must be preserved end-to-end so a single alert links back to a full request trace.
Prefer a log-based alerting approach (watch the existing stdout stream) over an embedded SDK
unless richer context capture justifies the coupling.

### Constraints
- **No new latency.** Event shipping must be async / fire-and-forget; a request must never
  block on the monitoring backend.
- **Fail open.** If the monitoring backend is down, the API keeps serving. Monitoring is
  observability, never a dependency.
- **Preserve the redaction boundary.** The app already guarantees raw errors never reach
  clients (`apierr` sentinels). The same guarantee must hold outbound to the aggregator —
  no secrets, tokens, or PII in event payloads.
- **Reuse, don't replace.** Build on `slog` + request-ID, not a parallel logging stack.
- **Start on a free tier.** No infra spend to prove value.

---

## 2. Dependency Scanning (transcript point #3)

### Why it's needed
The transcript's *"research the packages you use"* is really about supply-chain risk: a
known CVE in a transitive dependency is a pre-built entry point an attacker can look up as
easily as we can. The repo currently has zero automated detection — a vulnerable `pgx`,
`keyfunc`, or a compromised npm package could sit unnoticed until exploited. This is the
lowest-effort, highest-leverage gap remaining: it converts an unbounded unknown into a
continuous, automated signal.

### Design shape
Two complementary layers running in CI and on a schedule. First, a **detection** layer that
flags known vulnerabilities against advisory databases — covering both ecosystems present in
the monorepo. Second, an **update** layer that proposes version bumps as reviewable PRs.
Detection gates merges; updates never auto-apply. The two are independent: detection protects
what's shipped now, updates reduce future exposure.

### Constraints
- **Cover the whole workspace.** Both Go module roots (`pkg/shared`, `services/api` under
  `go.work`) and the `bun`-managed `web/` must be scanned. A partial scan is a false sense
  of safety.
- **Human-in-the-loop for changes.** Updates land as PRs only — never auto-merge, because a
  bumped dependency can break behavior the test suite doesn't cover.
- **Tune for signal, not noise.** Group patch/minor bumps; reserve hard CI failures for
  high/critical severity so day-to-day velocity isn't throttled by informational findings.
- **Respect existing gates.** Scanning slots into the current CI (the same checks that gate
  `dev`), not a separate pipeline.

---

## 3. Content-Type Enforcement (transcript point #5)

### Why it's needed
*"Treat everything the client sends as untrusted."* Body size and origin are already guarded
(`LimitBodySize`, CORS), but the *shape* of the request is not: a state-changing endpoint
will currently attempt to parse a body regardless of its declared Content-Type. Beyond
hygiene, this is a concrete CSRF lever — "simple" cross-origin requests using `text/plain`
sidestep the CORS preflight that otherwise protects mutating routes. Enforcing Content-Type
closes that bypass and makes the API's input contract explicit.

### Design shape
A central guard in the existing middleware chain that asserts the declared Content-Type on
requests that carry a body, rejecting mismatches before any handler runs. It belongs next to
the other cross-cutting `httpx` middleware so the policy is defined once and applied uniformly,
not re-checked per handler. Rejection uses the standard error envelope so clients get a
consistent, machine-readable response.

### Constraints
- **Body-bearing methods only.** GET / DELETE / OPTIONS without a body must pass untouched;
  the check keys off presence of a body, not the method alone.
- **Honor the one exception.** The CSV import path is multipart, not JSON — the policy must
  accommodate more than a single allowed type rather than hard-coding `application/json`.
- **Slot into the existing chain order.** It composes with `LimitBodySize`, `SecurityHeaders`,
  and `CORS`; it does not reorder or duplicate them.
- **Backward compatible.** The existing web client already sends correct Content-Types;
  enforcement must not break current callers — it only rejects malformed/forged ones.

---

## Sequencing note
Independent items — any order works. By leverage-per-effort: **(2) dependency scanning**
first (cheapest, continuous protection), then **(3) Content-Type** (small, closes a CSRF
lever), then **(1) monitoring** (largest, but unlocks visibility into everything else).
