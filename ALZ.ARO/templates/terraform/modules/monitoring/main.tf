terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 5.2"
      configuration_aliases = [azurerm.workload]
    }
  }
}

# Azure Verified Modules are the preferred source, but every candidate module still
# constrains azurerm to 4.x, so these resources are declared natively for now.
resource "azurerm_log_analytics_workspace" "this" {
  provider            = azurerm.workload
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.retention_in_days
  tags                = var.tags
}
