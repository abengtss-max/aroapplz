---
hide:
  - toc
---

<div class="aro-hero" markdown>
<p class="hero-kicker">Private ARO · plan first · GitHub OIDC</p>

# Build an ARO application landing zone with review gates

aroapplz prepares Azure state, separate plan/apply identities, and a private GitHub delivery repository for a **new private Azure Red Hat OpenShift cluster**. It is designed for platform engineers and application teams that need a repeatable workload landing zone without taking ownership of an existing hub.

<div class="aro-actions">
  <a class="aro-button primary" href="get-started/quickstart/">Start the quickstart</a>
  <a class="aro-button" href="concepts/how-it-works/">Explore the architecture</a>
</div>
</div>

<span class="status-chip success">Implemented: standalone + spoke</span>
<span class="status-chip">Private API and ingress</span>
<span class="status-chip warning">Plan before apply</span>

## Scope at a glance

This accelerator owns the ARO workload boundary: a new resource group, VNet, control-plane subnet, worker subnet, and ARO cluster. Bootstrap creates the delivery platform around that workload. It does **not** adopt an existing spoke, create a hub, create a firewall/NVA, or automatically apply the workload.

!!! important "Two deliberate deployment stages"
    Running `Deploy-AROLandingZone` defaults to a bootstrap **plan**. An explicit bootstrap apply creates state, identities, and the generated repository. The first ARO workload apply is then manually dispatched from that repository and passes through its protected `apply` environment. This is not a one-command deployment.

## Your four-step journey

<div class="aro-grid" markdown>
<div class="aro-step" markdown>
<div class="aro-step-number">1</div>
<div markdown>
### Choose
Select `standalone` or `spoke`, confirm network ownership, and prepare regional capacity and permissions.
</div>
</div>
<div class="aro-step" markdown>
<div class="aro-step-number">2</div>
<div markdown>
### Configure
Copy a sample JSON file. Preflight validates the mode and discovers or verifies an exact regional ARO version.
</div>
</div>
<div class="aro-step" markdown>
<div class="aro-step-number">3</div>
<div markdown>
### Bootstrap
Review the local Terraform plan, then explicitly apply it to create state, OIDC identities, and a private delivery repository.
</div>
</div>
<div class="aro-step" markdown>
<div class="aro-step-number">4</div>
<div markdown>
### Deliver
Add protected runtime secrets, use pull-request CI, then manually plan and apply an immutable commit SHA after approval.
</div>
</div>
</div>

## What you get

<div class="aro-grid three" markdown>
<div class="aro-card" markdown>
### Workload foundation

- New workload resource group
- New ARO VNet and required subnets
- Private ARO API and ingress profiles
- Exact regional ARO version pin
</div>
<div class="aro-card" markdown>
### Delivery controls

- Private generated GitHub repository
- Separate `plan` and `apply` environments
- OIDC-based Azure pipeline authentication
- Approval-gated apply of an exact plan artifact
</div>
<div class="aro-card red" markdown>
### State and guardrails

- Hardened Azure Storage for workload state
- Formatting, validation, Checkov, and Pester checks
- Manual `apply`/`destroy` selector in the `02` continuous-delivery workflow
- Dependabot update proposals
</div>
</div>

## Choose one of two deployment modes

<div class="aro-grid" markdown>
<div class="aro-card" markdown>
### `standalone`

Creates and owns the new ARO VNet and both ARO subnets. It performs no hub lookup and creates no peering or route table.

**Use when:** connectivity is managed outside this accelerator or the cluster does not need the provided hub route contract.

[Review standalone mode →](get-started/choose-mode.md#standalone)
</div>
<div class="aro-card red" markdown>
### `spoke`

Creates and owns the new ARO VNet and both ARO subnets, bidirectionally peers the VNet to an **existing** hub, and adds a default UDR toward an **existing** firewall/NVA private IP.

**Use when:** the platform team already provides the hub and next hop. The accelerator never creates or owns either one.

[Review spoke mode →](get-started/choose-mode.md#spoke)
</div>
</div>

## Security model

GitHub-to-Azure authentication is secretless: bootstrap creates separate user-assigned managed identities for plan and apply, each with a GitHub-environment federated credential. The plan identity receives workload-subscription `Reader`; the apply identity receives workload-subscription `Contributor` and `Role Based Access Control Administrator`; both receive state-container data access.

ARO also uses managed identities: one cluster identity and eight platform workload identities with purpose-built ARO roles. No ARO client secret is required. The optional Red Hat pull secret and Application Gateway certificate values remain protected runtime inputs and do not belong in configuration JSON.

[Understand identity boundaries →](reference/identity.md)

## Ingress status

| Value | Current behavior |
| --- | --- |
| `none` | Default. No external ingress integration contract is selected. |
| `front_door` | Records a follow-on integration contract only; Front Door is not provisioned. |
| `application_gateway` | Provisions WAF_v2, dedicated subnet, private ARO backend, HTTPS probe, and diagnostics. |

The ARO API and ingress profiles created by the workload are private. Operators own Front Door follow-on integration and Application Gateway DNS/certificate lifecycle.

## Cost and responsibility

aroapplz does not estimate or cap Azure charges. ARO cluster nodes, storage, networking, egress, state storage, and any existing hub or security appliances can incur costs. Validate current regional pricing, quota, policy, and ARO support requirements before apply; destroy unused workload resources through the guarded workflow when appropriate.

<div class="aro-callout" markdown>
**Ready to evaluate the fit?** Start with [prerequisites](get-started/prerequisites.md), then [choose a mode](get-started/choose-mode.md).
</div>
