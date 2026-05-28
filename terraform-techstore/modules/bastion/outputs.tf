output "bastion_public_ip" { value = aws_eip.bastion.public_ip }
output "bastion_instance_id" { value = aws_instance.bastion.id }
# SSH command to reach private instances:
# ssh -J ubuntu@<bastion_public_ip> ubuntu@<private_instance_ip> -i app-key.pem
