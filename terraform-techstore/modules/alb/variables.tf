variable "project" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_a_id" { type = string }
variable "public_subnet_b_id" { type = string }
variable "alb_sg_id" { type = string }
variable "app_instance_id" { type = string }
variable "acm_certificate_arn" { type = string }
variable "domain_name" { type = string }

variable "frontend_port" {
  type    = number
  default = 5173
}
variable "admin_port" {
  type    = number
  default = 5174
}
variable "backend_port" {
  type    = number
  default = 4000
}
