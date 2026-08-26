#requires -Version 5.1

Set-StrictMode -Version Latest

$script:InstallerLogPath = $null

function Write-InstallerMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Cyan' }
    }

    Write-Host $Message -ForegroundColor $color

    if (-not [string]::IsNullOrWhiteSpace($script:InstallerLogPath)) {
        try {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Add-Content -LiteralPath $script:InstallerLogPath -Value "[$timestamp] [$Level] $Message" -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            # Logging is best-effort and must never interrupt an installation.
        }
    }
}

function Initialize-InstallerLog {
    [CmdletBinding()]
    param()

    $basePath = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        $basePath = [System.IO.Path]::GetTempPath()
    }

    $logDirectory = Join-Path $basePath 'oneClickPrompt\Logs'
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null

    $logName = 'install-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $script:InstallerLogPath = Join-Path $logDirectory $logName
    New-Item -Path $script:InstallerLogPath -ItemType File -Force | Out-Null

    return $script:InstallerLogPath
}

function Test-IsWindows11 {
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

function Test-IsAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PendingRebootState {
    [CmdletBinding()]
    param()

    $rebootKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )

    foreach ($key in $rebootKeys) {
        if (Test-Path -LiteralPath $key) {
            return $true
        }
    }

    try {
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction Stop
        if ($null -ne $sessionManager.PendingFileRenameOperations) {
            return $true
        }
    }
    catch {
        # The value normally does not exist when no restart is pending.
    }

    return $false
}

function Remove-AnsiEscapeSequence {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $escapeCharacter = [string][char]27
    $ansiPattern = $escapeCharacter + '\[[0-?]*[ -/]*[@-~]'
    return $Text -replace $ansiPattern, ''
}

function Get-FixedWidthValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line,

        [Parameter(Mandatory = $true)]
        [int]$Start,

        [Parameter(Mandatory = $true)]
        [int]$Length
    )

    if ($Start -ge $Line.Length -or $Length -le 0) {
        return ''
    }

    $availableLength = [Math]::Min($Length, $Line.Length - $Start)
    return $Line.Substring($Start, $availableLength).Trim()
}

function ConvertFrom-WinGetSearchOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    $cleanLines = @($Lines | ForEach-Object { (Remove-AnsiEscapeSequence -Text ([string]$_)).TrimEnd() })
    $separatorIndex = -1

    for ($index = 1; $index -lt $cleanLines.Count; $index++) {
        if ($cleanLines[$index] -match '^\s*-{5,}\s*$') {
            $separatorIndex = $index
            break
        }
    }

    if ($separatorIndex -lt 1) {
        return @()
    }

    $header = $cleanLines[$separatorIndex - 1]
    $idStart = $header.IndexOf('Id', [StringComparison]::OrdinalIgnoreCase)
    $versionStart = $header.IndexOf('Version', [StringComparison]::OrdinalIgnoreCase)
    $matchStart = $header.IndexOf('Match', [StringComparison]::OrdinalIgnoreCase)
    $sourceStart = $header.LastIndexOf('Source', [StringComparison]::OrdinalIgnoreCase)

    if ($idStart -le 0 -or $versionStart -le $idStart -or $sourceStart -le $versionStart) {
        return @()
    }

    $versionEnd = $sourceStart
    if ($matchStart -gt $versionStart -and $matchStart -lt $sourceStart) {
        $versionEnd = $matchStart
    }

    $packages = New-Object System.Collections.Generic.List[object]

    for ($index = $separatorIndex + 1; $index -lt $cleanLines.Count; $index++) {
        $line = $cleanLines[$index]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $name = Get-FixedWidthValue -Line $line -Start 0 -Length $idStart
        $id = Get-FixedWidthValue -Line $line -Start $idStart -Length ($versionStart - $idStart)
        $version = Get-FixedWidthValue -Line $line -Start $versionStart -Length ($versionEnd - $versionStart)
        $source = Get-FixedWidthValue -Line $line -Start $sourceStart -Length ($line.Length - $sourceStart)

        if ([string]::IsNullOrWhiteSpace($name) -or
            [string]::IsNullOrWhiteSpace($id) -or
            $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$' -or
            $source -ne 'winget') {
            continue
        }

        $packages.Add([PSCustomObject]@{
            Name    = $name
            Id      = $id
            Version = $version
            Source  = $source
        })
    }

    return $packages.ToArray()
}

