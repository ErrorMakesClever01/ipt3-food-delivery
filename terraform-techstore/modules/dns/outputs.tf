output "certificate_arn" {
  value       = aws_acm_certificate_validation.main.certificate_arn
  description = "Validated ACM certificate ARN — pass to ALB module"
}

output "hosted_zone_id" {
  value       = aws_route53_zone.main.zone_id
  description = "Route53 Hosted Zone ID — used to create A records in root main.tf"
}

output "name_servers" {
  value       = aws_route53_zone.main.name_servers
  description = "IMPORTANT: Copy all 4 of these to Namecheap → Domain → Custom Nameservers"
}
