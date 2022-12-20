variable "velero_role_name" {
  description = "Role name for Velero service account"
  type        = string
}

variable "velero_bucket" {
  description = "Name of S3 bucket used for Velero"
  type        = string
}