function Invoke-WinGetSearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [ValidateRange(1, 25)]
        [int]$MaximumResults = 10
    )

    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        return [PSCustomObject]@{
            Available = $false
            ExitCode  = $null
            Packages  = @()
            RawOutput = @()
        }
    }

    $arguments = @(
        'search',
        '--query', $Query,
        '--source', 'winget',
        '--count', [string]$MaximumResults,
        '--accept-source-agreements',
        '--disable-interactivity'
    )

    $rawOutput = @(& $winget.Source @arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    $packages = @(ConvertFrom-WinGetSearchOutput -Lines $rawOutput)
    Add-RawLogLines -Lines $rawOutput

    return [PSCustomObject]@{
        Available = $true
        ExitCode  = $exitCode
        Packages  = $packages
        RawOutput = $rawOutput
    }
}

function Read-NumberSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 1000)]
        [int]$Maximum,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [switch]$AllowZero
    )

    while ($true) {
        $answer = (Read-Host $Prompt).Trim()
        if ($answer -match '^(?i:c|cancel)$') {
            return $null
        }

        $selection = 0
        if ([int]::TryParse($answer, [ref]$selection)) {
            if ($AllowZero -and $selection -eq 0) {
                return 0
            }

            if ($selection -ge 1 -and $selection -le $Maximum) {
                return $selection
            }
        }

        Write-InstallerMessage -Message 'Please enter one of the listed numbers, or C to cancel.' -Level Warning
    }
}

function Select-WinGetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Packages
    )

    Write-Host ''
    Write-InstallerMessage -Message 'WinGet matches:' -Level Info

    for ($index = 0; $index -lt $Packages.Count; $index++) {
        $package = $Packages[$index]
        Write-Host ('  [{0}] {1}  ({2})  Version {3}' -f ($index + 1), $package.Name, $package.Id, $package.Version)
    }

    Write-Host '  [0] None of these - try the reviewed direct-download catalog'
    Write-Host '  [C] Cancel'

    $selection = Read-NumberSelection -Maximum $Packages.Count -Prompt 'Select a package' -AllowZero
    if ($null -eq $selection -or $selection -eq 0) {
        return $selection
    }

    return $Packages[$selection - 1]
}

function Read-ManualWinGetPackage {
    [CmdletBinding()]
    param(
        [string[]]$RawOutput
    )

    Write-InstallerMessage -Message 'WinGet returned results, but this console format could not be parsed automatically.' -Level Warning
    Write-Host 'Enter the exact package ID from the WinGet output below, or press Enter to try the reviewed catalog.'
    Write-Host ''
    @($RawOutput) | ForEach-Object { Write-Host $_ }
    Write-Host ''

    while ($true) {
        $packageId = (Read-Host 'Exact WinGet package ID').Trim()
        if ([string]::IsNullOrWhiteSpace($packageId)) {
            return $null
        }

        if ($packageId -match '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
            return [PSCustomObject]@{
                Name    = $packageId
                Id      = $packageId
                Version = 'Latest'
                Source  = 'winget'
            }
        }

        Write-InstallerMessage -Message 'That does not look like a valid WinGet package ID.' -Level Warning
    }
}

function ConvertTo-NormalizedAppName {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return ($Value.ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Get-NativeWindowsArchitecture {
    [CmdletBinding()]
    param()

    $architecture = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($architecture)) {
        $architecture = $env:PROCESSOR_ARCHITECTURE
    }

    switch ($architecture.ToUpperInvariant()) {
        'AMD64' { return 'x64' }
        'ARM64' { return 'arm64' }
        'X86'   { return 'x86' }
        default { return $architecture.ToLowerInvariant() }
    }
}

function Get-CatalogEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CatalogPath
    )

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "Catalog not found: $CatalogPath"
    }

    $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $catalog.apps) {
        throw 'The catalog does not contain an apps collection.'
    }

    return @($catalog.apps)
}

