#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$CatalogPath = (Join-Path $PSScriptRoot 'config\app-catalog.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'src\Win11AppInstaller.psm1'

try {
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
