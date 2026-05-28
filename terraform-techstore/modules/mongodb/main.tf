# ─────────────────────────────────────────────────────────────────────────────
# modules/mongodb/main.tf
# EC2-2 — Private Subnet A (t3.small)
# MongoDB 7.0 with auth enabled
#
# FIX: instance_type was hardcoded as "t2.micro" — now uses variable (t3.small)
# FIX: node_exporter systemd unit had incorrect indentation
# FIX: mongod.conf had leading whitespace that would break YAML parsing
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "mongodb" {
  ami                    = var.ami_id
  instance_type          = var.instance_type # ✅ FIX: was hardcoded t2.micro
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.mongodb_sg_id]
  key_name               = var.key_name

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    throughput            = 125
    encrypted             = true
    delete_on_termination = false # ← NEVER auto-delete the database volume
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    exec > /var/log/userdata.log 2>&1

    echo "=== MongoDB Server Bootstrap ==="
    apt-get update -y
    apt-get install -y gnupg curl awscli jq

    # ── Install MongoDB 7.0 ──────────────────────────────────────────────
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
      gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
      https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
      tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    apt-get update -y
    apt-get install -y mongodb-org

    # ✅ FIX: mongod.conf had leading spaces causing YAML parse errors
    cat > /etc/mongod.conf << 'MONGOCFG'
storage:
  dbPath: /var/lib/mongodb
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log
net:
  port: 27017
  bindIp: 0.0.0.0
security:
  authorization: enabled
operationProfiling:
  slowOpThresholdMs: 100
MONGOCFG

    systemctl enable mongod
    systemctl start mongod

    # Wait for MongoDB to become ready
    sleep 8
    until mongosh --quiet --eval "db.runCommand({ping:1})" > /dev/null 2>&1; do
      echo "Waiting for MongoDB..."
      sleep 3
    done

    # ── Fetch credentials from Secrets Manager ────────────────────────────
    REGION="${var.region}"
    PROJECT="${var.project}"

    SECRET=$(aws secretsmanager get-secret-value \
      --secret-id "$PROJECT/mongodb/credentials" \
      --region "$REGION" --query SecretString --output text)

    MONGO_USER=$(echo "$SECRET" | jq -r '.username')
    MONGO_PASS=$(echo "$SECRET" | jq -r '.password')

    # ── Create app user ────────────────────────────────────────────────────
    mongosh --quiet admin --eval "
      db.createUser({
        user: '$MONGO_USER',
        pwd:  '$MONGO_PASS',
        roles: [
          { role: 'readWrite', db: 'fooddelivery' },
          { role: 'dbAdmin',   db: 'fooddelivery' }
        ]
      })
    " || echo "User may already exist, continuing..."

    # ── Install node_exporter ─────────────────────────────────────────────
    NODE_EXPORTER_VER="1.8.1"
    wget -q "https://github.com/prometheus/node_exporter/releases/download/v$${NODE_EXPORTER_VER}/node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
    tar xzf "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64.tar.gz"
    cp "node_exporter-$${NODE_EXPORTER_VER}.linux-amd64/node_exporter" /usr/local/bin/
    useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

    # ✅ FIX: service file had wrong indentation in original
    cat > /etc/systemd/system/node_exporter.service << 'SVCEOF'
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

    echo "=== MongoDB Bootstrap complete ==="
  EOF

  tags = { Name = "${var.project}-mongodb" }
}
