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

Describe 'Bootstrap workspace isolation' {
    BeforeAll { Import-Module $manifest -Force }

    It 'derives one workspace per service and environment' {
        InModuleScope 'ALZ.ARO' {
            Get-AROBootstrapWorkspaceName -ServiceName 'aro' -EnvironmentName 'dev' | Should -Be 'aro-dev'
            Get-AROBootstrapWorkspaceName -ServiceName 'aro' -EnvironmentName 'prod' | Should -Be 'aro-prod'
            Get-AROBootstrapWorkspaceName -ServiceName 'ARO' -EnvironmentName 'Dev' | Should -Be 'aro-dev'
            Get-AROBootstrapWorkspaceName -ServiceName 'my_app' -EnvironmentName 'test' | Should -Be 'my-app-test'
        }
    }

    It 'keeps environments apart' {
        InModuleScope 'ALZ.ARO' {
            $dev = Get-AROBootstrapWorkspaceName -ServiceName 'aro' -EnvironmentName 'dev'
            $test = Get-AROBootstrapWorkspaceName -ServiceName 'aro' -EnvironmentName 'test'
            $dev | Should -Not -Be $test
        }
    }

    It 'refuses to adopt state that belongs to another environment' {
        InModuleScope 'ALZ.ARO' {
            $root = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid())
            New-Item -ItemType Directory -Path $root | Out-Null
            @{ resources = @(@{ type = 'github_repository'; instances = @(@{ attributes = @{ name = 'aroapp-prod' } }) }) } |
                ConvertTo-Json -Depth 8 | Set-Content (Join-Path $root 'terraform.tfstate')
            Mock Invoke-NativeCommand { 'default' }
            { Use-AROBootstrapWorkspace -BootstrapRoot $root -Config @{ service_name = 'aroapp'; environment_name = 'dev'; github_repository = 'aroapp-dev' } } |
                Should -Throw '*belongs to ''aroapp-prod''*'
            Remove-Item $root -Recurse -Force
        }
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
