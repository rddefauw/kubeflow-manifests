resource "aws_security_group" "allow_tls" {
  name        = "allow_tls"
  description = "Allow TLS inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description      = "TLS from anywhere"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

resource "aws_lb" "cluster_redirect" {
  name_name_prefix = "kf-redirect"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_tls.id]
  subnets            = var.subnet_ids

}

resource "aws_lb_target_group" "empty_tg" {
  name_prefix     = "redirect-empty-tg"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = var.vpc_id
}

resource "aws_lb_listener" "redirector" {
  load_balancer_arn = aws_lb.cluster_redirect.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.empty_tg.arn
  }
}

resource "aws_lb_listener_rule" "redirect_to_kf" {
  listener_arn = aws_lb_listener.redirector.arn
  priority = 1

  action {
    type = "redirect"

    redirect {
      host = var.redirect_to
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values           = [var.redirect_from]
    }
  }
}

resource "aws_route53_record" "redirect_record" {
  zone_id         = var.zone_id
  allow_overwrite = true
  name    = var.redirect_from
  type    = "A"

  alias {
    name                   = aws_lb.cluster_redirect.dns_name
    zone_id                = aws_lb.cluster_redirect.zone_id
    evaluate_target_health = false
  }
}