# ─────────────────────────────────────────────────────────────────────────────
# outputs.tf — key values printed after terraform apply
# ─────────────────────────────────────────────────────────────────────────────

# ── Nameservers — copy to Namecheap ──────────────────────────────────────
output "namecheap_nameservers" {
  description = "STEP 1: Copy ALL 4 of these to Namecheap → Domain → Nameservers → Custom DNS"
  value       = module.dns.name_servers
}

# ── Live URLs ────────────────────────────────────────────────────────────
output "frontend_url" {
  description = "Frontend — public website"
  value       = "https://${var.domain_name}"
}

output "www_url" {
  description = "Frontend — www alias"
  value       = "https://www.${var.domain_name}"
}

output "admin_url" {
  description = "Admin panel"
  value       = "https://admin.${var.domain_name}"
}

output "api_url" {
  description = "Backend API base URL"
  value       = "https://api.${var.domain_name}"
}

# ── ALB ──────────────────────────────────────────────────────────────────
output "alb_dns_name" {
  description = "ALB DNS — all 4 Route53 A records already point here"
  value       = module.alb.alb_dns_name
}

# ── EC2 IPs ──────────────────────────────────────────────────────────────
output "app_server_public_ip" {
  description = "EC2-1 Elastic IP (Frontend + Backend + Admin + Jenkins)"
  value       = module.ec2.app_elastic_ip
}

output "app_server_private_ip" {
  description = "EC2-1 private IP"
  value       = module.ec2.app_private_ip
}

output "bastion_public_ip" {
  description = "Bastion Elastic IP — SSH jump host"
  value       = module.bastion.bastion_public_ip
}

output "mongodb_private_ip" {
  description = "EC2-2 MongoDB private IP"
  value       = module.mongodb.mongodb_private_ip
}

output "monitoring_private_ip" {
  description = "EC2-3 Monitoring private IP (Prometheus + Grafana)"
  value       = module.monitoring.monitoring_private_ip
}

# ── VPC ──────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

# ── SSH Commands ─────────────────────────────────────────────────────────
output "ssh_app_server" {
  description = "SSH directly to App Server (public IP)"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${module.ec2.app_elastic_ip}"
}

output "ssh_bastion" {
  description = "SSH to Bastion host"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${module.bastion.bastion_public_ip}"
}

output "ssh_mongodb_via_bastion" {
  description = "SSH to MongoDB server via bastion jump host"
  value       = "ssh -J ubuntu@${module.bastion.bastion_public_ip} ubuntu@${module.mongodb.mongodb_private_ip} -i ${var.key_name}.pem"
}

output "ssh_monitoring_via_bastion" {
  description = "SSH to Monitoring server via bastion jump host"
  value       = "ssh -J ubuntu@${module.bastion.bastion_public_ip} ubuntu@${module.monitoring.monitoring_private_ip} -i ${var.key_name}.pem"
}

# ── Grafana Access ────────────────────────────────────────────────────────
output "grafana_tunnel_command" {
  description = "SSH tunnel to access Grafana at http://localhost:3000"
  value       = "ssh -L 3000:${module.monitoring.monitoring_private_ip}:3000 ubuntu@${module.bastion.bastion_public_ip} -i ${var.key_name}.pem -N"
}

output "prometheus_tunnel_command" {
  description = "SSH tunnel to access Prometheus at http://localhost:9090"
  value       = "ssh -L 9090:${module.monitoring.monitoring_private_ip}:9090 ubuntu@${module.bastion.bastion_public_ip} -i ${var.key_name}.pem -N"
}

# ── Jenkins ────────────────────────────────────────────────────────────────
output "jenkins_url" {
  description = "Jenkins UI — open in browser (only your admin IP can reach port 8080)"
  value       = "http://${module.ec2.app_elastic_ip}:8080"
}

# ── Secrets Manager ARNs (for Jenkins pipelines) ────────────────────────
output "mongodb_secret_arn" {
  description = "AWS Secrets Manager ARN — MongoDB credentials"
  value       = module.secrets.mongodb_secret_arn
}

output "dockerhub_secret_arn" {
  description = "AWS Secrets Manager ARN — Docker Hub credentials"
  value       = module.secrets.dockerhub_secret_arn
}
