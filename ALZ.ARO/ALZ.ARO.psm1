Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command, [Parameter(Mandatory)][string[]]$Arguments)

    $output = & $Command @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed (exit $LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }
    return ($output -join [Environment]::NewLine)
}

function Read-AROConfig {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Configuration file not found: $Path" }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
    catch { throw "Configuration must be valid JSON: $($_.Exception.Message)" }
}

function New-AROConfigWizard {
    param([Parameter(Mandatory)][string]$OutputPath)

    $mode = Read-Host 'Deployment mode (standalone/spoke)'
    $approverInput = Read-Host 'GitHub apply approver usernames (comma-separated; at least one)'
    $config = [ordered]@{
        deployment_mode = $mode
        tenant_id = Read-Host 'Microsoft Entra tenant ID'
        bootstrap_subscription_id = Read-Host 'Bootstrap subscription ID'
        workload_subscription_id = Read-Host 'ARO workload subscription ID'
        connectivity_subscription_id = if ($mode -eq 'spoke') { Read-Host 'Existing hub connectivity subscription ID' } else { '' }
        location = Read-Host 'Azure region (for example eastus)'
        service_name = Read-Host 'Short service name'
        environment_name = Read-Host 'Environment name'
        github_organization = Read-Host 'GitHub organization or owner'
        github_repository = Read-Host 'New workload repository name'
        apply_approvers = @($approverInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        aro_version = Read-Host 'ARO version (leave empty to resolve newest available)'
        aro_domain = Read-Host 'Unique ARO domain prefix'
        aro_vnet_cidr = Read-Host 'New ARO VNet CIDR'
        control_plane_subnet_cidr = Read-Host 'Control-plane subnet CIDR'
        worker_subnet_cidr = Read-Host 'Worker subnet CIDR'
        hub_vnet_id = if ($mode -eq 'spoke') { Read-Host 'Existing hub VNet resource ID' } else { '' }
        next_hop_ip = if ($mode -eq 'spoke') { Read-Host 'Existing firewall/NVA private IP' } else { '' }
        ingress_mode = Read-Host 'Ingress mode (none/front_door/application_gateway; default none)'
    }
    if ([string]::IsNullOrWhiteSpace($config.ingress_mode)) { $config.ingress_mode = 'none' }
    $config.application_gateway_subnet_cidr = if ($config.ingress_mode -eq 'application_gateway') { Read-Host 'Dedicated Application Gateway subnet CIDR' } else { '' }
    $config.application_gateway_backend_host_name = if ($config.ingress_mode -eq 'application_gateway') { Read-Host 'OpenShift application hostname for the gateway health probe' } else { '' }
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    return $config
}

function Assert-AROConfig {
    param([Parameter(Mandatory)][hashtable]$Config)

    $required = @('deployment_mode','tenant_id','bootstrap_subscription_id','workload_subscription_id','location','service_name','environment_name','github_organization','github_repository','aro_domain','aro_vnet_cidr','control_plane_subnet_cidr','worker_subnet_cidr','ingress_mode')
    foreach ($name in $required) {
        if (-not $Config.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$Config[$name])) { throw "Missing required configuration value '$name'." }
    }
    if ($Config.deployment_mode -notin @('standalone','spoke')) { throw "deployment_mode must be exactly 'standalone' or 'spoke'." }
    if ($Config.ingress_mode -notin @('none','front_door','application_gateway')) { throw "ingress_mode must be exactly 'none', 'front_door', or 'application_gateway'." }
    if ($Config.ingress_mode -eq 'application_gateway') {
        foreach ($name in @('application_gateway_subnet_cidr','application_gateway_backend_host_name')) {
            if (-not $Config.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$Config[$name])) { throw "application_gateway mode requires '$name'." }
        }
    }
    if (-not $Config.ContainsKey('apply_approvers') -or @($Config.apply_approvers).Count -eq 0) { throw 'At least one GitHub apply approver is required to protect apply and destroy.' }
    if ($Config.deployment_mode -eq 'spoke') {
        foreach ($name in @('connectivity_subscription_id','hub_vnet_id','next_hop_ip')) {
            if (-not $Config.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$Config[$name])) { throw "spoke mode requires '$name'." }
        }
        if ($Config.hub_vnet_id -notmatch '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\.Network/virtualNetworks/[^/]+$') { throw 'hub_vnet_id must be a complete Azure VNet resource ID.' }
        $hubSubscription = ($Config.hub_vnet_id -split '/')[2]
        if ($hubSubscription -ne $Config.connectivity_subscription_id) { throw 'hub_vnet_id subscription must match connectivity_subscription_id.' }
        $ip = $null
        if (-not [System.Net.IPAddress]::TryParse([string]$Config.next_hop_ip, [ref]$ip)) { throw 'next_hop_ip must be an IP address.' }
    }
}

