output "s3_bucket_name" {
  value       = aws_s3_bucket.velero_store.id
  description = "The name of the created S3 bucket"
}