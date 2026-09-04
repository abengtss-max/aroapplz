terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.2"
    }
  }
}

provider "azurerm" {
  alias                           = "workload"
  subscription_id                 = var.workload_subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  features {}
}

provider "azurerm" {
  alias                           = "connectivity"
  subscription_id                 = var.deployment_mode == "spoke" ? var.connectivity_subscription_id : var.workload_subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
  features {}
}
