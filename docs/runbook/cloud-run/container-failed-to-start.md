# Cloud Run Container Failed to Start

## Symptoms

```
Error: Error waiting for Updating Service: Error code 9, message: The user-provided container failed to start and listen on the port defined provided by the PORT=8080 environment variable within the allocated timeout.
```

Container logs show:
```
ERROR required env var not set key=DATABASE_URL
Container called exit(1).
Default STARTUP TCP probe failed 1 time consecutively for container "mbgc-api-1" on port 8080.
```

## Root Cause

Terraform `ignore_changes` on individual template fields (`image`, `env`, `resources`, `scaling`) does **not** preserve those values when Terraform updates other fields (labels, ingress, service_account, deletion_protection). The provider sends the template as it exists in state — which has the placeholder `us-docker.pkg.dev/cloudrun/container/hello` image and zero env vars — creating a broken revision.

## Fix

### Immediate

Re-run the API deploy workflow to push a real revision with env vars:

```sh
gh workflow run deploy.yml --repo LuisMedinaG/mbgc --ref main
```

Or roll traffic back to the last healthy revision:

```sh
gcloud run services update-traffic mbgc-api \
  --region us-central1 --project myboardgamecollection-494214 \
  --to-revisions mbgc-api-00001-XXX=100
```

### Prevention

Use `ignore_changes = [template]` instead of granular field ignores. See `infra/modules/cloud-run/main.tf`.

## Related

- `infra/modules/cloud-run/main.tf` — lifecycle block
- `infra/AGENTS.md` — Cloud Run deployment notes
- [GCP Troubleshooting Guide](https://cloud.google.com/run/docs/troubleshooting#container-failed-to-start)
