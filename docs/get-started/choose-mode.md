# Choose a deployment mode

The `deployment_mode` value accepts exactly `standalone` or `spoke`. Both modes create and own a new workload resource group, ARO VNet, control-plane subnet, worker subnet, and private ARO cluster.

## Decision guide

| Question | `standalone` | `spoke` |
| --- | --- | --- |
| Creates a new ARO VNet and subnets | Yes | Yes |
| Adopts an existing spoke | No | No |
| Creates hub resources | No | No |
| Creates bidirectional hub peering | No | Yes, to an existing hub |
| Creates a default UDR | No | Yes, to an existing next hop |
| Creates a firewall or NVA | No | No |
| Requires connectivity subscription and hub inputs | No | Yes |

## `standalone`

Choose `standalone` when this project should create the ARO network without managing hub connectivity.

```json
{
  "deployment_mode": "standalone",
  "connectivity_subscription_id": "",
  "hub_vnet_id": "",
  "next_hop_ip": ""
}
```

Hub lookups, peerings, and the spoke route table have zero instances in Terraform. This does not claim that the resulting environment meets every production connectivity requirement; DNS, egress, ingress integration, and enterprise connectivity remain design decisions.

## `spoke`

Choose `spoke` when a platform team already operates a hub and firewall/NVA and authorizes this new ARO VNet to connect to them.

```json
{
  "deployment_mode": "spoke",
  "connectivity_subscription_id": "00000000-0000-0000-0000-000000000000",
  "hub_vnet_id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-connectivity/providers/Microsoft.Network/virtualNetworks/vnet-hub",
  "next_hop_ip": "10.0.1.4"
}
```

The workload creates forward and reverse VNet peerings and a `0.0.0.0/0` route toward the supplied virtual-appliance IP. The existing hub and next hop are identifiers, not Terraform-managed platform resources in this project.

!!! danger "Confirm routes before apply"
    A syntactically valid next-hop IP is not proof that the appliance can route ARO traffic. Platform owners must validate address overlap, return routes, forwarded traffic, DNS, and required outbound destinations.

## What mode does not control

Mode selection does not deploy Front Door or Application Gateway. `ingress_mode` is a separate contract with the values `none`, `front_door`, and `application_gateway`; see [configuration](../reference/configuration.md#ingress).
