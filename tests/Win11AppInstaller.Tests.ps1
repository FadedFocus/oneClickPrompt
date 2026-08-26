$modulePath = Join-Path $PSScriptRoot '..\src\Win11AppInstaller.psm1'
Import-Module $modulePath -Force

Describe 'Win11AppInstaller internals' {
    InModuleScope Win11AppInstaller {
        Describe 'ConvertFrom-WinGetSearchOutput' {
            It 'parses aligned WinGet rows into package objects' {
                $header = '{0,-30}{1,-35}{2,-12}{3,-18}{4}' -f 'Name', 'Id', 'Version', 'Match', 'Source'
                $separator = '-' * $header.Length
                $firstRow = '{0,-30}{1,-35}{2,-12}{3,-18}{4}' -f 'Visual Studio Code', 'Microsoft.VisualStudioCode', '1.99.0', 'Moniker: code', 'winget'
                $secondRow = '{0,-30}{1,-35}{2,-12}{3,-18}{4}' -f 'VSCodium', 'VSCodium.VSCodium', '1.99.1', 'Tag: vscode', 'winget'

                $result = @(ConvertFrom-WinGetSearchOutput -Lines @($header, $separator, $firstRow, $secondRow))

                $result.Count | Should -Be 2
                $result[0].Name | Should -Be 'Visual Studio Code'
                $result[0].Id | Should -Be 'Microsoft.VisualStudioCode'
                $result[1].Id | Should -Be 'VSCodium.VSCodium'
            }

            It 'returns no packages when a table is absent' {
                @(ConvertFrom-WinGetSearchOutput -Lines @('No package found matching input criteria.')).Count | Should -Be 0
            }
        }

        Describe 'Find-CatalogPackages' {
            BeforeAll {
                $script:catalog = @(
                    [PSCustomObject]@{ name = 'Mozilla Firefox'; aliases = @('firefox', 'mozilla'); architectures = @('x64', 'arm64', 'x86') },
                    [PSCustomObject]@{ name = 'Google Chrome'; aliases = @('chrome', 'google chrome'); architectures = @('x64', 'arm64', 'x86') }
                )
            }

            It 'prefers an exact normalized alias match' {
                $result = @(Find-CatalogPackages -Query 'Google-Chrome' -CatalogEntries $script:catalog)
                $result.Count | Should -Be 1
                $result[0].name | Should -Be 'Google Chrome'
            }

            It 'supports a partial catalog match' {
                $result = @(Find-CatalogPackages -Query 'Fire' -CatalogEntries $script:catalog)
                $result.Count | Should -Be 1
                $result[0].name | Should -Be 'Mozilla Firefox'
            }

            It 'returns no unrelated apps' {
                @(Find-CatalogPackages -Query 'Steam' -CatalogEntries $script:catalog).Count | Should -Be 0
            }
        }

        Describe 'Test-RestartSignal' {
            It 'recognizes MSI restart-required exit code 3010' {
                Test-RestartSignal -ExitCode 3010 -Output @() -PendingBefore $false -PendingAfter $false | Should -BeTrue
            }

            It 'recognizes WinGet restart-required HRESULT 0x8A150109' {
                Test-RestartSignal -ExitCode -1978334967 -Output @() -PendingBefore $false -PendingAfter $false | Should -BeTrue
            }

            It 'recognizes a newly created pending-reboot state' {
                Test-RestartSignal -ExitCode 0 -Output @() -PendingBefore $false -PendingAfter $true | Should -BeTrue
            }

            It 'does not mistake an explicit no-restart message for a requirement' {
                Test-RestartSignal -ExitCode 0 -Output @('A restart is not required.') -PendingBefore $false -PendingAfter $false | Should -BeFalse
            }
        }

        Describe 'Assert-CatalogPackage' {
            It 'rejects a non-HTTPS download' {
                $package = [PSCustomObject]@{
                    name = 'Unsafe App'
                    downloadUrl = 'http://example.test/setup.exe'
                    fileName = 'setup.exe'
                    installerType = 'exe'
                    architectures = @('x64', 'arm64', 'x86')
                    publisherPattern = 'Example'
                    silentArguments = @('/S')
                }

                { Assert-CatalogPackage -Package $package } | Should -Throw '*HTTPS*'
            }

            It 'rejects a file name containing a path' {
                $package = [PSCustomObject]@{
                    name = 'Unsafe App'
                    downloadUrl = 'https://example.test/setup.exe'
                    fileName = '..\setup.exe'
                    installerType = 'exe'
                    architectures = @('x64', 'arm64', 'x86')
                    publisherPattern = 'Example'
                    silentArguments = @('/S')
                }

                { Assert-CatalogPackage -Package $package } | Should -Throw '*unsafe file name*'
            }
        }
    }
}
