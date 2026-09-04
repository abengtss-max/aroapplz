BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $workload = Get-ChildItem (Join-Path $root 'ALZ.ARO\templates\terraform') -Filter *.tf | Get-Content -Raw | Out-String
    $bootstrap = Get-ChildItem (Join-Path $root 'bootstrap') -Filter *.tf -Recurse | Get-Content -Raw | Out-String
    $destroy = Get-Content (Join-Path $root 'ALZ.ARO\templates\.github\workflows\destroy.yml') -Raw
    $ci = Get-Content (Join-Path $root 'ALZ.ARO\templates\.github\workflows\ci.yml') -Raw
    $ciTemplate = Get-Content (Join-Path $root 'ALZ.ARO\templates\.github\workflows\ci-template.yml') -Raw
    $cd = Get-Content (Join-Path $root 'ALZ.ARO\templates\.github\workflows\cd.yml') -Raw
    $cdTemplate = Get-Content (Join-Path $root 'ALZ.ARO\templates\.github\workflows\cd-template.yml') -Raw
}

Describe 'Architecture contracts' {
    It 'only permits standalone and spoke modes' {
        $workload | Should -Match '\["standalone", "spoke"\]'
        $workload | Should -Not -Match 'existing.spoke|existing_spoke'
    }
    It 'uses managed identities for pipelines and the ARO cluster' {
        $bootstrap | Should -Match 'resource "azurerm_user_assigned_identity" "pipeline"'
        $workload | Should -Match 'platform_workload_identity_profile'
        $workload | Should -Match 'resource "azurerm_user_assigned_identity" "aro"'
        $workload | Should -Not -Match 'service_principal\s*\{'
    }
    It 'uses GitHub environment OIDC on managed identities' {
        $bootstrap | Should -Match 'azurerm_federated_identity_credential'
        $bootstrap | Should -Not -Match 'azuread_application_password|azuread_service_principal_password'
    }
    It 'maps GH_TOKEN to the Terraform provider token without persisting it' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match '\$env:GITHUB_TOKEN\s*=\s*\$env:GH_TOKEN'
        $bootstrap | Should -Not -Match 'variable\s+"github_token"|token\s*=\s*var\.github'
    }
    It 'documents the GitHub bootstrap PAT scopes' {
        $quickstart = Get-Content (Join-Path $root 'docs\get-started\quickstart.md') -Raw
        $quickstart | Should -Match '`repo`'
        $quickstart | Should -Match '`workflow`'
        $quickstart | Should -Match '`read:org`'
        $quickstart | Should -Match 'No `admin:org`, `delete_repo`'
    }
    It 'provisions Application Gateway rather than a preview contract' {
        $workload | Should -Match 'resource "azurerm_application_gateway" "aro"'
        $workload | Should -Match 'WAF_v2'
        $workload | Should -Match 'host_name\s+=\s+var\.application_gateway_backend_host_name'
        $workload | Should -Not -Match 'application_gateway_preview|preview-not-provisioned'
    }
    It 'uses ARO caller and reusable-template workflow pairs' {
        $ci | Should -Match '01 ARO Landing Zone Continuous Integration'
        $ci | Should -Match 'uses: \.\/\.github\/workflows\/ci-template\.yml'
        $ciTemplate | Should -Match 'workflow_call:'
        $cd | Should -Match '02 ARO Landing Zone Continuous Delivery'
        $cd | Should -Match 'uses: \.\/\.github\/workflows\/cd-template\.yml'
        $cdTemplate | Should -Match 'workflow_call:'
        $cdTemplate | Should -Match 'Apply the exact reviewed plan'
        $cdTemplate | Should -Match 'terraform apply -input=false -lock-timeout=5m tfplan'
    }
    It 'guards manual destruction with confirmation, branch and SHA checks' {
        $destroy | Should -Match "confirmation"
        $destroy | Should -Match "default_branch"
        $destroy | Should -Match "expected_sha"
    }
}
