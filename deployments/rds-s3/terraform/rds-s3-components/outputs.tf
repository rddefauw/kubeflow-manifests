output "rds_endpoint" {
  value       = try(module.rds[0].rds_endpoint, null)
  description = "The address of the RDS endpoint"
}

output "s3_bucket_name" {
  value       = try(module.s3[0].s3_bucket_name, null)
  description = "The name of the created S3 bucket"
}

output "rds_secret_name" {
  value       = try(module.rds[0].rds_secret_name, null)
  description = "The name of the RDS secret"
}

output "s3_secret_name" {
  value       = try(module.s3[0].s3_secret_name, null)
  description = "The name of the S3 secret"
}