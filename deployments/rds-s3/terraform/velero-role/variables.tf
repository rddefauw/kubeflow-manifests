variable "velero_role_name" {
  description = "Role name for Velero service account"
  type        = string
}

variable "force_destroy_bucket" {
  type = bool
  description = "Destroys s3 bucket even when the bucket is not empty"
  default = false
}