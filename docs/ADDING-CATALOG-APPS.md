# Adding an official-download fallback

Use the fallback catalog only when an app cannot be reliably installed from WinGet. WinGet should remain the preferred provider because its manifest already records installer URLs, hashes, silent switches, and expected return codes.

## Review checklist

Before adding an app to `config/app-catalog.json`, verify all of these items:

1. The homepage and download URL are controlled by the software publisher.
2. The download uses HTTPS.
3. The URL returns a Windows `.exe` or `.msi` installer, not an HTML page or archive.
4. The publisher documents a truly silent install mode.
5. The silent arguments suppress automatic restarts.
6. The expected Authenticode signer is known.
7. Success and restart exit codes come from publisher documentation.
8. The entry is tested on a clean Windows 11 virtual machine.

Do not add software obtained from mirrors, aggregators, URL shorteners, forums, or search-result redirects.

## Entry format

```json
{
  "name": "Example App",
  "aliases": ["example", "example app"],
  "homepage": "https://vendor.example/app",
  "downloadUrl": "https://vendor.example/download/app.exe",
  "fileName": "Example-App.exe",
  "installerType": "exe",
  "architectures": ["x64"],
  "silentArguments": ["/silent", "/norestart"],
  "publisherPattern": "Example Company, Inc\\.",
  "sha256": "",
  "requiresAdmin": true,
  "successExitCodes": [0, 1641, 3010],
  "restartExitCodes": [1641, 3010]
}
```

`publisherPattern` is a PowerShell regular expression matched against the signing certificate's subject. Escape punctuation that has a special regular-expression meaning.

## Moving versus versioned URLs

A moving URL such as `latest` cannot use a permanent SHA-256 value, so leave `sha256` empty and rely on the required Authenticode signer check. A version-pinned URL should include its 64-character SHA-256 hash whenever the publisher makes that hash available.

## Installer types

- `exe`: `silentArguments` are passed to the downloaded executable.
- `msi`: the project supplies `/i`, `/qn`, and `/norestart`; `silentArguments` should contain only additional MSI properties.

`architectures` may contain `x64`, `arm64`, or `x86`. Add only architectures supported by that exact download.

The downloaded file is deleted after the install attempt, whether the attempt succeeds or fails.
