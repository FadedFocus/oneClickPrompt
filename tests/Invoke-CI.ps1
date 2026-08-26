#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ModuleCachePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

try {
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    if ([string]::IsNullOrWhiteSpace($ModuleCachePath)) {
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force | Out-Null
        Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser -Force -SkipPublisherCheck
        Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
    }
    else {
        if (-not (Test-Path -LiteralPath $ModuleCachePath -PathType Container)) {
            throw "Module cache not found: $ModuleCachePath"
        }

        $env:PSModulePath = "$ModuleCachePath$([System.IO.Path]::PathSeparator)$env:PSModulePath"
    }

    Import-Module Pester -MinimumVersion 5.5 -Force
    Import-Module PSScriptAnalyzer -Force

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $analysisIssues = @(Invoke-ScriptAnalyzer -Path $repositoryRoot -Recurse -Severity Error)
    $analysisIssues | Format-Table -AutoSize
    if ($analysisIssues.Count -gt 0) {
        throw "PSScriptAnalyzer found $($analysisIssues.Count) error(s)."
    }

    $testResult = Invoke-Pester -Path $PSScriptRoot -CI -PassThru
    if ($testResult.FailedCount -gt 0) {
        throw "Pester reported $($testResult.FailedCount) failed test(s)."
    }
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
}
