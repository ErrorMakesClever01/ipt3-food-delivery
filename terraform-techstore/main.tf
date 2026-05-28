# ═════════════════════════════════════════════════════════════════════════════
# main.tf — Tech Store root module
# Region  : ap-south-1 (Mumbai)
# Domain  : tech-store.website  (Namecheap → Route53 nameservers)
# DockerHub: pranithaprabhakar
#
# EC2 Layout:
#   EC2-1  Public  Subnet A  — Frontend(:5173) + Backend(:4000) + Admin(:5174) + Jenkins(:8080)
#   EC2-2  Private Subnet A  — MongoDB(:27017)
#   EC2-3  Private Subnet B  — Prometheus(:9090) + Grafana(:3000) + CloudWatch Agent
#   Bastion Public Subnet B  — SSH jump host (t3.micro)
#
# DNS routing (host-header on ALB):
#   tech-store.website          → Frontend TG
#   www.tech-store.website      → Frontend TG
#   api.tech-store.website      → Backend  TG
#   admin.tech-store.website    → Admin    TG
# ═════════════════════════════════════════════════════════════════════════════

data "aws_caller_identity" "current" {}

# ── Auto-resolve latest Ubuntu 22.04 LTS AMI for ap-south-1 ─────────────
# If var.ami_id is set, use it; otherwise auto-resolve.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  # Use explicitly provided AMI or fall back to auto-resolved one
  resolved_ami = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1 — VPC: 2 public + 2 private subnets in ap-south-1a/b
# ─────────────────────────────────────────────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project               = var.project
  region                = var.region
  vpc_cidr              = "10.0.0.0/16"
  public_subnet_cidr_a  = "10.0.1.0/24" # EC2-1 (app) lives here
  public_subnet_cidr_b  = "10.0.2.0/24" # Bastion lives here
  private_subnet_cidr_a = "10.0.3.0/24" # EC2-2 (MongoDB)
  private_subnet_cidr_b = "10.0.4.0/24" # EC2-3 (Monitoring)
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 2 — Security Groups
# ─────────────────────────────────────────────────────────────────────────────
module "security_groups" {
  source = "./modules/security_groups"

  project       = var.project
  vpc_id        = module.vpc.vpc_id
  admin_ip      = var.admin_ip
  frontend_port = var.frontend_port
  admin_port    = var.admin_port
  backend_port  = var.backend_port
  mongodb_port  = var.mongodb_port
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 3 — Secrets Manager (MongoDB + Jenkins + DockerHub)
# Created before EC2 so instances can fetch secrets at boot
# ─────────────────────────────────────────────────────────────────────────────
module "secrets" {
  source = "./modules/secrets"

  project            = var.project
  mongodb_user       = var.mongodb_user
  mongodb_password   = var.mongodb_password
  mongodb_private_ip = "" # placeholder — app fetches host from secret at runtime
  jenkins_password   = var.jenkins_password
  dockerhub_user     = var.dockerhub_user
  dockerhub_password = var.dockerhub_password
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 4 — MongoDB EC2-2 (Private Subnet A, t3.small)
# ─────────────────────────────────────────────────────────────────────────────
module "mongodb" {
  source = "./modules/mongodb"

  project           = var.project
  ami_id            = local.resolved_ami
  instance_type     = var.db_instance_type # t3.small
  private_subnet_id = module.vpc.private_subnet_a_id
  mongodb_sg_id     = module.security_groups.mongodb_sg_id
  key_name          = var.key_name
  region            = var.region

  depends_on = [module.secrets]
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 5 — App Server EC2-1 (Public Subnet A, m7i-flex.large)
#          Runs: Frontend + Backend + Admin containers + Jenkins + node_exporter
# ─────────────────────────────────────────────────────────────────────────────
module "ec2" {
  source = "./modules/ec2"

  project              = var.project
  ami_id               = local.resolved_ami
  instance_type        = var.app_instance_type # m7i-flex.large
  public_subnet_id     = module.vpc.public_subnet_a_id
  app_sg_id            = module.security_groups.app_sg_id
  app_instance_profile = module.secrets.app_instance_profile_name
  key_name             = var.key_name
  region               = var.region
  dockerhub_user       = var.dockerhub_user
  frontend_port        = var.frontend_port
  admin_port           = var.admin_port
  backend_port         = var.backend_port
  domain_name          = var.domain_name

