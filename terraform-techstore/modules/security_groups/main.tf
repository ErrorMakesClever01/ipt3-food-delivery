# ─────────────────────────────────────────────────────────────────────────────
# modules/security_groups/main.tf
# Chain: Internet → ALB SG → App SG → MongoDB SG
#        Monitoring SG → (scrapes) App SG port 9100, MongoDB SG port 9100
#
# FIX: Previously monitoring SG had ingress FROM app SG on 9090/9100.
#      That was backwards. Prometheus lives on monitoring and REACHES OUT
#      to node_exporter on app and mongodb. So:
#        ✅ app_sg  gets ingress 9100 from monitoring_sg
#        ✅ mongodb gets ingress 9100 from monitoring_sg
#        ✅ monitoring SG only needs egress (already 0.0.0.0/0) + SSH from bastion
# ─────────────────────────────────────────────────────────────────────────────

# ── ALB Security Group ────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "ALB - HTTPS inbound, HTTP redirect"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP redirect to HTTPS"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-alb-sg" }
}

# ── Bastion Security Group ─────────────────────────────────────────────────
resource "aws_security_group" "bastion" {
  name        = "${var.project}-bastion-sg"
  description = "Bastion - SSH from admin IP only"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-bastion-sg" }
}

# ── Monitoring Security Group ──────────────────────────────────────────────
# Created before app/mongodb SGs so they can reference it in their ingress rules
resource "aws_security_group" "monitoring" {
  name        = "${var.project}-monitoring-sg"
  description = "Monitoring - Prometheus+Grafana; access via SSH tunnel through bastion"
  vpc_id      = var.vpc_id

  # Grafana UI — only reachable via SSH tunnel from bastion
  ingress {
    description     = "Grafana from bastion (SSH tunnel)"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Prometheus UI — only reachable via SSH tunnel from bastion
  ingress {
    description     = "Prometheus from bastion (SSH tunnel)"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # Prometheus scrapes node_exporter on remote hosts — outbound covers this.
  # No special inbound needed beyond the above.

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-monitoring-sg" }
}

# ── App Server Security Group ──────────────────────────────────────────────
resource "aws_security_group" "app" {
  name        = "${var.project}-app-sg"
  description = "App server - containers from ALB, Jenkins from admin IP, metrics from monitoring"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Frontend port from ALB"
    from_port       = var.frontend_port
    to_port         = var.frontend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Backend port from ALB"
    from_port       = var.backend_port
    to_port         = var.backend_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Admin port from ALB"
    from_port       = var.admin_port
    to_port         = var.admin_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Jenkins — only your admin IP (NOT via ALB; Jenkins should NOT be internet-public)
  ingress {
    description = "Jenkins UI from admin IP only"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # SSH — direct from admin IP (app server is public so direct SSH is fine)
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # ✅ FIX: node_exporter scrape - Prometheus (on monitoring SG) pulls metrics
  ingress {
    description     = "node_exporter scrape from Prometheus (monitoring server)"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-app-sg" }
}

# ── MongoDB Security Group ─────────────────────────────────────────────────
resource "aws_security_group" "mongodb" {
  name        = "${var.project}-mongodb-sg"
  description = "MongoDB - only app server and monitoring can connect"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MongoDB from app server only"
    from_port       = var.mongodb_port
    to_port         = var.mongodb_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "SSH from bastion for maintenance"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # ✅ FIX: node_exporter scrape - Prometheus (on monitoring SG) pulls metrics
  ingress {
    description     = "node_exporter scrape from Prometheus (monitoring server)"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-mongodb-sg" }
}