function Invoke-AROPreflight {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][ValidateSet('plan','apply','destroy')][string]$BootstrapAction
    )

    foreach ($tool in @('az','terraform')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required command '$tool' is not available on PATH." }
    }
    $account = Invoke-NativeCommand az @('account','show','--output','json') | ConvertFrom-Json
    if (-not $account.id) { throw 'Azure CLI is not authenticated. Run az login.' }
    if ([string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
            # The Terraform GitHub provider reads GITHUB_TOKEN. Accept GH_TOKEN
            # without persisting or printing its value.
            $env:GITHUB_TOKEN = $env:GH_TOKEN
        }
        elseif (Get-Command gh -ErrorAction SilentlyContinue) {
            # Reuse an authenticated GitHub CLI session without exposing the
            # credential in command history, generated input, or Terraform.
            $env:GITHUB_TOKEN = Invoke-NativeCommand gh @('auth','token')
        }
        else {
            throw 'Set GITHUB_TOKEN or GH_TOKEN, or authenticate GitHub CLI with gh auth login. The credential is never written or printed.'
        }
    }

    $githubHeaders = @{
        Accept                 = 'application/vnd.github+json'
        Authorization          = "Bearer $($env:GITHUB_TOKEN)"
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'ALZ.ARO-bootstrap'
    }
    $githubUserResponse = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $githubHeaders -SkipHttpErrorCheck
    if ([int]$githubUserResponse.StatusCode -ne 200) {
        throw 'GitHub rejected GITHUB_TOKEN. Replace the stale or invalid value (for example: $env:GITHUB_TOKEN = gh auth token) and retry.'
    }
    $githubUser = $githubUserResponse.Content | ConvertFrom-Json
    $owner = [uri]::EscapeDataString([string]$Config.github_organization)
    $githubOwnerResponse = Invoke-WebRequest -Uri "https://api.github.com/users/$owner" -Headers $githubHeaders -SkipHttpErrorCheck
    if ([int]$githubOwnerResponse.StatusCode -ne 200) {
        throw "GitHub owner '$($Config.github_organization)' is unavailable to the supplied credential."
    }
    $githubOwner = $githubOwnerResponse.Content | ConvertFrom-Json
    if ($githubOwner.type -eq 'User' -and $githubUser.login -ne $githubOwner.login) {
        throw "A personal repository can only be bootstrapped under the authenticated GitHub user '$($githubUser.login)', not '$($githubOwner.login)'."
    }

    # Required reviewers on private repositories require GitHub Enterprise.
    # The generic /users endpoint does not expose organization billing plans,
    # so query the organization endpoint when applicable and fail closed when
    # GitHub does not report Enterprise capability.
    $ownerPlan = if ($githubOwner.type -eq 'Organization') {
        $organizationResponse = Invoke-WebRequest -Uri "https://api.github.com/orgs/$owner" -Headers $githubHeaders -SkipHttpErrorCheck
        if ([int]$organizationResponse.StatusCode -eq 200) {
            $organization = $organizationResponse.Content | ConvertFrom-Json
            if ($organization.PSObject.Properties['plan']) { $organization.plan.name } else { $null }
        }
        else { $null }
    }
    elseif ($githubUser.PSObject.Properties['plan']) { $githubUser.plan.name }
    else { $null }
    $Config.apply_environment_reviewers_enabled = [string]$ownerPlan -eq 'enterprise'
    if (-not $Config.apply_environment_reviewers_enabled) {
        Write-Warning 'The GitHub owner plan does not support required reviewers for a private repository. The apply environment will be created without a reviewer rule; manual SHA confirmation and exact-plan apply safeguards remain enabled.'
    }

    # Classic PATs report scopes in this header. Fine-grained PATs do not, so
    # their repository permissions remain governed by GitHub API responses.
    $classicScopes = @([string]$githubUserResponse.Headers['X-OAuth-Scopes'] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($classicScopes.Count -gt 0) {
        $requiredScopes = @('repo', 'workflow')
        if ($githubOwner.type -eq 'Organization') { $requiredScopes += 'read:org' }
        if ($BootstrapAction -eq 'destroy') { $requiredScopes += 'delete_repo' }
        $missingScopes = @($requiredScopes | Where-Object { $_ -notin $classicScopes })
        if ($missingScopes.Count -gt 0) {
            throw "The classic GitHub PAT is missing required scope(s): $($missingScopes -join ', ')."
        }
    }
    [void](Invoke-NativeCommand az @('account','show','--subscription',[string]$Config.bootstrap_subscription_id,'--output','none'))
    [void](Invoke-NativeCommand az @('account','show','--subscription',[string]$Config.workload_subscription_id,'--output','none'))
    if ($Config.deployment_mode -eq 'spoke') {
        [void](Invoke-NativeCommand az @('network','vnet','show','--ids',[string]$Config.hub_vnet_id,'--subscription',[string]$Config.connectivity_subscription_id,'--output','none'))
    }
}

