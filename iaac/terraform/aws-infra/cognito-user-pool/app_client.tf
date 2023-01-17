resource "aws_cognito_user_pool_client" "platform" {
  name            = "kubeflow-${var.stage}"
  user_pool_id    = var.user_pool_id
  generate_secret = true

  callback_urls = ["https://kubeflow-${var.stage}.${var.aws_route53_subdomain_zone_name}/oauth2/idpresponse"]
  logout_urls   = ["https://kubeflow-${var.stage}.${var.aws_route53_subdomain_zone_name}"]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile", "aws.cognito.signin.user.admin"]
  supported_identity_providers         = ["COGNITO"]
}