function Find-CatalogPackages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [object[]]$CatalogEntries
    )

    $normalizedQuery = ConvertTo-NormalizedAppName -Value $Query
    if ([string]::IsNullOrWhiteSpace($normalizedQuery)) {
        return @()
    }

    $exactMatches = New-Object System.Collections.Generic.List[object]
    $partialMatches = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $CatalogEntries) {
        $supportedArchitectures = @((Get-OptionalPropertyValue -InputObject $entry -Name 'architectures' -DefaultValue @('x64', 'arm64', 'x86')) | ForEach-Object { ([string]$_).ToLowerInvariant() })
        if ((Get-NativeWindowsArchitecture) -notin $supportedArchitectures) {
            continue
        }

        $names = @([string]$entry.name)
        if ($null -ne $entry.aliases) {
            $names += @($entry.aliases | ForEach-Object { [string]$_ })
        }

        $normalizedNames = @($names | ForEach-Object { ConvertTo-NormalizedAppName -Value $_ })
        if ($normalizedNames -contains $normalizedQuery) {
            $exactMatches.Add($entry)
            continue
        }

        foreach ($name in $normalizedNames) {
            if ($name.Contains($normalizedQuery) -or $normalizedQuery.Contains($name)) {
                $partialMatches.Add($entry)
                break
            }
        }
    }

    if ($exactMatches.Count -gt 0) {
        return $exactMatches.ToArray()
    }

    return $partialMatches.ToArray()
}

function Select-CatalogPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Packages
    )

    if ($Packages.Count -eq 0) {
        return $null
    }

    Write-Host ''
    Write-InstallerMessage -Message 'Reviewed official-download matches:' -Level Info

    for ($index = 0; $index -lt $Packages.Count; $index++) {
        $package = $Packages[$index]
        Write-Host ('  [{0}] {1} - {2}' -f ($index + 1), $package.name, $package.homepage)
    }

    Write-Host '  [C] Cancel'
    $selection = Read-NumberSelection -Maximum $Packages.Count -Prompt 'Select a package'
    if ($null -eq $selection) {
        return $null
    }

    return $Packages[$selection - 1]
}

function Test-RestartSignal {
    [CmdletBinding()]
    param(
        [int]$ExitCode,
        [string[]]$Output,
        [bool]$PendingBefore,
        [bool]$PendingAfter
    )

    $winGetRestartExitCodes = @(
        -1978334967, # 0x8A150109: restart required to finish
        -1978334966, # 0x8A15010A: restart required before install
        -1978334965  # 0x8A15010B: restart initiated
    )

    if ($ExitCode -in (@(1641, 3010) + $winGetRestartExitCodes)) {
        return $true
    }

    foreach ($line in @($Output)) {
        if ($line -match '(?i)\b(no|not)\s+(reboot|restart)\s+(is\s+)?(required|needed)\b' -or
            $line -match '(?i)\b(reboot|restart)\s+(is\s+)?not\s+(required|needed)\b') {
            continue
        }

        if ($line -match '(?i)\b(reboot|restart)\b.{0,50}\b(required|needed|pending)\b' -or
            $line -match '(?i)\b(required|needed|pending)\b.{0,50}\b(reboot|restart)\b') {
            return $true
        }
    }

    return (-not $PendingBefore) -and $PendingAfter
}

function Add-RawLogLines {
    [CmdletBinding()]
    param(
        [string[]]$Lines
    )

    if ([string]::IsNullOrWhiteSpace($script:InstallerLogPath)) {
        return
    }

    foreach ($line in @($Lines)) {
        try {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Add-Content -LiteralPath $script:InstallerLogPath -Value "[$timestamp] [Process] $line" -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            # Logging is best-effort and must never interrupt an installation.
            return
        }
    }
}

