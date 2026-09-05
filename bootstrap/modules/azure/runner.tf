locals {
  runner_name = "vm-${var.names.repository}-runner"
}

resource "azurerm_virtual_network" "runner" {
  count               = var.use_self_hosted_runner ? 1 : 0
  name                = "vnet-${var.names.repository}-runner"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  address_space       = ["10.250.0.0/24"]
  tags                = var.tags
}

resource "azurerm_subnet" "runner" {
  count                = var.use_self_hosted_runner ? 1 : 0
  name                 = "snet-runner"
  resource_group_name  = azurerm_resource_group.state.name
  virtual_network_name = azurerm_virtual_network.runner[0].name
  address_prefixes     = ["10.250.0.0/26"]
}

resource "azurerm_subnet" "private_endpoints" {
  count                = var.use_self_hosted_runner ? 1 : 0
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.state.name
  virtual_network_name = azurerm_virtual_network.runner[0].name
  address_prefixes     = ["10.250.0.64/26"]
}

resource "azurerm_network_security_group" "runner" {
  count               = var.use_self_hosted_runner ? 1 : 0
  name                = "nsg-${var.names.repository}-runner"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "runner" {
  count                     = var.use_self_hosted_runner ? 1 : 0
  subnet_id                 = azurerm_subnet.runner[0].id
  network_security_group_id = azurerm_network_security_group.runner[0].id
}

resource "azurerm_public_ip" "runner" {
  count               = var.use_self_hosted_runner ? 1 : 0
  name                = "pip-${var.names.repository}-runner"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_network_interface" "runner" {
  count               = var.use_self_hosted_runner ? 1 : 0
  name                = "nic-${var.names.repository}-runner"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.runner[0].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.runner[0].id
  }
}

resource "azurerm_private_dns_zone" "blob" {
  count               = var.use_self_hosted_runner ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.state.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = var.use_self_hosted_runner ? 1 : 0
  name                  = "link-${var.names.repository}-runner"
  resource_group_name   = azurerm_resource_group.state.name
  private_dns_zone_name = azurerm_private_dns_zone.blob[0].name
  virtual_network_id    = azurerm_virtual_network.runner[0].id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "state_blob" {
  count               = var.use_self_hosted_runner ? 1 : 0
  name                = "pe-${var.names.state_storage}-blob"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location
  subnet_id           = azurerm_subnet.private_endpoints[0].id
  tags                = var.tags

  private_service_connection {
    name                           = "state-blob"
    private_connection_resource_id = azapi_resource.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob[0].id]
  }
}

resource "azurerm_linux_virtual_machine" "runner" {
  count                           = var.use_self_hosted_runner ? 1 : 0
  name                            = local.runner_name
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  size                            = var.runner_vm_size
  admin_username                  = "githubrunner"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.runner[0].id]
  custom_data                     = base64encode(file("${path.module}/runner-cloud-init.yaml"))
  tags                            = var.tags

  admin_ssh_key {
    username   = "githubrunner"
    public_key = var.runner_ssh_public_key
  }

  os_disk {
    name                 = "osdisk-${local.runner_name}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}

  depends_on = [azurerm_private_endpoint.state_blob]
}
