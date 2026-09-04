# ARO Application Landing Zone Accelerator

A concise PowerShell and Terraform accelerator for a private Azure Red Hat OpenShift (ARO) application landing zone. It bootstraps Azure state, Microsoft Entra workload identities, and a GitHub delivery repository; the generated repository then deploys the workload through reviewed plans.

> **Documentation:** [abengtss-max.github.io/aroapplz](https://abengtss-max.github.io/aroapplz/) — start with the [quickstart](https://abengtss-max.github.io/aroapplz/get-started/quickstart/) or review [how it works](https://abengtss-max.github.io/aroapplz/concepts/how-it-works/).

## Implemented scope

- Exactly two modes: `standalone` and `spoke`.
- Both modes create and own a new resource group, ARO VNet, control-plane subnet, worker subnet, and ARO cluster.
- `spoke` creates bidirectional peerings to an existing hub and a default UDR to an existing firewall/NVA. It never creates the hub, firewall, or NVA.
- Exact ARO version discovery/validation through `az aro get-versions --location`; the pin is persisted to JSON before bootstrap planning.
- Bootstrap creates hardened Azure Storage state, user-assigned managed identities for plan and apply, GitHub-environment OIDC credentials, RBAC, a private repository, environments, variables, files, and workflows.
- Workload CI performs formatting, validation, Checkov, and planning. CD plans a selected immutable SHA and applies the exact artifact after `apply` environment approval. Destroy is manual-only and guarded by confirmation, default-branch, and SHA checks.

No cloud operation runs merely by importing the module. `Deploy-AROLandingZone` defaults to bootstrap **plan**. Bootstrap apply creates the delivery platform but does not automatically apply the ARO workload.

## Ingress status

`ingress_mode` is exactly `none`, `front_door`, or `application_gateway`. `none` is the default. Front Door is a follow-on integration contract. Application Gateway provisions a dedicated subnet, public IP, WAF_v2 gateway, private ARO ingress backend, HTTPS probe, and Log Analytics diagnostics. The ARO API and ingress profiles remain private.

## Start

See the documentation [quickstart](https://abengtss-max.github.io/aroapplz/get-started/quickstart/), [configuration reference](https://abengtss-max.github.io/aroapplz/reference/configuration/), and [architecture](https://abengtss-max.github.io/aroapplz/concepts/how-it-works/). Import [ALZ.ARO/ALZ.ARO.psd1](ALZ.ARO/ALZ.ARO.psd1), prepare an input based on [config/standalone.json](config/standalone.json) or [config/spoke.json](config/spoke.json), then invoke `Deploy-AROLandingZone`.

## Documentation development

Install the pinned documentation dependencies and run the same strict build used by GitHub Pages:

```powershell
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
```

For an interactive local preview, run `python -m mkdocs serve` and stop it when finished. See [CONTRIBUTING.md](CONTRIBUTING.md) for repository validation and contribution boundaries.

## Security boundaries

The bootstrap creates no Azure client secret for GitHub or ARO. GitHub uses managed-identity client IDs plus OIDC. ARO uses one cluster identity and eight platform workload identities. The operator supplies GitHub provider authentication at runtime. The optional Red Hat pull secret and the PFX values required when Application Gateway is enabled are protected runtime inputs and are not placed in generated configuration.

The apply identity receives Azure `Contributor` and `Role Based Access Control Administrator` at workload-subscription scope because the workload resource group and required least-privilege ARO role assignments do not exist during bootstrap. Tighten these using a pre-created scope/custom role where organizational policy permits. The plan identity receives `Reader`; both receive state-container data access.

## Attribution

Structure and workflow ideas are adapted from [abengtss-max/aksapplz](https://github.com/abengtss-max/aksapplz), and ARO patterns were reviewed against [Azure/ARO-Landing-Zone-Accelerator](https://github.com/Azure/ARO-Landing-Zone-Accelerator). See [NOTICE](NOTICE).
