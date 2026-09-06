variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "resource_group_id" { type = string }
variable "names" { type = map(string) }
variable "tags" { type = map(string) }

variable "github_organization" { type = string }
variable "github_repository" { type = string }

# Exchanged by the runner image for a short lived registration token, so it is
# never written to state as a runner credential.
variable "github_runner_token" {
  type      = string
  sensitive = true
  validation {
    condition     = length(var.github_runner_token) > 0
    error_message = "A GitHub token is required to register self-hosted runners."
  }
}

variable "runner_count" {
  type = number
  validation {
    condition     = var.runner_count >= 1 && var.runner_count <= 20
    error_message = "runner_count must be between 1 and 20."
  }
}

variable "runner_image_tag" { type = string }
variable "runner_cpu" { type = number }
variable "runner_memory_gb" { type = number }

variable "virtual_network_cidr" { type = string }
variable "container_instances_subnet_cidr" { type = string }
variable "private_endpoint_subnet_cidr" { type = string }

variable "state_storage_account_id" { type = string }
