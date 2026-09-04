# Contributing

Contributions should preserve the accelerator's explicit ownership and safety boundaries.

## Development workflow

1. Create a focused branch and make the smallest coherent change.
2. Update implementation tests and documentation together when behavior changes.
3. Run the [validation suite](operations/validation.md).
4. Build this site with strict warnings enabled.
5. Open a focused pull request that explains behavior, security impact, and validation evidence.

## Preview documentation locally

Install the pinned dependencies:

```powershell
python -m pip install -r requirements-docs.txt
```

For a one-time production-equivalent check:

```powershell
python -m mkdocs build --strict
```

For interactive authoring, contributors may run `python -m mkdocs serve` locally and stop it when finished. The GitHub Pages workflow always uses the strict build and deploys only from `main` or manual dispatch.

## Contracts to preserve

- Supported deployment modes are exactly `standalone` and `spoke`.
- Both modes create a new ARO VNet and required subnets.
- Do not add existing-spoke adoption under an existing mode name.
- Do not add hub/firewall/NVA resources to workload Terraform without an explicit design change.
- Keep bootstrap plan/apply and workload deployment separate.
- Preserve immutable SHA planning, exact-artifact apply, approvals, and guarded destroy.
- Keep GitHub Azure authentication OIDC-based.
- Treat the ARO service-principal secret and optional pull secret as protected runtime values.
- Do not overstate ingress: Front Door and preview Application Gateway remain contracts until implementation changes.

## Security and repository hygiene

Never commit Terraform plans or state, local configuration, credentials, tokens, subscription/tenant values, pull secrets, or ARO client secrets. Avoid sensitive values in examples, tests, terminal output, screenshots, and issue reports.

Public GitHub Actions currently use stable major tags because verified immutable SHAs are not maintained in this scaffold. Dependabot proposes monthly updates; organizations may pin reviewed commits where required.

See the root [contribution policy](https://github.com/abengtss-max/aroapplz/blob/main/CONTRIBUTING.md) and [security policy](https://github.com/abengtss-max/aroapplz/blob/main/SECURITY.md).
