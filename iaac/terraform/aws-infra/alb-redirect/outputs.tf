output "alb_dns" {
    value = aws_lb.cluster_redirect.dns_name
}
output "redirect_dns" {
    value = aws_route53_record.redirect_record.name
}