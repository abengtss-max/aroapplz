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
variable "use_self_hosted_runner" {
  type    = bool
  default = false
}
variable "runner_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}
variable "runner_ssh_public_key" {
  type      = string
  default   = ""
  sensitive = true
  validation {
    condition     = !var.use_self_hosted_runner || length(trimspace(var.runner_ssh_public_key)) > 0
    error_message = "runner_ssh_public_key is required when use_self_hosted_runner is true."
  }
}
variable "tags" {
  type    = map(string)
  default = { managed_by = "terraform", accelerator = "ALZ.ARO" }
}
