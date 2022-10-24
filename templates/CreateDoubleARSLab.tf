terraform {
    required_providers {
        azurerm = {
            source  = "hashicorp/azurerm"
            version = "~> 3.26"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
    features {}
}

######################### Region1 deployment #########################


############################
# Ressource group Region 1 #
############################

resource "azurerm_resource_group" "RG1" {
    name = var.resource_group1_name
    location = var.region1
}

#################################
###### Hub1 VNET & subnets ######
#################################

resource "azurerm_virtual_network" "Hub1" {
    name                = "Hub1"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    address_space       = var.Hub1VNETRange
}

resource "azurerm_subnet" "Hub1GWSubnet" {
    name                 = "GatewaySubnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Hub1.name
    address_prefixes     = var.Hub1GWSubnet
}

resource "azurerm_subnet" "ARS1Subnet" {
    name                 = "RouteServerSubnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Hub1.name
    address_prefixes     = var.ARS1Subnet
}

resource "azurerm_subnet" "CSR1Subnet" {
    name                 = "CSR1Subnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Hub1.name
    address_prefixes     = var.CSR1Subnet
}

resource "azurerm_subnet" "Hub1VMSubnet" {
    name                 = "Hub1VMSubnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Hub1.name
    address_prefixes     = var.Hub1VMSubnet
}

resource "azurerm_subnet" "Hub1BastionSubnet" {
    name                 = "BastionSubnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Hub1.name
    address_prefixes     = var.Hub1BastionSubnet
}

##################################
###### Spoke1 VNET & subnet ######
##################################

resource "azurerm_virtual_network" "Spoke1" {
    name                = "Spoke1"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    address_space       = var.Spoke1VNETRange
}

resource "azurerm_subnet" "Spoke1VMSubnet" {
    name                 = "Spoke1VMSubnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Spoke1.name
    address_prefixes     = var.Spoke1VMSubnet
}

####################################
###### Branch1 VNET & subnets ######
####################################

resource "azurerm_virtual_network" "Branch1" {
    name                = "Branch1"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    address_space       = var.Branch1VNETRange
}

resource "azurerm_subnet" "Branch1GWSubnet" {
    name                 = "GatewaySubnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Branch1.name
    address_prefixes     = var.Branch1GWSubnet
}

resource "azurerm_subnet" "Branch1VMSubnet" {
    name = "Branch1VMSubnet"
    resource_group_name  = azurerm_resource_group.RG1.name
    virtual_network_name = azurerm_virtual_network.Branch1.name
    address_prefixes     = var.Branch1VMSubnet
}

#################################
###### Hub1/Spoke1 peering ######
#################################

resource "azurerm_virtual_network_peering" "Hub1-Spoke1" {
    name                         = "Hub1-Spoke1"
    resource_group_name          = azurerm_resource_group.RG1.name
    virtual_network_name         = azurerm_virtual_network.Hub1.name
    remote_virtual_network_id    = azurerm_virtual_network.Spoke1.id
    allow_virtual_network_access = true
    allow_forwarded_traffic      = true
    allow_gateway_transit        = true
}

resource "azurerm_virtual_network_peering" "Spoke1-Hub1" {
    name                          = "Spoke1-Hub1"
    resource_group_name           = azurerm_resource_group.RG1.name
    virtual_network_name          = azurerm_virtual_network.Spoke1.name
    remote_virtual_network_id     = azurerm_virtual_network.Hub1.id
    allow_virtual_network_access  = true
    allow_forwarded_traffic       = true
    allow_gateway_transit         = false
}

#####################
###### RG1 VMs ######
#####################

###### Hub1 VM ######

resource "azurerm_network_interface" "Hub1VM-NIC" {
    name                = "Hub1VM-NIC"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.Hub1VMSubnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

resource "azurerm_linux_virtual_machine" "Hub1VM" {
    name                  = "Hub1VM"
    resource_group_name   = azurerm_resource_group.RG1.name
    location              = var.region1
    size                  = "Standard_B2s"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.Hub1VM-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }
    source_image_reference { 
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }
}

###### Hub1 CSR ######

resource "azurerm_network_interface" "CSR1-NIC" {
    name                = "CSR1-NIC"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.CSR1Subnet.id
        private_ip_address_allocation = "Static"
        private_ip_address_version    = "IPv4"
        private_ip_address            = "10.0.253.4"
        
    }
}

resource "azurerm_linux_virtual_machine" "CSR1" {
    name                  = "CSR1"
    resource_group_name   = azurerm_resource_group.RG1.name
    location              = var.region1
    size                  = "Standard_DS2_v2"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.CSR1-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "StandardSSD_LRS"
    }

    plan {
        publisher = "cisco"
        name      = "cisco-csr-1000v"
        product   = "17_03_06-byol"
    }

    source_image_reference {
        publisher = "cisco"
        offer     = "cisco-csr-1000v"
        sku       = "17_03_06-byol"
        version   = "latest"
    }
}

