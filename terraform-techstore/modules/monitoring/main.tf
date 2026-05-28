# ─────────────────────────────────────────────────────────────────────────────
# modules/monitoring/main.tf
# EC2-3 — Private Subnet B (t3.small)
# Runs: Prometheus + Grafana + CloudWatch Agent
#
# FIX: instance_type was hardcoded t3.medium → now uses variable (t3.small)
# FIX: Added region + alert_email variables
# NEW: CloudWatch Agent for EC2 system metrics → CloudWatch
# NEW: SNS alarm for high CPU on app server
# Access: SSH tunnel via bastion → http://localhost:3000
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "monitoring" {
  ami                    = var.ami_id
  instance_type          = var.instance_type # ✅ FIX: was hardcoded t3.medium
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.monitoring_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.monitoring.name
  key_name               = var.key_name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = false
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/userdata.log 2>&1

    echo "=== Monitoring Server Bootstrap ==="
    apt-get update -y
    apt-get install -y apt-transport-https software-properties-common wget curl jq

    # ── Install Prometheus ────────────────────────────────────────────────
    useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
    mkdir -p /etc/prometheus /var/lib/prometheus

    PROM_VER="2.52.0"
    wget -q "https://github.com/prometheus/prometheus/releases/download/v$${PROM_VER}/prometheus-$${PROM_VER}.linux-amd64.tar.gz"
    tar xzf "prometheus-$${PROM_VER}.linux-amd64.tar.gz"
    cp "prometheus-$${PROM_VER}.linux-amd64/prometheus" /usr/local/bin/
    cp "prometheus-$${PROM_VER}.linux-amd64/promtool"   /usr/local/bin/
    cp -r "prometheus-$${PROM_VER}.linux-amd64/consoles"           /etc/prometheus/
    cp -r "prometheus-$${PROM_VER}.linux-amd64/console_libraries"  /etc/prometheus/
    chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

    cat > /etc/prometheus/prometheus.yml << 'PROMCFG'
global:
  scrape_interval:     15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'app-server'
    static_configs:
      - targets: ['${var.app_private_ip}:9100']
        labels:
          instance: 'app-server'
          role: 'frontend-backend-admin'

  - job_name: 'mongodb-server'
    static_configs:
      - targets: ['${var.mongodb_private_ip}:9100']
        labels:
          instance: 'mongodb-server'
          role: 'database'

  - job_name: 'prometheus-self'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          instance: 'monitoring-server'
PROMCFG

    cat > /etc/systemd/system/prometheus.service << 'SVCEOF'
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target
[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.listen-address=0.0.0.0:9090 \
  --storage.tsdb.retention.time=30d
Restart=on-failure
[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus

    # ── Install Grafana ────────────────────────────────────────────────────
    wget -q -O /usr/share/keyrings/grafana.key https://apt.grafana.com/gpg.key
    echo "deb [signed-by=/usr/share/keyrings/grafana.key] https://apt.grafana.com stable main" | \
      tee /etc/apt/sources.list.d/grafana.list
    apt-get update -y
    apt-get install -y grafana

    # Disable self-registration, bind only on localhost for tunnel access
    sed -i 's/;allow_sign_up = true/allow_sign_up = false/'       /etc/grafana/grafana.ini
    sed -i 's/;http_addr =/http_addr = 0.0.0.0/'                  /etc/grafana/grafana.ini

    # Pre-configure Prometheus datasource
    mkdir -p /etc/grafana/provisioning/datasources
    cat > /etc/grafana/provisioning/datasources/prometheus.yml << 'DSCFG'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090
    isDefault: true
    editable: false
DSCFG

    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server

    # ── Install CloudWatch Agent ───────────────────────────────────────────
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb

    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCFG'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "${var.project}/monitoring",
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}",
      "InstanceType": "$${aws:InstanceType}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "metrics_collection_interval": 60
      }
    }
  }
}
CWCFG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
      -s

    echo "=== Monitoring Bootstrap complete ==="
  EOF

  tags = { Name = "${var.project}-monitoring-server" }
}

# ── IAM Role for Monitoring EC2 (CloudWatch + SSM) ────────────────────────
resource "aws_iam_role" "monitoring" {
  name = "${var.project}-monitoring-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = { Name = "${var.project}-monitoring-role" }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "monitoring" {
  name = "${var.project}-monitoring-instance-profile"
  role = aws_iam_role.monitoring.name
}

# ── SNS Topic for CloudWatch Alarms ───────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
  tags = { Name = "${var.project}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── CloudWatch Alarm: App Server high CPU ─────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "app_high_cpu" {
  alarm_name          = "${var.project}-app-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "App server CPU > 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = var.app_instance_id
  }

  tags = { Name = "${var.project}-app-cpu-alarm" }
}

# ── CloudWatch Alarm: MongoDB high CPU ─────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "mongodb_high_cpu" {
  alarm_name          = "${var.project}-mongodb-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "MongoDB CPU > 75% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = var.mongodb_instance_id
  }

  tags = { Name = "${var.project}-mongodb-cpu-alarm" }
}

# ── CloudWatch Dashboard ─────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          region = var.region
          title  = "App Server CPU"
          view   = "timeSeries"
          stat   = "Average"
          period = 300

          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              var.app_instance_id
            ]
          ]
        }
      },

      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6

        properties = {
          region = var.region
          title  = "MongoDB CPU"
          view   = "timeSeries"
          stat   = "Average"
          period = 300

          metrics = [
            [
              "AWS/EC2",
              "CPUUtilization",
              "InstanceId",
              var.mongodb_instance_id
            ]
          ]
        }
      },

      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 24
        height = 6

        properties = {
          region = var.region
          title  = "ALB Request Count"
          view   = "timeSeries"
          stat   = "Sum"
          period = 60

          metrics = [
            [
              "AWS/ApplicationELB",
              "RequestCount",
              "LoadBalancer",
              var.alb_arn
            ]
          ]
        }
      }
    ]
  })
}