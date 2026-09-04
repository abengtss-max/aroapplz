# Validation

Local checks do not deploy resources:

- `Test-ModuleManifest ./ALZ.ARO/ALZ.ARO.psd1`
- `Invoke-Pester ./tests -Output Detailed`
- `terraform -chdir=bootstrap/alz/github fmt -check -recursive`
- `terraform -chdir=bootstrap/alz/github init -backend=false -input=false`
- `terraform -chdir=bootstrap/alz/github validate`
- `terraform -chdir=ALZ.ARO/templates/terraform fmt -check -recursive`
- `terraform -chdir=ALZ.ARO/templates/terraform init -backend=false -input=false`
- `terraform -chdir=ALZ.ARO/templates/terraform validate`
- `checkov --directory . --config-file .checkov.yaml`

The wrapper [../scripts/Validate-Project.ps1](../scripts/Validate-Project.ps1) runs module, Pester, formatting, initialization, and validation checks when the tools are available. Terraform initialization downloads providers but does not access Azure resources when backend is disabled. Do not run `plan` or `apply` merely to validate the source scaffold.
