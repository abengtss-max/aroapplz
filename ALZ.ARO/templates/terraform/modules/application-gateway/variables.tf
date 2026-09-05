variable "cluster_name" {
  type = string
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "backend_ip_address" {
  type = string
}
variable "backend_host_name" {
  type = string
}
variable "capacity" {
  type = number
}
variable "ssl_certificate_data" {
  type      = string
  sensitive = true
}
variable "ssl_certificate_password" {
  type      = string
  sensitive = true
}
variable "backend_root_certificate" {
  type      = string
  sensitive = true
  nullable  = true
}
variable "log_analytics_workspace_id" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
