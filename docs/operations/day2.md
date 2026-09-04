# Day-2 operations

Operate bootstrap, delivery, workload, and external connectivity as distinct boundaries.

## Change workflow

1. Keep configuration and the exact ARO version pin under pull-request review in the generated repository.
2. Use CI for formatting, validation, security scanning, and speculative plans.
3. Dispatch CD manually with a full immutable commit SHA.
4. Review the generated plan and approve the protected `apply` environment only when it matches intent.
5. Preserve deployment evidence according to organizational policy.

Re-run regional ARO version discovery before changing the pin and review the ARO support lifecycle. Do not infer regional availability from a version used elsewhere.

## Routine checks

Monitor and periodically test:

- ARO cluster and operator health;
- node capacity, quota, certificates, and supported versions;
- private API and ingress reachability from approved networks;
- required egress and DNS resolution;
- VNet peering and effective routes in `spoke`;
- firewall/NVA handling and return paths;
- state storage retention, versioning, authorization, and restore procedure;
- GitHub environment reviewers, OIDC subjects, and Azure RBAC;
- diagnostic coverage required by the platform;
- dependency proposals from Dependabot.

## Drift and external dependencies

Terraform can detect drift only for resources it manages. In `spoke`, record ownership and change contacts for the existing hub and firewall/NVA. A hub route, DNS, policy, or appliance change can affect ARO even though those resources are not in workload state.

Run plans after relevant platform changes, but do not apply merely to “see what happens.” Coordinate cross-team network validation first.

## Secret rotation

The ARO service-principal secret and optional Red Hat pull secret live in protected GitHub environments and may be represented in sensitive Terraform state during use. Rotate them using approved processes, update both `plan` and `apply` environments, and tightly control state access.

OIDC plan/apply identities have no Azure client secret. Review their federated credentials and role assignments instead.

## Ingress follow-on work

`front_door` and `application_gateway` do not provision complete ingress. Operators own design and operations for edge resources, certificates, DNS, origin reachability, health probes, security policy, and observability. Application Gateway remains preview contract-only in this release.

## Destroy

Use the generated manual destroy workflow only after dependency and retention review. It requires:

- execution from the default branch;
- the current full commit SHA;
- the exact confirmation word `DELETE`;
- protected-environment approval.

Destroy workload resources before separately retiring bootstrap resources. Confirm whether state, logs, DNS, identity records, and platform-side peering records require retention or separate cleanup.

!!! danger "External resources remain"
    Workload destroy does not destroy the existing hub or firewall/NVA. Coordinate cleanup of platform-owned peering, routing, DNS, and policy records according to ownership—even when Terraform removes the connection resources it owns.
