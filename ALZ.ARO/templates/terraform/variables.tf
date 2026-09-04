variable "deployment_mode" {
  description = "Exactly standalone or spoke. Both create a new owned ARO VNet."
  type        = string
  validation {
    condition     = contains(["standalone", "spoke"], var.deployment_mode)
    error_message = "deployment_mode must be exactly standalone or spoke."
  }
}
variable "tenant_id" { type = string }
variable "workload_subscription_id" { type = string }
variable "connectivity_subscription_id" {
  type    = string
  default = ""
}
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "cluster_name" { type = string }
variable "aro_domain" { type = string }
variable "aro_version" {
  description = "Exact version pin validated by az aro get-versions before rendering."
  type        = string
  validation {
    condition     = length(trimspace(var.aro_version)) > 0
    error_message = "aro_version must be explicitly pinned."
  }
}
variable "aro_vnet_cidr" { type = string }
variable "control_plane_subnet_cidr" { type = string }
variable "worker_subnet_cidr" { type = string }
variable "pod_cidr" {
  type    = string
  default = "10.128.0.0/14"
}
variable "service_cidr" {
  type    = string
  default = "172.30.0.0/16"
}
variable "control_plane_vm_size" {
  type    = string
  default = "Standard_D8s_v3"
}
variable "worker_vm_size" {
  type    = string
  default = "Standard_D4s_v3"
}
variable "worker_disk_size_gb" {
  type    = number
  default = 128
}
variable "worker_node_count" {
  type    = number
  default = 3
  validation {
    condition     = var.worker_node_count >= 3
    error_message = "ARO requires at least three worker nodes."
  }
}
variable "aro_service_principal_client_id" { type = string }
variable "aro_service_principal_client_secret" {
  type      = string
  sensitive = true
}
variable "aro_service_principal_object_id" { type = string }
variable "aro_resource_provider_object_id" { type = string }
variable "pull_secret" {
  type      = string
  sensitive = true
  default   = null
  nullable  = true
}
variable "hub_vnet_id" {
  type    = string
  default = ""
}
variable "next_hop_ip" {
  type    = string
  default = ""
}
variable "ingress_mode" {
  type    = string
  default = "none"
  validation {
    condition     = contains(["none", "front_door", "application_gateway"], var.ingress_mode)
    error_message = "ingress_mode must be exactly none, front_door, or application_gateway."
  }
}
variable "tags" {
  type    = map(string)
  default = { managed_by = "terraform", accelerator = "ALZ.ARO" }
}
