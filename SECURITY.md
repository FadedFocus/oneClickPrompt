# Security policy

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could cause an untrusted installer to be downloaded or executed. Report it privately through the repository owner's GitHub security contact or a private security advisory.

Include the affected commit, Windows and PowerShell versions, reproduction steps, and any relevant log output with personal paths removed.

## Trust model

- WinGet installs use the exact package ID selected by the user.
- Direct downloads must be explicitly listed in the local catalog.
- Direct downloads require HTTPS and a valid Authenticode signature from the configured publisher.
- A configured SHA-256 hash, when present, must match before execution.
- The project never bypasses UAC, disables antivirus, ignores a WinGet hash failure, or automatically executes an arbitrary search result.
