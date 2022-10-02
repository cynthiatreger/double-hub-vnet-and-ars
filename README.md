# DIY vWAN: double Hub VNET and Azure Route Server

# 1. Suggested pre-reading

This lab is inspired by:
-	Scenarios 4 & 5 of the [jocortems/azurehybridnetworking/ExpressRoute-Transit-with-Azure-RouteServer](https://github.com/jocortems/azurehybridnetworking/tree/main/ExpressRoute-Transit-with-Azure-RouteServer#4-multi-region--multi-nic-nvas-with-route-tables)
- Deplyment of an ARS with Cisco CSR NVA Hub VNET : [mddazure/azure-route-server-lab](https://github.com/mddazure/azure-route-server-lab).

Great MicroHack for a deep-dive on ARS routing scenarios : [malgebary/Azure-Route-Server-MicroHack](https://github.com/malgebary/Azure-Route-Server-MicroHack)

# 2. Introduction

This lab demonstrates how a double Hub & Spoke topology leveraging Azure Route Server (ARS) can be used to provide On-prem and Inter-region connectivity as well as On-prem failover, i.e. a customer-managed version of a small vWAN deployment.

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

## CSR configuration

CSR1
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

CSR2
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
| CSR | BGP neighbors & session status | Cisco CLI / `show ip bgp summary` |
| CSR | BGP routes learned from specified neighbor | Cisco CLI / `show ip bgp neighbors <peer_ip_@> routes` |
| CSR | advertised BGP routes | Cisco CLI / `show ip bgp neighbors <peer_ip_@> advertised-routes` |
| CSR | BGP originated routes in the IP routing table | Cisco CLI / `show ip route bgp` |

# 5. Scenario 1: Spoke-to-Spoke

Spoke to Spoke communication transits via the CSR NVA BGP peering.
Diagram?

In the *Effective Routes* list of Spoke1VM, Hub2 & Spoke2 ranges (20.0.0.0/16 & 20.3.0.0/16) have the Hub1 CSR NVA as next-hop virtual gateway:

<img width="698" alt="Scenario 1_Spoke1VM_Effective routes" src="https://user-images.githubusercontent.com/110976272/193460684-349a7d4a-a9b5-42cc-a605-e41b9c9b5141.png">

### Data path & route analysis:
 
- The ARS in Hub2 is advertising the Hub2 & Spoke2 ranges to the Hub2 CSR NVA:
<img width="219" alt="image" src="https://user-images.githubusercontent.com/110976272/193473914-917ff443-27e0-4d49-bd73-9cfff2fd442b.png">

- The Hub2 CSR NVA is installing these routes in its routing table and forwarding them to the Hub1 CSR NVA:
 <img width="574" alt="Scenario 1_CSR2_sh ip route bgp Spoke" src="https://user-images.githubusercontent.com/110976272/193465413-f14c9bc4-f339-4bbc-bd5a-31570cd3f9a3.png">
 <img width="599" alt="Scenario 1_CSR2_sh ip bgp nei adv routes_Spokes" src="https://user-images.githubusercontent.com/110976272/193465419-5e605e0b-39d5-463f-a4cb-817e366e02ab.png">

- Likewise, the Hub1 CSR NVA is installing the Hub2 & Spoke2 ranges in its routing table and advertising them further to ARS1:
 <img width="585" alt="Scenario 1_CSR_sh ip bgp advertised routes_spoke routes" src="https://user-images.githubusercontent.com/110976272/193465446-abe8678b-7e72-4884-8838-89a8db5b7c8b.png">

- The ARS in Hub1 VNET is learning the Hub2 and Spoke2 ranges from the Hub1 CSR NVA and programming all the VMs in its VNET and peered VNETs with these routes:
 <img width="235" alt="image" src="https://user-images.githubusercontent.com/110976272/193473788-fa4799cd-f457-4f52-9963-dfad714a5674.png">
 
# 6. Scenario 2: Azure <=> On-prem

## 6.1. Nominal mode
 
In nominal mode traffic between Azure and On-prem transits via the “local” VPN GW.
diagram?

Traffic from the Azure Spoke VNETs to the 10.2.0.0/16 On-prem subnet is sent to the peered Hub VPN GW. Effective routes of Spoke1VM-nic:

<img width="698" alt="Scenario 2_Spoke1VM_Effective routes" src="https://user-images.githubusercontent.com/110976272/193461177-fc5b5761-7d16-43cf-8db6-916567e18029.png">

Traffic from On-prem to Azure is directed to the Branch1 VNET VPN GW (Next Hop = 10.2.254.4). Branch1 VPN GW BGP learned routes:

<img width="827" alt="Scenario 2_Branch1 VPNGW learned routes" src="https://user-images.githubusercontent.com/110976272/193461603-711a4680-a216-405b-a1ab-76a31ff837cd.png">

Hub1 & Spoke1 ranges (10.0.0.0/16 & 10.3.0.0/16) are originated from the Hub1 VNET and advertised via the Hub1 VPN GW (AS 100).
 
Hub2 & Spoke2 ranges (20.0.0.0/16 & 20.3.0.0/16) are originated from the Hub2 VNET, propagated to Hub1 VNET and advertised via the Hub1 VPN GW. 
AS-path = ARS2 (65515 rewritten in 64000 when reaching ARS1) > NVA2 (64000) > NVA1 (iBGP) > ARS1 (65515) > VPNGW1 (100)
 
### Data path & route analysis:

- The ARS1 advertised routes to the Hub1 CSR NVA include the 10.2.0.0/16 On-prem range with AS-path = Branch1 VPN GW (300) > Hub1 VPN GW (100) > ARS1 (65515):
 <img width="234" alt="Scenario 2_ARS_Onprem routes_advertised to NVA" src="https://user-images.githubusercontent.com/110976272/193461058-1f88d944-9472-4c05-99c9-f24d6dfc903b.png">
 
 - The ARS1 learned routes from the Hub1 CSR NVA show that this same 10.2.0.0/16 On-prem route is reflected by the NVA from the ARS, as per the AS-path: Branch1VPNGW (300) > Hub1 VPN GW (100) > ARS1 ASN overridden (64000) > NVA1 ASN (64000). This looped route will no further be used but illustrates the impact of the *as-override* command configured on the CSR NVA session with the ASR.
 <img width="194" alt="Scenario 2_ARS_Onprem routes_NVA learned" src="https://user-images.githubusercontent.com/110976272/193466704-1d525002-309c-4bcc-a983-b8a303649894.png">

- The 10.2.0.0/16 On-prem range is also “locally” available in Hub2 and its peered VNETs, and advertised by ARS2 to the Hu2 CSR NVA and further to the Hub1 CSR NVA:
 <img width="221" alt="Scenario 2_ARS2_Onprem routes_advertised" src="https://user-images.githubusercontent.com/110976272/193465940-2194951d-66ab-4e7f-af4b-96cad04e9c0c.png">

However the Hub1 CSR NVA prefers the “local” Hub1 route and will not advertise the routes learned from Hub2.

## 6.2. Failover mode (Hub1 S2S down)

To simulate the failover, the Hub1VPNGW S2S Connection is deleted:

<img width="747" alt="Scenario 2_disable S2S" src="https://user-images.githubusercontent.com/110976272/193461941-49e14adb-fdb7-4867-91d4-92e50c0f56fb.png">

Traffic between Azure and On-prem switches to the cross-Hub VNET NVA path to use the remaining exit to On-prem.

Traffic from Azure to the 10.2.0.0/16 On-prem subnet is now sent to the Hub1 CSR NVA, where it will be passed to the Hub2 CSR NVA and Hub2 VPN GW. Effective routes of Spoke1VM-nic:

<img width="686" alt="Scenario 2_Spoke1VM_Effective routes_failover" src="https://user-images.githubusercontent.com/110976272/193469419-52cfc04d-0870-4807-a592-298f1be8673b.png">

The return updated On-prem routes can be observed from the Branch2 VPNGW BGP learned routes:

<img width="787" alt="Scenario 2_Branch2 VPNGW learned routes_failover" src="https://user-images.githubusercontent.com/110976272/193469432-bfedd908-026e-41e4-b3e0-e403e8d427e4.png">

Hub1 & Spoke 1 ranges (10.0.0.0/16 & 10.3.0.0/16) are originated from the Hub1 VNET but now propagated via the Hub1 CSR NVA BGP peering to the Hub2 VNET and advertised via the Hub2 VPN GW. AS-path = ARS1 (65515 rewritten in 64000 when reaching ARS2) > NVA1 (64000) > NVA2 (iBGP) > ARS2 (65515) > VPNGW2 (200)

### Data path & route analysis:

- The On-prem route already observed in nominal mode and advertised by ARS2 to NVA2 is still valid. AS-path = Branch1VPNGW (300) > Hub2VPNGW (200) > ARS2 (65515)
<img width="221" alt="Scenario 2_ARS2_Onprem routes_advertised" src="https://user-images.githubusercontent.com/110976272/193469560-216ebfec-5644-4489-a681-a8baada0d8a3.png">

- The CSR1 routing table for the 10.2.0.0/16 On-prem range has now NVA2 as next-hop:
<img width="562" alt="Scenario 2_CSR_sh ip route Onprem_failover" src="https://user-images.githubusercontent.com/110976272/193469614-aa0e06fc-a9b6-4082-8e88-8822ce8d398b.png">

- This route is BGP learned from NVA2:
 <img width="473" alt="Scenario 2_CSR_sh ip bgp Onprem range_failover" src="https://user-images.githubusercontent.com/110976272/193469646-c5256b28-8162-48ba-b627-7d89848f97d5.png">

- As per the ARS1 learned routes from CSR NVA1, the On-prem range is no longer locally reflected but received from the Hub2 CSR NVA. This route will be programmed in all the VMs in the Hub1 VNET and its peered VNETs. Updated AS-path: Branch1VPNGW (300) > Hub2VPNGW (200) > ARS2 ASN overridden (64000) > NVA ASN (64000)
<img width="259" alt="Scenario 2_ARS_Onprem routes_learned_failover" src="https://user-images.githubusercontent.com/110976272/193469739-5564240c-6a8a-4ee6-8f14-cad878722532.png">

# 7. Scenario 3: On-prem to On-prem


