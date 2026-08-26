#requires -Version 5.1

[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository = 'FadedFocus/oneClickPrompt',

    [ValidateNotNullOrEmpty()]
    [string]$Ref = 'main',

    [switch]$SkipWinGetBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-BootstrapWindows11 {
    [CmdletBinding()]
    param()

    if ($env:OS -ne 'Windows_NT') {
        return $false
    }

    try {
        $windowsVersion = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        return [int]$windowsVersion.CurrentBuildNumber -ge 22000
    }
    catch {
        return [Environment]::OSVersion.Version.Build -ge 22000
    }
}

function Get-CurrentPowerShellExecutable {
    [CmdletBinding()]
    param()

    $executableName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $executablePath = Join-Path $PSHOME $executableName

    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "Could not locate the current PowerShell executable: $executablePath"
    }

    return $executablePath
}

function Invoke-RepositoryArchiveDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryName,

        [Parameter(Mandatory = $true)]
        [string]$SourceRef,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $escapedRef = [Uri]::EscapeDataString($SourceRef)
    $requestNonce = [Guid]::NewGuid().ToString('N')
    $commitUri = "https://api.github.com/repos/$RepositoryName/commits/$escapedRef`?oneClickPrompt=$requestNonce"
    $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        $requestHeaders = @{
            Accept          = 'application/vnd.github+json'
            'Cache-Control' = 'no-cache'
            'User-Agent'    = 'oneClickPrompt-bootstrap'
        }
        $commitResponse = Invoke-WebRequest `
            -Uri $commitUri `
            -Headers $requestHeaders `
            -UseBasicParsing `
            -ErrorAction Stop
        $commit = $commitResponse.Content | ConvertFrom-Json
        $commitSha = [string]$commit.sha
        if ($commitSha -notmatch '^[a-fA-F0-9]{40}$') {
            throw "GitHub did not return a valid commit for ref '$SourceRef'."
        }

        $archiveUri = "https://api.github.com/repos/$RepositoryName/zipball/$commitSha`?oneClickPrompt=$requestNonce"
        Invoke-WebRequest `
            -Uri $archiveUri `
            -Headers $requestHeaders `
            -OutFile $DestinationPath `
            -UseBasicParsing `
            -MaximumRedirection 10 `
            -ErrorAction Stop

        return $commitSha
    }
    finally {
        [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
    }
}

if (-not (Test-BootstrapWindows11)) {
    throw 'oneClickPrompt supports Windows 11 only.'
}

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('oneClickPrompt-bootstrap-{0}' -f [Guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $temporaryRoot 'oneClickPrompt.zip'
$extractedPath = Join-Path $temporaryRoot 'source'

try {
    New-Item -Path $temporaryRoot -ItemType Directory -Force | Out-Null

    Write-Host "Downloading $Repository at ref '$Ref'..." -ForegroundColor Cyan
    $resolvedCommit = Invoke-RepositoryArchiveDownload -RepositoryName $Repository -SourceRef $Ref -DestinationPath $archivePath
    Write-Host "Resolved '$Ref' to commit $($resolvedCommit.Substring(0, 7))." -ForegroundColor DarkGray

    Write-Host 'Preparing oneClickPrompt...' -ForegroundColor Cyan
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractedPath -Force

    $sourceRoots = @(Get-ChildItem -LiteralPath $extractedPath -Directory -ErrorAction Stop)
    if ($sourceRoots.Count -ne 1) {
        throw 'The downloaded repository archive did not contain exactly one source directory.'
    }

    $installerPath = Join-Path $sourceRoots[0].FullName 'Install-App.ps1'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw 'The downloaded repository did not contain Install-App.ps1.'
    }

    $powerShellExecutable = Get-CurrentPowerShellExecutable
    $installerArguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $installerPath
    )

    if ($SkipWinGetBootstrap) {
        $installerArguments += '-SkipWinGetBootstrap'
    }

    & $powerShellExecutable @installerArguments
    $installerExitCode = $LASTEXITCODE

    if ($installerExitCode -ne 0) {
        throw "oneClickPrompt exited with code $installerExitCode."
    }
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
