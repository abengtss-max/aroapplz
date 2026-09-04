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
  source                       = "../../modules/github"
  organization                 = var.github_organization
  repository                   = var.github_repository
  apply_approvers              = var.apply_approvers
  repository_files             = merge(var.repository_files, local.generated_files)
  tenant_id                    = var.tenant_id
  workload_subscription_id     = var.workload_subscription_id
  connectivity_subscription_id = var.connectivity_subscription_id
  client_ids                   = module.azure.client_ids
  backend_resource_group_name  = module.azure.state_resource_group_name
  backend_storage_account_name = module.azure.state_storage_account_name
  backend_container_name       = module.azure.state_container_name
}
