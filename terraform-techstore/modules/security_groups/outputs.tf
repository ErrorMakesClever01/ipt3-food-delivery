output "alb_sg_id" { value = aws_security_group.alb.id }
output "bastion_sg_id" { value = aws_security_group.bastion.id }
output "app_sg_id" { value = aws_security_group.app.id }
output "mongodb_sg_id" { value = aws_security_group.mongodb.id }
output "monitoring_sg_id" { value = aws_security_group.monitoring.id }
