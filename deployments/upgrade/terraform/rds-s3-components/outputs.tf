output "kubelow_platform_domain" {
    value = try(module.ingress_cognito[0].kubelow_platform_domain, null)
}