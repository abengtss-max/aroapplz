terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 5.2"
      configuration_aliases = [azurerm.workload]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Registry and vault names are globally unique, so a stable suffix is generated once.
resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  alphanumeric_cluster_name = lower(replace(var.cluster_name, "/[^a-zA-Z0-9]/", ""))
  registry_name             = substr("acr${local.alphanumeric_cluster_name}${random_string.suffix.result}", 0, 50)
  key_vault_name            = substr("kv-${local.alphanumeric_cluster_name}-${random_string.suffix.result}", 0, 24)
}

locals {
  private_dns_zones = merge(
    var.container_registry_enabled ? { registry = "privatelink.azurecr.io" } : {},
    var.key_vault_enabled ? { vault = "privatelink.vaultcore.azure.net" } : {},
  )
}

resource "azurerm_private_dns_zone" "this" {
  provider            = azurerm.workload
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  provider             = azurerm.workload
  for_each             = azurerm_private_dns_zone.this
  name                 = "link-${var.cluster_name}"
  private_dns_zone_id  = each.value.id
  virtual_network_id   = var.virtual_network_id
  registration_enabled = false
  tags                 = var.tags
}

resource "azurerm_container_registry" "this" {
  provider                      = azurerm.workload
  count                         = var.container_registry_enabled ? 1 : 0
  name                          = local.registry_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.container_registry_sku
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_private_endpoint" "registry" {
  provider            = azurerm.workload
  count               = var.container_registry_enabled ? 1 : 0
  name                = "pe-acr-${var.cluster_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "acr"
    private_connection_resource_id = azurerm_container_registry.this[0].id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["registry"].id]
  }
}

resource "azurerm_key_vault" "this" {
  provider                      = azurerm.workload
  count                         = var.key_vault_enabled ? 1 : 0
  name                          = local.key_vault_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "standard"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
}

resource "azurerm_private_endpoint" "key_vault" {
  provider            = azurerm.workload
  count               = var.key_vault_enabled ? 1 : 0
  name                = "pe-kv-${var.cluster_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "vault"
    private_connection_resource_id = azurerm_key_vault.this[0].id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["vault"].id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "registry" {
  provider                   = azurerm.workload
  count                      = var.container_registry_enabled ? 1 : 0
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_container_registry.this[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category_group = "allLogs" }
  enabled_metric { category = "AllMetrics" }
}

# Key Vault audit events are a security control, not optional telemetry.
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  provider                   = azurerm.workload
  count                      = var.key_vault_enabled ? 1 : 0
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_key_vault.this[0].id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category_group = "audit" }
  enabled_log { category_group = "allLogs" }
  enabled_metric { category = "AllMetrics" }
}
