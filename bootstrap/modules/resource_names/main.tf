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
    plan_identity        = "id-${local.normalized}-plan"
    apply_identity       = "id-${local.normalized}-apply"

    runner_virtual_network            = "vnet-${local.normalized}-bootstrap"
    runner_subnet_private_endpoints   = "snet-private-endpoints"
    runner_subnet_container_instances = "snet-container-instances"
    runner_public_ip                  = "pip-${local.normalized}-runner"
    runner_nat_gateway                = "ng-${local.normalized}-runner"
    runner_container_registry         = substr("cr${local.compact}runner", 0, 50)
    runner_identity                   = "id-${local.normalized}-runner"
    runner_container_group            = "ci-${local.normalized}-runner"
    runner_image                      = "github-runner"
    state_private_endpoint            = "pe-${local.normalized}-state-blob"
    runner_registry_private_endpoint  = "pe-${local.normalized}-registry"
  }
}

output "names" { value = local.names }
