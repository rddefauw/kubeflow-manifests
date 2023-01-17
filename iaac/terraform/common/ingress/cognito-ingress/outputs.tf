output "kubeflow_platform_domain" {
  value = "kubeflow-${var.stage}.${data.aws_route53_zone.platform.name}"
}