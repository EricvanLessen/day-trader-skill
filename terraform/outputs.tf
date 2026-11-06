output "image" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.monitor.repository_id}/day-trader-monitor:${var.image_tag}"
}
output "namespace" {
  value = kubernetes_namespace_v1.monitor.metadata[0].name
}
output "port_forward" {
  value = "kubectl -n ${var.namespace} port-forward svc/day-trader-monitor 8080:8080"
}