function Invoke-WinGetInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName
    )

    $winget = Get-Command 'winget.exe' -ErrorAction Stop
    $pendingBefore = Get-PendingRebootState
    $arguments = @(
        'install',
        '--id', $PackageId,
        '--exact',
        '--source', 'winget',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )

    Write-InstallerMessage -Message "Installing $DisplayName with WinGet..." -Level Info
    $output = New-Object System.Collections.Generic.List[string]

    & $winget.Source @arguments 2>&1 | ForEach-Object {
        $line = [string]$_
        $output.Add($line)
        Write-Host $line
    }

    $exitCode = $LASTEXITCODE
    $pendingAfter = Get-PendingRebootState
    Add-RawLogLines -Lines $output.ToArray()

    $winGetCompletedWithRestart = @(
        -1978334967, # 0x8A150109: restart required to finish
        -1978334965  # 0x8A15010B: restart initiated
    )
    $winGetRestartBeforeInstall = -1978334966 # 0x8A15010A
    $succeeded = ($exitCode -eq 0) -or ($exitCode -in @(1641, 3010)) -or ($exitCode -in $winGetCompletedWithRestart)
    $restartRequired = Test-RestartSignal -ExitCode $exitCode -Output $output.ToArray() -PendingBefore $pendingBefore -PendingAfter $pendingAfter

    if ($succeeded) {
        Write-InstallerMessage -Message "$DisplayName installed successfully." -Level Success
    }
    elseif ($exitCode -eq $winGetRestartBeforeInstall) {
        Write-InstallerMessage -Message "Windows must restart before WinGet can install $DisplayName." -Level Warning
    }
    else {
        Write-InstallerMessage -Message "$DisplayName failed with WinGet exit code $exitCode." -Level Error
        try {
            $errorText = @(& $winget.Source 'error' ([string]$exitCode) 2>&1 | ForEach-Object { [string]$_ })
            if ($errorText.Count -gt 0) {
                $errorText | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow }
                Add-RawLogLines -Lines $errorText
            }
        }
        catch {
            # The WinGet error helper is best-effort only.
        }
    }

    return [PSCustomObject]@{
        Name            = $DisplayName
        Method          = 'WinGet'
        Succeeded       = $succeeded
        ExitCode        = $exitCode
        RestartRequired = $restartRequired
    }
}

function Get-OptionalPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object]$DefaultValue = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }

    return $property.Value
}

function Assert-CatalogPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Package
    )

    $requiredProperties = @('name', 'downloadUrl', 'fileName', 'installerType', 'publisherPattern', 'silentArguments', 'architectures')
    foreach ($propertyName in $requiredProperties) {
        $property = $Package.PSObject.Properties[$propertyName]
        if ($null -eq $property -or $null -eq $property.Value) {
            throw "Catalog entry is missing required property '$propertyName'."
        }
    }

    foreach ($stringProperty in @('name', 'downloadUrl', 'fileName', 'installerType', 'publisherPattern')) {
        $stringPropertyValue = [string]($Package.PSObject.Properties[$stringProperty].Value)
        if ([string]::IsNullOrWhiteSpace($stringPropertyValue)) {
            throw "Catalog entry property '$stringProperty' cannot be empty."
        }
    }

    $downloadUri = $null
    if (-not [Uri]::TryCreate([string]$Package.downloadUrl, [UriKind]::Absolute, [ref]$downloadUri) -or $downloadUri.Scheme -ne 'https') {
        throw "Catalog entry '$($Package.name)' must use an absolute HTTPS download URL."
    }

    if ([string]$Package.installerType -notin @('exe', 'msi')) {
        throw "Catalog entry '$($Package.name)' has an unsupported installer type."
    }

    $installerExtension = [System.IO.Path]::GetExtension([string]$Package.fileName).TrimStart('.').ToLowerInvariant()
    if ($installerExtension -ne ([string]$Package.installerType).ToLowerInvariant()) {
        throw "Catalog entry '$($Package.name)' file extension does not match its installer type."
    }

    $supportedArchitectures = @($Package.architectures | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if ($supportedArchitectures.Count -eq 0) {
        throw "Catalog entry '$($Package.name)' must declare at least one architecture."
    }

    if ((Get-NativeWindowsArchitecture) -notin $supportedArchitectures) {
        throw "Catalog entry '$($Package.name)' does not support this PC's architecture."
    }

    if ([string]$Package.installerType -eq 'exe' -and @($Package.silentArguments).Count -eq 0) {
        throw "Catalog entry '$($Package.name)' must provide silent arguments for its executable installer."
    }

    $safeFileName = [System.IO.Path]::GetFileName([string]$Package.fileName)
    if ($safeFileName -ne [string]$Package.fileName -or [string]::IsNullOrWhiteSpace($safeFileName)) {
        throw "Catalog entry '$($Package.name)' has an unsafe file name."
    }
}

