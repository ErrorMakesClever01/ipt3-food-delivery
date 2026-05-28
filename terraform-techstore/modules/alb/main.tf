# ─────────────────────────────────────────────────────────────────────────────
# modules/alb/main.tf
# Application Load Balancer — public subnets A + B
#
# FIX: Switched from path-based to HOST-HEADER routing:
#   tech-store.website + www.*  → Frontend TG  (default)
#   api.tech-store.website      → Backend  TG  (host-header rule)
#   admin.tech-store.website    → Admin    TG  (host-header rule)
#
# This is cleaner for separate subdomains and avoids path conflicts
# between the admin SPA and the frontend SPA.
#
# WAF: AWS Managed Rules (Common + IP Reputation + SQLi)
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = [var.public_subnet_a_id, var.public_subnet_b_id]

  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = { Name = "${var.project}-alb" }
}

# ── S3 bucket for ALB access logs ─────────────────────────────────────────
resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.project}-alb-logs-${substr(md5(var.project), 0, 8)}"
  force_destroy = true
  tags          = { Name = "${var.project}-alb-logs" }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "log-retention"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ALBAccessLogs"
      Effect = "Allow"
      Principal = {
        # AWS Elastic Load Balancing service account for ap-south-1
        AWS = "arn:aws:iam::718504428378:root"
      }
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.alb_logs.arn}/alb/AWSLogs/*"
    }]
  })
}

# ── Target Groups ──────────────────────────────────────────────────────────

resource "aws_lb_target_group" "frontend" {
  name        = "${var.project}-frontend-tg"
  port        = var.frontend_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = { Name = "${var.project}-frontend-tg" }
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.project}-backend-tg"
  port        = var.backend_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = { Name = "${var.project}-backend-tg" }
}

resource "aws_lb_target_group" "admin" {
  name        = "${var.project}-admin-tg"
  port        = var.admin_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  tags = { Name = "${var.project}-admin-tg" }
}

# ── Target Group Attachments — all to the same EC2-1 ─────────────────────

resource "aws_lb_target_group_attachment" "frontend" {
  target_group_arn = aws_lb_target_group.frontend.arn
  target_id        = var.app_instance_id
  port             = var.frontend_port
}

resource "aws_lb_target_group_attachment" "backend" {
  target_group_arn = aws_lb_target_group.backend.arn
  target_id        = var.app_instance_id
  port             = var.backend_port
}

resource "aws_lb_target_group_attachment" "admin" {
  target_group_arn = aws_lb_target_group.admin.arn
  target_id        = var.app_instance_id
  port             = var.admin_port
}

# ── HTTPS Listener ─────────────────────────────────────────────────────────
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  # Default action → Frontend (catches tech-store.website and www.*)
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

# ✅ FIX: Host-header rule — api.tech-store.website → Backend
resource "aws_lb_listener_rule" "backend_subdomain" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = ["api.${var.domain_name}"]
    }
  }
}

# ✅ FIX: Host-header rule — admin.tech-store.website → Admin
resource "aws_lb_listener_rule" "admin_subdomain" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.admin.arn
  }

  condition {
    host_header {
      values = ["admin.${var.domain_name}"]
    }
  }
}

# ── HTTP → HTTPS redirect ──────────────────────────────────────────────────
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ── WAF v2 — attached to ALB ───────────────────────────────────────────────
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "CommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AmazonIpReputationList"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "SQLiRuleSet"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project}-sqli-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project}-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.project}-waf" }
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
