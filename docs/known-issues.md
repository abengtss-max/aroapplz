# Known issues and limitations

These boundaries reflect the current implementation, not planned functionality.

## No existing-spoke mode

Both `standalone` and `spoke` create a new ARO VNet and both ARO subnets. The accelerator cannot adopt an existing spoke VNet.

## Existing hub and appliance required

`spoke` requires an existing hub VNet and existing firewall/NVA private IP. aroapplz creates connection resources but no hub, firewall, NVA, DNS platform, or route appliance.

## Ingress integrations are contracts

`front_door` records follow-on integration intent only. `application_gateway` is preview, disabled by default, and represented by a contract resource; it does not provision a gateway. The workload creates private ARO API and ingress profiles.

## Apply role is subscription-scoped

The generated apply service principal receives `Contributor` on the workload subscription because its resource group does not exist during bootstrap. Organizations requiring narrower access need a pre-created scope and tested custom role that still permits the implemented lifecycle.

## ARO still needs a client secret

GitHub-to-Azure authentication uses OIDC, but ARO itself requires a dedicated service-principal client secret. It remains a protected runtime secret and sensitive Terraform input/state value.

## State endpoint is network-public

The workload state storage endpoint is reachable from GitHub-hosted runners. Anonymous and shared-key access are disabled and Entra authorization is used, but organizations requiring private network access need self-hosted runner connectivity and a modified/tested bootstrap.

## Workload apply is separate

Bootstrap apply creates the delivery platform and generated repository only. It does not automatically plan or apply the ARO workload. The first workload deployment is a manual GitHub workflow operation using an immutable commit SHA and protected approval.

## Local bootstrap state

Bootstrap state starts locally. Secure and manage it according to organizational policy; do not commit it.

## Cost estimation is not implemented

The accelerator does not calculate ARO, compute, storage, networking, egress, or platform costs. Validate current prices and quota before deployment.
