BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $workload = Get-ChildItem (Join-Path $root 'ALZ.ARO\templates\terraform') -Filter *.tf | Get-Content -Raw | Out-String
    $bootstrap = Get-ChildItem (Join-Path $root 'bootstrap') -Filter *.tf -Recurse | Get-Content -Raw | Out-String
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
        $bootstrap | Should -Match 'github_owner_id.*github_repository.*module\.github\.repository_id'
        $bootstrap | Should -Not -Match 'azuread_application_password|azuread_service_principal_password'
    }
    It 'creates state through the ARM plane with shared keys disabled' {
        $bootstrap | Should -Match 'resource "azapi_resource" "state"'
        $bootstrap | Should -Match 'allowSharedKeyAccess\s+=\s+false'
        $bootstrap | Should -Match 'resource "azapi_update_resource" "blob_service"'
        $bootstrap | Should -Match 'resource_id\s*=\s*"\$\{azapi_resource\.state\.id\}/blobServices/default"'
        $bootstrap | Should -Match 'from = azapi_resource\.blob_service'
        $bootstrap | Should -Match 'destroy = false'
        $bootstrap | Should -Match 'resource "azapi_resource" "state_container"'
        $bootstrap | Should -Not -Match 'resource "azurerm_storage_account" "state"'
    }
    It 'selects but does not provision a self-hosted runner' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match "runner_label -notin @\('ubuntu-latest','self-hosted'\)"
        $module | Should -Match "runner_label: self-hosted"
        $forbiddenRunnerPattern = ('azurerm_' + 'linux_virtual_machine|actions/runners/' + 'registration-token|runner_registration_token|github_runner_token')
        $bootstrap | Should -Not -Match $forbiddenRunnerPattern
    }
    It 'only configures private repository reviewers when the owner plan supports them' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $githubModule = Get-Content (Join-Path $root 'bootstrap\modules\github\main.tf') -Raw
        $module | Should -Match '\[string\]\$ownerPlan -eq ''enterprise'''
        $githubModule | Should -Match 'var\.apply_environment_reviewers_enabled \? \[1\] : \[\]'
    }
    It 'does not send empty Actions variables to GitHub' {
        $githubModule = Get-Content (Join-Path $root 'bootstrap\modules\github\main.tf') -Raw
        $githubModule | Should -Match 'for name, value in local\.repository_variables.*if value != ""'
    }
    It 'requires an explicit GitHub token and maps GH_TOKEN without persisting it' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match '\$env:GITHUB_TOKEN\s*=\s*\$env:GH_TOKEN'
        $module | Should -Match 'does not reuse GitHub CLI authentication'
        $module | Should -Not -Match "Invoke-NativeCommand gh @\('auth','token'\)"
        $module | Should -Match "GitHub rejected GITHUB_TOKEN"
        $bootstrap | Should -Not -Match 'variable\s+"github_token"|token\s*=\s*var\.github'
    }
    It 'documents the GitHub bootstrap PAT scopes' {
        $quickstart = Get-Content (Join-Path $root 'docs\get-started\quickstart.md') -Raw
        $quickstart | Should -Match 'fine-grained PAT'
        $quickstart | Should -Match 'Administration.*Read and write'
        $quickstart | Should -Match 'Workflows.*Read and write'
        $quickstart | Should -Match "Read-Host 'Fine-grained GitHub PAT' -MaskInput"
        $quickstart | Should -Not -Match 'gh auth token'
    }
    It 'provides a plan-first bootstrap destroy path and clean-slate documentation' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $cleanup = Get-Content (Join-Path $root 'docs\operations\cleanup.md') -Raw
        $module | Should -Match "ValidateSet\('plan','apply','destroy'\)"
        $module | Should -Match 'terraform @\(''apply'',''-input=false'', \$planPath\)'
        $module | Should -Match "requiredScopes \+= 'delete_repo'"
        $cleanup | Should -Match 'Destroy the ARO workload first'
        $cleanup | Should -Match '-BootstrapAction destroy'
        $cleanup | Should -Match '-WhatIf'
        $cleanup | Should -Match 'Only remove local state after both Terraform destroy and verification succeed'
    }
    It 'reuses existing local configuration when no input path is supplied' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match 'Test-Path -LiteralPath \$OutputConfigPath -PathType Leaf'
        $module | Should -Match 'Using existing configuration:'
    }
    It 'excludes Terraform provider caches from generated repository files' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match "notmatch '\(\^\|/\)\\\.terraform/'"
        $module | Should -Match "notmatch '\\\.\(tfplan\|log\)\$'"
    }
    It 'provisions Application Gateway rather than a preview contract' {
        $workload | Should -Match 'resource "azurerm_application_gateway" "aro"'
        $workload | Should -Match 'WAF_v2'
        $workload | Should -Match 'host_name\s+=\s+var\.application_gateway_backend_host_name'
        $workload | Should -Not -Match 'application_gateway_preview|preview-not-provisioned'
    }
    It 'uses ARO caller and reusable-template workflow pairs' {
        @(Get-ChildItem (Join-Path $root 'ALZ.ARO\templates\.github\workflows') -File).Count | Should -Be 4
        $ci | Should -Match '01 ARO Landing Zone Continuous Integration'
        $ci | Should -Match 'uses: \.\/\.github\/workflows\/ci-template\.yml'
        $ciTemplate | Should -Match 'workflow_call:'
        $cd | Should -Match '02 ARO Landing Zone Continuous Delivery'
        $cd | Should -Match 'uses: \.\/\.github\/workflows\/cd-template\.yml'
        $cd | Should -Match 'options:\s+\- apply\s+\- destroy'
        $cdTemplate | Should -Match 'workflow_call:'
        $cdTemplate | Should -Match 'Apply the exact reviewed plan'
        $cdTemplate | Should -Match 'terraform apply -input=false -lock-timeout=5m tfplan'
        $cdTemplate | Should -Match 'terraform plan -destroy.*-out=tfplan'
    }
    It 'guards destruction in the CD pair with action, branch, SHA, and exact-plan checks' {
        $cd | Should -Match 'workflow_dispatch:'
        $cdTemplate | Should -Match "inputs.action.*= 'destroy'"
        $cdTemplate | Should -Match 'github\.event\.repository\.default_branch'
        $cdTemplate | Should -Match 'git rev-parse HEAD'
        Test-Path (Join-Path $root 'ALZ.ARO\templates\.github\workflows\destroy.yml') | Should -BeFalse
    }
}