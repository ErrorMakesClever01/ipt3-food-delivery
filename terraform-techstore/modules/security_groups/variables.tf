variable "project" { type = string }
variable "vpc_id" { type = string }
variable "admin_ip" { type = string }
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
