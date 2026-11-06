terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "current" {}

data "google_container_cluster" "rhodium" {
  name     = var.cluster_name
  location = var.cluster_location
  project  = var.project_id
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.rhodium.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.rhodium.master_auth[0].cluster_ca_certificate)
}

resource "google_artifact_registry_repository" "monitor" {
  location      = var.region
  repository_id = var.artifact_repository
  description   = "Day Trader Monitor container images"
  format        = "DOCKER"
}

resource "kubernetes_namespace_v1" "monitor" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_deployment_v1" "monitor" {
  wait_for_rollout = false
  metadata {
    name      = "day-trader-monitor"
    namespace = kubernetes_namespace_v1.monitor.metadata[0].name
    labels    = { app = "day-trader-monitor" }
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "day-trader-monitor" }
    }
    template {
      metadata {
        labels = { app = "day-trader-monitor" }
      }
      spec {
        container {
          name              = "monitor"
          image             = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.monitor.repository_id}/day-trader-monitor:${var.image_tag}"
          image_pull_policy = "Always"
          port {
            container_port = 8080
          }
          env {
            name = "ANTHROPIC_API_KEY"
            value_from {
              secret_key_ref {
                name = "day-trader-anthropic"
                key  = "api-key"
              }
            }
          }
          env {
            name  = "CLAUDE_MODEL"
            value = var.claude_model
          }
          env {
            name  = "AUTO_SCAN"
            value = tostring(var.auto_scan)
          }
          env {
            name  = "TRADER_DATA_DIR"
            value = "/data"
          }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "1000m", memory = "512Mi" }
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 10
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 30
          }
        }
        volume {
          name = "data"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "monitor" {
  metadata {
    name      = "day-trader-monitor"
    namespace = kubernetes_namespace_v1.monitor.metadata[0].name
  }
  spec {
    selector = { app = "day-trader-monitor" }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}
