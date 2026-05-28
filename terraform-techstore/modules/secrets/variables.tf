variable "project" { type = string }
variable "mongodb_user" { type = string }
variable "mongodb_password" {
  type      = string
  sensitive = true
}
variable "mongodb_private_ip" {
  type    = string
  default = ""
}
variable "jenkins_password" {
  type      = string
  sensitive = true
}
variable "dockerhub_user" { type = string }
variable "dockerhub_password" {
  type      = string
  sensitive = true
  default   = "REPLACE_DOCKERHUB_PASSWORD"
}
