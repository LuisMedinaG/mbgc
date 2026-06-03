# Cloudflare Incidents & Recovery

Runbook for common Cloudflare issues: DNS failures, Pages build failures, token rotation, and emergency recovery.

## DNS Propagation / Resolution Issues

**Symptoms:** `api.lumedina.dev` or `www.lumedina.dev` don't resolve; NXDOMAIN errors.

### Check DNS records exist in Cloudflare

```sh
# Check what Terraform created
cd infra/environments/prod
terraform state show 'cloudflare_dns_record.apex'
terraform state show 'cloudflare_dns_record.www'
terraform state show 'cloudflare_dns_record.api'
```

### Query live DNS from CF

```sh
# From Cloudflare dashboard: lumedina.dev → DNS
# Should show:
#   @ (apex)     CNAME   *.pages.dev  (proxied)
#   www          CNAME   *.pages.dev  (proxied)
#   api          A       Cloud Run IP (DNS-only, not proxied)

# Verify with dig
dig api.lumedina.dev
dig www.lumedina.dev
dig lumedina.dev
```

### Nameserver mismatch

If queries return SERVFAIL or timeout:

```sh
# Check your registrar (where you bought lumedina.dev)
# Confirm it points to Cloudflare nameservers:
#   NS1.CLOUDFLARE.COM
#   NS2.CLOUDFLARE.COM
#   (NOT your old registrar's NS records)

# Verify with:
dig lumedina.dev NS
```

If nameservers are wrong, update at your registrar (GoDaddy, Namecheap, etc.). Allow 24–48h for propagation.

### DNS-only vs proxied

- **Apex & www:** should be **CNAME → *.pages.dev (proxied through CF)**
- **api:** should be **A → ghs.googlehosted.com (DNS-only, Cloud Run terminates TLS)**

If api is marked "proxied", Cloudflare will intercept HTTPS and break mTLS to Cloud Run.

**Fix in Cloudflare dashboard:**
1. lumedina.dev → DNS
2. Click "api" record
3. Toggle **orange cloud → gray cloud** (DNS-only)
4. Save

---

## Cloudflare Pages Build Failures

**Symptoms:** Pages deployment stuck in "In Progress" or shows "Build Error".

### Check Pages project status

**In Terraform:**
```sh
cd infra/environments/prod
terraform state show 'cloudflare_pages_project.this'
# Note: Terraform only creates the project shell. Build config is dashboard-only.
```

**In Cloudflare dashboard:**
1. Pages → mbgc-web
2. Deployments tab
3. Click latest deployment → see logs

### Common causes

| Issue | Fix |
|---|---|
| GitHub not linked | Pages → Settings → Git configuration → Connect GitHub repo |
| Wrong build command | Settings → Build settings → set to: `bun run build` |
| Wrong output dir | Settings → Build settings → output dir: `dist/` |
| No env vars set | Settings → Environment variables → add `NODE_ENV=production` (if needed) |
| Missing `.env` at build time | Build vars defined in CF dashboard, NOT committed to git |

### GitHub integration

Pages requires explicit GitHub repo connection. If disconnected:
1. Pages → mbgc-web → Settings → Git configuration
2. **Disconnect and reconnect**
3. Authorize Cloudflare to access `LuisMedinaG/mbgc`
4. Select branch: `main`
5. Next build will trigger automatically on push to main

### Verify GitHub workflow status

```sh
gh run list --repo LuisMedinaG/mbgc --limit 1
```

If Pages is failing, also check: does `web/dist/` exist locally?

```sh
cd web
bun install
bun run build
ls -la dist/
```

---

## Cloudflare API Token Issues

**Symptoms:** Bootstrap fails with "insufficient permissions" or "invalid token"; Terraform apply fails during Cloudflare resource creation.

### Verify token scopes

```sh
# Run this in bootstrap.sh (see improvement #2) — checks token validity
curl -s -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq '.result'
# Should output: { "id": "...", "status": "active", "token": "***" }
```

### Required scopes

