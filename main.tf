terraform {
  #required_version = ">=1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.19.0"
    }
    #random = {
    #  source  = "hashicorp/random"
    # version = "3.6.3"
    #}
  }

   backend "azurerm" {
    resource_group_name  = "terraform-backend-rg"
    storage_account_name = "demoterraformstg"
    container_name       = "azureterraformstate"
    key                  = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  #subscription_id = "6afbc9be-d7fa-42c8-b64f-40f20a891093"
  #tenant_id       = "2539017a-c353-4780-9e06-3623d10dd919"
  #client_id       = "ce0ec517-4831-44c6-841f-2bac07b5e2c8"
  #"
}

resource "random_string" "random" {
  length  = 10
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg1" {
  name     = "dell${random_string.random.id}"
  location = "eastus"

  tags = {
    environment = "Dev"
    Dept        = "IT"
  }
}

resource "azurerm_virtual_network" "myVnet3" {
  name                = "myVnet3"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name

  tags = {
    environment = "Dev"
    Dept        = "IT"
  }
}

resource "azurerm_subnet" "mysubnet" {
  name                 = "mysubnet"
  resource_group_name  = azurerm_resource_group.rg1.name
  virtual_network_name = azurerm_virtual_network.myVnet3.name
  address_prefixes     = ["10.10.1.0/24"]

}

resource "azurerm_public_ip" "mypublicip" {
  name                = "mysubnet"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  allocation_method   = "Static"


  tags = {
    environment = "Dev"
    Dept        = "IT"
  }
}

resource "azurerm_network_interface" "myvmnic" {
  name                = "mysubnet"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location
  ip_configuration {
    name                          = "myvmicConfig"
    subnet_id                     = azurerm_subnet.mysubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mypublicip.id
  }
  tags = {
    environment = "Dev"
    Dept        = "IT"
  }

}

resource "azurerm_network_security_group" "mynsg" {
  name                = "mynsg"
  resource_group_name = azurerm_resource_group.rg1.name
  location            = azurerm_resource_group.rg1.location

  tags = {
    environment = "Dev"
    Dept        = "IT"
  }

  security_rule {
    name                       = "Allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "mysubnet-association" {
  subnet_id                 = azurerm_subnet.mysubnet.id
  network_security_group_id = azurerm_network_security_group.mynsg.id

}

resource "azurerm_linux_virtual_machine" "mylinuxvm" {
  name                = "mylinuxvm-1"
  computer_name       = "devlinuxvm-1"
  location            = azurerm_resource_group.rg1.location
  resource_group_name = azurerm_resource_group.rg1.name
  size                = "Standard_B1s"
  admin_username      = "aks357"
  #admin_password      = "Password1234"
  admin_ssh_key {
    username   = "aks357"
    public_key = file("~/.ssh/id_ed25519.pub") #public key to vm
  }
  #disable_password_authentication = false
  network_interface_ids = [azurerm_network_interface.myvmnic.id]
  os_disk {
    name                 = "myOsDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  source_image_reference {
   publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = "echo ${azurerm_linux_virtual_machine.mylinuxvm.public_ip_address} > public_ip.txt"
  }
}

resource "null_resource" "file_copy_remote_exec" {
  provisioner "file" {
    source      = "${path.module}/apache-install.sh"
    destination = "/tmp/apache-install.sh"
    connection {
      type        = "ssh"
      host        = azurerm_public_ip.mypublicip.ip_address
      user        = "aks357"
      private_key = file("~/.ssh/id_ed25519")
     
    }
  }
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = azurerm_public_ip.mypublicip.ip_address
      user        = "aks357"
      private_key = file("~/.ssh/id_ed25519")
      }
    inline = [
      "sudo chmod +x /tmp/apache-install.sh",
      "sudo /tmp/apache-install.sh"
    ]
  }
  depends_on = [azurerm_linux_virtual_machine.mylinuxvm]
}