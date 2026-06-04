# Troubleshooting Runbook

Common issues and their fixes for the mbgc infrastructure.

## Deployment

- [Production Deploy](prod-deploy.md) — step-by-step release checklist (migrations → merge → verify)

## Troubleshooting Categories

- [Cloudflare](cloudflare/) — DNS, Pages, token management, setup
- [Cloud Run](cloud-run/)
- [Terraform](terraform/)
- [Supabase](supabase/)
- [CI/CD](ci-cd/)

## How to use

1. Search by error message: `rg "error text" docs/runbook/`
2. Browse by category
3. Add new entries as you encounter issues

## Entry format

Each issue file should contain:
- Symptoms (error messages, logs)
- Root cause
- Fix (immediate steps)
- Prevention (long-term mitigation)
- Related files/links
