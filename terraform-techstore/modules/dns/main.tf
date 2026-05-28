# ─────────────────────────────────────────────────────────────────────────────
# modules/dns/main.tf
# Creates: Route53 Hosted Zone + ACM SSL Certificate + DNS validation records
#
# FIX: Route53 A records (root, www, api, admin) are NOT here anymore.
#      They are created in the ROOT main.tf AFTER the ALB is built.
#      This breaks the circular dependency: dns depends on alb depends on dns.
#
# Deployment flow:
#   1. This module runs → zone + cert created → cert validated via DNS
#   2. ALB module runs → uses certificate_arn from this module
#   3. Root main.tf creates A records pointing to ALB DNS
#   4. You copy the 4 name_servers to Namecheap
# ─────────────────────────────────────────────────────────────────────────────

# ── Route53 Hosted Zone ────────────────────────────────────────────────────
resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "Managed by Terraform — ${var.project}"

  tags = { Name = "${var.project}-hosted-zone" }
}

# ── ACM SSL Certificate (covers root + all subdomains) ────────────────────
resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"] # covers api.*, admin.*, www.*
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.project}-ssl-cert" }
}

# ── DNS Validation CNAME records ───────────────────────────────────────────
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

# ── Wait for ACM certificate to be validated ───────────────────────────────
resource "aws_acm_certificate_validation" "main" {
  certificate_arn = aws_acm_certificate.main.arn

  validation_record_fqdns = [
    for record in aws_route53_record.cert_validation : record.fqdn
  ]
}
