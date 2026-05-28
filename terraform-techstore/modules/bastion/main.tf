# ─────────────────────────────────────────────────────────────────────────────
# modules/bastion/main.tf
# Bastion host — public subnet B (t3.micro)
# SSH jump server — reach private instances without exposing them directly
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.instance_type # t3.micro
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 10
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
  EOF

  tags = { Name = "${var.project}-bastion" }
}

# Elastic IP — stable IP for the bastion
resource "aws_eip" "bastion" {
  instance   = aws_instance.bastion.id
  domain     = "vpc"
  depends_on = [aws_instance.bastion]
  tags       = { Name = "${var.project}-bastion-eip" }
}
