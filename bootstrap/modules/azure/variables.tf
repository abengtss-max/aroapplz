variable "location" { type = string }
variable "tenant_id" { type = string }
variable "bootstrap_subscription_id" { type = string }
variable "workload_subscription_id" { type = string }
variable "github_organization" { type = string }
variable "github_repository" { type = string }
variable "names" { type = map(string) }
variable "tags" { type = map(string) }
