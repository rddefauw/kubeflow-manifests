variable "minio_aws_access_key_id" {
  type        = string
  description = "AWS access key ID to authenticate minio client"
}

variable "minio_aws_secret_access_key" {
  type        = string
  description = "AWS secret access key to authenticate minio client"
}

variable "secret_recovery_window_in_days" {
  type = number
  default = 7
}

variable "force_destroy_bucket" {
  type = bool
  description = "Destroys s3 bucket even when the bucket is not empty"
  default = false
}

variable "use_secrets" {
  type = bool
  description = "Store access data in Secrets Manager"
  default = true
}

variable "bucket_prefix" {
  type = string
  description = "Prefix for S3 bucket name"
  default = "kf-artifact-store-"
}