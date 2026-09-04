locals {
  is_spoke      = var.deployment_mode == "spoke"
  hub_id_parts  = local.is_spoke ? split("/", var.hub_vnet_id) : []
  hub_rg_name   = local.is_spoke ? local.hub_id_parts[4] : ""
  hub_vnet_name = local.is_spoke ? local.hub_id_parts[8] : ""
}

resource "azurerm_virtual_network" "aro" {
  provider            = azurerm.workload
  name                = "vnet-${var.cluster_name}"
  location            = azurerm_resource_group.aro.location
  resource_group_name = azurerm_resource_group.aro.name
  address_space       = [var.aro_vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "control_plane" {
  provider                                      = azurerm.workload
  name                                          = "snet-control-plane"
  resource_group_name                           = azurerm_resource_group.aro.name
  virtual_network_name                          = azurerm_virtual_network.aro.name
  address_prefixes                              = [var.control_plane_subnet_cidr]
  private_link_service_network_policies_enabled = false
  service_endpoints                             = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "worker" {
  provider             = azurerm.workload
  name                 = "snet-worker"
  resource_group_name  = azurerm_resource_group.aro.name
  virtual_network_name = azurerm_virtual_network.aro.name
  address_prefixes     = [var.worker_subnet_cidr]
  service_endpoints    = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_route_table" "egress" {
  provider                      = azurerm.workload
  count                         = local.is_spoke ? 1 : 0
  name                          = "rt-${var.cluster_name}-egress"
  location                      = azurerm_resource_group.aro.location
  resource_group_name           = azurerm_resource_group.aro.name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name                   = "default-to-existing-nva"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.next_hop_ip
  }
}

resource "azurerm_subnet_route_table_association" "control_plane" {
  provider       = azurerm.workload
  count          = local.is_spoke ? 1 : 0
  subnet_id      = azurerm_subnet.control_plane.id
  route_table_id = azurerm_route_table.egress[0].id
}

resource "azurerm_subnet_route_table_association" "worker" {
  provider       = azurerm.workload
  count          = local.is_spoke ? 1 : 0
  subnet_id      = azurerm_subnet.worker.id
  route_table_id = azurerm_route_table.egress[0].id
}

resource "azurerm_virtual_network_peering" "aro_to_hub" {
  provider                     = azurerm.workload
  count                        = local.is_spoke ? 1 : 0
  name                         = "peer-${azurerm_virtual_network.aro.name}-to-${local.hub_vnet_name}"
  resource_group_name          = azurerm_resource_group.aro.name
  virtual_network_name         = azurerm_virtual_network.aro.name
  remote_virtual_network_id    = var.hub_vnet_id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "hub_to_aro" {
  provider                     = azurerm.connectivity
  count                        = local.is_spoke ? 1 : 0
  name                         = "peer-${local.hub_vnet_name}-to-${azurerm_virtual_network.aro.name}"
  resource_group_name          = local.hub_rg_name
  virtual_network_name         = local.hub_vnet_name
  remote_virtual_network_id    = azurerm_virtual_network.aro.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
