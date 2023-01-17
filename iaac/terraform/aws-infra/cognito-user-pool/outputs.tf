output "app_client_id" {
  description = "Cognito App client Id"
  value       = aws_cognito_user_pool_client.platform.id
}