# oneClickPrompt

An interactive PowerShell installer for Windows 11. The user types a program name, chooses the intended package, and oneClickPrompt completes the installation silently whenever the installer supports it.

## What it does

1. Prompts for a program name.
2. Searches the live WinGet community source.
3. Shows matching packages and requires an exact selection.
4. Installs the selected package with WinGet's silent and non-interactive flags.
5. If WinGet has no suitable package, checks a reviewed catalog of official vendor installers.
6. Downloads catalog installers over HTTPS, validates their digital signature and optional SHA-256 hash, then runs their documented silent arguments.
7. Prompts to restart now or later when the installation reports that a restart is required.
8. Prompts to install another program or finish.

## Quick start

1. Download and extract the project.
2. Double-click `Run-Installer.bat`.
3. Type a program name, such as `Discord`, `Firefox`, or `Steam`.
4. Select the exact package you want.

The batch file launches Windows PowerShell 5.1 with the included script. It does not permanently change the computer's PowerShell execution policy.

You can also launch it directly:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\Install-App.ps1
```

## Requirements

- Windows 11
- Internet access
- Windows PowerShell 5.1 or PowerShell 7+
- WinGet for general package search and installation

WinGet is normally included with Windows 11 as part of Microsoft's App Installer. If WinGet is unavailable, the script can install only apps present in `config/app-catalog.json`.

## Safety boundary

The script deliberately does not scrape a search engine and execute the first `.exe` it finds. A generic search result cannot reliably prove all of the following:

- the download is from the real publisher;
- the file has not been replaced or tampered with;
- the installer's silent arguments are correct;
- the exit codes accurately indicate success or a required restart.

The fallback path is therefore allowlisted. Every catalog entry must use HTTPS, name an expected Authenticode publisher, and define installer-specific silent and exit-code behavior. A bad signature stops the installation before execution.

## User prompts

Prompts are limited to decisions that cannot safely be assumed:

- selecting the intended package when several names match;
- approving Windows User Account Control when administrator rights are required;
- choosing whether to restart now or later;
- choosing whether to install another program.

Package license and source-agreement prompts are suppressed through WinGet's supported flags. Some vendor installers may still display UI if the vendor does not provide a fully silent mode.

The restart handler recognizes standard MSI exit codes `1641` and `3010`, WinGet's restart HRESULTs, restart messages, and a newly created Windows pending-reboot state.

## Logs

Each run writes a log under:

```text
%LOCALAPPDATA%\oneClickPrompt\Logs
```

The exact path is shown at the beginning and end of the session.

## Repository layout

```text
.
|-- Install-App.ps1
|-- Run-Installer.bat
|-- config/
|   |-- app-catalog.json
|   `-- app-catalog.schema.json
|-- docs/
|   `-- ADDING-CATALOG-APPS.md
|-- src/
|   `-- Win11AppInstaller.psm1
`-- tests/
    `-- Win11AppInstaller.Tests.ps1
```

## Testing

Tests use Pester 5:

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester -Path .\tests -CI
```

The GitHub Actions workflow runs the suite on a Windows runner for every push and pull request.

## Current scope

This first version supports interactive, one-at-a-time installation on Windows 11. It does not silently execute arbitrary web search results, auto-accept UAC, bypass publisher verification, or force a restart.

Microsoft references: [WinGet search](https://learn.microsoft.com/windows/package-manager/winget/search), [WinGet install](https://learn.microsoft.com/windows/package-manager/winget/install), and [WinGet troubleshooting](https://learn.microsoft.com/windows/package-manager/winget/troubleshooting).
