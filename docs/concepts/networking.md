# Networking

Both deployment modes create the network boundary required for a new private ARO cluster. The difference is whether aroapplz also creates a connection from that new VNet to an existing hub.

## Owned in both modes

- A new ARO virtual network using `aro_vnet_cidr`
- A control-plane subnet using `control_plane_subnet_cidr`
- A worker subnet using `worker_subnet_cidr`
- A private ARO API profile
- A private ARO ingress profile

The workload also configures ARO pod and service CIDRs. Template defaults are `10.128.0.0/14` and `172.30.0.0/16`; ensure all relevant ranges are compatible with the wider network design.

## Standalone topology

```mermaid
flowchart TB
  RG[New workload resource group]
  RG --> VNet[New ARO VNet]
  VNet --> CP[Control-plane subnet]
  VNet --> WK[Worker subnet]
  CP & WK --> ARO[Private ARO cluster]
```

No hub data lookup, peering, route table, or firewall/NVA resource is instantiated by the mode.

## Spoke topology

```mermaid
flowchart LR
  subgraph Workload[Workload subscription]
    ARO[Private ARO cluster]
    VNet[New ARO VNet]
    RT[Route table: 0.0.0.0/0]
    ARO --- VNet
    VNet --- RT
  end
  subgraph Connectivity[Connectivity subscription]
    Hub[Existing hub VNet]
    NVA[Existing firewall or NVA]
  end
  VNet <-->|bidirectional peering| Hub
  RT -->|VirtualAppliance next hop| NVA
```

The workload creates:

- peering from the new ARO VNet to the existing hub;
- reverse peering from the existing hub to the new ARO VNet;
- a route table and default route targeting the supplied firewall/NVA private IP;
- route-table associations required by the workload template.

The workload does not create the hub, firewall, NVA, or their supporting platform resources.

## Platform integration checklist

Before `spoke` apply, confirm with network owners:

- ARO VNet, subnet, pod, and service CIDRs do not overlap connected networks.
- The hub permits the required peering and forwarded-traffic behavior.
- Return routes exist for the new ARO ranges.
- The next-hop IP belongs to a functioning virtual appliance path.
- DNS resolution works for Azure, ARO, and organizational dependencies.
- Firewall policy permits required ARO egress and operational access.

### Grant the pipeline identities access to the hub

Bootstrap grants the plan and apply identities roles on the **workload** subscription only. It deliberately grants nothing in the connectivity subscription, because a workload pipeline should not hold standing write access to platform networking.

`spoke` mode creates the reverse peering inside the hub through the `azurerm.connectivity` provider, so without an explicit grant the apply fails with `AuthorizationFailed` on `Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write`.

A connectivity owner grants the minimum, scoped to the hub VNet rather than the subscription:

```bash
APPLY_ID=$(az identity show -g rg-<service>-<env>-bootstrap -n id-<service>-<env>-apply --query principalId -o tsv)
PLAN_ID=$(az identity show -g rg-<service>-<env>-bootstrap -n id-<service>-<env>-plan --query principalId -o tsv)

az role assignment create --assignee-object-id "$APPLY_ID" --assignee-principal-type ServicePrincipal \
  --role "Network Contributor" --scope "<HUB_VNET_ID>"
az role assignment create --assignee-object-id "$PLAN_ID" --assignee-principal-type ServicePrincipal \
  --role Reader --scope "<HUB_VNET_ID>"
```

Network Contributor is used because peering needs `virtualNetworkPeerings/write` on the hub side and `virtualNetworks/peer/action` on the remote side; it is the least-privilege built-in role carrying both. Plan needs only Reader to refresh the peering it does not own.

## Ingress and edge routing

Private ARO ingress does not make an application publicly reachable. The current `front_door` and `application_gateway` values are integration contracts only; operators must design, provision, and validate any edge service, origin connectivity, certificates, DNS, probes, and security policy.

## State storage connectivity

The generated workload state storage endpoint remains publicly reachable so GitHub-hosted runners can connect, but anonymous access and shared-key authentication are disabled. Microsoft Entra authorization is used. An organization that mandates private state endpoints must provide self-hosted runner connectivity and adapt the platform design.
