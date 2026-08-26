$modulePath = Join-Path $PSScriptRoot '..\src\OneClickPromptPrerequisites.psm1'
Import-Module $modulePath -Force

Describe 'oneClickPrompt prerequisite bootstrap' {
    InModuleScope OneClickPromptPrerequisites {
        BeforeEach {
            Mock Write-Host
        }

        It 'does not change the computer when WinGet is already available' {
            Mock Get-WinGetExecutable { 'C:\WindowsApps\winget.exe' }
            Mock Register-WinGetForCurrentUser
            Mock Install-WinGetForCurrentUser
            Mock Read-PrerequisiteInstallConsent

            Initialize-OneClickPromptPrerequisites | Should -BeTrue

            Should -Not -Invoke Register-WinGetForCurrentUser
            Should -Not -Invoke Install-WinGetForCurrentUser
            Should -Not -Invoke Read-PrerequisiteInstallConsent
        }

        It 'registers an existing App Installer before downloading a repair module' {
            $script:discoveryCount = 0
            Mock Get-WinGetExecutable {
                $script:discoveryCount++
                if ($script:discoveryCount -gt 1) {
                    return 'C:\WindowsApps\winget.exe'
                }

                return $null
            }
            Mock Register-WinGetForCurrentUser { $true }
            Mock Install-WinGetForCurrentUser
            Mock Read-PrerequisiteInstallConsent { $true }

            Initialize-OneClickPromptPrerequisites | Should -BeTrue

            Should -Invoke Register-WinGetForCurrentUser -Times 1 -Exactly
            Should -Not -Invoke Install-WinGetForCurrentUser
            Should -Invoke Read-PrerequisiteInstallConsent -Times 1 -Exactly
        }

        It 'honors the skip option when WinGet is unavailable' {
            Mock Get-WinGetExecutable { $null }
            Mock Register-WinGetForCurrentUser { $false }
            Mock Install-WinGetForCurrentUser
            Mock Read-PrerequisiteInstallConsent

            Initialize-OneClickPromptPrerequisites -SkipWinGetBootstrap | Should -BeFalse

            Should -Not -Invoke Register-WinGetForCurrentUser
            Should -Not -Invoke Install-WinGetForCurrentUser
            Should -Not -Invoke Read-PrerequisiteInstallConsent
        }

        It 'repairs WinGet after the user consents' {
            $script:discoveryCount = 0
            Mock Get-WinGetExecutable {
                $script:discoveryCount++
                if ($script:discoveryCount -gt 1) {
                    return 'C:\WindowsApps\winget.exe'
                }

                return $null
            }
            Mock Register-WinGetForCurrentUser { $false }
            Mock Read-PrerequisiteInstallConsent { $true }
            Mock Install-WinGetForCurrentUser

            Initialize-OneClickPromptPrerequisites | Should -BeTrue

            Should -Invoke Install-WinGetForCurrentUser -Times 1 -Exactly
        }

        It 'continues safely when the user declines WinGet setup' {
            Mock Get-WinGetExecutable { $null }
            Mock Register-WinGetForCurrentUser { $false }
            Mock Read-PrerequisiteInstallConsent { $false }
            Mock Install-WinGetForCurrentUser

            Initialize-OneClickPromptPrerequisites | Should -BeFalse

            Should -Not -Invoke Install-WinGetForCurrentUser
        }
    }
}
