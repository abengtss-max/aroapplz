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
variable "control_plane_subnet_cidr" {
  type = string
  validation {
    condition     = tonumber(split("/", var.control_plane_subnet_cidr)[1]) <= 27
    error_message = "ARO control-plane and worker subnets must be /27 or larger."
  }
}
variable "worker_subnet_cidr" {
  type = string
  validation {
    condition     = tonumber(split("/", var.worker_subnet_cidr)[1]) <= 27
    error_message = "ARO control-plane and worker subnets must be /27 or larger."
  }
}
variable "pod_cidr" {
  type    = string
  default = "10.128.0.0/14"
  validation {
    condition     = tonumber(split("/", var.pod_cidr)[1]) <= 18
    error_message = "pod_cidr must be /18 or larger; each node consumes a /23."
  }
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
variable "aro_resource_provider_object_id" { type = string }
variable "managed_resource_group_name" {
  description = "Deterministic ARO-managed resource group name so platform teams can scope policy exemptions before deployment. Defaults to rg-<cluster_name>-managed."
  type        = string
  default     = ""
  validation {
    condition     = var.managed_resource_group_name == lower(var.managed_resource_group_name)
    error_message = "managed_resource_group_name cannot contain uppercase characters."
  }
}
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
variable "application_gateway_subnet_cidr" {
  description = "Dedicated Application Gateway subnet CIDR. Required when ingress_mode is application_gateway."
  type        = string
  default     = ""
}
variable "application_gateway_backend_host_name" {
  description = "A routable OpenShift application host used by the HTTPS health probe. Required when ingress_mode is application_gateway."
  type        = string
  default     = ""
}
variable "application_gateway_capacity" {
  type    = number
  default = 2
  validation {
    condition     = var.application_gateway_capacity >= 1 && var.application_gateway_capacity <= 10
    error_message = "application_gateway_capacity must be between 1 and 10."
  }
}
variable "application_gateway_ssl_certificate_data" {
  description = "Base64-encoded PFX certificate required for Application Gateway. Supply at runtime through TF_VAR_application_gateway_ssl_certificate_data."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}
variable "application_gateway_ssl_certificate_password" {
  description = "PFX password required for Application Gateway. Supply at runtime through TF_VAR_application_gateway_ssl_certificate_password."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}
variable "application_gateway_backend_root_certificate" {
  description = "Base64-encoded root certificate of the OpenShift ingress certificate. Application Gateway v2 marks a self-signed backend unhealthy without it. Omit only when the ingress controller presents a certificate from a well-known CA."
  type        = string
  default     = null
  nullable    = true
}
variable "tags" {
  type    = map(string)
  default = { managed_by = "terraform", accelerator = "ALZ.ARO" }
}
