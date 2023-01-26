output "kubelow_platform_domain" {
    value = try(module.ingress_cognito[0].kubeflow_platform_domain, null)
}