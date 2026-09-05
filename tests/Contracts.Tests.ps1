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
    It 'checks ARO provider registration before bootstrap creation' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match "'provider','show'"
        $module | Should -Match "'Microsoft.RedHatOpenShift'"
        $module | Should -Match "\$BootstrapAction -ne 'destroy'"
        $module | Should -Match 'az provider register --namespace Microsoft.RedHatOpenShift'
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
    It 'grants the ARO cluster subnets both service endpoints the resource provider requires' {
        $network = Get-Content (Join-Path $root 'ALZ.ARO\templates\terraform\network.tf') -Raw
        foreach ($subnet in @('control_plane', 'worker')) {
            $block = [regex]::Match($network, "resource `"azurerm_subnet`" `"$subnet`" \{.*?\n\}", 'Singleline').Value
            $block | Should -Match 'service\s+=\s+"Microsoft\.Storage"'
            $block | Should -Match 'service\s+=\s+"Microsoft\.ContainerRegistry"'
        }
    }
    It 'attaches a dedicated preconfigured NSG to each cluster subnet with the required operator roles' {
        $workload | Should -Match 'resource "azurerm_network_security_group" "aro"'
        $workload | Should -Match ([regex]::Escape('toset(["control-plane", "worker"])'))
        $workload | Should -Match ([regex]::Escape('azurerm_network_security_group.aro["control-plane"].id'))
        $workload | Should -Match ([regex]::Escape('azurerm_network_security_group.aro["worker"].id'))
        $workload | Should -Match 'preconfigured_network_security_group_enabled\s+=\s+true'
        $workload | Should -Match 'nsg_role_assignments'
        $workload | Should -Match 'resource "azurerm_role_assignment" "operator_nsg"'
        $workload | Should -Match 'resource "azurerm_role_assignment" "aro_resource_provider_nsg"'
        $workload | Should -Not -Match 'checkov:skip=CKV2_AZURE_31'
        foreach ($operator in @('cloud-controller-manager', 'file-csi-driver', 'machine-api', 'aro-operator')) {
            $workload | Should -Match ([regex]::Escape($operator))
        }
    }
    It 'pins a deterministic ARO managed resource group name' {
        $workload | Should -Match 'managed_resource_group_name\s+=\s+local\.managed_resource_group_name'
        $workload | Should -Match 'coalesce\(var\.managed_resource_group_name, "rg-\$\{var\.cluster_name\}-managed"\)'
        $workload | Should -Match 'variable "managed_resource_group_name"'
    }
    It 'forces UserDefinedRouting egress whenever a hub route table is attached' {
        $workload | Should -Match 'outbound_type\s+=\s+local\.is_spoke \? "UserDefinedRouting" : "Loadbalancer"'
        $workload | Should -Match 'visibility = "Private"'
    }
    It 'enforces the documented ARO subnet and pod CIDR minimums' {
        $workload | Should -Match 'ARO control-plane and worker subnets must be /27 or larger'
        $workload | Should -Match 'pod_cidr must be /18 or larger'
    }
    It 'supports hub gateway transit and landing-zone route control in spoke mode' {
        $workload | Should -Match 'use_remote_gateways\s+=\s+var\.hub_gateway_transit_enabled'
        $workload | Should -Match 'allow_gateway_transit\s+=\s+var\.hub_gateway_transit_enabled'
        $workload | Should -Match 'bgp_route_propagation_enabled\s+=\s+var\.egress_bgp_route_propagation_enabled'
    }
    It 'exposes the ARO data-protection options as opt-in' {
        $workload | Should -Match 'fips_enabled\s+=\s+var\.fips_enabled'
        $workload | Should -Match 'encryption_at_host_enabled\s+=\s+var\.encryption_at_host_enabled'
        $workload | Should -Match 'disk_encryption_set_id\s+=\s+var\.disk_encryption_set_id'
    }
    It 'does not attempt ARO resource diagnostic settings, which the platform does not expose' {
        $workload | Should -Not -Match 'azurerm_monitor_diagnostic_setting" "aro"'
    }
    It 'warns about landing-zone policy assignments that block ARO before apply' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match 'function Test-AROPolicyCompatibility'
        $module | Should -Match "'policy', 'assignment', 'list'"
        $module | Should -Match '--disable-scope-strict-match'
        $module | Should -Match "'Deny-PublicPaaSEndpoints'"
        $module | Should -Match "'MCAPSGovDeployPolicies'"
        $module | Should -Match 'DoNotEnforce'
        $module | Should -Match 'az group create -n \$\(\$Config\.managed_resource_group_name\)'
        $module | Should -Match 'az policy exemption create'
    }
    It 'evaluates policy inherited from management groups, which subscription scope does not return' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match 'function Get-AROManagementGroupAncestorScope'
        $module | Should -Match "'account', 'management-group', 'entities', 'list'"
        $module | Should -Match 'Get-AROManagementGroupAncestorScope -SubscriptionId \$SubscriptionId'
        $module | Should -Match 'Management Group Reader'
    }
    It 'derives the managed resource group name once and reuses it everywhere' {
        $module = Get-Content (Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1') -Raw
        $module | Should -Match '\$Config\.managed_resource_group_name = "rg-\$\(\$Config\.cluster_name\)-managed"'
        $module | Should -Match 'managed_resource_group_name = \$Config\.managed_resource_group_name'
        $module | Should -Match 'resource_group_name = \$Config\.resource_group_name'
        $module | Should -Match 'cluster_name = \$Config\.cluster_name'
        $module | Should -Not -Match 'rg-aro-\$\(\$Config\.service_name\)'
    }
    It 'documents Azure Landing Zone deployment guidance' {
        $page = Join-Path $root 'docs\governance\azure-landing-zone.md'
        Test-Path $page | Should -BeTrue
        $guidance = Get-Content $page -Raw
        $guidance | Should -Match 'Deny-PublicPaaSEndpoints'
        $guidance | Should -Match 'Enable-DDoS-VNET'
        $guidance | Should -Match 'rg-aro-<service_name>-<environment_name>-managed'
        $guidance | Should -Match 'az policy exemption create'
        $guidance | Should -Match '--managed-by'
        $guidance | Should -Match 'ClusterResourceGroupAlreadyExists'
        $guidance | Should -Match 'Why the accelerator does not create the exemption'
        (Get-Content (Join-Path $root 'mkdocs.yml') -Raw) | Should -Match 'governance/azure-landing-zone\.md'
    }
    It 'never creates policy exemptions from workload Terraform' {
        $workload | Should -Not -Match 'azurerm_(resource_group|subscription|management_group)_policy_exemption'
    }
    It 'routes operators to the policy carve-out before the workload apply' {
        $prerequisites = Get-Content (Join-Path $root 'docs\get-started\prerequisites.md') -Raw
        $prerequisites | Should -Match 'Deny-PublicPaaSEndpoints'
        $prerequisites | Should -Match 'before the first workload apply'
        $prerequisites | Should -Match '\.\./governance/azure-landing-zone\.md#create-the-exemption'
        $quickstart = Get-Content (Join-Path $root 'docs\get-started\quickstart.md') -Raw
        $quickstart | Should -Match '## 4\. Clear the policy carve-out'
        $quickstart | Should -Match '## 5\. Deploy ARO'
        $quickstart | Should -Match 'az policy exemption create'
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