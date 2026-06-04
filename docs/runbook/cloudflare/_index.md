# Cloudflare Operations & Troubleshooting

Cloudflare manages the frontend (Pages) and DNS for `lumedina.dev`.

## Quick Links

| Need | Guide |
|---|---|
| **Setup** | [operations.md & First-Time Setup](operations.md#first-time-setup) |
| **API Token** | [operations.md & Rotate API Token](operations.md#rotate-api-token) |
| **DNS Issues** | [incidents.md & DNS Propagation](incidents.md#dns-propagation--resolution-issues) |
| **Pages Broken** | [incidents.md & Pages Build Failures](incidents.md#cloudflare-pages-build-failures) |
| **Dashboard Config** | [pages-setup.md](pages-setup.md) |
| **Monitoring** | [operations.md & Monitor Pages](operations.md#monitor-pages) |

## Guides

- **[operations.md](operations.md)** — Operations reference: setup, token rotation, DNS, Pages monitoring, security
- **[incidents.md](incidents.md)** — Troubleshooting: DNS failures, Pages errors, token issues, emergency recovery
- **[pages-setup.md](pages-setup.md)** — Step-by-step: dashboard configuration for GitHub integration and builds

## Quick Commands

**Check if Cloudflare is working:**
```sh
make smoke  # includes Pages deployment status
```

**Rotate API token:**
```sh
make rotate-secrets cloudflare
```

**Verify DNS:**
```sh
dig api.lumedina.dev
dig www.lumedina.dev
```

**Check Pages status:**
```sh
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/pages/projects/mbgc-web/deployments" \
  | jq '.result[0] | {status, created_on}'
```

## Infrastructure Context

| Component | Managed | Notes |
|---|---|---|
| Pages project | Terraform (shell only) | GitHub integration + build config must be done in CF dashboard |
| DNS records | Terraform | apex & www → Pages (proxied), api → Cloud Run (DNS-only) |
| API token | `infra/.env` (gitignored) | Validated by bootstrap.sh, rotated via make rotate-secrets |
| Token storage | GitHub Actions secrets | Synced by bootstrap.sh after validation |

See [../../infra/AGENTS.md](../../infra/AGENTS.md) for provider version, security posture, and known issues.
