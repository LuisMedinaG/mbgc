# Cloudflare Operations Guide

Quick reference for all Cloudflare operations: setup, token management, DNS, Pages, and troubleshooting.

## Quick Links

| Task | Guide |
|---|---|
| First-time setup | [Setup](#first-time-setup) |
| Token rotation | [Rotate API Token](#rotate-api-token) |
| Check DNS records | [Verify DNS](#verify-dns) |
| Check Pages status | [Monitor Pages](#monitor-pages) |
| Troubleshooting | [cloudflare-incidents.md](incidents.md) |
| Pages dashboard config | [cloudflare-pages-setup.md](pages-setup.md) |

---

## First-Time Setup

### Prerequisites

- Cloudflare account (free or paid)
- Domain registered (can be at any registrar, or transfer to CF)
- GCP project, Supabase project (via `make bootstrap`)

### Step 1: Create Cloudflare API Token

1. **dash.cloudflare.com** → your avatar → **My Profile**
2. **API Tokens** → **Create Token**
3. Use template: **"Edit Cloudflare Pages"** (includes Pages, Zone, DNS scopes)
4. Or manually:
   - **Permissions:**
     - Account → Cloudflare Pages:Edit
     - Zone (select `lumedina.dev`) → DNS:Edit
     - Zone (select `lumedina.dev`) → Zone:Edit
   - **IP Address Allowlist:** (leave blank for now)
   - **TTL:** 365 days (or your preference)
5. Copy token → paste into `infra/.env` as `CLOUDFLARE_API_TOKEN`

### Step 2: Get Account & Zone IDs

1. **dash.cloudflare.com** → select `lumedina.dev`
2. **Overview** tab → right sidebar:
   - **Account ID** → paste into `infra/.env` as `CF_ACCOUNT_ID`
   - **Zone ID** → paste into `infra/.env` as `CLOUDFLARE_ZONE_ID`

### Step 3: Update Domain Registrar Nameservers

⚠️ **Critical step — without this, DNS won't resolve.**

1. **dash.cloudflare.com** → **Overview** → find "Nameservers" section
2. Copy Cloudflare's two nameservers (usually `NS1.CLOUDFLARE.COM`, `NS2.CLOUDFLARE.COM`)
3. Go to your domain registrar (GoDaddy, Namecheap, etc.)
4. Update nameserver records to point to Cloudflare's
5. Save — allow 24–48h for propagation

**Verify:**
```sh
dig lumedina.dev NS
# Should show Cloudflare nameservers
```

### Step 4: Bootstrap Infrastructure

```sh
make bootstrap
# Reads infra/.env, validates token, syncs secrets to GitHub
```

**Expected output:**
- ✓ token valid
- ✓ GitHub secrets synced
- ✓ Terraform init complete

### Step 5: Apply Terraform

```sh
cd infra/environments/prod
terraform plan    # review
terraform apply
```

This creates:
- Cloudflare Pages project shell (`mbgc-web`)
- DNS records (apex → Pages, www → Pages, api → Cloud Run)

### Step 6: Configure Pages in Dashboard

See [cloudflare-pages-setup.md](pages-setup.md) for detailed walkthrough:
1. Link GitHub repo
2. Set build command: `bun install && bun run build`
3. Set output directory: `dist`
4. Set root directory: `web`
5. Trigger first build

### Step 7: Run Smoke Tests

```sh
sh infra/scripts/smoke.sh
# Verifies Cloud Run, DNS, Cloudflare Pages all working
```

---

## Rotate API Token

**When:** Token compromised, expires, or security policy requires rotation.

### Option A: Via Script (Recommended)

```sh
make rotate-secrets cloudflare
# Prompts for new token, updates GitHub + tfvars
```

### Option B: Manual

1. **dash.cloudflare.com** → **My Profile** → **API Tokens**
2. Find old token → click three dots → **Revoke**
3. **Create Token** → follow [First-Time Setup Step 1](#step-1-create-cloudflare-api-token)
4. Copy new token
5. Update locally:
   ```sh
   # Edit infra/.env
   CLOUDFLARE_API_TOKEN=<paste-new-token>
   # Sync to GitHub
   make bootstrap
   ```

**Verify token works:**
```sh
curl -s -H "Authorization: Bearer <TOKEN>" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq '.success'
# Should print: true
```

---

## Verify DNS

### Check DNS Records Exist

```sh
# In Terraform state
cd infra/environments/prod
terraform state show cloudflare_dns_record.apex
terraform state show cloudflare_dns_record.www
terraform state show cloudflare_dns_record.api
```

### Check Live DNS Resolution

```sh
# Resolve from public DNS
dig +short lumedina.dev
dig +short www.lumedina.dev
dig +short api.lumedina.dev

# Resolve from Cloudflare nameservers only
dig +short @ns1.cloudflare.com lumedina.dev
dig +short @ns1.cloudflare.com api.lumedina.dev
```

### Expected Results

| Record | Type | Target | Proxied? |
|---|---|---|---|
| @ (apex) | CNAME | *.pages.dev | Yes (orange cloud) |
| www | CNAME | *.pages.dev | Yes (orange cloud) |
| api | A | ghs.googlehosted.com | No (gray cloud) |

**If results differ, see [cloudflare-incidents.md — DNS Issues](incidents.md#dns-propagation--resolution-issues).**

---

## Monitor Pages

### Check Latest Deployment Status

```sh
# Via API (requires CF_ACCOUNT_ID + token from env)
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/pages/projects/mbgc-web/deployments" \
  | jq '.result[0] | {status, created_on, environment}'
```

### Check Pages Build Logs

1. **dash.cloudflare.com** → **Pages** → **mbgc-web**
2. **Deployments** tab → click latest build
3. View build command output, build errors, etc.

### Trigger Manual Deploy

```sh
git push origin main
# Pages auto-builds on push

# OR: trigger from dashboard
# Pages → mbgc-web → Deployments → "Trigger deployment"
```

### Expected Status Values

| Status | Action |
|---|---|
| `success` | Build completed, live at `mbgc-web.pages.dev` |
| `failure` | Build failed — check logs |
| `queued` | Build in progress — wait and recheck |
| `cancelled` | Build was manually cancelled |

---

## Check API Token Scopes

Verify token has required permissions:

```sh
TOKEN="your-token-here"
curl -s -H "Authorization: Bearer $TOKEN" \
  https://api.cloudflare.com/client/v4/user/tokens/verify | jq '.result.policies'
```

Expected output:
```json
[
  {
    "id": "...",
    "effect": "allow",
    "resources": { "com.cloudflare.api.account.id": "<account-id>", ... },
    "permission_groups": [
      { "id": "...", "name": "Cloudflare Pages" },
      { "id": "...", "name": "Zone Write" },
      { "id": "...", "name": "DNS Write" }
    ]
  }
]
```

**If missing permissions, recreate token** with correct scopes.

---

## Update DNS Record Manually

**Use case:** DNS-only vs proxied settings, change target, TTL, etc.

### Via Terraform

Safer — keeps config as code:

```sh
# Edit infra/environments/prod/main.tf
# Change cloudflare_dns_record.api block
# Run terraform plan to preview
terraform plan
# Review changes
terraform apply
```

### Via Cloudflare Dashboard (Not Recommended)

1. dash.cloudflare.com → **DNS**
2. Click record → edit TTL/proxy setting/target
3. Save

⚠️ **Problem:** Changes won't be tracked in git. Next `terraform apply` may overwrite. **Avoid unless Terraform is disabled for DNS.**

---

## Cloudflare Analytics

Monitor traffic, cache hit rate, page load time:

1. **Pages** → **mbgc-web** → **Analytics** tab
2. View:
   - Request volume over time
   - Cache hit ratio
   - Origin latency
   - Top paths
   - Status code distribution

Use this to spot:
- Build failures (sudden drop in requests)
- Pages offline (error spikes)
- Slow origin (high latency)

---

## Security Best Practices

### Token Security

- ✅ Store in `infra/.env` (gitignored)
- ✅ Sync to GitHub Actions via bootstrap
- ✅ Rotate every 1–2 years
- ❌ Don't commit to git
- ❌ Don't log in scripts (except masked in GitHub Actions)

### IP Allowlist (Optional)

Restrict token to specific IPs:

1. **API Tokens** → click token → **Edit**
2. **IP Address Allowlist** → add GitHub Actions IP ranges + your office
3. Save

See: https://docs.github.com/en/actions/learn-github-actions/usage-limits-billing-and-administration#github-hosted-runner-ip-addresses

### Domain Registrar

Protect domain account:
- Enable 2FA on registrar
- Use strong unique password
- Set registrar lock (prevent unauthorized transfer)
- Monitor WHOIS for changes

### DNS DNSSEC (Optional)

Cloudflare can enable DNSSEC to prevent DNS spoofing:
1. **DNS** → **DNSSEC** → enable
2. Copy DS records to registrar (if supported)

---

## Limits & Quotas

| Resource | Limit | Tier |
|---|---|---|
| Pages projects | 100 | Free |
| DNS records | Unlimited | Free |
| API requests | 1,200/5min | Free |
| Deployments/month | Unlimited | Free |
| Custom domains | Unlimited (with DNS) | Free |

See: https://developers.cloudflare.com/pages/platform/limits/

---

## Related

- [cloudflare-incidents.md](incidents.md) — troubleshooting
- [cloudflare-pages-setup.md](pages-setup.md) — Pages dashboard config
- [infra/AGENTS.md](../../infra/AGENTS.md) — Terraform provider details
- [rotate-secrets.sh](../../infra/scripts/rotate-secrets.sh) — secret rotation
- [bootstrap.sh](../../infra/scripts/bootstrap.sh) — token validation