function Resolve-AROVersion {
    param([Parameter(Mandatory)][hashtable]$Config)

    $raw = Invoke-NativeCommand az @('aro','get-versions','--location',[string]$Config.location,'--subscription',[string]$Config.workload_subscription_id,'--output','json')
    $result = $raw | ConvertFrom-Json
    $versions = @($result | ForEach-Object {
        if ($_ -is [string]) { $_ }
        elseif ($_.version) { [string]$_.version }
    } | Where-Object { $_ } | Sort-Object { [version]($_ -replace '[^0-9.].*$','') } -Descending -Unique)
    if ($versions.Count -eq 0) { throw "No ARO versions were returned for location '$($Config.location)'." }
    if (-not [string]::IsNullOrWhiteSpace([string]$Config.aro_version)) {
        if ([string]$Config.aro_version -notin $versions) { throw "ARO version '$($Config.aro_version)' is unavailable in '$($Config.location)'. Available: $($versions -join ', ')." }
        return [string]$Config.aro_version
    }
    return [string]$versions[0]
}

function New-BootstrapInput {
    param([hashtable]$Config, [string]$RepositoryRoot, [string]$OutputPath)

    $files = @{}
    $templateRoot = Join-Path $RepositoryRoot 'ALZ.ARO\templates'
    Get-ChildItem -LiteralPath $templateRoot -File -Recurse | Where-Object {
        $relative = [IO.Path]::GetRelativePath($templateRoot, $_.FullName).Replace('\','/')
        $relative -notmatch '(^|/)\.terraform/' -and $relative -notmatch '\.(tfplan|log)$'
    } | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath($templateRoot, $_.FullName).Replace('\','/')
        $files[$relative] = Get-Content -LiteralPath $_.FullName -Raw
    }
    $workload = [ordered]@{
        deployment_mode = $Config.deployment_mode
        tenant_id = $Config.tenant_id
        workload_subscription_id = $Config.workload_subscription_id
        connectivity_subscription_id = $Config.connectivity_subscription_id
        location = $Config.location
        resource_group_name = "rg-$($Config.service_name)-$($Config.environment_name)-aro"
        cluster_name = "aro-$($Config.service_name)-$($Config.environment_name)"
        aro_domain = $Config.aro_domain
        aro_version = $Config.aro_version
        aro_vnet_cidr = $Config.aro_vnet_cidr
        control_plane_subnet_cidr = $Config.control_plane_subnet_cidr
        worker_subnet_cidr = $Config.worker_subnet_cidr
        hub_vnet_id = $Config.hub_vnet_id
        next_hop_ip = $Config.next_hop_ip
        ingress_mode = $Config.ingress_mode
        application_gateway_subnet_cidr = if ($Config.ContainsKey('application_gateway_subnet_cidr')) { $Config.application_gateway_subnet_cidr } else { '' }
        application_gateway_backend_host_name = if ($Config.ContainsKey('application_gateway_backend_host_name')) { $Config.application_gateway_backend_host_name } else { '' }
    }
    $files['terraform/aro.auto.tfvars.json'] = $workload | ConvertTo-Json -Depth 10
    $input = [ordered]@{
        tenant_id = $Config.tenant_id
        bootstrap_subscription_id = $Config.bootstrap_subscription_id
        workload_subscription_id = $Config.workload_subscription_id
        connectivity_subscription_id = $Config.connectivity_subscription_id
        location = $Config.location
        service_name = $Config.service_name
        environment_name = $Config.environment_name
        github_organization = $Config.github_organization
        github_repository = $Config.github_repository
        apply_approvers = @($Config.apply_approvers)
        apply_environment_reviewers_enabled = [bool]$Config.apply_environment_reviewers_enabled
        repository_files = $files
    }
    $input | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
}

function Deploy-AROLandingZone {
    <#
    .SYNOPSIS
    Generates configuration and plans or applies the ARO landing-zone bootstrap.
    .DESCRIPTION
    With InputConfigPath, runs noninteractively. Without it, runs a JSON configuration wizard. Plan is the default; apply creates bootstrap resources, and destroy removes the generated repository and Azure bootstrap resources through an exact reviewed destroy plan. The selected ARO version is validated and persisted exactly before Terraform is invoked. Secrets are accepted only through environment variables and are never printed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [string]$InputConfigPath,
        [string]$OutputConfigPath,
        [ValidateSet('plan','apply','destroy')][string]$BootstrapAction = 'plan',
        [switch]$GenerateConfig,
        [switch]$AutoApprove
    )

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($OutputConfigPath)) { $OutputConfigPath = Join-Path $repositoryRoot 'config\local.json' }
    $configPath = if ($InputConfigPath) { (Resolve-Path -LiteralPath $InputConfigPath).Path } else { $OutputConfigPath }
    $config = if ($InputConfigPath) { Read-AROConfig $configPath } else { New-AROConfigWizard $configPath }
    Assert-AROConfig $config
    if ($GenerateConfig) { Write-Host "Configuration written to $configPath"; return }

    Invoke-AROPreflight -Config $config -BootstrapAction $BootstrapAction
    $config.aro_version = Resolve-AROVersion $config
    $config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM
    Write-Host "Validated and pinned ARO version $($config.aro_version) in $configPath"

    $bootstrapRoot = Join-Path $repositoryRoot 'bootstrap\alz\github'
    $tfvars = Join-Path $bootstrapRoot 'terraform.tfvars.json'
    New-BootstrapInput -Config $config -RepositoryRoot $repositoryRoot -OutputPath $tfvars
    Push-Location $bootstrapRoot
    try {
        [void](Invoke-NativeCommand terraform @('init','-input=false'))
        [void](Invoke-NativeCommand terraform @('validate','-no-color'))
        $planName = if ($BootstrapAction -eq 'destroy') { 'bootstrap-destroy.tfplan' } else { 'bootstrap.tfplan' }
        $planPath = Join-Path $bootstrapRoot $planName
        $planArguments = @('plan','-input=false','-out', $planPath)
        if ($BootstrapAction -eq 'destroy') { $planArguments = @('plan','-destroy','-input=false','-out', $planPath) }
        [void](Invoke-NativeCommand terraform $planArguments)
        Write-Host "Bootstrap plan created: $planPath"
        if ($BootstrapAction -eq 'apply') {
            if ($AutoApprove -or $PSCmdlet.ShouldProcess("$($config.github_organization)/$($config.github_repository)", 'Apply exact bootstrap Terraform plan')) {
                [void](Invoke-NativeCommand terraform @('apply','-input=false', $planPath))
                Write-Host 'Bootstrap apply completed. No workload apply was triggered.'
            }
        }
        elseif ($BootstrapAction -eq 'destroy') {
            $target = "$($Config.github_organization)/$($Config.github_repository) and rg-$($Config.service_name)-$($Config.environment_name)-bootstrap"
            if ($AutoApprove -or $PSCmdlet.ShouldProcess($target, 'Apply exact bootstrap destroy plan, including deletion of the generated GitHub repository and state platform')) {
                [void](Invoke-NativeCommand terraform @('apply','-input=false', $planPath))
                Write-Host 'Bootstrap destroy completed. The generated GitHub repository and Azure bootstrap resources were removed.'
            }
        }
    }
    finally { Pop-Location }
}

Export-ModuleMember -Function Deploy-AROLandingZone
