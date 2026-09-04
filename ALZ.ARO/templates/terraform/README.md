# Generated workload Terraform

This root owns the ARO resource group, cluster, VNet, and both ARO subnets. `spoke` additionally owns two VNet peerings (one in each subscription) and a route table whose default route targets an existing firewall/NVA. It never owns the hub or next hop. `standalone` creates no hub, peering, or route resources.

ARO uses one cluster user-assigned identity plus eight operator identities and stores no client secret. The bootstrap discovers the Microsoft-managed ARO resource-provider object ID and renders it into a generated tfvars file. Supply only the optional `TF_VAR_pull_secret` and Application Gateway PFX values at runtime.

The selected ARO version is an exact pin. `front_door` is an integration contract, not a Front Door deployment. `application_gateway` provisions WAF_v2 and connects it to the private ARO ingress IP; configure its dedicated subnet CIDR and a routable OpenShift health-probe hostname.
