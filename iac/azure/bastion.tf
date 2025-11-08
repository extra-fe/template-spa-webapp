resource "azurerm_network_security_group" "bastion_vm" {
  name                = "${var.app-name}-${var.environment}-bastion-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.local-pc-ip-addresses
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "bastion_vm" {
  name                = "${var.app-name}-${var.environment}-bastion-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

resource "azurerm_network_interface" "bastion_vm" {
  name                = "${var.app-name}-${var.environment}-bastion-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bastion_vm.id
  }
}

data "azurerm_key_vault" "vault" {
  name                = var.public-key-vault-name
  resource_group_name = var.public-key-vault-rg-name
}

data "azurerm_key_vault_secret" "ssh_key" {
  name         = var.public-key-vault-secret
  key_vault_id = data.azurerm_key_vault.vault.id
}

resource "azurerm_linux_virtual_machine" "bastion_vm" {
  name                = "${var.app-name}-${var.environment}-bastion-vm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  network_interface_ids = [
    azurerm_network_interface.bastion_vm.id,
  ]
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  computer_name                   = "${var.app-name}-${var.environment}-bastion"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = data.azurerm_key_vault_secret.ssh_key.value
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}
