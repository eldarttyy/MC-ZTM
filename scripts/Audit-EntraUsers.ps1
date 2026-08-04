#Requires -Version 7.0

<#
.SYNOPSIS
    Audits Entra ID for users without MFA and exports a multi-cloud identity
    security report as JSON.

.DESCRIPTION
    Calls Microsoft Graph to answer three questions a zero-trust review always
    asks:

      1. Which users can authenticate with a single factor?
      2. Who is currently a member of the privileged cloud groups?
      3. Which privileged accounts are also the weakest (admin + no MFA)?

    Authentication is interactive by default. Pass -AppOnly to use client
    credentials from the environment, which is how the CI job runs it.

    Required Graph permissions:
      User.Read.All
      Group.Read.All
      UserAuthenticationMethod.Read.All
      AuditLog.Read.All          (for the registration-details report)

.PARAMETER TenantId
    Entra ID tenant. Falls back to $env:ENTRA_TENANT_ID.

.PARAMETER Groups
    Display names of the security groups to inventory.

.PARAMETER OutputPath
    Destination JSON file. Parent directories are created if missing.

.PARAMETER AppOnly
    Authenticate as an application using $env:ENTRA_CLIENT_ID and
    $env:ENTRA_CLIENT_SECRET instead of a signed-in user.

.PARAMETER FailOnUnprotectedAdmin
    Exit non-zero when a member of a privileged group has no MFA method
    registered. Intended for pipeline gating.

.EXAMPLE
    ./Audit-EntraUsers.ps1 -OutputPath ../reports/entra-audit.json

.EXAMPLE
    ./Audit-EntraUsers.ps1 -AppOnly -FailOnUnprotectedAdmin

.NOTES
    Part of MC-ZTM. Read-only: this script never writes to the directory.
#>

