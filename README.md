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

*Allow Gateway Transit* and *Use Remote Gateway* are enabled between the Spoke and Hub VNETs, disabled for the Hub VNET peering.

## BGP peering

Each CSR NVA establishes BGP peerings using its NIC IP address:
-	with its local ARS (2 eBGP sessions) 
-	with the remote CSR (1 iBGP session)

Loopback addresses are configured and used for “probing” the NVA route propagation. It is not possible to use loopback addresses on the peering with the ARS.
The ARS is NOT in the data path but will enable the routing information received from the BGP peering between the ARS and the CSR NVA to be added to the Hub and peered VNETs. 

Because the ARS ASN is hard coded to 65515, BGP *as-override* is configured on the CSR NVA BGP sessions towards the ARS. This guarantees the expected route advertisements between the 2 Hub VNETs and further to the Spokes/Branches by replacing the 65515 ARS ASN in the AS-path by the CSR NVA ASN (64000) before readvertisement to the remote ARS. 

Finally, *next-hop-self* is required on the iBGP session between the 2 CSR NVAs so that when routes get advertised from one Hub VNET to the other, the ARS Next-Hop is replaced by the CSR NIC IP.

## UDRs

With this design static routes to the targeted destination VNETs are mandatory on the *CSRSubnet* to avoid routing loops out of the CSR NVA NIC. The UDR constraint can be removed by using VxLAN or IPSec between the 2 CSR NVAs but will result in throughput limitation.

## CSR confdiguration

### CSR1

```
interface Loopback11
 ip address 1.1.1.1 255.255.255.255
!
! default route pointing to CSR subnet default gateway, so that tunnel outside traffic and internet go out LAN port
ip route 0.0.0.0 0.0.0.0 GigabitEthernet1 10.0.253.1
! neighbor reachability of the remote CSR to prevent recursive routing failure ! for CSR2 BGP endpoint learned via BGP
ip route 20.0.253.4 255.255.255.255 GigabitEthernet1 10.0.253.1
! ARS subnet reachability to prevent recursive routing
ip route 10.0.0.0 255.255.255.0 10.0.253.1
!
router bgp 64000
 bgp log-neighbor-changes
 network 1.1.1.1 mask 255.255.255.255
 ! BGP session towards the local ARS instances
 ! as-override will replace 65515 by 64000 in the AS-path of any advertised routes to these 2 neighbors
 neighbor 10.0.0.4 remote-as 65515
 neighbor 10.0.0.4 ebgp-multihop 255
 neighbor 10.0.0.4 as-override
 neighbor 10.0.0.4 soft-reconfiguration inbound
 neighbor 10.0.0.5 remote-as 65515
 neighbor 10.0.0.5 ebgp-multihop 255
 neighbor 10.0.0.5 as-override
 ! BGP session towards the remote CSR
 neighbor 20.0.253.4 remote-as 64000
 ! iBGP session: next-hop-self will force the next-hop of advertised routes (remote ARS) to be replaced by the local CSR address
 neighbor 20.0.253.4 next-hop-self
!
```

### CSR2

```
interface Loopback22
 ip address 2.2.2.2 255.255.255.255
!
! default route pointing to CSR subnet default gateway, so that tunnel outside traffic and internet go out LAN port
ip route 0.0.0.0 0.0.0.0 GigabitEthernet1 20.0.253.1
! neighbor reachability of the remote CSR to prevent recursive routing failure ! for CSR1 BGP endpoint learned via BGP
ip route 10.0.253.4 255.255.255.255 GigabitEthernet1 20.0.253.1
! ARS subnet reachability to prevent recursive routing failure
ip route 20.0.0.0 255.255.255.0 20.0.253.1
!
router bgp 64000
 bgp log-neighbor-changes
 network 2.2.2.2 mask 255.255.255.255
 ! BGP session towards the remote CSR
 neighbor 10.0.253.4 remote-as 64000
 ! iBGP session: next-hop-self will force the next-hop of advertised routes (remote ARS) to be replaced by the local CSR address
 neighbor 10.0.253.4 next-hop-self
 ! BGP session towards the local ARS instances
 ! as-override will replace 65515 by 64000 in the AS-path of any advertised routes to these 2 neighbors
 neighbor 20.0.0.4 remote-as 65515
 neighbor 20.0.0.4 ebgp-multihop 255
 neighbor 20.0.0.4 as-override
 neighbor 20.0.0.5 remote-as 65515
 neighbor 20.0.0.5 ebgp-multihop 255
 neighbor 20.0.0.5 as-override
!
```

