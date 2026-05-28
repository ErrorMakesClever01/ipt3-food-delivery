# ─────────────────────────────────────────────────────────────────────────────
# modules/secrets/main.tf
# AWS Secrets Manager — MongoDB + Jenkins + Docker Hub credentials
# IAM Role + Instance Profile for app EC2 to read secrets + write CW logs
#
# FIX: dockerhub_password was referenced but never stored in the secret version
# NEW: IAM policy also allows writing CloudWatch logs (for --log-driver awslogs)
# ─────────────────────────────────────────────────────────────────────────────

# ── MongoDB Credentials ────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "mongodb" {
  name                    = "${var.project}/mongodb/credentials"
  description             = "MongoDB username + password for ${var.project}"
  recovery_window_in_days = 7
  tags                    = { Name = "${var.project}-mongodb-secret" }
}

resource "aws_secretsmanager_secret_version" "mongodb" {
  secret_id = aws_secretsmanager_secret.mongodb.id
  secret_string = jsonencode({
    username = var.mongodb_user
    password = var.mongodb_password
    host     = var.mongodb_private_ip
    port     = 27017
    database = "fooddelivery"
  })
}

# ── Jenkins Admin Password ─────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "jenkins" {
  name                    = "${var.project}/jenkins/admin-password"
  description             = "Jenkins admin password for ${var.project}"
  recovery_window_in_days = 7
  tags                    = { Name = "${var.project}-jenkins-secret" }
}

resource "aws_secretsmanager_secret_version" "jenkins" {
  secret_id     = aws_secretsmanager_secret.jenkins.id
  secret_string = jsonencode({ password = var.jenkins_password })
}

# ── Docker Hub Credentials ─────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "dockerhub" {
  name                    = "${var.project}/dockerhub/credentials"
  description             = "Docker Hub pull credentials for ${var.dockerhub_user}"
  recovery_window_in_days = 7
  tags                    = { Name = "${var.project}-dockerhub-secret" }
}

resource "aws_secretsmanager_secret_version" "dockerhub" {
  secret_id = aws_secretsmanager_secret.dockerhub.id
  # ✅ FIX: dockerhub_password was missing from the stored JSON
  secret_string = jsonencode({
    username = var.dockerhub_user
    password = var.dockerhub_password
  })
}

# ── IAM Role for App EC2 ──────────────────────────────────────────────────
resource "aws_iam_role" "app_role" {
  name = "${var.project}-app-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = { Name = "${var.project}-app-ec2-role" }
}

resource "aws_iam_role_policy" "app_permissions" {
  name = "${var.project}-app-permissions"
  role = aws_iam_role.app_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read secrets at boot
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.mongodb.arn,
          aws_secretsmanager_secret.jenkins.arn,
          aws_secretsmanager_secret.dockerhub.arn
        ]
      },
      # ✅ NEW: Write Docker container logs to CloudWatch
      {
        Sid    = "WriteCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # ✅ NEW: CloudWatch Agent metrics
      {
        Sid    = "CloudWatchAgent"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project}-app-instance-profile"
  role = aws_iam_role.app_role.name
}
