# ─────────────────────────────────────────────────────────────────────────────
# modules/ec2/main.tf
# EC2-1 — Public Subnet A (m7i-flex.large)
# Runs: Frontend + Backend + Admin (Docker) + Jenkins + node_exporter
#
# FIX: Added aws_eip for the app server (was only on bastion before)
# FIX: Fetches secrets by project name (not hardcoded)
# FIX: domain_name injected for CORS/env config
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "app" {
  ami                         = var.ami_id
  instance_type               = var.instance_type # m7i-flex.large
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.app_sg_id]
  iam_instance_profile        = var.app_instance_profile
  key_name                    = var.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 50 # Increased for Docker images + Jenkins
    volume_type           = "gp3"
    throughput            = 125
    encrypted             = true
    delete_on_termination = false
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/userdata.log 2>&1

    echo "=== Tech Store App Server Bootstrap ==="
    apt-get update -y
    apt-get install -y docker.io docker-compose awscli jq curl

    # Enable Docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    # ── Fetch secrets from AWS Secrets Manager ───────────────────────────
    REGION="${var.region}"
    PROJECT="${var.project}"

    MONGO_SECRET=$(aws secretsmanager get-secret-value \
      --secret-id "$PROJECT/mongodb/credentials" \
      --region "$REGION" --query SecretString --output text)

    DOCKER_SECRET=$(aws secretsmanager get-secret-value \
      --secret-id "$PROJECT/dockerhub/credentials" \
      --region "$REGION" --query SecretString --output text)

    MONGO_USER=$(echo "$MONGO_SECRET" | jq -r '.username')
    MONGO_PASS=$(echo "$MONGO_SECRET" | jq -r '.password')
    MONGO_HOST=$(echo "$MONGO_SECRET" | jq -r '.host')
    MONGO_URI="mongodb://$MONGO_USER:$MONGO_PASS@$MONGO_HOST:${var.mongodb_port}/fooddelivery?authSource=admin"

    DOCKER_USER=$(echo "$DOCKER_SECRET" | jq -r '.username')
    DOCKER_PASS=$(echo "$DOCKER_SECRET" | jq -r '.password')

    # Docker Hub login
    echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin

    # ── Write shared environment file ────────────────────────────────────
    cat > /home/ubuntu/.env << ENVEOF
MONGO_URI=$MONGO_URI
BACKEND_PORT=${var.backend_port}
FRONTEND_PORT=${var.frontend_port}
ADMIN_PORT=${var.admin_port}
VITE_API_URL=https://api.${var.domain_name}
VITE_ADMIN_URL=https://admin.${var.domain_name}
NODE_ENV=production
ENVEOF
    chmod 600 /home/ubuntu/.env

    # ── Pull & run containers ────────────────────────────────────────────
    docker pull ${var.dockerhub_user}/food-delivery-frontend:latest
    docker pull ${var.dockerhub_user}/food-delivery-backend:latest
    docker pull ${var.dockerhub_user}/food-delivery-admin:latest

    docker run -d --name frontend \
      --env-file /home/ubuntu/.env \
      -p ${var.frontend_port}:${var.frontend_port} \
      --restart unless-stopped \
      --log-driver awslogs \
      --log-opt awslogs-region="$REGION" \
      --log-opt awslogs-group="/${var.project}/frontend" \
      --log-opt awslogs-create-group=true \
      ${var.dockerhub_user}/food-delivery-frontend:latest

    docker run -d --name backend \
      --env-file /home/ubuntu/.env \
      -p ${var.backend_port}:${var.backend_port} \
      --restart unless-stopped \
      --log-driver awslogs \
      --log-opt awslogs-region="$REGION" \
      --log-opt awslogs-group="/${var.project}/backend" \
      --log-opt awslogs-create-group=true \
      ${var.dockerhub_user}/food-delivery-backend:latest

    docker run -d --name admin \
      --env-file /home/ubuntu/.env \
      -p ${var.admin_port}:${var.admin_port} \
      --restart unless-stopped \
      --log-driver awslogs \
      --log-opt awslogs-region="$REGION" \
      --log-opt awslogs-group="/${var.project}/admin" \
      --log-opt awslogs-create-group=true \
      ${var.dockerhub_user}/food-delivery-admin:latest

    # ── Install Jenkins ──────────────────────────────────────────────────
    apt-get install -y openjdk-17-jdk
    wget -q -O /usr/share/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
      https://pkg.jenkins.io/debian-stable binary/" | \
      tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    apt-get update -y
    apt-get install -y jenkins
    systemctl enable jenkins
    systemctl start jenkins

    # Add jenkins user to docker group so Jenkins pipelines can run docker
    usermod -aG docker jenkins

    # ── Install Node Exporter (for Prometheus scraping) ──────────────────
    NODE_EXPORTER_VER="1.8.1"
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VER}/node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
    tar xzf "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
    cp "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64/node_exporter" /usr/local/bin/
    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

    cat > /etc/systemd/system/node_exporter.service << SVCEOF
[Unit]
Description=Prometheus Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable node_exporter
    systemctl start node_exporter

    echo "=== Bootstrap complete ==="
  EOF

  tags = { Name = "${var.project}-app-server" }
}

# ── Elastic IP for App Server ──────────────────────────────────────────────
# FIX: Previously missing — app server only had a dynamic public IP.
# This ensures the IP is stable across reboots and is used in outputs.
resource "aws_eip" "app" {
  instance   = aws_instance.app.id
  domain     = "vpc"
  depends_on = [aws_instance.app]
  tags       = { Name = "${var.project}-app-eip" }
}

# ── CloudWatch Log Groups for Docker containers ───────────────────────────
resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/${var.project}/frontend"
  retention_in_days = 30
  tags              = { Name = "${var.project}-frontend-logs" }
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/${var.project}/backend"
  retention_in_days = 30
  tags              = { Name = "${var.project}-backend-logs" }
}

resource "aws_cloudwatch_log_group" "admin" {
  name              = "/${var.project}/admin"
  retention_in_days = 30
  tags              = { Name = "${var.project}-admin-logs" }
}
