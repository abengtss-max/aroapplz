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
variable "repository_files" { type = map(string) }
variable "tags" {
  type    = map(string)
  default = { managed_by = "terraform", accelerator = "ALZ.ARO" }
}
