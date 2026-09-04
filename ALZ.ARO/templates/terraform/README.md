# Generated workload Terraform

This root owns the ARO resource group, cluster, VNet, and both ARO subnets. `spoke` additionally owns two VNet peerings (one in each subscription) and a route table whose default route targets an existing firewall/NVA. It never owns the hub or next hop. `standalone` creates no hub, peering, or route resources.

Supply sensitive values only at runtime:

- `TF_VAR_aro_service_principal_client_id`
- `TF_VAR_aro_service_principal_client_secret`
- `TF_VAR_aro_service_principal_object_id`
- `TF_VAR_aro_resource_provider_object_id`
- optionally `TF_VAR_pull_secret`

The selected ARO version is an exact pin. `front_door` is currently an integration contract, not a Front Door deployment. `application_gateway` is a disabled-by-default preview contract and does not provision a gateway.
