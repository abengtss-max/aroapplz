# Get started

aroapplz separates delivery-platform bootstrap from ARO workload deployment. Begin by validating ownership and prerequisites rather than applying infrastructure immediately.

## Recommended path

1. [Check prerequisites](prerequisites.md), permissions, quota, and policy.
2. [Choose `standalone` or `spoke`](choose-mode.md).
3. [Follow the plan-first quickstart](quickstart.md).
4. Review [how the two stages work](../concepts/how-it-works.md).

## Before continuing

You should be able to answer these questions:

- Is the target a **new** ARO VNet and cluster?
- Who owns the workload, bootstrap, and—when applicable—connectivity subscriptions?
- For `spoke`, who approves hub peering, address space, DNS, routing, and firewall egress?
- Which GitHub users can approve the protected apply environment?
- How will ARO service-principal and optional Red Hat pull-secret values be stored in GitHub environments?

!!! warning "No existing-spoke adoption"
    Both modes create a new ARO VNet and both required ARO subnets. If the intended design adopts an existing spoke VNet, this accelerator does not currently implement it.
