BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $workload = Get-ChildItem (Join-Path $root 'ALZ.ARO\templates\terraform') -Filter *.tf | Get-Content -Raw | Out-String
    $bootstrap = Get-ChildItem (Join-Path $root 'bootstrap') -Filter *.tf -Recurse | Get-Content -Raw | Out-String
    $destroy = Get-Content (Join-Path $root 'ALZ.ARO\templates\.github\workflows\destroy.yml') -Raw
}

Describe 'Architecture contracts' {
    It 'only permits standalone and spoke modes' {
        $workload | Should -Match '\["standalone", "spoke"\]'
        $workload | Should -Not -Match 'existing.spoke|existing_spoke'
    }
    It 'uses Entra applications and service principals rather than managed identities' {
        $bootstrap | Should -Match 'azuread_application'
        $bootstrap | Should -Match 'azuread_service_principal'
        $bootstrap | Should -Not -Match 'azurerm_user_assigned_identity'
    }
    It 'uses GitHub environment OIDC without application passwords' {
        $bootstrap | Should -Match 'azuread_application_federated_identity_credential'
        $bootstrap | Should -Not -Match 'azuread_application_password'
    }
    It 'guards manual destruction with confirmation, branch and SHA checks' {
        $destroy | Should -Match "confirmation"
        $destroy | Should -Match "default_branch"
        $destroy | Should -Match "expected_sha"
    }
}
