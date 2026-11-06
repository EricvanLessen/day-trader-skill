variable "project_id" {
  type = string
}
variable "region" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "cluster_location" {
  type = string
}
variable "namespace" {
  type    = string
  default = "rhodium-trading"
}
variable "artifact_repository" {
  type    = string
  default = "day-trader"
}
variable "image_tag" {
  type    = string
  default = "v1"
}
variable "claude_model" {
  type    = string
  default = "claude-sonnet-4-5"
}
variable "auto_scan" {
  type    = bool
  default = true
}
