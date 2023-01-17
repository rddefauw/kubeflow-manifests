variable "user_pool_id" {
  description = "Cognito User Pool ID"
  type        = string
}

variable "aws_route53_subdomain_zone_name" {
  description = "SUBDOMAIN Route 53 hosted zone name(e.g. platform.example.com) which will be used for Kubeflow Platform. Must match exactly one zone"
  type        = string
}

variable "stage" {
  description = "Deployment stage"
  type = string
  default = "test"
}