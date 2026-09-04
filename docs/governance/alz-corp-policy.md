# Azure Landing Zones corporate policy

aroapplz deploys an application landing zone workload; it does not assign management groups or create platform-scope policy. Place the workload subscription under the intended Azure Landing Zones management-group hierarchy before deployment.

## Policy areas to assess

Evaluate inherited and subscription policy for:

- approved Azure regions and VM SKUs;
- required tags and naming conventions;
- private networking and public network access;
- route tables, peering, and centralized DNS;
- role assignment and service-principal restrictions;
- diagnostic settings, Defender for Cloud, and retention;
- storage replication, encryption, and endpoint controls;
- ARO resource-provider and cluster requirements.

Run a bootstrap and workload plan in the target policy context. A valid Terraform configuration can still be denied by organizational policy.

## State endpoint trade-off

Bootstrap hardens workload state storage with Microsoft Entra authorization, disabled shared-key authentication, disabled anonymous access, TLS, infrastructure encryption, ZRS, versioning, change feed, and deletion retention. Its data endpoint remains publicly reachable because the generated design uses GitHub-hosted runners.

!!! warning "Private endpoint policy"
    A policy that denies public state endpoints requires a changed runner/network design. Provide a self-hosted runner with private network reachability and adapt/test the bootstrap; do not create a private endpoint while retaining runners that cannot reach it.

## Spoke governance

For `spoke`, obtain platform-owner approval for:

- address-space allocation and overlap checks;
- bidirectional peering and forwarded traffic;
- UDR propagation and return routing;
- the existing firewall/NVA next-hop IP;
- DNS and required ARO egress;
- cross-subscription permissions and resource locks;
- monitoring and incident ownership.

The accelerator references the existing hub and next hop but never creates or manages those platform resources.

## Identity governance

The plan identity receives workload-subscription `Reader`; the apply identity receives workload-subscription `Contributor` and `Role Based Access Control Administrator`; both receive state-container data access. Review these assignments against policy.

The apply scope exists because the resource group is created later by workload Terraform. A platform may pre-create a narrower scope and implement a tested custom role, provided all ARO, networking, role-assignment, and resource-group lifecycle needs are retained.

## Exceptions and evidence

Document any policy exemption with owner, scope, expiry, justification, compensating controls, and review date. Preserve reviewed plans, environment approvals, identity assignments, and validation results according to the organization's evidence requirements.
