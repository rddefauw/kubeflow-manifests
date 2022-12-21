output "s3_secret_name" {
    value = aws_secretsmanager_secret.s3_secret.name
}

output "s3_bucket_name" {
    value = aws_s3_bucket.artifact_store.id
}

output "s3_bucket_arn" {
    value = aws_s3_bucket.artifact_store.arn
}