## Troubleshooting

| Component | Description | GUI / CLI |
| --- | --- | --- |
| VMs | routes used by a given NIC | GUI / NIC *Effective routes* blade |
| VPN GW | BGP learned and advertised routes | GUI / VPNGW *BGP peers* blade |
| ARS | routes learned from the NVA | az CLI / `az network routeserver peering list-learned-routes --name <rs_peer_name> --routeserver <rs_name> --resource-group <rg_name>` |
| ARS | routes advertised to the NVA | az CLI / `az network routeserver peering list-advertised-routes --name <rs_peer_name> --routeserver <rs_name> --resource-group <rg_name>` 
| CSR | BGP session status | Cisco CLI / `show ip bgp summary` |
| CSR | BGP routes learned from specified neighbor | Cisco CLI / `show ip bgp neighbors <peer_ip_@> routes` |
| CSR | advertised BGP routes | Cisco CLI / `show ip bgp neighbors <peer_ip_@> advertised-routes` |
| CSR | BGP originated routes in the IP routing table | Cisco CLI / `show ip route bgp` |

# 5. Scenario 1: Spoke-to-Spoke

Spoke to Spoke communication transits via the CSR NVA BGP peering.
The ARS in Hub1 VNET is learning the Hub2 and Spoke 2 ranges from the Hub1 CSR NVA:
<img width="196" alt="Scenario 1_ARS_Spoke routes_NVA learned" src="https://user-images.githubusercontent.com/110976272/193460642-2685a3e9-c556-4b7b-af40-e25e96906f4a.png">

Hub2 & Spoke 2 ranges (20.0.0.0/16 & 20.3.0.0/16) have the Hub1 CSR NVA as next-hop virtual gateway:
<img width="698" alt="Scenario 1_Spoke1VM_Effective routes" src="https://user-images.githubusercontent.com/110976272/193460684-349a7d4a-a9b5-42cc-a605-e41b9c9b5141.png">

The same observations are mirrored on ARS2 and Spoke2VM.
 
# 6. Scenario 2: Azure <=> On-prem

## Nominal mode
 
In nominal mode traffic between Azure and On-prem transits via the “local” VPN GW.
 diagram?
 
The ARS1 advertised routes to the CSR NVA contain the 10.2.0.0/16 On-prem range with AS-path = Branch1VPNGW (300) > Hub1VPNGW (100) > ARS1 (65515):
<img width="234" alt="Scenario 2_ARS_Onprem routes_advertised to NVA" src="https://user-images.githubusercontent.com/110976272/193461058-1f88d944-9472-4c05-99c9-f24d6dfc903b.png">

The ARS1 learned routes from the CSR NVA show that this same 10.2.0.0/16 On-prem route is reflected by the NVA from the ARS, as per the the AS-path: Branch1VPNGW (300) > Hub1VPNGW (100) > ARS1 ASN overridden (64000) > NVA1 ASN (64000):
<img width="194" alt="Scenario 2_ARS_Onprem routes_NVA learned" src="https://user-images.githubusercontent.com/110976272/193461076-0f31fb53-6ff0-4231-924e-a1acfc45e255.png">
This looped route will no further be used but illustrate the impact of the as-override command configured on the CSR NVA session with the ASR.

Traffic from the Azure Spoke VNETs to the 10.2.0.0/16 On-prem subnet is sent to the peered Hub VPN GW. Effective routes of Spoke1VM-nic:
<img width="698" alt="Scenario 2_Spoke1VM_Effective routes" src="https://user-images.githubusercontent.com/110976272/193461177-fc5b5761-7d16-43cf-8db6-916567e18029.png">

## Failover mode

# 7. Scenario 3: On-prem to On-prem


