locals {
  aro_operator_names = toset([
    "aro-operator",
    "cloud-controller-manager",
    "cloud-network-config",
    "disk-csi-driver",
    "file-csi-driver",
    "image-registry",
    "ingress",
    "machine-api"
  ])

  aro_identity_names = setunion(local.aro_operator_names, toset(["aro-cluster"]))

  aro_operator_identities = {
    for name in local.aro_operator_names : name => azurerm_user_assigned_identity.aro[name]
  }

  subnet_role_assignments = merge([
    for operator, role_id in {
      cloud-controller-manager = "a1f96423-95ce-4224-ab27-4e3dc72facd4"
      ingress                  = "0336e1d3-7a87-462b-b6db-342b63f7802c"
      machine-api              = "0358943c-7e01-48ba-8889-02cc51d78637"
      aro-operator             = "4436bae4-7702-4c84-919b-c4069ff25ee2"
      } : {
      for subnet, scope in {
        control-plane = azurerm_subnet.control_plane.id
        worker        = azurerm_subnet.worker.id
        } : "${operator}-${subnet}" => {
        operator = operator
        role_id  = role_id
        scope    = scope
      }
    }
  ]...)

  vnet_role_assignments = {
    cloud-network-config = "be7a6435-15ae-4171-8f30-4a343eff9e8f"
    file-csi-driver      = "0d7aedc0-15fd-4a67-a412-efad370c947e"
    image-registry       = "8b32b316-c2f5-4ddf-b05b-83dacd2d08b5"
  }

  route_table_role_assignments = local.is_spoke ? {
    cloud-controller-manager = "a1f96423-95ce-4224-ab27-4e3dc72facd4"
    file-csi-driver          = "0d7aedc0-15fd-4a67-a412-efad370c947e"
    machine-api              = "0358943c-7e01-48ba-8889-02cc51d78637"
    aro-operator             = "4436bae4-7702-4c84-919b-c4069ff25ee2"
  } : {}
}

resource "azurerm_user_assigned_identity" "aro" {
  provider            = azurerm.workload
  for_each            = local.aro_identity_names
  name                = "id-${var.cluster_name}-${each.key}"
  resource_group_name = azurerm_resource_group.aro.name
  location            = azurerm_resource_group.aro.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "cluster_federated_credential" {
  provider           = azurerm.workload
  for_each           = local.aro_operator_identities
  scope              = each.value.id
  role_definition_id = "/subscriptions/${var.workload_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ef318e2a-8334-4a05-9e4a-295a196c6a6e"
  principal_id       = azurerm_user_assigned_identity.aro["aro-cluster"].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_subnet" {
  provider           = azurerm.workload
  for_each           = local.subnet_role_assignments
  scope              = each.value.scope
  role_definition_id = "/subscriptions/${var.workload_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value.role_id}"
  principal_id       = azurerm_user_assigned_identity.aro[each.value.operator].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_vnet" {
  provider           = azurerm.workload
  for_each           = local.vnet_role_assignments
  scope              = azurerm_virtual_network.aro.id
  role_definition_id = "/subscriptions/${var.workload_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azurerm_user_assigned_identity.aro[each.key].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_route_table" {
  provider           = azurerm.workload
  for_each           = local.route_table_role_assignments
  scope              = azurerm_route_table.egress[0].id
  role_definition_id = "/subscriptions/${var.workload_subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value}"
  principal_id       = azurerm_user_assigned_identity.aro[each.key].principal_id
  principal_type     = "ServicePrincipal"
}