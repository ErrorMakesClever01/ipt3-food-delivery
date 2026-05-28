output "security_sns_arn" { value = aws_sns_topic.security_alerts.arn }
output "guardduty_id" {
  value = try(aws_guardduty_detector.main[0].id, null)
}
output "cloudtrail_s3_bucket" { value = aws_s3_bucket.cloudtrail.id }
