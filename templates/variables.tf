######################
# Region 1 variables #
######################

variable "resource_group1_name" {
  default = "ars-lab1"
}

variable "resource_group1_location" {
  default = "westeurope"
}

variable "region1" {
    default = "westeurope"
}

# Hub1 variables #

variable Hub1VNETRange {
default = ["10.0.0.0/16"]
}

variable Hub1GWSubnet {
default = ["10.0.254.0/24"]
}

variable ARS1Subnet {
default = ["10.0.0.0/24"]
}

variable CSR1Subnet {
default = ["10.0.253.0/24"]
}

variable Hub1VMSubnet {
default = ["10.0.1.0/24"]
}

variable Hub1BastionSubnet {
default = ["10.0.255.0/24"]
}

# Spoke1 variables #

variable Spoke1VNETRange {
default = ["10.3.0.0/16"]
}

variable Spoke1VMSubnet {
default = ["10.3.0.0/24"]
}

# PseudoOnprem1 variables #

variable Branch1VNETRange {
default = ["10.2.0.0/16"]
}

variable Branch1GWSubnet {
default = ["10.2.254.0/24"]
}

variable Branch1VMSubnet {
default = ["10.2.0.0/24"]
}

######################
# Region 2 variables #
######################

variable "resource_group2_name" {
  default = "ars-lab2"
}

variable "resource_group2_location" {
  default = "northeurope"
}

variable "region2" {
    default = "northeurope"
}

# Hub2 variables #

variable Hub2VNETRange {
default = ["20.0.0.0/16"]
}

variable Hub2GWSubnet {
default = ["20.0.254.0/24"]
}

variable ARS2Subnet {
default = ["20.0.0.0/24"]
}

variable CSR2Subnet {
default = ["20.0.253.0/24"]
}

variable Hub2VMSubnet {
default = ["20.0.1.0/24"]
}

variable Hub2BastionSubnet {
default = ["20.0.255.0/24"]
}

# Spoke2 variables #

variable Spoke2VNETRange {
default = ["20.3.0.0/16"]
}

variable Spoke2VMSubnet {
default = ["20.3.0.0/24"]
}

# PseudoOnprem2 variables #

variable Branch2VNETRange {
default = ["10.2.0.0/16"]
}

variable Branch2GWSubnet {
default = ["10.2.254.0/24"]
}

variable Branch2VMSubnet {
default = ["10.2.0.0/24"]
}