function Test-InstallerSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$PublisherPattern
    )

    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Installer signature is not valid. Signature status: $($signature.Status)."
    }

    if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch $PublisherPattern) {
        throw "Installer signer did not match the expected publisher pattern '$PublisherPattern'."
    }

    return $signature.SignerCertificate.Subject
}

function Invoke-CatalogInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Package
    )

    $displayName = [string](Get-OptionalPropertyValue -InputObject $Package -Name 'name' -DefaultValue 'Unknown catalog app')
    $temporaryRoot = $null

    try {
        Assert-CatalogPackage -Package $Package

        $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('oneClickPrompt\{0}' -f [Guid]::NewGuid().ToString('N'))
        $installerPath = Join-Path $temporaryRoot ([string]$Package.fileName)
        $pendingBefore = Get-PendingRebootState
        New-Item -Path $temporaryRoot -ItemType Directory -Force | Out-Null

        Write-InstallerMessage -Message "Downloading $displayName from its reviewed official source..." -Level Info

        $oldSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri ([string]$Package.downloadUrl) -OutFile $installerPath -UseBasicParsing -MaximumRedirection 10 -ErrorAction Stop
        }
        finally {
            [Net.ServicePointManager]::SecurityProtocol = $oldSecurityProtocol
        }

        if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf) -or (Get-Item -LiteralPath $installerPath).Length -eq 0) {
            throw 'The downloaded installer is empty or missing.'
        }

        $expectedHash = [string](Get-OptionalPropertyValue -InputObject $Package -Name 'sha256' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($expectedHash)) {
            $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) {
                throw 'The downloaded installer SHA-256 hash did not match the catalog.'
            }
        }

        $signer = Test-InstallerSignature -Path $installerPath -PublisherPattern ([string]$Package.publisherPattern)
        Write-InstallerMessage -Message "Verified digital signature: $signer" -Level Success

        $successExitCodes = @((Get-OptionalPropertyValue -InputObject $Package -Name 'successExitCodes' -DefaultValue @(0, 1641, 3010)) | ForEach-Object { [int]$_ })
        $restartExitCodes = @((Get-OptionalPropertyValue -InputObject $Package -Name 'restartExitCodes' -DefaultValue @(1641, 3010)) | ForEach-Object { [int]$_ })
        $requiresAdmin = [bool](Get-OptionalPropertyValue -InputObject $Package -Name 'requiresAdmin' -DefaultValue $false)
        $silentArguments = @($Package.silentArguments | ForEach-Object { [string]$_ })

        $startParameters = @{
            Wait        = $true
            PassThru    = $true
            ErrorAction = 'Stop'
        }

        if ([string]$Package.installerType -eq 'msi') {
            $startParameters.FilePath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
            $escapedInstallerPath = $installerPath.Replace('"', '\"')
            $argumentText = '/i "{0}" /qn /norestart' -f $escapedInstallerPath
            if ($silentArguments.Count -gt 0) {
                $argumentText = "$argumentText $($silentArguments -join ' ')"
            }
            $startParameters.ArgumentList = $argumentText
        }
        else {
            $startParameters.FilePath = $installerPath
            if ($silentArguments.Count -gt 0) {
                $startParameters.ArgumentList = ($silentArguments -join ' ')
            }
        }

        if ($requiresAdmin -and -not (Test-IsAdministrator)) {
            $startParameters.Verb = 'RunAs'
            Write-InstallerMessage -Message 'Windows will request administrator approval because this installer requires it.' -Level Warning
        }

        Write-InstallerMessage -Message "Installing $displayName silently..." -Level Info
        $process = Start-Process @startParameters
        $exitCode = [int]$process.ExitCode
        $pendingAfter = Get-PendingRebootState
        $succeeded = $exitCode -in $successExitCodes
        $restartRequired = ($exitCode -in $restartExitCodes) -or ((-not $pendingBefore) -and $pendingAfter)

        if ($succeeded) {
            Write-InstallerMessage -Message "$displayName installed successfully." -Level Success
        }
        else {
            Write-InstallerMessage -Message "$displayName failed with installer exit code $exitCode." -Level Error
        }

        return [PSCustomObject]@{
            Name            = $displayName
            Method          = 'Official download'
            Succeeded       = $succeeded
            ExitCode        = $exitCode
            RestartRequired = $restartRequired
        }
    }
    catch {
        Write-InstallerMessage -Message "$displayName failed: $($_.Exception.Message)" -Level Error
        return [PSCustomObject]@{
            Name            = $displayName
            Method          = 'Official download'
            Succeeded       = $false
            ExitCode        = $null
            RestartRequired = $false
        }
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($temporaryRoot) -and (Test-Path -LiteralPath $temporaryRoot)) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-YesNo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $answer = (Read-Host "$Prompt $suffix").Trim()
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }

        if ($answer -match '^(?i:y|yes)$') {
            return $true
        }

        if ($answer -match '^(?i:n|no)$') {
            return $false
        }

        Write-InstallerMessage -Message 'Please answer Y or N.' -Level Warning
    }
}

