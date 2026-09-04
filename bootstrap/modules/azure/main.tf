data "azurerm_subscription" "workload" {
  subscription_id = var.workload_subscription_id
}

data "azuread_service_principal" "aro_resource_provider" {
  client_id = "f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875"
}

resource "azurerm_resource_group" "state" {
  name     = var.names.state_resource_group
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "state" {
  name                              = var.names.state_storage
  resource_group_name               = azurerm_resource_group.state.name
  location                          = azurerm_resource_group.state.location
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  account_kind                      = "StorageV2"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  public_network_access_enabled     = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  tags                              = var.tags

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

locals {
  pipelines = {
    plan  = var.names.plan_identity
    apply = var.names.apply_identity
  }
}

resource "azurerm_user_assigned_identity" "pipeline" {
  for_each            = local.pipelines
  name                = each.value
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "github" {
  for_each            = local.pipelines
  name                = "github-${each.key}"
  resource_group_name = azurerm_resource_group.state.name
  parent_id           = azurerm_user_assigned_identity.pipeline[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_organization}/${var.github_repository}:environment:${each.key}"
}

resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.workload.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.pipeline["plan"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = data.azurerm_subscription.workload.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.pipeline["apply"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "apply_rbac_administrator" {
  scope                = data.azurerm_subscription.workload.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.pipeline["apply"].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "state" {
  for_each             = local.pipelines
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.pipeline[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
