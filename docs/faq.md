# Frequently asked questions

## Does aroapplz deploy ARO in one command?

No. `Deploy-AROLandingZone` defaults to a bootstrap plan. An explicit bootstrap apply creates state, identities, and a generated private repository. A separate manual workflow in that repository plans an immutable SHA and applies the approved artifact. No workload apply is automatic.

## Which deployment modes exist?

Exactly `standalone` and `spoke`. Both create a new ARO VNet and control-plane/worker subnets. There is no existing-spoke mode.

## Does `spoke` create a hub or firewall?

No. It creates bidirectional peerings to an existing hub and a default route toward an existing firewall/NVA private IP. The platform resources must already exist and remain externally owned.

## Is the ARO cluster public?

The implemented ARO API and ingress profiles are private. Any approved access path and external application ingress require platform integration.

## Does it deploy Front Door or Application Gateway?

`front_door` is a follow-on integration contract. `application_gateway` provisions a WAF_v2 gateway with public frontend, private ARO ingress backend, HTTPS health probe, and Log Analytics diagnostics. `none` is the default.

## Is Azure authentication secretless?

Yes. Separate plan/apply managed identities use GitHub OIDC, and ARO uses cluster and platform workload managed identities. No Azure client secret is required.

## Where should ARO secrets go?

Add the optional Red Hat pull secret and Application Gateway PFX values to both protected GitHub environments when required. Never put them in local configuration, generated source, logs, or pull requests.

## How is the ARO version selected?

Before bootstrap planning, the module calls `az aro get-versions` for the target location and workload subscription. It validates a supplied exact version or selects the newest version returned, then writes the exact pin into local configuration.

## Why does apply have subscription `Contributor`?

The workload resource group does not exist during bootstrap. The initial implementation grants apply `Contributor` at workload-subscription scope so Terraform can create and manage the resource-group lifecycle. A pre-created scope and tested custom role can reduce access if organizational policy permits.

## Can state storage use a private endpoint?

Not with the generated GitHub-hosted runner path unchanged. The endpoint is network-public but Entra-only. Private endpoint enforcement requires a self-hosted runner with network reachability and corresponding tested changes.

## Does importing the module change Azure?

No. Import only loads `Deploy-AROLandingZone`. Cloud interaction starts when the function runs; its default Terraform action remains plan.

## Where should I start troubleshooting?

Run the [repository validation](operations/validation.md), check configuration and tool preflight, then inspect the exact failing bootstrap or generated workflow step. For `spoke`, include hub peering, effective routes, DNS, and firewall/NVA owners early.