###### Spoke1 VM ######

resource "azurerm_network_interface" "Spoke1VM-NIC" {
    name                = "Spoke1VM-NIC"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.Spoke1VMSubnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

resource "azurerm_linux_virtual_machine" "Spoke1VM" {
    name                  = "Spoke1VM"
    resource_group_name   = azurerm_resource_group.RG1.name
    location              = var.region1
    size                  = "Standard_B2s"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.Spoke1VM-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }
    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }
}

###### Branch1 VM ######

resource "azurerm_network_interface" "Branch1VM-NIC" {
    name                = "Branch1VM-NIC"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.Branch1VMSubnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

resource "azurerm_linux_virtual_machine" "Branch1VM" {
    name                  = "Branch1VM"
    resource_group_name   = azurerm_resource_group.RG1.name
    location              = var.region1
    size                  = "Standard_B2s"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.Branch1VM-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }
    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }
}

#########################
###### RG1 VPN GWs ######
#########################

###### Hub1 VPN GW ######

resource "azurerm_public_ip" "Hub1VPNGW-PIP1" {
    name                = "Hub1VPNGW-PIP1"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    allocation_method   = "Dynamic"
}

resource "azurerm_public_ip" "Hub1VPNGW-PIP2" {
    name                = "Hub1VPNGW-PIP2"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "Hub1VPNGW" {
    name                = "Hub1VPNGW"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name

    type     = "Vpn"
    vpn_type = "RouteBased"

    active_active = true
    enable_bgp    = true
    sku           = "VpnGw2"

    ip_configuration {
        name                          = "Hub1VPNGWConfig1"
        public_ip_address_id          = azurerm_public_ip.Hub1VPNGW-PIP1.id
        subnet_id                     = azurerm_subnet.Hub1GWSubnet.id
        private_ip_address_allocation = "Dynamic"
    }

    ip_configuration {
        name                          = "Hub1VPNGWConfig2"
        public_ip_address_id          = azurerm_public_ip.Hub1VPNGW-PIP2.id
        subnet_id                     = azurerm_subnet.Hub1GWSubnet.id
        private_ip_address_allocation = "Dynamic"
    }

    bgp_settings {
        asn = 100
    }  
}

###### Branch1 VPN GW ######

resource "azurerm_public_ip" "Branch1VPNGW-PIP" {
    name                = "Branch1VPNGW-PIP"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name
    allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "Branch1VPNGW" {
    name                = "Branch1VPNGW"
    location            = var.region1
    resource_group_name = azurerm_resource_group.RG1.name

    type     = "Vpn"
    vpn_type = "RouteBased"

    active_active = false
    enable_bgp    = true
    sku           = "VpnGw2"

    ip_configuration {
        name                          = "Branch1VPNGWConfig"
        public_ip_address_id          = azurerm_public_ip.Branch1VPNGW-PIP.id
        subnet_id                     = azurerm_subnet.Branch1GWSubnet.id
        private_ip_address_allocation = "Dynamic"
    }

    bgp_settings {
        asn = 300
    }  
}

###### RG1 Local Network Gateways & Connections ######

resource "azurerm_local_network_gateway" "Hub1Branch1-LNG" {
    name                = "Hub1Branch1-LNG"
    resource_group_name = azurerm_resource_group.RG1.name
    location            = var.region1
    gateway_address     = "$(azurerm_public_ip.Branch1VPNGW-PIP.ip_address)"

    bgp_settings {
        asn = 300
        bgp_peering_address = "10.2.254.4"
    }
}

resource "azurerm_virtual_network_gateway_connection" "Hub1Branch1-Conn" {
  name                       = "Hub1Branch1-Conn"
  location                   = var.region1
  resource_group_name        = azurerm_resource_group.RG1.name
  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.Hub1VPNGW.id
  local_network_gateway_id   = azurerm_local_network_gateway.Hub1Branch1-LNG.id
  shared_key                 = "SecretK3y"
}


resource "azurerm_local_network_gateway" "Branch1Hub1-LNG" {
    name                = "Branch1Hub1-LNG"
    resource_group_name = azurerm_resource_group.RG1.name
    location            = var.region1
    gateway_address     = "$(azurerm_public_ip.Hub1VPNGW-PIP1.ip_address)"

    bgp_settings {
        asn = 100
        bgp_peering_address = "10.0.254.4"
  }
}

resource "azurerm_virtual_network_gateway_connection" "Branch1Hub1-Conn" {
    name                       = "Branch1Hub1-Conn"
    location                   = var.region1
    resource_group_name        = azurerm_resource_group.RG1.name
    type                       = "IPsec"
    virtual_network_gateway_id = azurerm_virtual_network_gateway.Branch1VPNGW.id
    local_network_gateway_id   = azurerm_local_network_gateway.Branch1Hub1-LNG.id
    shared_key                 = "SecretK3y"
}

#######################
###### Hub1 ARS #######
#######################

resource "azurerm_public_ip" "ARS1_PIP" {
    name                = "ARS1-PIP"
    resource_group_name = azurerm_resource_group.RG1.name
    location            = var.region1
    allocation_method   = "Static"
    sku                 = "Standard"
}

resource "azurerm_route_server" "ARS1" {
    name                             = "ARS1"
    resource_group_name              = azurerm_resource_group.RG1.name
    location                         = var.region1
    sku                              = "Standard"
    public_ip_address_id             = azurerm_public_ip.ARS1_PIP.id
    subnet_id                        = azurerm_subnet.ARS1Subnet.id
    branch_to_branch_traffic_enabled = true
}

resource "azurerm_route_server_bgp_connection" "ARS1BGP" {
    name            = "ARS1BGP"
    route_server_id = azurerm_route_server.ARS1.id
    peer_asn        = "64000"
    peer_ip         = azurerm_network_interface.CSR1-NIC.ip_configuration[0].private_ip_address
}

######################### Region2 deployment #########################


############################
# Ressource group Region 2 #
############################

resource "azurerm_resource_group" "RG2" {
    name = var.resource_group2_name
    location = var.region2
}

#################################
###### Hub2 VNET & subnets ######
#################################

resource "azurerm_virtual_network" "Hub2" {
    name                = "Hub2"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    address_space       = var.Hub2VNETRange
}

resource "azurerm_subnet" "Hub2GWSubnet" {
    name                 = "GatewaySubnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Hub2.name
    address_prefixes     = var.Hub2GWSubnet
}

resource "azurerm_subnet" "ARS2Subnet" {
    name                 = "RouteServerSubnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Hub2.name
    address_prefixes     = var.ARS2Subnet
}

resource "azurerm_subnet" "CSR2Subnet" {
    name                 = "CSR2Subnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Hub2.name
    address_prefixes     = var.CSR2Subnet
}

resource "azurerm_subnet" "Hub2VMSubnet" {
    name                 = "Hub2VMSubnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Hub2.name
    address_prefixes     = var.Hub2VMSubnet
}

resource "azurerm_subnet" "Hub2BastionSubnet" {
    name                 = "BastionSubnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Hub2.name
    address_prefixes     = var.Hub2BastionSubnet
}

##################################
###### Spoke2 VNET & subnet ######
##################################

resource "azurerm_virtual_network" "Spoke2" {
    name                = "Spoke2"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    address_space       = var.Spoke2VNETRange
}

resource "azurerm_subnet" "Spoke2VMSubnet" {
    name                 = "Spoke2VMSubnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Spoke2.name
    address_prefixes     = var.Spoke2VMSubnet
}

####################################
###### Branch2 VNET & subnets ######
####################################

resource "azurerm_virtual_network" "Branch2" {
    name                = "Branch2"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    address_space       = var.Branch2VNETRange
}

resource "azurerm_subnet" "Branch2GWSubnet" {
    name                 = "GatewaySubnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Branch2.name
    address_prefixes     = var.Branch2GWSubnet
}

resource "azurerm_subnet" "Branch2VMSubnet" {
    name = "Branch2VMSubnet"
    resource_group_name  = azurerm_resource_group.RG2.name
    virtual_network_name = azurerm_virtual_network.Branch2.name
    address_prefixes     = var.Branch2VMSubnet
}

#################################
###### Hub2/Spoke2 peering ######
#################################

resource "azurerm_virtual_network_peering" "Hub2-Spoke2" {
    name                         = "Hub2-Spoke2"
    resource_group_name          = azurerm_resource_group.RG2.name
    virtual_network_name         = azurerm_virtual_network.Hub2.name
    remote_virtual_network_id    = azurerm_virtual_network.Spoke2.id
    allow_virtual_network_access = true
    allow_forwarded_traffic      = true
    allow_gateway_transit        = true
}

resource "azurerm_virtual_network_peering" "Spoke2-Hub2" {
    name                          = "Spoke2-Hub2"
    resource_group_name           = azurerm_resource_group.RG2.name
    virtual_network_name          = azurerm_virtual_network.Spoke2.name
    remote_virtual_network_id     = azurerm_virtual_network.Hub2.id
    allow_virtual_network_access  = true
    allow_forwarded_traffic       = true
    allow_gateway_transit         = false
}

#####################
###### RG2 VMs ######
#####################

###### Hub2 VM ######

resource "azurerm_network_interface" "Hub2VM-NIC" {
    name                = "Hub2VM-NIC"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.Hub2VMSubnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

resource "azurerm_linux_virtual_machine" "Hub2VM" {
    name                  = "Hub2VM"
    resource_group_name   = azurerm_resource_group.RG2.name
    location              = var.region2
    size                  = "Standard_B2s"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.Hub2VM-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }
    source_image_reference { 
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }
}

###### Hub2 CSR ######

resource "azurerm_network_interface" "CSR2-NIC" {
    name                = "CSR2-NIC"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.CSR2Subnet.id
        private_ip_address_allocation = "Static"
        private_ip_address_version    = "IPv4"
        private_ip_address            = "20.0.253.4"
        
    }
}

resource "azurerm_linux_virtual_machine" "CSR2" {
    name                  = "CSR2"
    resource_group_name   = azurerm_resource_group.RG2.name
    location              = var.region2
    size                  = "Standard_DS2_v2"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.CSR2-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "StandardSSD_LRS"
    }

    plan {
        publisher = "cisco"
        name      = "cisco-csr-1000v"
        product   = "17_03_06-byol"
    }

    source_image_reference {
        publisher = "cisco"
        offer     = "cisco-csr-1000v"
        sku       = "17_03_06-byol"
        version   = "latest"
    }
}