[CmdletBinding()]
param(
    [string]   $TenantId = $env:ENTRA_TENANT_ID,
    [string[]] $Groups = @('Cloud-Admins', 'Audit-Team', 'Copilot-Early-Access'),
    [string]   $OutputPath = (Join-Path $PSScriptRoot '../reports/entra-security-report.json'),
    [switch]   $AppOnly,
    [switch]   $FailOnUnprotectedAdmin
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Methods that satisfy a second factor. Password and (deprecated) SMS-only
# configurations deliberately do not appear here.
$script:StrongMethods = @(
    'microsoftAuthenticatorAuthenticationMethod'
    'fido2AuthenticationMethod'
    'windowsHelloForBusinessAuthenticationMethod'
    'softwareOathAuthenticationMethod'
    'phoneAuthenticationMethod'
    'temporaryAccessPassAuthenticationMethod'
    'x509CertificateAuthenticationMethod'
)

$script:PrivilegedGroups = @('Cloud-Admins')

function Assert-GraphModule {
    $required = @(
        'Microsoft.Graph.Authentication'
        'Microsoft.Graph.Users'
        'Microsoft.Graph.Groups'
        'Microsoft.Graph.Identity.SignIns'
        'Microsoft.Graph.Reports'
    )

    $missing = $required | Where-Object { -not (Get-Module -ListAvailable -Name $_) }
    if ($missing) {
        throw "Missing PowerShell modules: $($missing -join ', '). Install with: Install-Module Microsoft.Graph -Scope CurrentUser"
    }

    $required | ForEach-Object { Import-Module $_ -ErrorAction Stop }
}

function Connect-Tenant {
    param([string] $TenantId, [switch] $AppOnly)

    $scopes = @(
        'User.Read.All'
        'Group.Read.All'
        'UserAuthenticationMethod.Read.All'
        'AuditLog.Read.All'
    )

    if ($AppOnly) {
        if (-not $env:ENTRA_CLIENT_ID -or -not $env:ENTRA_CLIENT_SECRET) {
            throw 'AppOnly requires ENTRA_CLIENT_ID and ENTRA_CLIENT_SECRET in the environment.'
        }
        if (-not $TenantId) {
            throw 'AppOnly requires -TenantId or ENTRA_TENANT_ID.'
        }

        $secret = ConvertTo-SecureString $env:ENTRA_CLIENT_SECRET -AsPlainText -Force
        $credential = [System.Management.Automation.PSCredential]::new($env:ENTRA_CLIENT_ID, $secret)

        Write-Verbose "Connecting to tenant $TenantId as application $($env:ENTRA_CLIENT_ID)"
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $credential -NoWelcome
    }
    else {
        $connectArgs = @{ Scopes = $scopes; NoWelcome = $true }
        if ($TenantId) { $connectArgs.TenantId = $TenantId }

        Write-Verbose 'Connecting interactively'
        Connect-MgGraph @connectArgs
    }

    Get-MgContext
}

function Get-MfaRegistrationMap {
    <#
        Preferred path is the registration-details report: one call, all users.
        Tenants that have not enabled the reporting API (or app registrations
        lacking AuditLog.Read.All) fall back to per-user method enumeration,
        which is correct but O(n) requests.
    #>
    param([array] $Users)

    try {
        Write-Verbose 'Reading authentication method registration details'
        $details = Get-MgReportAuthenticationMethodUserRegistrationDetail -All

        $map = @{}
        foreach ($detail in $details) {
            $map[$detail.Id] = [pscustomobject]@{
                MfaCapable     = [bool] $detail.IsMfaCapable
                MfaRegistered  = [bool] $detail.IsMfaRegistered
                PasswordlessOk = [bool] $detail.IsPasswordlessCapable
                Methods        = @($detail.MethodsRegistered)
                Source         = 'registrationDetailsReport'
            }
        }
        return $map
    }
    catch {
        Write-Warning "Registration report unavailable ($($_.Exception.Message)). Falling back to per-user enumeration."
    }

    $map = @{}
    foreach ($user in $Users) {
        try {
            $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction Stop
            $types = @($methods | ForEach-Object { $_.AdditionalProperties['@odata.type'] -replace '^#microsoft\.graph\.', '' })
            $strong = @($types | Where-Object { $_ -in $script:StrongMethods })

            $map[$user.Id] = [pscustomobject]@{
                MfaCapable     = $strong.Count -gt 0
                MfaRegistered  = $strong.Count -gt 0
                PasswordlessOk = ($types -contains 'fido2AuthenticationMethod') -or
                                 ($types -contains 'windowsHelloForBusinessAuthenticationMethod')
                Methods        = $types
                Source         = 'authenticationMethods'
            }
        }
        catch {
            Write-Warning "Could not read methods for $($user.UserPrincipalName): $($_.Exception.Message)"
            $map[$user.Id] = [pscustomobject]@{
                MfaCapable     = $null
                MfaRegistered  = $null
                PasswordlessOk = $null
                Methods        = @()
                Source         = 'unavailable'
            }
        }
    }
    return $map
}

function Get-GroupInventory {
    param([string[]] $Groups)

    $inventory = [ordered]@{}

    foreach ($name in $Groups) {
        # Group display names are not unique in Entra ID; report every match
        # rather than silently auditing the first one.
        $matched = @(Get-MgGroup -Filter "displayName eq '$name'" -All -ErrorAction SilentlyContinue)

        if ($matched.Count -eq 0) {
            Write-Warning "Group '$name' not found in tenant."
            $inventory[$name] = [ordered]@{
                found   = $false
                members = @()
            }
            continue
        }

        if ($matched.Count -gt 1) {
            Write-Warning "Group name '$name' resolves to $($matched.Count) groups; auditing all of them."
        }

        $members = foreach ($group in $matched) {
            foreach ($member in (Get-MgGroupMember -GroupId $group.Id -All)) {
                $props = $member.AdditionalProperties
                [pscustomobject]@{
                    id                = $member.Id
                    displayName       = $props['displayName']
                    userPrincipalName = $props['userPrincipalName']
                    type              = ($props['@odata.type'] -replace '^#microsoft\.graph\.', '')
                    groupObjectId     = $group.Id
                }
            }
        }

        $inventory[$name] = [ordered]@{
            found        = $true
            objectIds    = @($matched.Id)
            isAssignable = @($matched | ForEach-Object { [bool] $_.IsAssignableToRole })
            memberCount  = @($members).Count
            members      = @($members)
        }
    }

    return $inventory
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Assert-GraphModule
$context = Connect-Tenant -TenantId $TenantId -AppOnly:$AppOnly
Write-Host "Connected to tenant $($context.TenantId) as $($context.Account ?? $context.ClientId)" -ForegroundColor Cyan

Write-Host 'Enumerating users...' -ForegroundColor Cyan
$users = @(Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled,userType,createdDateTime')
Write-Host "  $($users.Count) users" -ForegroundColor DarkGray

Write-Host 'Evaluating MFA posture...' -ForegroundColor Cyan
$mfaMap = Get-MfaRegistrationMap -Users $users

Write-Host 'Inventorying group membership...' -ForegroundColor Cyan
$groupInventory = Get-GroupInventory -Groups $Groups

$privilegedUpns = @(
    foreach ($name in $script:PrivilegedGroups) {
        if ($groupInventory.Contains($name) -and $groupInventory[$name].found) {
            $groupInventory[$name].members |
                Where-Object { $_.type -eq 'user' } |
                ForEach-Object { $_.userPrincipalName }
        }
    }
) | Where-Object { $_ } | Sort-Object -Unique

$assessed = foreach ($user in $users) {
    $mfa = if ($mfaMap.ContainsKey($user.Id)) {
        $mfaMap[$user.Id]
    }
    else {
        # A user missing from the report is unknown, not compliant.
        [pscustomobject]@{
            MfaCapable = $null; MfaRegistered = $null; PasswordlessOk = $null
            Methods    = @();   Source        = 'notReported'
        }
    }
    $isPrivileged = $user.UserPrincipalName -in $privilegedUpns

    [pscustomobject]@{
        id                = $user.Id
        displayName       = $user.DisplayName
        userPrincipalName = $user.UserPrincipalName
        accountEnabled    = $user.AccountEnabled
        userType          = $user.UserType
        createdDateTime   = $user.CreatedDateTime
        mfaRegistered     = $mfa.MfaRegistered
        mfaCapable        = $mfa.MfaCapable
        passwordlessReady = $mfa.PasswordlessOk
        methodsRegistered = @($mfa.Methods)
        evidenceSource    = $mfa.Source
        privileged        = $isPrivileged
        # Enabled + privileged + single factor is the finding that matters.
        riskLevel         = $(
            if (-not $user.AccountEnabled) { 'none' }
            elseif ($mfa.MfaRegistered -eq $true) { 'low' }
            elseif ($isPrivileged) { 'critical' }
            else { 'high' }
        )
    }
}

$withoutMfa = @($assessed | Where-Object { $_.accountEnabled -and $_.mfaRegistered -ne $true })
$criticalFindings = @($assessed | Where-Object { $_.riskLevel -eq 'critical' })

$report = [ordered]@{
    metadata = [ordered]@{
        generatedUtc  = (Get-Date).ToUniversalTime().ToString('o')
        tenantId      = $context.TenantId
        generatedBy   = ($context.Account ?? $context.ClientId)
        authMode      = $(if ($AppOnly) { 'application' } else { 'delegated' })
        scriptVersion = '1.0.0'
        project       = 'MC-ZTM'
    }
    summary = [ordered]@{
        totalUsers          = $users.Count
        enabledUsers        = @($assessed | Where-Object { $_.accountEnabled }).Count
        guestUsers          = @($assessed | Where-Object { $_.userType -eq 'Guest' }).Count
        mfaRegistered       = @($assessed | Where-Object { $_.mfaRegistered -eq $true }).Count
        mfaMissing          = $withoutMfa.Count
        mfaCoveragePercent  = $(
            if ($users.Count -gt 0) {
                [math]::Round((@($assessed | Where-Object { $_.mfaRegistered -eq $true }).Count / $users.Count) * 100, 1)
            }
            else { 0 }
        )
        privilegedUsers     = $privilegedUpns.Count
        criticalFindings    = $criticalFindings.Count
    }
    findings = [ordered]@{
        usersWithoutMfa       = @($withoutMfa | Select-Object userPrincipalName, displayName, userType, riskLevel)
        privilegedWithoutMfa  = @($criticalFindings | Select-Object userPrincipalName, displayName)
    }
    groups = $groupInventory
    users  = @($assessed)
}

$outputDir = Split-Path -Parent $OutputPath
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding utf8
Write-Host "Report written to $OutputPath" -ForegroundColor Green

Write-Host ''
Write-Host 'MFA coverage : ' -NoNewline
Write-Host "$($report.summary.mfaCoveragePercent)%" -ForegroundColor Yellow
Write-Host 'Users w/o MFA: ' -NoNewline
Write-Host $report.summary.mfaMissing -ForegroundColor Yellow
Write-Host 'Critical     : ' -NoNewline
Write-Host $report.summary.criticalFindings -ForegroundColor ($criticalFindings.Count -gt 0 ? 'Red' : 'Green')

foreach ($finding in $criticalFindings) {
    Write-Host "  [CRITICAL] $($finding.userPrincipalName) is in a privileged group with no MFA method" -ForegroundColor Red
}

Disconnect-MgGraph | Out-Null

if ($FailOnUnprotectedAdmin -and $criticalFindings.Count -gt 0) {
    exit 1
}
