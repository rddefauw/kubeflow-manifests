variable "force_destroy_bucket" {
  type = bool
  description = "Destroys s3 bucket even when the bucket is not empty"
  default = false
}
variable "eks_cluster_id" {
  type = string
}
variable "eks_cluster_endpoint" {
  type = string
}
variable "oidc_provider" {
  type = string
}
variable "eks_cluster_version" {
  type = string
}
variable "eks_cluster_certificate_authority_data" {
  type = string
}
variable "region" {
  type = string
}