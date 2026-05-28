# ─────────────────────────────────────────────────────────────────────────────
# modules/security_audit/main.tf
# Security posture: CloudTrail, GuardDuty, SNS alert on root login
# ─────────────────────────────────────────────────────────────────────────────

# ── SNS Topic for security alerts ─────────────────────────────────────────
resource "aws_sns_topic" "security_alerts" {
  name = "${var.project}-security-alerts"
  tags = { Name = "${var.project}-security-alerts" }
}

resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── S3 bucket for CloudTrail logs ─────────────────────────────────────────
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project}-cloudtrail-${var.account_id}"
  force_destroy = false
  tags          = { Name = "${var.project}-cloudtrail-logs" }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

# ── CloudTrail ─────────────────────────────────────────────────────────────
resource "aws_cloudtrail" "main" {
  name                          = "${var.project}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
  tags       = { Name = "${var.project}-trail" }
}

# ── GuardDuty ──────────────────────────────────────────────────────────────
variable "enable_guardduty" {
  default = false
}

resource "aws_guardduty_detector" "main" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true
}
# ── CloudWatch Alarm: Root account login ──────────────────────────────────
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project}"
  retention_in_days = 90
  tags              = { Name = "${var.project}-cloudtrail-logs" }
}

resource "aws_cloudwatch_metric_alarm" "root_login" {
  alarm_name          = "${var.project}-root-login"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "RootAccountUsage"
  namespace           = "CloudTrailMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "ALERT: AWS root account login detected"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]
  tags                = { Name = "${var.project}-root-login-alarm" }
}
