variable "cluster_name" {
  type = string
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "managed_resource_group_name" {
  description = "ARO-managed resource group that holds the cluster internal load balancer."
  type        = string
}
variable "ingress_ip_address" {
  description = "Private ingress address reported by the cluster, used to select the correct load balancer frontend."
  type        = string
}
variable "private_link_subnet_id" {
  type = string
}
variable "backend_host_name" {
  description = "OpenShift application hostname presented to the origin."
  type        = string
}
variable "custom_domain" {
  description = "Public hostname served by Front Door. Empty serves only the azurefd.net endpoint."
  type        = string
  default     = ""
}
variable "sku" {
  type = string
}
variable "waf_mode" {
  type = string
}
variable "subscription_id" {
  type = string
}
variable "log_analytics_workspace_id" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
