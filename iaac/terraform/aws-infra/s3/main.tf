# todo add https only policy as a configurable option
# does this need to be a configurable option in helm also?

resource "aws_s3_bucket" "artifact_store" {
  bucket_prefix = var.bucket_prefix
  force_destroy = var.force_destroy_bucket
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact_store_encryption" {
  bucket = aws_s3_bucket.artifact_store.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "AES256"
    }
  }
}

resource "aws_secretsmanager_secret" "s3_secret" {
  count = var.use_secrets ? 1 : 0
  name_prefix = "s3-secret-"
  recovery_window_in_days = var.secret_recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "s3_secret_version" {
  count = var.use_secrets ? 1 : 0
  secret_id     = aws_secretsmanager_secret.s3_secret[0].id
  secret_string = jsonencode({
    accesskey = var.minio_aws_access_key_id
    secretkey = var.minio_aws_secret_access_key
  })
}

resource "aws_s3_bucket_public_access_block" "artifact_store_block_access" {
  bucket = aws_s3_bucket.artifact_store.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "artifact_store_versioning" {
  bucket = aws_s3_bucket.artifact_store.id
  versioning_configuration {
    status = "Enabled"
  }
}