Token must have these exact permissions:
- **Account** (not zone): `Cloudflare Pages:Edit`
- **Zone** (lumedina.dev): `DNS:Edit`, `Zone:Edit`

**To create or rotate token:**
1. dash.cloudflare.com → your avatar → My Profile
2. API Tokens → Create Token
3. Use **"Edit Cloudflare Pages"** template + edit:
   - Account → Cloudflare Pages:Edit ✓
   - Zone → Zone:Edit ✓
   - Zone → DNS:Edit ✓
   - Specific zone → select `lumedina.dev`
4. Copy token → paste into `infra/.env` → `CLOUDFLARE_API_TOKEN=...`
5. Re-run `make bootstrap` to sync to GitHub

### Token rotation

```sh
make rotate-secrets cloudflare
# Prompts for new token, updates GitHub Actions + local tfvars
```

---

## API Error Responses from Cloudflare

**Symptoms:** `terraform apply` fails with error from `cloudflare_*` resource.

### Decode error message

```sh
# Example error:
# Error: error from Cloudflare API: ..., code: 6003, message: "Invalid request"

# Look up code at: https://developers.cloudflare.com/api/
# 6003 = invalid zone ID or missing permissions
```

### Common codes

| Code | Meaning | Fix |
|---|---|---|
| 6003 | Invalid zone ID or permissions | Check CLOUDFLARE_ZONE_ID in infra/.env, verify token has Zone:Edit |
| 6004 | Account not found | Check CF_ACCOUNT_ID, confirm you're in right Cloudflare org |
| 6013 | Maintenance mode | Pages service under maintenance; wait 5–10 min and retry |
| 8000 | Pages project conflict | Project name already exists; check dashboard |

---

## Emergency Recovery: Full DNS Failover

**If Cloudflare DNS is completely down or misconfigured:**

Cloudflare DNS can be bypassed by updating your domain registrar to point directly to Cloud Run IPs.

⚠️ **Last resort only.** Usually takes 24h+ to propagate. Better to fix Cloudflare.

### Temporary: Point directly to Cloud Run

1. Get Cloud Run API IP:
   ```sh
   gcloud run services describe mbgc-api --region us-central1 --format='value(status.url)'
   # Extract domain, then: nslookup api.run.app → get IP
   ```

2. At registrar (GoDaddy, etc.):
   - Change `api` A record from `ghs.googlehosted.com` to Cloud Run IP
   - **Keep** `www` and apex pointing to CF

3. Flush your local DNS cache:
   ```sh
   sudo dscacheutil -flushcache   # macOS
   # or just wait 5–10 min
   ```

4. Verify:
   ```sh
   dig api.lumedina.dev
   curl https://api.lumedina.dev/healthz
   ```

---

## Cloudflare Provider Known Issues

### Issue: `lifecycle { ignore_changes = all }` silently no-ops changes

**Context:** `infra/modules/cloudflare-pages/main.tf` line 33–39.

Cloudflare provider v5 sends malformed PATCH requests for computed `source` fields. To avoid perpetual Terraform drift, all post-creation changes are ignored.

**Implication:** If you rename the Pages project or change `production_branch`, you must:
1. Manually delete the Pages project from Cloudflare dashboard
2. Run `terraform apply` to recreate it
3. Manually reconnect GitHub in the dashboard

**Don't edit** `lifecycle { ignore_changes = all }` — that's a workaround, not a bug.

---

## Monitoring & Alerts (Recommended)

Consider setting up:

- **Pages deployment failures** → Email alert from CF dashboard (Settings → Notifications)
- **DNS changes** → Terraform plan review before apply (CI gate on `infra/**` changes)
- **API token expiration** → Calendar reminder 30 days before token created (manual; CF doesn't auto-expire)
- **Page load time** → CF Analytics → set up alert if latency > 2s

---

## Related

- [Cloudflare Pages Setup](pages-setup.md) — dashboard walkthrough
- [infra/AGENTS.md](../../infra/AGENTS.md) — IaC security posture, provider quirks
- [rotate-secrets.sh](../../infra/scripts/rotate-secrets.sh) — token rotation automation
