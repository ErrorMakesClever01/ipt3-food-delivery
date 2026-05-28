variable "project" { type = string }
variable "ami_id" { type = string }
variable "instance_type" { type = string }
variable "public_subnet_id" { type = string }
variable "app_sg_id" { type = string }
variable "app_instance_profile" { type = string }
variable "key_name" { type = string }
variable "region" { type = string }
variable "dockerhub_user" { type = string }
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
variable "mongodb_port" {
  type    = number
  default = 27017
}
