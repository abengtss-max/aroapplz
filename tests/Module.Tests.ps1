BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $manifest = Join-Path $root 'ALZ.ARO\ALZ.ARO.psd1'
}

Describe 'ALZ.ARO module' {
    It 'has a valid manifest' {
        Test-ModuleManifest $manifest | Should -Not -BeNullOrEmpty
    }

    It 'exports only the public entrypoint' {
        $module = Import-Module $manifest -Force -PassThru
        @($module.ExportedFunctions.Keys) | Should -Be @('Deploy-AROLandingZone')
    }

    It 'parses on PowerShell 7' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'ALZ.ARO\ALZ.ARO.psm1'), [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}

Describe 'GitHub token permission probe' {
    BeforeAll { Import-Module $manifest -Force }

    It 'names every missing permission in a single message' {
        InModuleScope 'ALZ.ARO' {
            Mock Invoke-WebRequest {
                if ($Uri -match '/contents/README.md$|/actions/variables$') {
                    return [pscustomobject]@{
                        StatusCode = 403
                        Headers    = @{ 'x-accepted-github-permissions' = @('contents=write') }
                    }
                }
                return [pscustomobject]@{ StatusCode = 200; Headers = @{} }
            }
            $detail = Get-MissingGitHubPermission -RepositoryPath 'owner/repo' -Headers @{ Authorization = 'Bearer token' }
            $detail | Should -Match 'contents=write'
            $detail | Should -Match 'repository files'
            $detail | Should -Match 'Actions variables'
            $detail | Should -Not -Match 'workflow dispatch'
        }
    }

    It 'reports unknown when GitHub omits the permission header' {
        InModuleScope 'ALZ.ARO' {
            Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 403; Headers = @{} } }
            Get-MissingGitHubPermission -RepositoryPath 'owner/repo' -Headers @{} | Should -Match 'unknown'
        }
    }

    It 'stays silent when every probe succeeds' {
        InModuleScope 'ALZ.ARO' {
            Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200; Headers = @{} } }
            Get-MissingGitHubPermission -RepositoryPath 'owner/repo' -Headers @{} | Should -BeNullOrEmpty
        }
    }
}