  depends_on = [module.secrets, module.mongodb]
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 6 — Bastion Host (Public Subnet B, t3.micro)
#          SSH jump server — reach private instances without opening them publicly
# ─────────────────────────────────────────────────────────────────────────────
module "bastion" {
  source = "./modules/bastion"

  project          = var.project
  ami_id           = local.resolved_ami
  instance_type    = var.bastion_instance_type
  public_subnet_id = module.vpc.public_subnet_b_id
  bastion_sg_id    = module.security_groups.bastion_sg_id
  key_name         = var.key_name
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 7 — DNS: Route53 Hosted Zone + ACM Certificate (no A records yet)
#          FIX: A records are created BELOW (after ALB exists) to avoid
#          the circular dependency dns↔alb
# ─────────────────────────────────────────────────────────────────────────────
module "dns" {
  source = "./modules/dns"

  project     = var.project
  domain_name = var.domain_name
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 8 — ALB (public subnets A+B)
#          Now that ACM cert exists, wire it in.
#          Routes traffic by Host header:
#            tech-store.website / www.*  → frontend TG
#            api.*                       → backend  TG
#            admin.*                     → admin    TG
# ─────────────────────────────────────────────────────────────────────────────
module "alb" {
  source = "./modules/alb"

  project             = var.project
  vpc_id              = module.vpc.vpc_id
  public_subnet_a_id  = module.vpc.public_subnet_a_id
  public_subnet_b_id  = module.vpc.public_subnet_b_id
  alb_sg_id           = module.security_groups.alb_sg_id
  app_instance_id     = module.ec2.app_instance_id
  acm_certificate_arn = module.dns.certificate_arn # ✅ cert exists before ALB
  domain_name         = var.domain_name
  frontend_port       = var.frontend_port
  admin_port          = var.admin_port
  backend_port        = var.backend_port

  depends_on = [module.dns, module.ec2]
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 9 — Route53 A records (created AFTER ALB to break the cycle)
#          FIX: These were previously inside the dns module causing a cycle.
# ─────────────────────────────────────────────────────────────────────────────

# tech-store.website → ALB
resource "aws_route53_record" "root" {
  zone_id = module.dns.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# www.tech-store.website → ALB
resource "aws_route53_record" "www" {
  zone_id = module.dns.hosted_zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# api.tech-store.website → ALB (routes to backend via host header)
resource "aws_route53_record" "api" {
  zone_id = module.dns.hosted_zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# admin.tech-store.website → ALB (routes to admin via host header)
resource "aws_route53_record" "admin_subdomain" {
  zone_id = module.dns.hosted_zone_id
  name    = "admin.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.alb_dns_name
    zone_id                = module.alb.alb_zone_id
    evaluate_target_health = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 10 — Monitoring EC2-3 (Private Subnet B, t3.small)
#           Prometheus + Grafana + CloudWatch Agent
# ─────────────────────────────────────────────────────────────────────────────
module "monitoring" {
  source = "./modules/monitoring"

  project           = var.project
  ami_id            = local.resolved_ami
  instance_type     = var.monitoring_instance_type # t3.small
  private_subnet_id = module.vpc.private_subnet_b_id
  monitoring_sg_id  = module.security_groups.monitoring_sg_id
  key_name          = var.key_name
  region            = var.region
  alert_email       = var.alert_email

  app_private_ip     = module.ec2.app_private_ip
  mongodb_private_ip = module.mongodb.mongodb_private_ip

  # For CloudWatch dashboards and alarms
  app_instance_id     = module.ec2.app_instance_id
  mongodb_instance_id = module.mongodb.mongodb_instance_id
  alb_arn             = module.alb.alb_arn

  depends_on = [module.ec2, module.mongodb]
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 11 — Security Audit (CloudTrail + Config + GuardDuty + SNS alerts)
# ─────────────────────────────────────────────────────────────────────────────
module "security_audit" {
  source = "./modules/security_audit"

  project     = var.project
  account_id  = data.aws_caller_identity.current.account_id
  alert_email = var.alert_email
}
