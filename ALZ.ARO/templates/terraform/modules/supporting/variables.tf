variable "cluster_name" {
  type = string
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "resource_group_id" {
  type = string
}
variable "tenant_id" {
  type = string
}
variable "virtual_network_id" {
  type = string
}
variable "private_endpoint_subnet_id" {
  type = string
}
variable "container_registry_enabled" {
  type = bool
}
variable "container_registry_sku" {
  type = string
}
variable "key_vault_enabled" {
  type = bool
}
variable "tags" {
  type    = map(string)
  default = {}
}