###### Spoke2 VM ######

resource "azurerm_network_interface" "Spoke2VM-NIC" {
    name                = "Spoke2VM-NIC"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.Spoke2VMSubnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

resource "azurerm_linux_virtual_machine" "Spoke2VM" {
    name                  = "Spoke2VM"
    resource_group_name   = azurerm_resource_group.RG2.name
    location              = var.region2
    size                  = "Standard_B2s"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.Spoke2VM-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }
    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }
}

###### Branch2 VM ######

resource "azurerm_network_interface" "Branch2VM-NIC" {
    name                = "Branch2VM-NIC"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    
    ip_configuration {
        name                          = "internal"
        subnet_id                     = azurerm_subnet.Branch2VMSubnet.id
        private_ip_address_allocation = "Dynamic"
    }
}

resource "azurerm_linux_virtual_machine" "Branch2VM" {
    name                  = "Branch2VM"
    resource_group_name   = azurerm_resource_group.RG2.name
    location              = var.region2
    size                  = "Standard_B2s"
    admin_username        = var.admin_username
    admin_password        = var.admin_password
    disable_password_authentication = false
    network_interface_ids = [
        azurerm_network_interface.Branch2VM-NIC.id,
    ]
    
    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }
    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }
}

#########################
###### RG2 VPN GWs ######
#########################

