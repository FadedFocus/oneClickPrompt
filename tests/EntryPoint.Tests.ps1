Describe 'Install-App entry point' {
    BeforeAll {
        $entryPointPath = Join-Path $PSScriptRoot '..\Install-App.ps1'
    }

    It 'binds its default parameters in Windows PowerShell and PowerShell 7' {
        $engines = @(
            (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'),
            (Get-Command 'pwsh.exe' -ErrorAction Stop).Source
        )

        foreach ($engine in $engines) {
            & $engine -NoLogo -NoProfile -ExecutionPolicy Bypass -File $entryPointPath '-?' *> $null
            $LASTEXITCODE | Should -Be 0
        }
    }
}
