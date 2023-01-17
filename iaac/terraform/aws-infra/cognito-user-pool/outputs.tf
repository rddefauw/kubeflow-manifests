output "app_client_id" {
  description = "Cognito App client Id"
  value       = aws_cognito_user_pool_client.platform.id
}
output "logout_url" {
  description = "Logout URL"
  value       = "https://${var.cognito_user_pool_domain}/logout?client_id=${aws_cognito_user_pool_client.platform.id}&logout_uri=https://kubeflow-${var.stage}.${var.aws_route53_subdomain_zone_name}}"
}