variable "location" { type = string }
variable "service_name" { type = string }
variable "environment_name" { type = string }

locals {
  normalized = lower(replace("${var.service_name}-${var.environment_name}", "_", "-"))
  compact    = substr(replace(local.normalized, "-", ""), 0, 16)
  names = {
    state_resource_group = "rg-${local.normalized}-bootstrap"
    state_storage        = substr("st${local.compact}tf", 0, 24)
    repository           = local.normalized
    plan_application     = "app-${local.normalized}-plan"
    apply_application    = "app-${local.normalized}-apply"
  }
}

output "names" { value = local.names }
