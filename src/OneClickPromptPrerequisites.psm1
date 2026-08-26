#requires -Version 5.1

Set-StrictMode -Version Latest

function Add-WinGetDirectoryToProcessPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ExecutablePath
    )

    $directory = Split-Path -Parent $ExecutablePath
    $pathEntries = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($directory -notin $pathEntries) {
        $env:Path = "$directory;$env:Path"
    }
}

function Get-WinGetExecutable {
    [CmdletBinding()]
    param()

    $command = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
        return $command.Source
    }

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidatePaths.Add((Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'))
    }

    try {
        $appInstallerPackages = @(Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
        foreach ($package in $appInstallerPackages) {
            if (-not [string]::IsNullOrWhiteSpace([string]$package.InstallLocation)) {
                $candidatePaths.Add((Join-Path ([string]$package.InstallLocation) 'winget.exe'))
            }
        }
    }
    catch {
        # AppX discovery is best-effort. The supported repair path is tried later.
    }

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            Add-WinGetDirectoryToProcessPath -ExecutablePath $candidatePath
            return $candidatePath
        }
    }

    return $null
}

function Register-WinGetForCurrentUser {
    [CmdletBinding()]
    param()

    $addAppxPackage = Get-Command 'Add-AppxPackage' -ErrorAction SilentlyContinue
    if ($null -eq $addAppxPackage) {
        return $false
    }

    try {
        if ($addAppxPackage.Parameters.ContainsKey('RegisterByFamilyName')) {
            Add-AppxPackage `
                -RegisterByFamilyName `
                -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' `
                -ErrorAction Stop
            return $true
        }

        $package = Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($null -ne $package -and -not [string]::IsNullOrWhiteSpace([string]$package.InstallLocation)) {
            $manifestPath = Join-Path ([string]$package.InstallLocation) 'AppxManifest.xml'
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
                return $true
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function Install-WinGetForCurrentUser {
    [CmdletBinding()]
    param()

    $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    $previousGalleryPolicy = $null
    $galleryPolicyChanged = $false

    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        if ($null -eq (Get-Command 'Install-PackageProvider' -ErrorAction SilentlyContinue) -or
            $null -eq (Get-Command 'Install-Module' -ErrorAction SilentlyContinue)) {
            throw 'PowerShellGet and PackageManagement are unavailable on this computer.'
        }

        $powerShellGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction SilentlyContinue
        if ($null -eq $powerShellGallery) {
            Register-PSRepository -Default -ErrorAction Stop
            $powerShellGallery = Get-PSRepository -Name 'PSGallery' -ErrorAction Stop
        }

        $previousGalleryPolicy = [string]$powerShellGallery.InstallationPolicy
        if ($previousGalleryPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
            $galleryPolicyChanged = $true
        }

        Install-PackageProvider `
            -Name 'NuGet' `
            -MinimumVersion '2.8.5.201' `
            -Scope CurrentUser `
            -Force `
            -ErrorAction Stop | Out-Null

        Install-Module `
            -Name 'Microsoft.WinGet.Client' `
            -Scope CurrentUser `
            -Repository 'PSGallery' `
            -Force `
            -AllowClobber `
            -Confirm:$false `
            -ErrorAction Stop | Out-Null

        Import-Module 'Microsoft.WinGet.Client' -Force -ErrorAction Stop
        Repair-WinGetPackageManager -Force -Latest -ErrorAction Stop | Out-Null
    }
    finally {
        if ($galleryPolicyChanged -and -not [string]::IsNullOrWhiteSpace($previousGalleryPolicy)) {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy $previousGalleryPolicy -ErrorAction SilentlyContinue
        }

        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
    }
}

function Read-PrerequisiteInstallConsent {
    [CmdletBinding()]
    param()

    while ($true) {
        $answer = (Read-Host 'Install or repair WinGet for your Windows account now? [Y/n]').Trim()
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(?i:y|yes)$') {
            return $true
        }

        if ($answer -match '^(?i:n|no)$') {
            return $false
        }

        Write-Host 'Please answer Y or N.' -ForegroundColor Yellow
    }
}

function Initialize-OneClickPromptPrerequisites {
    [CmdletBinding()]
    param(
        [switch]$SkipWinGetBootstrap
    )

    $winGetPath = Get-WinGetExecutable
    if ($null -ne $winGetPath) {
        Write-Host "WinGet is ready: $winGetPath" -ForegroundColor Green
        return $true
    }

    Write-Host 'WinGet is not currently available.' -ForegroundColor Yellow

    if ($SkipWinGetBootstrap) {
        Write-Host 'Automatic WinGet setup was skipped. Reviewed catalog fallbacks remain available.' -ForegroundColor Yellow
        return $false
    }

    Write-Host 'oneClickPrompt can register an existing App Installer or use Microsoft PowerShell Gallery to repair WinGet.' -ForegroundColor Cyan
    Write-Host 'Windows may show a normal administrator approval prompt while App Installer is repaired.' -ForegroundColor Cyan

    if (-not (Read-PrerequisiteInstallConsent)) {
        Write-Host 'WinGet setup was declined. Reviewed catalog fallbacks remain available.' -ForegroundColor Yellow
        return $false
    }

    if (Register-WinGetForCurrentUser) {
        $winGetPath = Get-WinGetExecutable
        if ($null -ne $winGetPath) {
            Write-Host 'Registered the existing Windows App Installer for this account.' -ForegroundColor Green
            return $true
        }
    }

    try {
        Write-Host 'Installing or repairing WinGet with Microsoft.WinGet.Client...' -ForegroundColor Cyan
        Install-WinGetForCurrentUser
        $winGetPath = Get-WinGetExecutable

        if ($null -eq $winGetPath) {
            throw 'WinGet was repaired, but winget.exe is not available in this PowerShell session.'
        }

        Write-Host "WinGet is ready: $winGetPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Automatic WinGet setup failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Install Microsoft App Installer from https://aka.ms/getwinget, then run oneClickPrompt again.' -ForegroundColor Yellow
        Write-Host 'Reviewed catalog fallbacks remain available in this session.' -ForegroundColor Yellow
        return $false
    }
}

Export-ModuleMember -Function Initialize-OneClickPromptPrerequisites
