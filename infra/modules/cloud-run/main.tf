resource "google_cloud_run_v2_service" "this" {
  name                = var.name
  location            = var.region
  project             = var.project
  ingress             = var.public ? "INGRESS_TRAFFIC_ALL" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
  labels              = var.labels
  deletion_protection = var.deletion_protection

  template {
    service_account = var.service_account != "" ? var.service_account : null

    scaling {
      min_instance_count = 0
      max_instance_count = var.max_instances
    }

    containers {
      # Placeholder — each service repo's CI/CD pushes the real image.
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }

  lifecycle {
    # Image, env vars, resources, and scaling are owned by each service repo's
    # CI/CD (`gcloud run deploy` flags). Ignoring the entire template prevents
    # Terraform from overwriting the live container spec when updating other
    # fields (labels, ingress, service_account, deletion_protection).
    # See: https://cloud.google.com/run/docs/troubleshooting#container-failed-to-start
    ignore_changes = [
      template,
      client,
      client_version,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  count    = var.public ? 1 : 0
  project  = var.project
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "invokers" {
  for_each = toset(var.invokers)
  project  = var.project
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${each.value}"
}
