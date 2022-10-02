# DIY vWAN: double Hub VNET and Azure Route Server

# 1. Suggested pre-reading

This lab is inspired by:
-	Scenarios 4 & 5 of the [jocortems/azurehybridnetworking/ExpressRoute-Transit-with-Azure-RouteServer](https://github.com/jocortems/azurehybridnetworking/tree/main/ExpressRoute-Transit-with-Azure-RouteServer#4-multi-region--multi-nic-nvas-with-route-tables)
- Deplyment of an ARS with Cisco CSR NVA Hub VNET : [mddazure/azure-route-server-lab](https://github.com/mddazure/azure-route-server-lab).

Great MicroHack for a deep-dive on ARS routing scenarios : [malgebary/Azure-Route-Server-MicroHack](https://github.com/malgebary/Azure-Route-Server-MicroHack)

# 2. Introduction

This lab demonstrates how a double Hub & Spoke topology leveraging Azure Route Server (ARS) can be used to provide On-prem, Transit and Inter-region connectivity as well as On-prem failover, i.e. a customer-managed version of a small vWAN deployment.

Why?

The Inter-region (Spoke-to-Spoke) and On-prem scenarios have been successfully deployed with both S2S VPN and ER On-prem connectivity. For simplicity and ease of reproduction, only the S2S VPN deployment is detailed here.

# 3. Lab Description and Topology

## Description

The lab consists of 2 regions, each hosting:
-	1 Hub VNET
-	1 peered Spoke VNET
-	1 Branch VNET emulating the On-prem

The 2 Hub VNETs are connected by VNET peering.

The connectivity between Azure and On-prem is provided by S2S VPN.

Each VNET contains a test VM in the *VMSubnet*.

In addition, each hub VNET contains:
-	1 x ARS in the *RouteServerSubnet*
-	1 x active/active VPN GW (mandatory for the deployment of ARS in the Hub VNET) in the GatewaySubnet
-	1 x CSR NVA in the *CSRSubnet*

Bastion is configured in the Hub and Branch VNETs for VM connectivity.

*The On-prem is emulated by 2 separate Branch VNETs configured intentionally with the same address space, to appear as a single network from the Azure VNETs and avoid the transitivity that would have resulted from having a single Branch VNET with 2 tunnels to each Hub VPN GWs.*

## Topology

<Diagram>

# 4. Routing and Troubleshooting

## VNET peering

## BGP peering

## ARS

## UDRs

## Troubleshooting

<Table> 

# 5. Scenario 1: Spoke-to-Spoke

# 6. Scenario 2: Azure <=> On-prem

## 6.1. Nominal mode

## 6.2. Failover mode

# 7. Scenario 3: On-prem to On-prem


