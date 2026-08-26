# Changelog

## Unreleased

- Renamed the project to `oneClickPrompt`.
- Added a one-line PowerShell bootstrap that downloads and runs the project without Git.
- Added automatic registration and user-approved repair of a missing WinGet installation.
- Fixed the Windows CI workflow and added prerequisite bootstrap tests.

## 0.1.0 - 2026-08-25

- Added interactive program search and exact WinGet package selection.
- Added silent, non-interactive WinGet installation.
- Added reviewed official-download fallbacks with HTTPS and Authenticode validation.
- Added restart detection and restart-now-or-later handling.
- Added repeat installation loop, session logs, Pester tests, and Windows CI.
