#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$CatalogPath,

    [switch]$SkipWinGetBootstrap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $PSScriptRoot 'config\app-catalog.json'
}

$modulePath = Join-Path $PSScriptRoot 'src\Win11AppInstaller.psm1'
$prerequisiteModulePath = Join-Path $PSScriptRoot 'src\OneClickPromptPrerequisites.psm1'

try {
    Import-Module $prerequisiteModulePath -Force -ErrorAction Stop
    Initialize-OneClickPromptPrerequisites -SkipWinGetBootstrap:$SkipWinGetBootstrap | Out-Null

    Import-Module $modulePath -Force -ErrorAction Stop
    Start-AppInstaller -CatalogPath $CatalogPath
    exit 0
}
catch {
    Write-Host ''
    Write-Host "Fatal error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'No additional software will be installed.' -ForegroundColor Yellow
    Read-Host 'Press Enter to close' | Out-Null
    exit 1
}
