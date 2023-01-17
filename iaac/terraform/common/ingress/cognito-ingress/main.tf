data "aws_route53_zone" "platform" {
  name = var.aws_route53_subdomain_zone_name
}

# Implement ingress in terraform instead of using chart to use features like wait_for_load_balancer
resource "kubernetes_ingress_v1" "istio_ingress" {
  wait_for_load_balancer = true

  metadata {
    annotations = {
        "alb.ingress.kubernetes.io/auth-type": "cognito",
        "alb.ingress.kubernetes.io/auth-idp-cognito": "{\"UserPoolArn\":\"${var.cognito_user_pool_arn}\",\"UserPoolClientId\":\"${var.cognito_app_client_id}\", \"UserPoolDomain\":\"${var.cognito_user_pool_domain}\"}"
        "alb.ingress.kubernetes.io/certificate-arn": "${var.certificate_arn}"
        "alb.ingress.kubernetes.io/listen-ports": "[{\"HTTPS\":443}]",
        "alb.ingress.kubernetes.io/load-balancer-attributes": "routing.http.drop_invalid_header_fields.enabled=true",
        "alb.ingress.kubernetes.io/scheme": "${var.load_balancer_scheme}"
    }
    name = "istio-ingress"
    namespace = "istio-system"
  }

  spec {
    ingress_class_name = "alb"
    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = "istio-ingressgateway"
              port {
                number = 80
              }
            }
          }
          path_type = "ImplementationSpecific"
        }
      }
    }
  }
}

# Import by tag because ALB cannot be imported by DNS provided by output of Ingress status
data "aws_lb" "istio_ingress" {
  tags = {
    "elbv2.k8s.aws/cluster" = var.cluster_name
    "ingress.k8s.aws/stack" = "istio-system/istio-ingress"
  }
  depends_on = [
    kubernetes_ingress_v1.istio_ingress
  ]
}

resource "aws_route53_record" "cname_record" {
  allow_overwrite = true
  zone_id         = data.aws_route53_zone.platform.zone_id
  name            = "kubeflow-${var.stage}.${data.aws_route53_zone.platform.name}"
  type            = "CNAME"
  records         = [data.aws_lb.istio_ingress.dns_name]
  ttl             = "300"
}