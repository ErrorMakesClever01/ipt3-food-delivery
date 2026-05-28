# ─────────────────────────────────────────────────────────────────────────────
# terraform.tfvars — fill in real values before running terraform apply
# ─────────────────────────────────────────────────────────────────────────────

project = "tech-store"
region  = "ap-south-1" # Mumbai

# AMI — Ubuntu 22.04 LTS ap-south-1 (Canonical official)
# Leave as-is; versions.tf uses a data source to auto-resolve the latest Ubuntu 22.04
# Or pin to a specific AMI: ami_id = "ami-0f5ee92e2d63afc18"
ami_id = ""

# ── Instance Types ──────────────────────────────────────────────────────────
app_instance_type        = "m7i-flex.large" # EC2-1: Frontend + Backend + Admin + Jenkins
db_instance_type         = "t3.small"       # EC2-2: MongoDB
monitoring_instance_type = "t3.small"       # EC2-3: Prometheus + Grafana + CloudWatch Agent
bastion_instance_type    = "t3.micro"       # Bastion jump host

# ── SSH Key ────────────────────────────────────────────────────────────────
# Create this key pair in AWS Console → EC2 → Key Pairs → ap-south-1 BEFORE applying
key_name = "techstore-key"

# ── Domain ────────────────────────────────────────────────────────────────
domain_name = "tech-store.website"
# After terraform apply, copy the 4 Route53 nameservers (shown in outputs)
# to Namecheap → Domain → Nameservers → Custom DNS

# ── Docker Hub ─────────────────────────────────────────────────────────────
dockerhub_user     = "pranithaprabhakar"
dockerhub_password = "Pranithap2020."

# ── Your Admin IP ──────────────────────────────────────────────────────────
# Google "what is my ip" and paste it here
admin_ip = "115.97.69.72/32"

# ── MongoDB Credentials ────────────────────────────────────────────────────
mongodb_user     = "fooddelivery_user"
mongodb_password = "DbHelloaws@1"

# ── Jenkins ────────────────────────────────────────────────────────────────
jenkins_password = "JenkinsHelloaws@1"

# ── Alerts ────────────────────────────────────────────────────────────────
alert_email = "pranithap68@gmail.com"

# ── Ports (match your docker-compose / Dockerfile EXPOSE values) ──────────
frontend_port = 5173
admin_port    = 5174
backend_port  = 4000
mongodb_port  = 27017
