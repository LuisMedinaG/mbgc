# Cloudflare Pages — Dashboard Setup

After `terraform apply` creates the Pages project shell, you must configure GitHub integration and build settings in the **Cloudflare dashboard**. This guide walks through the required manual steps.

## Prerequisites

- Cloudflare account with `lumedina.dev` domain
- Terraform has successfully created the Pages project (check: Pages → mbgc-web exists)
- GitHub account with push access to `LuisMedinaG/mbgc`
- Admin permission in both Cloudflare and GitHub

## Step 1: Link GitHub Repository

**In Cloudflare dashboard:**

1. **Pages** → **mbgc-web**
2. **Settings** tab → **Git configuration** section
3. Click **Connect GitHub**
4. Authorize Cloudflare to access your GitHub account
   - Cloudflare will ask for org/repo permissions
   - Click **Authorize cloudflare** (required for automated deployments)
5. **Select repository:** `LuisMedinaG/mbgc`
6. **Select production branch:** `main` (must match `production_branch = "main"` in Terraform)
7. Click **Save and deploy**

After saving, Pages will attempt the first build (likely will fail until build settings are configured — this is expected).

## Step 2: Configure Build Settings

**Still in Pages → mbgc-web → Settings:**

1. **Build settings** section:
   - **Framework preset:** None (custom build)
   - **Build command:** `bun install && bun run build`
   - **Build output directory:** `dist`
   - **Root directory (advanced):** `web` (project lives in `web/`)
   
   > If you don't set Root directory, CF looks for build output at the repo root instead of `web/dist/`.

2. **Click Save**

## Step 3: Environment Variables

**Pages → mbgc-web → Settings → Environment variables**

Pages build happens inside CF's container — any env vars your build needs must be set here.

**Add these if your build uses them:**

| Variable | Value | Required? |
|---|---|---|
| `NODE_ENV` | `production` | Optional (bun build already assumes this) |
| `VITE_API_URL` | `https://api.lumedina.dev` | If web hardcodes API URL (probably in `.env.example`) |

> **Note:** Do NOT commit `.env` files. Use `web/.env.example` with placeholders; CF dashboard fills in secrets at build time.

If `web/` doesn't need build-time env vars, skip this section.

## Step 4: Trigger First Deploy

**Pages → mbgc-web → Deployments:**

Click **Trigger deployment** → select **Deploy from branch** → pick `main`.

CF will pull latest `main`, run your build command, and deploy. Check the **Deployment log** (click in-progress build) to see output.

**Expected success:** build completes in <2 min, shows "Build Status: Success ✓", subdomain live at `https://mbgc-web.pages.dev/`.

**Expected failures (if config wrong):**
- `Build command not found` — check build command syntax
- `dist/: No such file or directory` — check build output directory name
- `web/: not found` — check root directory setting

See [cloudflare-incidents.md](incidents.md#cloudflare-pages-build-failures) for troubleshooting.

## Step 5: Custom Domain Setup

After first successful build, you can assign the custom domain (`www.lumedina.dev`).

**Pages → mbgc-web → Custom domains:**

1. Click **Add custom domain**
2. Enter: `www.lumedina.dev`
3. CF checks that a DNS record exists (apex/www CNAME to `*.pages.dev` — Terraform created this)
4. Click **Continue**
5. Pages will now serve at `https://www.lumedina.dev/`

> **Note:** Apex domain (`lumedina.dev`) redirect to `www` is optional. Terraform already points both to Pages.

## Step 6: Deploy Previews (Optional)

**Pages → mbgc-web → Settings → Builds & deployments:**

**Preview deployments** section:
- Set to: `All pull requests` (default is "None")

This makes Pages auto-build every PR so you can preview changes at `https://[branch-name].mbgc-web.pages.dev/`.

Helpful for code reviews; can be left disabled if not needed.

## Step 7: Verify Live Deployment

Test that traffic reaches your build:

```sh
# Check CNAME chain
dig www.lumedina.dev +noall +answer
# Should show: www.lumedina.dev CNAME *.pages.dev

# Fetch homepage
curl -I https://www.lumedina.dev/
# Should return 200 + content from your build

# Check that static files are served
curl https://www.lumedina.dev/index.html | head -20
```

## Automated Deploys

**Push to `main` triggers automatic deployment:**

```sh
git push origin main
# Pages auto-detects the push, runs build command, deploys
```

Check **Pages → Deployments** to monitor.

## Troubleshooting

### Build fails with "web/: not found"

**Root directory setting is missing.** Pages is looking for build output at repo root instead of inside `web/`.

**Fix:** Pages Settings → Build settings → **Root directory (advanced)** → set to `web` → Save → Re-trigger deployment.

### "Build command not found" error

**Build command syntax is wrong or missing bun.**

**Fix:**
- Verify command: `bun install && bun run build`
- Check `web/package.json` has `"build"` script
- Test locally: `cd web && bun run build` — should succeed

### Deploy preview URLs don't work

**Preview deployments not enabled.**

**Fix:** Pages → Settings → Builds & deployments → Preview deployments → **All pull requests** → Save.

### Static assets (CSS/JS) 404

**Build output directory is wrong.**

**Fix:** Pages Settings → **Build output directory** → confirm it's `dist` (not `build`, `out`, etc.)

### Domain points to wrong content

**DNS record exists but doesn't resolve to Pages.**

**Fix:**
1. Check: Pages → mbgc-web → Custom domains — is `www.lumedina.dev` listed and active?
2. Run: `dig www.lumedina.dev` — confirm CNAME → `*.pages.dev`
3. If wrong, delete custom domain from Pages + re-add it
4. If DNS record is missing, Terraform may have failed — re-run `terraform plan && apply`

## Environment-Specific Builds

**If you need prod vs dev builds with different configs:**

1. Create a `dev` branch or use GitHub environment variables
2. In Pages Settings → add second project for dev branch, OR
3. Use single project but set **Preview deployments** → **Custom deployments** with conditional build commands

This is advanced; not required for basic setup.

## Monitoring & Alerts

**Optional but recommended:**

1. Pages → mbgc-web → Settings → Notifications
   - Enable email alerts for build failures
2. Set Slack webhook (if org has Slack): Notifications → Add Slack
3. Monitor performance: Pages → Analytics tab shows request volume, cache hit rate, latency

## Related

- [cloudflare-incidents.md](incidents.md) — troubleshooting
- [infra/AGENTS.md](../../infra/AGENTS.md) — why Terraform ignores Pages build settings
- [SETUP.md](../../SETUP.md) — full infra setup guide
