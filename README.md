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

## Run directly from PowerShell

Open Windows PowerShell or PowerShell 7 and run:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod -Uri "https://api.github.com/repos/FadedFocus/oneClickPrompt/contents/Bootstrap.ps1?ref=main&cache=$([Guid]::NewGuid().ToString('N'))" -Headers @{ Accept = 'application/vnd.github.raw+json'; 'Cache-Control' = 'no-cache'; 'User-Agent' = 'oneClickPrompt-launcher' })))
```

No Git client, PowerShell modules, or preinstalled WinGet command are required. The bootstrap script:

1. downloads a temporary copy of this repository from GitHub over HTTPS;
2. uses the PowerShell version that launched it;
3. detects whether WinGet is available;
4. with approval, first tries to register an existing Windows App Installer for the current account;
5. uses Microsoft's `Microsoft.WinGet.Client` repair flow if WinGet is still missing;
6. starts oneClickPrompt and removes the temporary project copy when it closes.

The script asks before registering, installing, or repairing WinGet. If that setup is declined or fails, the reviewed direct-download catalog remains available.

The one-line command executes the current `main` branch. On a shared or managed computer, review [Bootstrap.ps1](https://github.com/FadedFocus/oneClickPrompt/blob/main/Bootstrap.ps1) before running it.

## Run a downloaded copy

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
- permission to install software on the computer or for the current Windows account

Windows 11 includes Windows PowerShell 5.1. WinGet is normally included as part of Microsoft's App Installer; when it is unavailable, oneClickPrompt offers to register or repair it with Microsoft's supported PowerShell commands. No Pester, Git, or third-party plugin is required to run the application.

Use `-SkipWinGetBootstrap` when running `Bootstrap.ps1` or `Install-App.ps1` if the computer is managed and prerequisite changes are not allowed. In that mode, only apps present in `config/app-catalog.json` can be installed when WinGet is missing.

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
|-- Bootstrap.ps1
|-- Run-Installer.bat
|-- config/
|   |-- app-catalog.json
|   `-- app-catalog.schema.json
|-- docs/
|   `-- ADDING-CATALOG-APPS.md
|-- src/
|   |-- OneClickPromptPrerequisites.psm1
|   `-- Win11AppInstaller.psm1
`-- tests/
    |-- EntryPoint.Tests.ps1
    |-- Invoke-CI.ps1
    |-- OneClickPromptPrerequisites.Tests.ps1
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

Microsoft references: [WinGet search](https://learn.microsoft.com/windows/package-manager/winget/search), [WinGet install](https://learn.microsoft.com/windows/package-manager/winget/install), [WinGet troubleshooting and repair](https://learn.microsoft.com/windows/package-manager/winget/troubleshooting), and [App Installer installation](https://learn.microsoft.com/windows/msix/app-installer/install-update-app-installer).
