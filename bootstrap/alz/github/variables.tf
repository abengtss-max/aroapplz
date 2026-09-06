variable "tenant_id" { type = string }
variable "bootstrap_subscription_id" { type = string }
variable "workload_subscription_id" { type = string }
variable "connectivity_subscription_id" {
  type    = string
  default = ""
}
variable "location" { type = string }
variable "service_name" { type = string }
variable "environment_name" { type = string }
variable "github_organization" { type = string }
variable "github_repository" { type = string }
variable "github_owner_id" { type = string }
variable "apply_approvers" {
  type = list(string)
  validation {
    condition     = length(var.apply_approvers) > 0
    error_message = "At least one GitHub apply approver is required."
  }
}
variable "apply_environment_reviewers_enabled" {
  type    = bool
  default = false
}
variable "repository_files" { type = map(string) }
variable "tags" {
  type    = map(string)
  default = { managed_by = "terraform", accelerator = "ALZ.ARO" }
}

variable "self_hosted_runner_enabled" {
  type    = bool
  default = false
}

# Supplied from the environment, never from the configuration file.
variable "github_runner_token" {
  type      = string
  sensitive = true
  default   = ""
  validation {
    condition     = !var.self_hosted_runner_enabled || length(var.github_runner_token) > 0
    error_message = "github_runner_token is required when self_hosted_runner_enabled is true."
  }
}

variable "runner_count" {
  type    = number
  default = 2
}

variable "runner_image_tag" {
  type    = string
  default = "latest"
}

variable "runner_cpu" {
  type    = number
  default = 2
}

variable "runner_memory_gb" {
  type    = number
  default = 8
}

variable "runner_virtual_network_cidr" {
  type    = string
  default = ""
  validation {
    condition     = !var.self_hosted_runner_enabled || can(cidrhost(var.runner_virtual_network_cidr, 0))
    error_message = "runner_virtual_network_cidr must be a valid CIDR when self_hosted_runner_enabled is true."
  }
}

variable "runner_container_instances_subnet_cidr" {
  type    = string
  default = ""
  validation {
    condition     = !var.self_hosted_runner_enabled || can(cidrhost(var.runner_container_instances_subnet_cidr, 0))
    error_message = "runner_container_instances_subnet_cidr must be a valid CIDR when self_hosted_runner_enabled is true."
  }
}

variable "runner_private_endpoint_subnet_cidr" {
  type    = string
  default = ""
  validation {
    condition     = !var.self_hosted_runner_enabled || can(cidrhost(var.runner_private_endpoint_subnet_cidr, 0))
    error_message = "runner_private_endpoint_subnet_cidr must be a valid CIDR when self_hosted_runner_enabled is true."
  }
}