function Request-SystemRestart {
    [CmdletBinding()]
    param()

    Write-InstallerMessage -Message 'Restarting Windows now...' -Level Warning
    $shutdownPath = Join-Path $env:SystemRoot 'System32\shutdown.exe'

    if (Test-IsAdministrator) {
        Start-Process -FilePath $shutdownPath -ArgumentList '/r /t 0' -ErrorAction Stop | Out-Null
    }
    else {
        Start-Process -FilePath $shutdownPath -ArgumentList '/r /t 0' -Verb RunAs -ErrorAction Stop | Out-Null
    }
}

function Show-InstallSummary {
    [CmdletBinding()]
    param(
        [object[]]$Results,
        [bool]$RestartDeferred
    )

    Write-Host ''
    Write-InstallerMessage -Message 'Installation summary' -Level Info

    if ($Results.Count -eq 0) {
        Write-Host '  No installations were attempted.'
    }
    else {
        foreach ($result in $Results) {
            $status = if ($result.Succeeded) {
                'Installed'
            }
            elseif ($result.RestartRequired) {
                'Pending'
            }
            else {
                'Failed'
            }
            Write-Host ('  {0,-10} {1} via {2} (exit code: {3})' -f $status, $result.Name, $result.Method, $result.ExitCode)
        }
    }

    if ($RestartDeferred) {
        Write-InstallerMessage -Message 'A restart is still pending. Save your work and restart Windows when convenient.' -Level Warning
    }

    if (-not [string]::IsNullOrWhiteSpace($script:InstallerLogPath)) {
        Write-Host "  Log: $script:InstallerLogPath" -ForegroundColor DarkGray
    }
}

