# ─────────────────────────────────────────────────────────────────────────────
# variables.tf — root module variables
# ─────────────────────────────────────────────────────────────────────────────

variable "project" {
  type        = string
  description = "Project name — used as prefix for all resource names"
}

variable "region" {
  type        = string
  description = "AWS region"
  default     = "ap-south-1"
}

# ── AMI ────────────────────────────────────────────────────────────────────
# Leave empty to auto-resolve Ubuntu 22.04 LTS in the selected region via data source.
# Or specify an explicit AMI ID to pin the version.
variable "ami_id" {
  type        = string
  description = "Ubuntu 22.04 LTS AMI ID for ap-south-1 (leave blank to auto-resolve)"
  default     = ""
}

# ── Instance Types ──────────────────────────────────────────────────────────
variable "app_instance_type" {
  type        = string
  description = "App server EC2 instance type (EC2-1: Frontend + Backend + Admin + Jenkins)"
  default     = "m7i-flex.large"
}

variable "db_instance_type" {
  type        = string
  description = "MongoDB EC2 instance type (EC2-2)"
  default     = "t3.small"
}

variable "monitoring_instance_type" {
  type        = string
  description = "Monitoring EC2 instance type (EC2-3: Prometheus + Grafana)"
  default     = "t3.small"
}

variable "bastion_instance_type" {
  type        = string
  description = "Bastion host instance type"
  default     = "t3.micro"
}

# ── SSH Key ────────────────────────────────────────────────────────────────
variable "key_name" {
  type        = string
  description = "Name of an existing EC2 Key Pair for SSH access"
}

# ── Domain ────────────────────────────────────────────────────────────────
variable "domain_name" {
  type        = string
  description = "Root domain name purchased from Namecheap (e.g. tech-store.website)"
}

# ── Docker Hub ─────────────────────────────────────────────────────────────
variable "dockerhub_user" {
  type        = string
  description = "Docker Hub username for pulling images"
}

variable "dockerhub_password" {
  type        = string
  sensitive   = true
  description = "Docker Hub password / access token for pulling images"
}

# ── Networking ────────────────────────────────────────────────────────────
variable "admin_ip" {
  type        = string
  description = "Your public IP in CIDR notation (e.g. 1.2.3.4/32) — allows SSH and Jenkins access"
}

# ── MongoDB Credentials ────────────────────────────────────────────────────
variable "mongodb_user" {
  type        = string
  description = "MongoDB application username"
  default     = "fooddelivery_user"
}

variable "mongodb_password" {
  type        = string
  sensitive   = true
  description = "MongoDB application password — use a strong random value"
}

# ── Jenkins ────────────────────────────────────────────────────────────────
variable "jenkins_password" {
  type        = string
  sensitive   = true
  description = "Jenkins admin password"
}

# ── Alert Email ────────────────────────────────────────────────────────────
variable "alert_email" {
  type        = string
  description = "Email address to receive CloudWatch and security alerts"
}

# ── Application Ports ─────────────────────────────────────────────────────
variable "frontend_port" {
  type    = number
  default = 5173
}

variable "admin_port" {
  type    = number
  default = 5174
}

variable "backend_port" {
  type    = number
  default = 4000
}

variable "mongodb_port" {
  type    = number
  default = 27017
}
