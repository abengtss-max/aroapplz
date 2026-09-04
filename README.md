# ARO Application Landing Zone Accelerator

A concise PowerShell and Terraform accelerator for a private Azure Red Hat OpenShift (ARO) application landing zone. It bootstraps Azure state, Microsoft Entra workload identities, and a GitHub delivery repository; the generated repository then deploys the workload through reviewed plans.

## Implemented scope

- Exactly two modes: `standalone` and `spoke`.
- Both modes create and own a new resource group, ARO VNet, control-plane subnet, worker subnet, and ARO cluster.
- `spoke` creates bidirectional peerings to an existing hub and a default UDR to an existing firewall/NVA. It never creates the hub, firewall, or NVA.
- Exact ARO version discovery/validation through `az aro get-versions --location`; the pin is persisted to JSON before bootstrap planning.
- Bootstrap creates hardened Azure Storage state, Entra applications/service principals for plan and apply, GitHub-environment OIDC credentials, RBAC, a private repository, environments, variables, files, and workflows.
- Workload CI performs formatting, validation, Checkov, and planning. CD plans a selected immutable SHA and applies the exact artifact after `apply` environment approval. Destroy is manual-only and guarded by confirmation, default-branch, and SHA checks.

No cloud operation runs merely by importing the module. `Deploy-AROLandingZone` defaults to bootstrap **plan**. Bootstrap apply creates the delivery platform but does not automatically apply the ARO workload.

## Ingress status

`ingress_mode` is exactly `none`, `front_door`, or `application_gateway`. `none` is the default. Front Door is currently a follow-on integration contract only. Application Gateway is explicitly **preview**, disabled by default, and represented by a contract resource; it does not provision a gateway. The ARO API and ingress profiles are private.

## Start

See [Quickstart](docs/quickstart.md), [configuration](docs/configuration.md), and [architecture](docs/architecture.md). Import [ALZ.ARO/ALZ.ARO.psd1](ALZ.ARO/ALZ.ARO.psd1), prepare an input based on [config/standalone.json](config/standalone.json) or [config/spoke.json](config/spoke.json), then invoke `Deploy-AROLandingZone`.

## Security boundaries

The bootstrap creates no Azure client secret for GitHub. GitHub uses client IDs plus OIDC. The operator supplies GitHub provider authentication at runtime. ARO's own service-principal secret and optional Red Hat pull secret are separate runtime inputs in protected GitHub environments and are not placed in generated configuration.

The apply principal currently receives Azure `Contributor` at workload-subscription scope because the workload resource group does not exist during bootstrap. Tighten this using a pre-created scope/custom role where organizational policy permits. The plan principal receives `Reader`; both receive state-container data access.

## Attribution

Structure and workflow ideas are adapted from [abengtss-max/aksapplz](https://github.com/abengtss-max/aksapplz), and ARO patterns were reviewed against [Azure/ARO-Landing-Zone-Accelerator](https://github.com/Azure/ARO-Landing-Zone-Accelerator). See [NOTICE](NOTICE).