function Start-AppInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CatalogPath
    )

    if (-not (Test-IsWindows11)) {
        throw 'This project supports Windows 11 only.'
    }

    try {
        $logPath = Initialize-InstallerLog
    }
    catch {
        $script:InstallerLogPath = $null
        $logPath = 'Unavailable'
        Write-Host "Warning: A session log could not be created: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    $catalogEntries = @(Get-CatalogEntries -CatalogPath $CatalogPath)
    $results = New-Object System.Collections.Generic.List[object]
    $restartDeferred = $false

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '              oneClickPrompt' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host 'WinGet is preferred. Reviewed official downloads are used only as a fallback.'
    Write-Host 'Type Q at the program prompt to finish.'
    Write-Host ''
    Write-InstallerMessage -Message "Session log: $logPath" -Level Info

    if ($null -eq (Get-Command 'winget.exe' -ErrorAction SilentlyContinue)) {
        Write-InstallerMessage -Message 'WinGet was not found. Only reviewed catalog fallbacks will be available.' -Level Warning
    }

    while ($true) {
        Write-Host ''
        $query = (Read-Host 'Program to install').Trim()
        if ([string]::IsNullOrWhiteSpace($query)) {
            Write-InstallerMessage -Message 'Enter a program name, or Q to finish.' -Level Warning
            continue
        }

        if ($query -match '^(?i:q|quit|exit)$') {
            break
        }

        Write-InstallerMessage -Message "Searching for '$query'..." -Level Info
        $selectedWinGetPackage = $null
        $tryCatalog = $true
        $searchResult = Invoke-WinGetSearch -Query $query

        if ($searchResult.Available -and $searchResult.Packages.Count -gt 0) {
            $selectedWinGetPackage = Select-WinGetPackage -Packages @($searchResult.Packages)
            if ($null -ne $selectedWinGetPackage -and $selectedWinGetPackage -ne 0) {
                $tryCatalog = $false
            }
            elseif ($null -eq $selectedWinGetPackage) {
                $tryCatalog = $false
            }
        }
        elseif ($searchResult.Available -and $searchResult.ExitCode -eq 0 -and $searchResult.RawOutput.Count -gt 0) {
            $selectedWinGetPackage = Read-ManualWinGetPackage -RawOutput @($searchResult.RawOutput)
            if ($null -ne $selectedWinGetPackage) {
                $tryCatalog = $false
            }
        }
        elseif ($searchResult.Available -and $searchResult.ExitCode -ne 0) {
            Write-InstallerMessage -Message "WinGet did not return an installable match (exit code $($searchResult.ExitCode))." -Level Warning
        }

        $installResult = $null
        if ($null -ne $selectedWinGetPackage -and $selectedWinGetPackage -ne 0) {
            $installResult = Invoke-WinGetInstall -PackageId $selectedWinGetPackage.Id -DisplayName $selectedWinGetPackage.Name
        }
        elseif ($tryCatalog) {
            $catalogMatches = @(Find-CatalogPackages -Query $query -CatalogEntries $catalogEntries)
            if ($catalogMatches.Count -eq 0) {
                Write-InstallerMessage -Message 'No safe match was found. Nothing was downloaded or executed.' -Level Warning
                Write-Host 'To support this app, add a reviewed entry to config\app-catalog.json.' -ForegroundColor DarkGray
            }
            else {
                $selectedCatalogPackage = Select-CatalogPackage -Packages $catalogMatches
                if ($null -ne $selectedCatalogPackage) {
                    $installResult = Invoke-CatalogInstall -Package $selectedCatalogPackage
                }
            }
        }

        if ($null -ne $installResult) {
            $results.Add($installResult)

            if ($installResult.RestartRequired) {
                if ($installResult.Succeeded) {
                    Write-InstallerMessage -Message "$($installResult.Name) requires a Windows restart." -Level Warning
                }
                else {
                    Write-InstallerMessage -Message "Restart Windows, then run this project again to install $($installResult.Name)." -Level Warning
                }

                if (Read-YesNo -Prompt 'Restart now?') {
                    Show-InstallSummary -Results $results.ToArray() -RestartDeferred $false
                    Request-SystemRestart
                    return
                }

                $restartDeferred = $true
            }
        }

        if (-not (Read-YesNo -Prompt 'Install another program?')) {
            break
        }
    }

    Show-InstallSummary -Results $results.ToArray() -RestartDeferred $restartDeferred
    Write-Host ''
    Read-Host 'Press Enter to close' | Out-Null
}

Export-ModuleMember -Function Start-AppInstaller
