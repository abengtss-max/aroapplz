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

resource "azapi_resource" "state" {
  type      = "Microsoft.Storage/storageAccounts@2023-05-01"
  name      = var.names.state_storage
  parent_id = azurerm_resource_group.state.id
  location  = azurerm_resource_group.state.location
  tags      = var.tags
  body = {
    kind = "StorageV2"
    sku  = { name = "Standard_ZRS" }
    properties = {
      allowBlobPublicAccess    = false
      allowSharedKeyAccess     = false
      minimumTlsVersion        = "TLS1_2"
      publicNetworkAccess      = "Enabled"
      supportsHttpsTrafficOnly = true
      encryption = {
        keySource                       = "Microsoft.Storage"
        requireInfrastructureEncryption = true
        services = {
          blob = { enabled = true, keyType = "Account" }
          file = { enabled = true, keyType = "Account" }
        }
      }
    }
  }
}

resource "azapi_update_resource" "blob_service" {
  type        = "Microsoft.Storage/storageAccounts/blobServices@2023-05-01"
  resource_id = "${azapi_resource.state.id}/blobServices/default"
  body = {
    properties = {
      changeFeed                     = { enabled = true }
      containerDeleteRetentionPolicy = { enabled = true, days = 30 }
      deleteRetentionPolicy          = { enabled = true, days = 30 }
      isVersioningEnabled            = true
    }
  }
}

# The default blob service is created automatically with the storage account.
# Forget the former create-managed resource during upgrades without deleting it.
removed {
  from = azapi_resource.blob_service

  lifecycle {
    destroy = false
  }
}

resource "azapi_resource" "state_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = "tfstate"
  parent_id = azapi_update_resource.blob_service.resource_id
  body = {
    properties = { publicAccess = "None" }
  }
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
  scope                = azapi_resource.state_container.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.pipeline[each.key].principal_id
  principal_type       = "ServicePrincipal"
}
