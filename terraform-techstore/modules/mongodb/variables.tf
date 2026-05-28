variable "project" { type = string }
variable "ami_id" { type = string }
variable "instance_type" { type = string } # ✅ FIX: added (was missing, causing hardcoded t2.micro)
variable "private_subnet_id" { type = string }
variable "mongodb_sg_id" { type = string }
variable "key_name" { type = string }
variable "region" { type = string }
