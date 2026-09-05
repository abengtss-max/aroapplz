terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.30" }
    azapi   = { source = "Azure/azapi", version = "~> 2.4" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.4" }
    github  = { source = "integrations/github", version = "~> 6.6" }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.bootstrap_subscription_id
  tenant_id                       = var.tenant_id
  resource_provider_registrations = "none"
}

provider "azapi" {}
provider "azuread" { tenant_id = var.tenant_id }
provider "github" { owner = var.github_organization }
