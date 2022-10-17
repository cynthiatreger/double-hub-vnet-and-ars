# DIY vWAN: double Hub VNET and Azure Route Server

# 1. Suggested pre-reading

This lab has been suggested by my networking friend Daniele Gaiulli in support of his recent article on traffic segregation over mutiple ER circuits, to illustrate one of the many scenarios addressed: [Danieleg82/EXR-segregation-options](https://github.com/Danieleg82/EXR-segregation-options#scenario-1c--double-hub-and-direct-peering-between-hubs--azure-route-server)

And inspired by:
-	Scenarios 4 & 5 of the [jocortems/azurehybridnetworking/ExpressRoute-Transit-with-Azure-RouteServer](https://github.com/jocortems/azurehybridnetworking/tree/main/ExpressRoute-Transit-with-Azure-RouteServer#4-multi-region--multi-nic-nvas-with-route-tables)
- Deplyment of an ARS with Cisco CSR NVA Hub VNET : [mddazure/azure-route-server-lab](https://github.com/mddazure/azure-route-server-lab).

Great MicroHack for a deep-dive on ARS routing scenarios : [malgebary/Azure-Route-Server-MicroHack](https://github.com/malgebary/Azure-Route-Server-MicroHack)

# 2. Introduction

This lab demonstrates how a double Hub & Spoke topology leveraging Azure Route Server (ARS) can be used to provide On-prem, Inter-region and Transit connectivity as well as On-prem failover, i.e. a customer-managed version of a small vWAN deployment.

The Inter-region (Spoke-to-Spoke) and On-prem scenarios have been successfully deployed with both S2S VPN and ER On-prem connectivity. For simplicity and ease of reproduction, only the S2S VPN deployment is detailed here.

*As highlighted by Daniele, this solution should be preferred to its vWAN version only in case of specific blockers regarding the adoption of vWAN/vhubs, since it  offers the same topology but with much higher implementation complexity.*

**TABLE OF CONTENT:**

[Lab Description and Topology](# 3. Lab Description and Topology)

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
-	1 x ARS in the *RouteServerSubnet* with B2B enabled
-	1 x active/active VPN GW (mandatory for the deployment of ARS in the Hub VNET) in the GatewaySubnet
-	1 x CSR NVA in the *CSRSubnet*

Bastion is configured in the Hub and Branch VNETs for VM connectivity.

*The On-prem is emulated by 2 separate Branch VNETs configured intentionally with the same address space, to appear as a single network from the Azure VNETs and avoid the transitivity that would have resulted from having a single Branch VNET with 2 tunnels to each Hub VPN GWs.*

## Topology

<img width="821" alt="image" src="https://user-images.githubusercontent.com/110976272/194036536-f05acd7b-fcfd-43de-8931-a8c0de36fbb0.png">

# 4. Deployment

Log in to Azure Cloud Shell at https://shell.azure.com/ and select Bash.

Ensure Azure CLI and extensions are up to date:
```
az upgrade --yes
```

If necessary select your target subscription:
```
az account set --subscription <Name or ID of subscription>
```
Download the Navigate to the template directory.

Accept the terms for the CSR1000v Marketplace offer before deploying the template:
```
az vm image terms accept --urn cisco:cisco-csr-1000v:<offer_id>-byol:latest
```

# 5. Routing and Troubleshooting

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
! default route pointing to CSR subnet default gateway, to force traffic out of the LAN port
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
! default route pointing to CSR subnet default gateway, to force traffic out of the LAN port
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
| CSR (NVA) | BGP neighbors & session status | Cisco CLI / `show ip bgp summary` |
| CSR (NVA) | BGP routes learned from specified neighbor | Cisco CLI / `show ip bgp neighbors <peer_ip_@> routes` |
| CSR (NVA) | advertised BGP routes | Cisco CLI / `show ip bgp neighbors <peer_ip_@> advertised-routes` |
| CSR (NVA) | BGP originated routes in the IP routing table | Cisco CLI / `show ip route bgp` |

# 6. Scenario 1: Spoke-to-Spoke

Spoke to Spoke communications transit via the CSR NVA BGP peering.

In the *Effective Routes* list of Spoke1VM, Hub2 & Spoke2 ranges (20.0.0.0/16 & 20.3.0.0/16) have NVA1 as next-hop virtual gateway:

<img width="698" alt="Scenario 1_Spoke1VM_Effective routes" src="https://user-images.githubusercontent.com/110976272/193460684-349a7d4a-a9b5-42cc-a605-e41b9c9b5141.png">

### Data path & route analysis:
 
- ARS2 advertises the Hub2 & Spoke2 ranges to NVA2, AS-path = ARS2 (65515):
 <img width="234" alt="image" src="https://user-images.githubusercontent.com/110976272/193474025-79bcb2b0-8d41-4851-b9bd-8a8f0e066e82.png">

- NVA2 installs these routes in its routing table and forwarding them to NVA1, the AS-path in unchanged:
 <img width="574" alt="Scenario 1_CSR2_sh ip route bgp Spoke" src="https://user-images.githubusercontent.com/110976272/193465413-f14c9bc4-f339-4bbc-bd5a-31570cd3f9a3.png">
 <img width="599" alt="Scenario 1_CSR2_sh ip bgp nei adv routes_Spokes" src="https://user-images.githubusercontent.com/110976272/193465419-5e605e0b-39d5-463f-a4cb-817e366e02ab.png">

- Likewise, NVA1 installs the Hub2 & Spoke2 ranges in its routing table and advertises them further to ARS1:
 <img width="585" alt="Scenario 1_CSR_sh ip bgp advertised routes_spoke routes" src="https://user-images.githubusercontent.com/110976272/193465446-abe8678b-7e72-4884-8838-89a8db5b7c8b.png">

- ARS1 learns the Hub2 and Spoke2 ranges from NVA1 and programs all the VMs in its VNET and peered VNETs with these routes. The resulting AS-path illustrates the impact of the *as-override* configured on the NVA sessions with the ARS: the 65515 ARS2 ASN is replaced by 64000 (the NVAs ASN) before reaching ARS1:
 <img width="235" alt="image" src="https://user-images.githubusercontent.com/110976272/193473788-fa4799cd-f457-4f52-9963-dfad714a5674.png">
 
# 7. Scenario 2: Azure <=> On-prem

## 7.1. Nominal mode
 
In nominal mode traffic between Azure and On-prem transits via the “local” VPN GW.

Traffic from the Azure Spoke VNETs to the 10.2.0.0/16 On-prem subnet is sent to the peered Hub VPN GW. *Effective routes* of Spoke1VM-nic:

<img width="698" alt="Scenario 2_Spoke1VM_Effective routes" src="https://user-images.githubusercontent.com/110976272/193461177-fc5b5761-7d16-43cf-8db6-916567e18029.png">

Traffic from On-prem to Azure is directed to the Branch VNET VPN GW (Next Hop = 10.2.254.4). Branch11 VPN GW BGP learned routes:

<img width="827" alt="Scenario 2_Branch1 VPNGW learned routes" src="https://user-images.githubusercontent.com/110976272/193461603-711a4680-a216-405b-a1ab-76a31ff837cd.png">

Hub1 & Spoke1 ranges (10.0.0.0/16 & 10.3.0.0/16) are originated from the Hub1 VNET and advertised via the Hub1 VPN GW (AS 100).
 
Hub2 & Spoke2 ranges (20.0.0.0/16 & 20.3.0.0/16) are originated from the Hub2 VNET, propagated to Hub1 VNET and advertised via the Hub1 VPN GW. 
AS-path = ARS2 (65515 overriden to 64000 when reaching ARS1) > NVA2 (64000) > NVA1 (iBGP) > ARS1 (65515) > Hub1VPNGW (100)
 
### Data path & route analysis:

- The ARS1 advertised routes to the NVA1 include the 10.2.0.0/16 On-prem range with AS-path = Branch1 (300) > Hub1VPNGW (100) > ARS1 (65515):
 <img width="232" alt="image" src="https://user-images.githubusercontent.com/110976272/193522830-b7bfbd72-6749-418d-9df0-cb68e1b28d1c.png">
 
- The 10.2.0.0/16 On-prem range is also “locally” available in Hub2 and its peered VNETs, and advertised by ARS2 to NVA2 and further to NVA1:
 <img width="242" alt="image" src="https://user-images.githubusercontent.com/110976272/193474073-d0d03030-99ec-479e-8fab-bbf3c4dd2577.png">

- However the NVA1 prefers its “local” Hub1 On-prem route and will not propagate the On-prem route learned from Hub2:
 <img width="512" alt="image" src="https://user-images.githubusercontent.com/110976272/193524009-a3ad1f2b-b64f-45de-8572-00b943d04728.png">
  
- Instead, it will reflect back to ARS1 the Hub1 10.2.0.0/16 On-prem route received:
 <img width="604" alt="image" src="https://user-images.githubusercontent.com/110976272/193526327-12d8edcc-1000-4c37-84f1-563d43dfefa1.png">

- This looped route (no further used) can also be observed on the ARS1 learned routes from NVA1, as per the AS-path:
  Branch1 (300) > Hub1VPNGW (100) > ARS1 (65515 overriden to 64000) > NVA1 (64000).
 <img width="263" alt="image" src="https://user-images.githubusercontent.com/110976272/193523250-53db5d97-980d-4a69-a5fe-d04574c84275.png">

## 7.2. Failover mode (Hub1-Branch1 S2S down)

To simulate the failover, the Hub1-Branch1 S2S Connection is deleted:
 <img width="986" alt="image" src="https://user-images.githubusercontent.com/110976272/193523469-1063a433-8323-456f-bf38-97357946e0b4.png">

Traffic between Azure and On-prem switches to the cross-Hub VNET NVA path to use the remaining exit to On-prem.

Traffic from Azure to the 10.2.0.0/16 On-prem subnet is now sent to NVA1, where it will be passed to the NVA2 and Hub2 VPN GW. *Effective routes* of Spoke1VM-nic:
 
<img width="686" alt="Scenario 2_Spoke1VM_Effective routes_failover" src="https://user-images.githubusercontent.com/110976272/193469419-52cfc04d-0870-4807-a592-298f1be8673b.png">

The return updated On-prem routes can be observed from the Branch2 VPNGW BGP learned routes:
 <img width="787" alt="Scenario 2_Branch2 VPNGW learned routes_failover" src="https://user-images.githubusercontent.com/110976272/193469432-bfedd908-026e-41e4-b3e0-e403e8d427e4.png">

Hub1 & Spoke 1 ranges (10.0.0.0/16 & 10.3.0.0/16) are originated from the Hub1 VNET but now propagated via the NVA1 BGP peering to NVA2 and the Hub2 VNET and advertised via the Hub2 VPN GW. AS-path = ARS1 (65515 overridden to 64000 when reaching ARS2) > NVA1 (64000) > NVA2 (iBGP) > ARS2 (65515) > Hub2VPNGW (200)

### Data path & route analysis:

- The On-prem route already observed in nominal mode and advertised by ARS2 to NVA2 is still valid. AS-path = Branch2 (300) > Hub2VPNGW (200) > ARS2 (65515)
 <img width="242" alt="image" src="https://user-images.githubusercontent.com/110976272/193474108-e658d9c9-9967-4157-84c1-a21949602d19.png">

- The CSR1 routing table for the 10.2.0.0/16 On-prem range has now NVA2 as next-hop:
 <img width="562" alt="Scenario 2_CSR_sh ip route Onprem_failover" src="https://user-images.githubusercontent.com/110976272/193469614-aa0e06fc-a9b6-4082-8e88-8822ce8d398b.png">

- This route is BGP learned from NVA2:
 <img width="473" alt="Scenario 2_CSR_sh ip bgp Onprem range_failover" src="https://user-images.githubusercontent.com/110976272/193469646-c5256b28-8162-48ba-b627-7d89848f97d5.png">

- As per the ARS1 learned routes from NVA1, the On-prem range is no longer locally reflected but received from NVA2. This route will be programmed in all the VMs in the Hub1 VNET and its peered VNETs. 
 Updated AS-path: Branch2 (300) > Hub2VPNGW (200) > ARS2 (65515 overridden to 64000) > NVA2 (64000) > NVA1 (iBGP)
 <img width="254" alt="image" src="https://user-images.githubusercontent.com/110976272/193474166-628a8a9e-bd44-4ad3-8d23-8bf18f969924.png">

# 8. Scenario 3: On-prem to On-prem

To demonstrate the On-prem to On-prem connectivity, the initial lab topology is slightly modified with 2 separate ASNs and address spaces for Branch 1 and Branch2.

<img width="698" alt="image" src="https://user-images.githubusercontent.com/110976272/194040394-f30ca234-080f-461c-aa01-32ee2707e15b.png">

Each remote Branch address space is available in the local Branch VM NIC *Effective routes*:

 Branch1 VM:
 
 <img width="713" alt="Scenario 3_Branch1 VM NIC" src="https://user-images.githubusercontent.com/110976272/193650189-2459794d-17b4-4d6b-bd5b-85e5f2a7fc1d.png">

Branch2 VM:
 
 <img width="725" alt="Scenario 3_Branch2VM NIC" src="https://user-images.githubusercontent.com/110976272/193650302-64a7e12d-d642-4975-bd3f-b531b8772529.png">

### Data path & route analysis:

- The 10.8.0.0/24 Branch2 On-prem route is advertised by ARS2 to NVA2, AS-path = Branch2 (400) > Hub2VPNGW (200) > ARS2 (65515):
 <img width="260" alt="image" src="https://user-images.githubusercontent.com/110976272/193651506-692c27c3-1e53-4f2a-aaf9-33c53c3b59ee.png">

- NVA1 receives this route via iBGP from NVA2 and advertises it to ARS1:
 <img width="559" alt="image" src="https://user-images.githubusercontent.com/110976272/193651835-f5c59732-be83-46e1-9063-860f28638fe9.png">
 <img width="615" alt="image" src="https://user-images.githubusercontent.com/110976272/193652034-93cbd61a-2512-4631-afa8-a439a488c0c8.png">
 
- When received by ARS1 from NVA1, the  AS-path is the following: Branch2 (400) > Hub2VPNGW (200) > ARS2 (65515 overridden to 64000) > NVA2 (64000) > NVA1 (iBGP).
 <img width="272" alt="image" src="https://user-images.githubusercontent.com/110976272/193650715-791e664e-dfe2-4117-a526-cc655e9da207.png">

- Finally, after crossing the Hub1 VPN GW, the Branch2 VPN GW contains the 10.8.0.0/24 Branch2 On-prem route with AS-path = Branch2 (400) > Hub2VPNGW (200) > ARS2 (65515 overridden to 64000) > NVA2 (64000) > NVA1 (iBGP) > ARS1 (65515) > Hub1VPNGW (100) :
 <img width="842" alt="image" src="https://user-images.githubusercontent.com/110976272/193651176-a19456b5-5c31-4800-8565-23dac9de8201.png">
