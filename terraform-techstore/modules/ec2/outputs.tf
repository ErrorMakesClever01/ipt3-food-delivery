output "app_instance_id" { value = aws_instance.app.id }
output "app_private_ip" { value = aws_instance.app.private_ip }
output "app_public_ip" { value = aws_instance.app.public_ip }

# Stable Elastic IP — use this for SSH and Jenkins URLs
output "app_elastic_ip" { value = aws_eip.app.public_ip }
