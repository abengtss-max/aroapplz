# Configuration

Configuration is JSON so PowerShell 7 needs no YAML dependency. The supplied samples contain placeholders and no usable identifiers or secrets.

## Shared required values

`deployment_mode`, tenant/bootstrap/workload subscription IDs, `location`, service/environment names, GitHub owner/repository, ARO domain and network CIDRs, and `ingress_mode` are required. `aro_version` may be empty before preflight; the module resolves, validates, and writes an exact regional pin.

## Mode contract

- `standalone`: connectivity subscription, hub VNet ID, and next-hop IP remain empty. No peering, route table, or hub lookup is instantiated.
- `spoke`: all three values are required. The hub VNet ID subscription must equal the connectivity subscription. The next hop must be an existing firewall/NVA IP.

Both modes always create a new ARO VNet and both ARO subnets. There is no existing-spoke mode.

## Runtime secrets

Never add secrets to configuration. Configure optional `REDHAT_PULL_SECRET` in the generated GitHub environments. When Application Gateway HTTPS is enabled, also configure its base64 PFX data and password as documented in the reference. Pipeline and ARO authentication use managed identities.
