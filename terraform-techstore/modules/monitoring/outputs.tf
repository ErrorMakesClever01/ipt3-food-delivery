output "monitoring_instance_id" { value = aws_instance.monitoring.id }
output "monitoring_private_ip" { value = aws_instance.monitoring.private_ip }
output "sns_alerts_arn" { value = aws_sns_topic.alerts.arn }
