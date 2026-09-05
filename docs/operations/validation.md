# Validation

Validation is split between repository checks, bootstrap-plan review, and post-deployment verification. Source validation does not require a Terraform plan or apply.

## Repository validation

From the repository root, run the wrapper:

```powershell
./scripts/Validate-Project.ps1
```

The script runs applicable module, Pester, Terraform formatting, initialization, and validation checks when required tools are available. Terraform initialization uses `-backend=false`; it downloads providers but does not access Azure resources.

Equivalent focused checks include:

```powershell
Test-ModuleManifest ./ALZ.ARO/ALZ.ARO.psd1
Invoke-Pester ./tests -Output Detailed
terraform -chdir=bootstrap/alz/github fmt -check -recursive
terraform -chdir=bootstrap/alz/github init -backend=false -input=false
terraform -chdir=bootstrap/alz/github validate
terraform -chdir=ALZ.ARO/templates/terraform fmt -check -recursive
terraform -chdir=ALZ.ARO/templates/terraform init -backend=false -input=false
terraform -chdir=ALZ.ARO/templates/terraform validate
checkov --directory . --config-file .checkov.yaml
```

The repository contains Pester contract and module tests plus Checkov configuration. Do not run `plan` or `apply` merely to validate source scaffolding.

## Documentation validation

Install the pinned documentation dependencies and perform a strict build:

```powershell
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
```

Strict mode treats warnings as errors, including invalid internal links and navigation mistakes.

## Bootstrap plan review

Before bootstrap apply, verify:

- the target GitHub owner and repository name;
- bootstrap/workload/connectivity subscription IDs;
- resource names and region;
- `standalone` versus `spoke` conditional resources;
- no unexpected hub, firewall, or NVA resource creation;
- separate plan/apply applications and federated subjects;
- role-assignment scopes;
- state storage controls and network accessibility;
- generated repository visibility, environment reviewers, files, and workflows.

Apply only the plan that was reviewed.

## Generated repository checks

Pull-request CI should complete formatting, initialization, validation, Checkov, and speculative planning. For deployment, confirm that manual CD:

- receives a full intended commit SHA;
- plans the same immutable source;
- uploads the plan artifact;
- waits for `apply` environment approval;
- applies the exact artifact rather than replanning after approval.

## Post-deployment checks

Validate at least:

- the expected workload resource group exists;
- the ARO VNet and both subnets match approved CIDRs;
- the ARO cluster reports the intended version and private API/ingress profiles;
- the console URL output is present and reachable only from intended paths;
- ARO cluster operators and nodes are healthy;
- required DNS and egress behavior works;
- state is stored and protected as designed.

For `spoke`, additionally validate both peerings, effective routes, next-hop processing, return paths, and platform monitoring. For any follow-on ingress solution, separately validate certificates, origins, probes, DNS, access policy, and observability.
