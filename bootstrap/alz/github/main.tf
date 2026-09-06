module "resource_names" {
  source           = "../../modules/resource_names"
  location         = var.location
  service_name     = var.service_name
  environment_name = var.environment_name
}

module "azure" {
  source                    = "../../modules/azure"
  location                  = var.location
  tenant_id                 = var.tenant_id
  bootstrap_subscription_id = var.bootstrap_subscription_id
  workload_subscription_id  = var.workload_subscription_id
  github_organization       = var.github_organization
  github_repository         = var.github_repository
  names                     = module.resource_names.names
  tags                      = var.tags
}

# Optional. Customers who already operate a runner leave this disabled and set
# runner_label to their own runner instead.
module "runner" {
  count  = var.self_hosted_runner_enabled ? 1 : 0
  source = "../../modules/runner"

  location            = var.location
  resource_group_name = module.azure.state_resource_group_name
  resource_group_id   = module.azure.state_resource_group_id
  names               = module.resource_names.names
  tags                = var.tags

  github_organization = var.github_organization
  github_repository   = var.github_repository
  github_runner_token = var.github_runner_token

  runner_count     = var.runner_count
  runner_image_tag = var.runner_image_tag
  runner_cpu       = var.runner_cpu
  runner_memory_gb = var.runner_memory_gb

  virtual_network_cidr            = var.runner_virtual_network_cidr
  container_instances_subnet_cidr = var.runner_container_instances_subnet_cidr
  private_endpoint_subnet_cidr    = var.runner_private_endpoint_subnet_cidr

  state_storage_account_id = module.azure.state_storage_account_id

  depends_on = [module.github]
}

locals {
  generated_files = {
    "terraform/backend.tf" = <<-EOT
      terraform {
        backend "azurerm" {
          resource_group_name  = "${module.azure.state_resource_group_name}"
          storage_account_name = "${module.azure.state_storage_account_name}"
          container_name       = "${module.azure.state_container_name}"
          key                  = "aro.tfstate"
          use_azuread_auth     = true
        }
      }
    EOT
    "terraform/aro-resource-provider.auto.tfvars.json" = jsonencode({
      aro_resource_provider_object_id = module.azure.aro_resource_provider_object_id
    })
  }
}

module "github" {
  source                              = "../../modules/github"
  organization                        = var.github_organization
  repository                          = var.github_repository
  apply_approvers                     = var.apply_approvers
  apply_environment_reviewers_enabled = var.apply_environment_reviewers_enabled
  repository_files                    = merge(var.repository_files, local.generated_files)
  tenant_id                           = var.tenant_id
  workload_subscription_id            = var.workload_subscription_id
  connectivity_subscription_id        = var.connectivity_subscription_id
  client_ids                          = module.azure.client_ids
  backend_resource_group_name         = module.azure.state_resource_group_name
  backend_storage_account_name        = module.azure.state_storage_account_name
  backend_container_name              = module.azure.state_container_name
}

resource "azurerm_federated_identity_credential" "github" {
  for_each                  = toset(["plan", "apply"])
  name                      = "github-${each.key}"
  user_assigned_identity_id = module.azure.identity_ids[each.key]
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_organization}@${var.github_owner_id}/${var.github_repository}@${module.github.repository_id}:environment:${each.key}"
}

moved {
  from = module.azure.azurerm_federated_identity_credential.github["plan"]
  to   = azurerm_federated_identity_credential.github["plan"]
}

moved {
  from = module.azure.azurerm_federated_identity_credential.github["apply"]
  to   = azurerm_federated_identity_credential.github["apply"]
}