###### Hub2 VPN GW ######

resource "azurerm_public_ip" "Hub2VPNGW-PIP1" {
    name                = "Hub2VPNGW-PIP1"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    allocation_method   = "Dynamic"
}

resource "azurerm_public_ip" "Hub2VPNGW-PIP2" {
    name                = "Hub2VPNGW-PIP2"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "Hub2VPNGW" {
    name                = "Hub2VPNGW"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name

    type     = "Vpn"
    vpn_type = "RouteBased"

    active_active = true
    enable_bgp    = true
    sku           = "VpnGw2"

    ip_configuration {
        name                          = "Hub2VPNGWConfig1"
        public_ip_address_id          = azurerm_public_ip.Hub2VPNGW-PIP1.id
        subnet_id                     = azurerm_subnet.Hub2GWSubnet.id
        private_ip_address_allocation = "Dynamic"
    }

    ip_configuration {
        name                          = "Hub2VPNGWConfig2"
        public_ip_address_id          = azurerm_public_ip.Hub2VPNGW-PIP2.id
        subnet_id                     = azurerm_subnet.Hub2GWSubnet.id
        private_ip_address_allocation = "Dynamic"
    }

    bgp_settings {
        asn = 100
    }  
}

###### Branch2 VPN GW ######

resource "azurerm_public_ip" "Branch2VPNGW-PIP" {
    name                = "Branch2VPNGW-PIP"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name
    allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "Branch2VPNGW" {
    name                = "Branch2VPNGW"
    location            = var.region2
    resource_group_name = azurerm_resource_group.RG2.name

    type     = "Vpn"
    vpn_type = "RouteBased"

    active_active = false
    enable_bgp    = true
    sku           = "VpnGw2"

    ip_configuration {
        name                          = "Branch2VPNGWConfig"
        public_ip_address_id          = azurerm_public_ip.Branch2VPNGW-PIP.id
        subnet_id                     = azurerm_subnet.Branch2GWSubnet.id
        private_ip_address_allocation = "Dynamic"
    }

    bgp_settings {
        asn = 300
    }  
}

###### RG2 Local Network Gateways & Connections ######

resource "azurerm_local_network_gateway" "Hub2Branch2-LNG" {
    name                = "Hub2Branch2-LNG"
    resource_group_name = azurerm_resource_group.RG2.name
    location            = var.region2
    gateway_address     = "$(azurerm_public_ip.Branch2VPNGW-PIP.ip_address)"

    bgp_settings {
        asn = 300
        bgp_peering_address = "10.2.254.4"
    }
}

resource "azurerm_virtual_network_gateway_connection" "Hub2Branch2-Conn" {
    name                       = "Hub2Branch2-Conn"
    location                   = var.region2
    resource_group_name        = azurerm_resource_group.RG2.name
    type                       = "IPsec"
    virtual_network_gateway_id = azurerm_virtual_network_gateway.Hub2VPNGW.id
    local_network_gateway_id   = azurerm_local_network_gateway.Hub2Branch2-LNG.id
    shared_key                 = "SecretK3y"
    }


resource "azurerm_local_network_gateway" "Branch2Hub2-LNG" {
    name                = "Branch2Hub2-LNG"
    resource_group_name = azurerm_resource_group.RG2.name
    location            = var.region2
    gateway_address     = "$(azurerm_public_ip.Hub2VPNGW-PIP1.ip_address)"

    bgp_settings {
        asn = 100
        bgp_peering_address = "20.0.254.4"
  }
}

resource "azurerm_virtual_network_gateway_connection" "Branch2Hub2-Conn" {
    name                       = "Branch2Hub2-Conn"
    location                   = var.region2
    resource_group_name        = azurerm_resource_group.RG2.name
    type                       = "IPsec"
    virtual_network_gateway_id = azurerm_virtual_network_gateway.Branch2VPNGW.id
    local_network_gateway_id   = azurerm_local_network_gateway.Branch2Hub2-LNG.id
    shared_key                 = "SecretK3y"
}

#######################
###### Hub2 ARS #######
#######################

resource "azurerm_public_ip" "ARS2_PIP" {
    name                = "ARS2-PIP"
    resource_group_name = azurerm_resource_group.RG2.name
    location            = var.region2
    allocation_method   = "Static"
    sku                 = "Standard"
}

resource "azurerm_route_server" "ARS2" {
    name                             = "ARS2"
    resource_group_name              = azurerm_resource_group.RG2.name
    location                         = var.region2
    sku                              = "Standard"
    public_ip_address_id             = azurerm_public_ip.ARS2_PIP.id
    subnet_id                        = azurerm_subnet.ARS2Subnet.id
    branch_to_branch_traffic_enabled = true
}

resource "azurerm_route_server_bgp_connection" "ARS2BGP" {
    name            = "ARS2BGP"
    route_server_id = azurerm_route_server.ARS2.id
    peer_asn        = "64000"
    peer_ip         = azurerm_network_interface.CSR2-NIC.ip_configuration[0].private_ip_address
}

###############################
###### Hub1/Hub2 peering ######
############################### 

resource "azurerm_virtual_network_peering" "Hub1-Hub2" {
    name                         = "Hub1-Hub2"
    resource_group_name          = azurerm_resource_group.RG1.name
    virtual_network_name         = azurerm_virtual_network.Hub1.name
    remote_virtual_network_id    = azurerm_virtual_network.Hub2.id
    allow_virtual_network_access = true
    allow_forwarded_traffic      = true
    allow_gateway_transit        = false
}

resource "azurerm_virtual_network_peering" "Hub2-Hub1" {
    name                          = "Hub2-Hub1"
    resource_group_name           = azurerm_resource_group.RG2.name
    virtual_network_name          = azurerm_virtual_network.Hub2.name
    remote_virtual_network_id     = azurerm_virtual_network.Hub1.id
    allow_virtual_network_access  = true
    allow_forwarded_traffic       = true
    allow_gateway_transit         = false
}