variable "project" { type = string }
variable "ami_id" { type = string }
variable "instance_type" { type = string }
variable "private_subnet_id" { type = string }
variable "monitoring_sg_id" { type = string }
variable "key_name" { type = string }
variable "region" { type = string }
variable "alert_email" { type = string }
variable "app_private_ip" { type = string }

variable "mongodb_private_ip" {
  type    = string
  default = ""
}

# For CloudWatch alarms — optional (alarms are skipped if not provided)
variable "app_instance_id" {
  type    = string
  default = ""
}

variable "mongodb_instance_id" {
  type    = string
  default = ""
}

variable "alb_arn" {
  type    = string
  default = ""
}
