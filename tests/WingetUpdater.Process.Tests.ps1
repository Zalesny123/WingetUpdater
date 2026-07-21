#requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester setup variables are consumed by It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Fixture helpers only modify the Pester TestDrive.')]
param()

BeforeDiscovery {
    $script:IsWindowsProcessTest = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:WindowsSystemDirectory = if ($script:IsWindowsProcessTest -and -not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        Join-Path $env:SystemRoot 'System32'
    }
    else {
        $null
    }
    $script:WindowsPowerShellPath = if ($script:WindowsSystemDirectory) {
        Join-Path $script:WindowsSystemDirectory 'WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        $null
    }
    $script:CmdPath = if ($script:IsWindowsProcessTest -and -not [string]::IsNullOrWhiteSpace($env:ComSpec)) {
        $env:ComSpec
    }
    else {
        $null
    }
    $script:PwshPath = if ($script:IsWindowsProcessTest) {
        $pwshCommand = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $pwshCommand) {
            $pwshCommand.Source
        }
    }
    $script:WindowsIntegrationAvailable = (
        $script:IsWindowsProcessTest -and
        -not [string]::IsNullOrWhiteSpace($script:CmdPath) -and
        (Test-Path -LiteralPath $script:CmdPath -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $script:WindowsSystemDirectory 'where.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $script:WindowsSystemDirectory 'choice.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath $script:WindowsPowerShellPath -PathType Leaf)
    )
    $script:FakeWingetPath = Join-Path $PSScriptRoot 'fixtures\fake-winget.cmd'
    $script:FakeWingetAvailable = $script:IsWindowsProcessTest -and (Test-Path -LiteralPath $script:FakeWingetPath -PathType Leaf)
    $script:EarlyEofFixturePath = Join-Path $PSScriptRoot 'fixtures\fake-winget-streams.cs'
    $script:EarlyEofFixtureAvailable = $script:IsWindowsProcessTest -and (Test-Path -LiteralPath $script:EarlyEofFixturePath -PathType Leaf)
    $script:RealWingetAliasPath = if ($script:IsWindowsProcessTest -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    }
    $script:RealWingetAliasAvailable = $script:IsWindowsProcessTest -and (Test-Path -LiteralPath $script:RealWingetAliasPath -PathType Leaf)
}

BeforeAll {
    $script:IsWindowsProcessTest = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $script:WindowsSystemDirectory = if ($script:IsWindowsProcessTest -and -not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        Join-Path $env:SystemRoot 'System32'
    }
    else {
        $null
    }
    $script:WindowsPowerShellPath = if ($script:WindowsSystemDirectory) {
        Join-Path $script:WindowsSystemDirectory 'WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        $null
    }
    $script:CmdPath = if ($script:IsWindowsProcessTest -and -not [string]::IsNullOrWhiteSpace($env:ComSpec)) {
        $env:ComSpec
    }
    else {
        $null
    }
    $script:PwshPath = if ($script:IsWindowsProcessTest) {
        $pwshCommand = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $pwshCommand) {
            $pwshCommand.Source
        }
    }

    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $modulePath = Join-Path $repositoryRoot 'WingetUpdater.Core.psm1'
    Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop
    $launcherPath = Join-Path $repositoryRoot 'Start.bat'
    $scriptPath = Join-Path $repositoryRoot 'WingetUpdater.ps1'
    $fakeWingetPath = Join-Path $PSScriptRoot 'fixtures\fake-winget.cmd'
    $earlyEofFixturePath = Join-Path $PSScriptRoot 'fixtures\fake-winget-streams.cs'
    $script:RealWingetAliasPath = if ($script:IsWindowsProcessTest -and -not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    }
    $processTestPath = Join-Path $PSScriptRoot 'WingetUpdater.Process.Tests.ps1'
    $launcherSource = [System.IO.File]::ReadAllText($launcherPath)
    $scriptSource = [System.IO.File]::ReadAllText($scriptPath)
    $launcherLines = @($launcherSource -split "`r?`n")
    $scriptTokens = $null
    $scriptParseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$scriptTokens,
        [ref]$scriptParseErrors
    )
    $processTestTokens = $null
    $processTestParseErrors = $null
    $processTestAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $processTestPath,
        [ref]$processTestTokens,
        [ref]$processTestParseErrors
    )

    function New-LauncherFixture {
        param([string]$DirectoryName)

        $launcherDirectory = Join-Path $TestDrive $DirectoryName
        [void](New-Item -ItemType Directory -Path $launcherDirectory -Force)
        Copy-Item -LiteralPath $launcherPath -Destination (Join-Path $launcherDirectory 'Start.bat')
        Copy-Item -LiteralPath (Join-Path $repositoryRoot 'LICENSE') -Destination (Join-Path $launcherDirectory 'LICENSE')

        $stubSource = @'
param([switch]$LaunchedFromStartBat)

$record = [ordered]@{
    HostPath = (Get-Process -Id $PID).Path
    ScriptPath = $MyInvocation.MyCommand.Path
    LaunchedFromStartBat = [bool]$LaunchedFromStartBat
    RemainingArguments = @($args)
}
$json = $record | ConvertTo-Json -Compress
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($env:WINGET_UPDATER_TEST_RECORD, $json, $utf8)
exit [int]$env:WINGET_UPDATER_TEST_EXIT_CODE
'@
        $stubPath = Join-Path $launcherDirectory 'WingetUpdater.ps1'
        [System.IO.File]::WriteAllText($stubPath, ($stubSource -replace "`r?`n", "`r`n"), [System.Text.Encoding]::ASCII)
        return $launcherDirectory
    }

    function Invoke-LauncherFixture {
        param(
            [string]$LauncherDirectory,
            [string]$LocalAppData,
            [string[]]$PathEntries,
            [AllowNull()]
            [string]$InputText,
            [int]$SentinelExitCode
        )

        [void](New-Item -ItemType Directory -Path $LocalAppData -Force)
        $recordPath = Join-Path (Split-Path -Parent $LocalAppData) ('launcher-record-' + [guid]::NewGuid().ToString('N') + '.json')
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $script:CmdPath
        if ($null -ne $InputText) {
            $inputPath = Join-Path $LauncherDirectory 'launcher-input.txt'
            [System.IO.File]::WriteAllText($inputPath, $InputText + "`r`n", [System.Text.Encoding]::ASCII)
            $startInfo.Arguments = '/d /c call Start.bat < launcher-input.txt'
        }
        else {
            $startInfo.Arguments = '/d /c call Start.bat < nul'
        }
        $startInfo.WorkingDirectory = $LauncherDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables['LOCALAPPDATA'] = $LocalAppData
        $startInfo.EnvironmentVariables['PATH'] = ($PathEntries -join ';')
        $startInfo.EnvironmentVariables['WINGET_UPDATER_TEST_RECORD'] = $recordPath
        $startInfo.EnvironmentVariables['WINGET_UPDATER_TEST_EXIT_CODE'] = [string]$SentinelExitCode

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()

        if (-not $process.WaitForExit(30000)) {
            try {
                $process.Kill()
            }
            catch {
                Write-Verbose "Launcher test process cleanup failed: $($_.Exception.Message)"
            }
            throw "Start.bat did not exit within 30 seconds in $LauncherDirectory."
        }

        $result = [pscustomobject]@{
            ExitCode = $process.ExitCode
            StandardOutput = $process.StandardOutput.ReadToEnd()
            StandardError = $process.StandardError.ReadToEnd()
            RecordPath = $recordPath
        }
        $process.Dispose()
        return $result
    }

    function Get-ScriptFunctionText {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Name', Justification = 'The parameter is captured by the AST predicate script block.')]
        param([string]$Name)

        $functionAst = @($scriptAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
        }, $true))
        if ($functionAst.Count -ne 1) {
            return ''
        }
        return $functionAst[0].Extent.Text
    }
}

Describe 'Start.bat startup contract' {
    It 'uses an informational MIT notice with only Continue and Exit choices' {
        $launcherSource | Should -Match '(?im)MIT LICENSE NOTICE'
        $launcherSource | Should -Match '(?im)^\s*choice\s+/C\s+CE\s+/N\s+/M\s+"[^"]*Continue[^"]*Exit[^"]*"\s*$'
        $launcherSource.Replace('.license-accepted', '') | Should -Not -Match '(?i)accept|akcept|umowa'
    }

    It 'stores the notice marker in LocalAppData' {
        $launcherSource | Should -Match '(?im)^\s*set "NOTICE_MARKER=%LOCALAPPDATA%\\WingetUpdater\\\.license-notice-shown"\s*$'
        $launcherSource | Should -Match '(?im)^\s*set "NOTICE_DIRECTORY=%LOCALAPPDATA%\\WingetUpdater"\s*$'
    }

    It 'recognizes the legacy application marker only as a shown notice' {
        $launcherSource | Should -Match '(?im)^\s*set "LEGACY_NOTICE_MARKER=%~dp0\.license-accepted"\s*$'
        $launcherSource | Should -Match '(?ims)if exist "%LEGACY_NOTICE_MARKER%"\s*\(\s*call :WriteNoticeMarker\s*if errorlevel 1 exit /b 1\s*goto NoticeComplete\s*\)'
        $launcherSource | Should -Not -Match '(?im)^\s*(del|erase)\s+.*LEGACY_NOTICE_MARKER'
    }

    It 'resolves only an absolute trusted runtime and rejects a current-directory pwsh' {
        $launcherSource | Should -Match '(?im)^\s*for %%D in \("\.\\pwsh\.exe"\) do set "CURRENT_DIRECTORY_PWSH=%%~fsD"\s*$'
        $launcherSource | Should -Match '(?im)^\s*for /f "usebackq delims=" %%P in \(`\^""%SystemRoot%\\System32\\where\.exe" "\$PATH:pwsh\.exe" 2\^>nul\^"`\) do if not defined POWERSHELL_EXE if /I not "%%~fsP"=="%CURRENT_DIRECTORY_PWSH%" set "POWERSHELL_EXE=%%~fP"\s*$'
        $launcherSource | Should -Match '(?im)^\s*if not defined POWERSHELL_EXE if exist "%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe" set "POWERSHELL_EXE=%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe"\s*$'
        $launcherSource | Should -Not -Match '(?im)^\s*where(?:\.exe)?\s'
        $launcherSource | Should -Not -Match '(?im)set "POWERSHELL_EXE=(?:pwsh|powershell)\.exe"'
        $launcherSource | Should -Not -Match '(?i)Wybierz sposob|SELECTED|AddChoice|CMD_RUNTIME|ComSpec'
    }

    It 'prints an ASCII MIT summary and refers to LICENSE without decoding it through cmd' {
        $launcherSource | Should -Match '(?im)^\s*echo This program is distributed under the MIT License\.\s*$'
        $launcherSource | Should -Match '(?im)^\s*echo The complete license text is available at:\s*$'
        $launcherSource | Should -Match '(?im)^\s*echo "%LICENSE_FILE%"\s*$'
        $launcherSource | Should -Not -Match '(?im)^\s*type\s+"%LICENSE_FILE%"\s*$'
        $launcherSource | Should -Not -Match '(?im)^\s*chcp\s'
    }

    It 'launches the script directly with the required process arguments' {
        $launcherSource | Should -Match '(?im)^\s*"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -STA -File "%APP%" -LaunchedFromStartBat\s*$'
        $launcherSource | Should -Not -Match '(?i)-Command|Start-Process|Set-ExecutionPolicy'
    }

    It 'keeps every application-directory expansion quoted and safe for special characters' {
        $appDirectoryLines = @($launcherLines | Where-Object { $_ -like '*%~dp0*' })
        $appDirectoryLines.Count | Should -BeGreaterOrEqual 2
        foreach ($line in $appDirectoryLines) {
            $line | Should -Match '^\s*set "[A-Z_]+=%~dp0[^"]*"\s*$'
        }

        $launchLine = @($launcherLines | Where-Object { $_ -match '-File "%APP%"' })
        $launchLine.Count | Should -Be 1
        $specialScriptPath = "C:\Program Files\100% Ready! O'Brien & Sons\WingetUpdater.ps1"
        $expandedLaunchLine = $launchLine[0].Replace('"%APP%"', '"' + $specialScriptPath + '"')
        $expectedArgumentSegment = '-File "' + $specialScriptPath + '" -LaunchedFromStartBat'
        $expandedLaunchLine | Should -Match ([regex]::Escape($expectedArgumentSegment))
    }
}

Describe 'Pester lifecycle contract' {
    It 'computes Windows skip capabilities in BeforeDiscovery' {
        @($processTestParseErrors).Count | Should -Be 0
        $beforeDiscoveryCommands = @($processTestAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'BeforeDiscovery'
        }, $true))

        $beforeDiscoveryCommands.Count | Should -Be 1
        $beforeDiscoveryCommands[0].Extent.Text | Should -Match '\$script:WindowsIntegrationAvailable\s*='
        $beforeDiscoveryCommands[0].Extent.Text | Should -Match '\$script:PwshPath\s*='
    }

    It 'initializes every helper-consumed Windows path in BeforeAll run scope' {
        $beforeAllCommands = @($processTestAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'BeforeAll'
        }, $true))

        $beforeAllCommands.Count | Should -Be 1
        foreach ($variableName in @('WindowsSystemDirectory', 'WindowsPowerShellPath', 'CmdPath', 'PwshPath')) {
            $beforeAllCommands[0].Extent.Text | Should -Match ("\`$script:$variableName\s*=")
        }
    }
}

Describe 'Start.bat Windows integration' {
    It 'prefers PATH pwsh, rejects a current-directory decoy, preserves special paths, creates the marker, and propagates exit' -Skip:(-not $script:WindowsIntegrationAvailable -or [string]::IsNullOrWhiteSpace($script:PwshPath)) {
        $launcherDirectory = New-LauncherFixture -DirectoryName "Launcher 100% Ready! O'Brien & Sons"
        $localAppData = Join-Path $TestDrive "Local AppData 100% Ready! O'Brien & Sons"
        [System.IO.File]::WriteAllText((Join-Path $launcherDirectory 'pwsh.exe'), 'current-directory decoy', [System.Text.Encoding]::ASCII)
        $pwshDirectory = Split-Path -Parent $script:PwshPath

        $result = Invoke-LauncherFixture `
            -LauncherDirectory $launcherDirectory `
            -LocalAppData $localAppData `
            -PathEntries @($launcherDirectory, $pwshDirectory, $script:WindowsSystemDirectory) `
            -InputText 'C' `
            -SentinelExitCode 37

        $result.ExitCode | Should -Be 37
        $result.StandardOutput | Should -Match ([regex]::Escape((Join-Path $launcherDirectory 'LICENSE')))
        Test-Path -LiteralPath (Join-Path $localAppData 'WingetUpdater\.license-notice-shown') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.RecordPath -PathType Leaf | Should -BeTrue
        $record = Get-Content -LiteralPath $result.RecordPath -Raw | ConvertFrom-Json
        [System.IO.Path]::GetFullPath($record.HostPath) | Should -Be ([System.IO.Path]::GetFullPath($script:PwshPath))
        [System.IO.Path]::GetFullPath($record.ScriptPath) | Should -Be ([System.IO.Path]::GetFullPath((Join-Path $launcherDirectory 'WingetUpdater.ps1')))
        $record.LaunchedFromStartBat | Should -BeTrue
        @($record.RemainingArguments).Count | Should -Be 0
    }

    It 'exits without a marker or child process when Exit is redirected to the notice prompt' -Skip:(-not $script:WindowsIntegrationAvailable) {
        $launcherDirectory = New-LauncherFixture -DirectoryName 'Launcher Exit Case'
        $localAppData = Join-Path $TestDrive 'Exit LocalAppData'

        $result = Invoke-LauncherFixture `
            -LauncherDirectory $launcherDirectory `
            -LocalAppData $localAppData `
            -PathEntries @($script:WindowsSystemDirectory) `
            -InputText 'E' `
            -SentinelExitCode 38

        $result.ExitCode | Should -Be 1
        Test-Path -LiteralPath (Join-Path $localAppData 'WingetUpdater\.license-notice-shown') | Should -BeFalse
        Test-Path -LiteralPath $result.RecordPath | Should -BeFalse
    }

    It 'maps the old application marker only to the LocalAppData notice marker and uses the known fallback' -Skip:(-not $script:WindowsIntegrationAvailable) {
        $launcherDirectory = New-LauncherFixture -DirectoryName 'Launcher Legacy Marker'
        $localAppData = Join-Path $TestDrive 'Legacy LocalAppData'
        $legacyMarker = Join-Path $launcherDirectory '.license-accepted'
        [void](New-Item -ItemType File -Path $legacyMarker)

        $result = Invoke-LauncherFixture `
            -LauncherDirectory $launcherDirectory `
            -LocalAppData $localAppData `
            -PathEntries @($script:WindowsSystemDirectory) `
            -InputText $null `
            -SentinelExitCode 39

        $result.ExitCode | Should -Be 39
        Test-Path -LiteralPath (Join-Path $localAppData 'WingetUpdater\.license-notice-shown') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $legacyMarker -PathType Leaf | Should -BeTrue
        $record = Get-Content -LiteralPath $result.RecordPath -Raw | ConvertFrom-Json
        [System.IO.Path]::GetFullPath($record.HostPath) | Should -Be ([System.IO.Path]::GetFullPath($script:WindowsPowerShellPath))
        $record.LaunchedFromStartBat | Should -BeTrue
        @($record.RemainingArguments).Count | Should -Be 0
    }
}

Describe 'WingetUpdater.ps1 launcher-origin guard' {
    It 'uses a plain switch instead of a secret or magic value' {
        @($scriptParseErrors).Count | Should -Be 0
        $launcherParameter = @($scriptAst.ParamBlock.Parameters | Where-Object {
            $_.Name.VariablePath.UserPath -eq 'LaunchedFromStartBat'
        })

        $launcherParameter.Count | Should -Be 1
        $launcherParameter[0].StaticType.FullName | Should -BeExactly 'System.Management.Automation.SwitchParameter'
        ($launcherSource + $scriptSource) | Should -Not -Match '(?i)LauncherSecret|StartBat123'
    }

    It 'retains a friendly guard that directs normal users to Start.bat' {
        $scriptSource | Should -Match '(?is)if\s*\(\s*-not\s+\$LaunchedFromStartBat\s*\).*?Start\.bat.*?exit 1'
        $scriptSource | Should -Not -Match '(?i)launcher.{0,20}(secret|password|token|authenticat|authoriz)'
    }
}

Describe 'Winget process pipeline Windows integration' {
    It 'resolves the real Windows winget AppExecutionAlias as a reparse-point Application' -Skip:(-not $script:RealWingetAliasAvailable) {
        $commands = @(Get-Command winget -CommandType Application -All -ErrorAction SilentlyContinue)
        $attributes = [System.IO.File]::GetAttributes($script:RealWingetAliasPath)

        ($attributes -band [System.IO.FileAttributes]::ReparsePoint) | Should -Be ([System.IO.FileAttributes]::ReparsePoint)
        Resolve-WingetApplicationPath -Commands $commands -LocalAppDataPath $env:LOCALAPPDATA |
            Should -BeExactly ([System.IO.Path]::GetFullPath($script:RealWingetAliasPath))
    }

    It 'uses the absolute fake executable, preserves both streams, metadata, arguments, timestamps, and a complete UTF-8 log' -Skip:(-not $script:FakeWingetAvailable) {
        $logsDirectory = Join-Path $TestDrive 'logs'
        $package = [pscustomobject]@{
            Id = 'Contoso.App'
            Name = 'Contoso Package'
            CurrentVersion = '1.0'
            AvailableVersion = '2.0'
            Source = 'private source'
        }
        $applicationPath = [System.IO.Path]::GetFullPath($script:CmdPath)
        $arguments = @('/d', '/c', 'call', [System.IO.Path]::GetFullPath($fakeWingetPath), 'streams', 'two words', 'plain-value')

        $result = Invoke-WingetProcess `
            -ApplicationPath $applicationPath `
            -Arguments $arguments `
            -LogsDirectory $logsDirectory `
            -Package $package

        $result.ApplicationPath | Should -BeExactly $applicationPath
        @($result.Arguments) | Should -BeExactly $arguments
        $result.DisplayCommand | Should -BeExactly ((Join-CommandLineArguments -Arguments @($applicationPath)) + ' ' + (Join-CommandLineArguments -Arguments $arguments))
        $result.PackageId | Should -BeExactly 'Contoso.App'
        $result.PackageName | Should -BeExactly 'Contoso Package'
        $result.CurrentVersion | Should -BeExactly '1.0'
        $result.AvailableVersion | Should -BeExactly '2.0'
        $result.Source | Should -BeExactly 'private source'
        $result.StartedAtUtc.Kind | Should -Be ([DateTimeKind]::Utc)
        $result.EndedAtUtc.Kind | Should -Be ([DateTimeKind]::Utc)
        $result.EndedAtUtc | Should -BeGreaterOrEqual $result.StartedAtUtc
        $result.Started | Should -BeTrue
        $result.InfrastructureError | Should -BeNullOrEmpty
        $result.CleanupGuaranteed | Should -BeTrue
        $result.ExitCode | Should -Be 23
        $result.Cancelled | Should -BeFalse
        $result.StandardOutput | Should -Match 'stdout-one'
        $result.StandardOutput | Should -Match 'ARG1=two words'
        $result.StandardOutput | Should -Match 'ARG2=plain-value'
        $result.StandardError | Should -Match 'stderr-one'
        $result.StandardError | Should -Match 'stderr-two'
        $result.CombinedOutput | Should -Match 'stdout-one'
        $result.CombinedOutput | Should -Match 'stderr-one'
        Test-Path -LiteralPath $result.LogPath -PathType Leaf | Should -BeTrue

        $logBytes = [System.IO.File]::ReadAllBytes($result.LogPath)
        if ($logBytes.Length -ge 3) {
            @($logBytes[0..2]) | Should -Not -Be @(0xEF, 0xBB, 0xBF)
        }
        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $logText = $strictUtf8.GetString($logBytes)
        $logText | Should -Match ([regex]::Escape($result.DisplayCommand))
        $logText | Should -Match 'stdout-one'
        $logText | Should -Match 'stderr-one'
        $logText | Should -Match ([regex]::Escape($result.LogPath))
    }

    It 'does not truncate large stdout in the result or per-command log' -Skip:(-not $script:FakeWingetAvailable) {
        $logsDirectory = Join-Path $TestDrive 'large-logs'
        $arguments = @('/d', '/c', 'call', [System.IO.Path]::GetFullPath($fakeWingetPath), 'large')

        $result = Invoke-WingetProcess `
            -ApplicationPath ([System.IO.Path]::GetFullPath($script:CmdPath)) `
            -Arguments $arguments `
            -LogsDirectory $logsDirectory

        $result.ExitCode | Should -Be 0
        $result.StandardOutput | Should -Match 'LINE-5000-END'
        $result.StandardOutput.Length | Should -BeGreaterThan 50000
        [System.IO.File]::ReadAllText($result.LogPath) | Should -Match 'LINE-5000-END'
    }

    It 'does not start the child when command-log preflight fails' -Skip:(-not $script:FakeWingetAvailable) {
        $logsDirectory = Join-Path $TestDrive 'denied-logs'
        $sideEffectPath = Join-Path $TestDrive 'child-started.txt'
        [void](New-Item -ItemType Directory -Path $logsDirectory)
        $acl = Get-Acl -LiteralPath $logsDirectory
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $identity,
            [System.Security.AccessControl.FileSystemRights]::CreateFiles,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None,
            [System.Security.AccessControl.AccessControlType]::Deny
        )
        [void]$acl.AddAccessRule($denyRule)
        Set-Acl -LiteralPath $logsDirectory -AclObject $acl
        $arguments = @('/d', '/c', 'call', [System.IO.Path]::GetFullPath($fakeWingetPath), 'side-effect', $sideEffectPath)

        try {
            { Invoke-WingetProcess `
                -ApplicationPath ([System.IO.Path]::GetFullPath($script:CmdPath)) `
                -Arguments $arguments `
                -LogsDirectory $logsDirectory } | Should -Throw

            Test-Path -LiteralPath $sideEffectPath | Should -BeFalse
        }
        finally {
            $acl = Get-Acl -LiteralPath $logsDirectory
            [void]$acl.RemoveAccessRuleSpecific($denyRule)
            Set-Acl -LiteralPath $logsDirectory -AclObject $acl
        }
    }

    It 'pulses repeatedly while a quiet child is still running' -Skip:(-not $script:FakeWingetAvailable) {
        $logsDirectory = Join-Path $TestDrive 'quiet-logs'
        $pulseState = [pscustomobject]@{
            Count = 0
            FirstUtc = $null
        }
        $onPulse = {
            $pulseState.Count++
            if ($null -eq $pulseState.FirstUtc) {
                $pulseState.FirstUtc = [datetime]::UtcNow
            }
        }.GetNewClosure()
        $arguments = @('/d', '/c', 'call', [System.IO.Path]::GetFullPath($fakeWingetPath), 'quiet')

        $result = Invoke-WingetProcess `
            -ApplicationPath ([System.IO.Path]::GetFullPath($script:CmdPath)) `
            -Arguments $arguments `
            -LogsDirectory $logsDirectory `
            -OnPulse $onPulse

        $result.ExitCode | Should -Be 0
        $pulseState.Count | Should -BeGreaterThan 2
        $pulseState.FirstUtc | Should -BeLessThan $result.EndedAtUtc
    }

    It 'cancels a running process tree without reporting an ordinary nonzero failure' -Skip:(-not $script:FakeWingetAvailable) {
        $logsDirectory = Join-Path $TestDrive 'cancelled-logs'
        $cancellationState = New-WingetUpdaterCancellationState
        $pulseState = [pscustomobject]@{ Count = 0 }
        $onPulse = {
            $pulseState.Count++
            if ($pulseState.Count -eq 2) {
                Request-WingetUpdaterCancellation -State $cancellationState
            }
        }.GetNewClosure()
        $arguments = @('/d', '/c', 'call', [System.IO.Path]::GetFullPath($fakeWingetPath), 'quiet')
        $startedAt = [datetime]::UtcNow

        $result = Invoke-WingetProcess `
            -ApplicationPath ([System.IO.Path]::GetFullPath($script:CmdPath)) `
            -Arguments $arguments `
            -LogsDirectory $logsDirectory `
            -CancellationState $cancellationState `
            -OnPulse $onPulse

        ([datetime]::UtcNow - $startedAt).TotalMilliseconds | Should -BeLessThan 1500
        $result.Started | Should -BeTrue
        $result.Cancelled | Should -BeTrue
        $result.ExitCode | Should -BeNullOrEmpty
        $result.CleanupGuaranteed | Should -BeTrue
        $result.InfrastructureError | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText($result.LogPath) | Should -Match 'Cancelled: true'
    }

    It 'keeps pulsing after both redirected streams close until the process exits' -Skip:(-not $script:EarlyEofFixtureAvailable) {
        $logsDirectory = Join-Path $TestDrive 'early-eof-logs'
        $streamsClosedMarker = Join-Path $TestDrive 'streams-closed.marker'
        $earlyEofExecutable = Join-Path $TestDrive 'fake-winget-streams.exe'
        $cscPath = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        & $cscPath /nologo /target:exe "/out:$earlyEofExecutable" $earlyEofFixturePath
        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath $earlyEofExecutable -PathType Leaf | Should -BeTrue
        $pulseState = [pscustomobject]@{ Count = 0 }
        $onPulse = {
            if (Test-Path -LiteralPath $streamsClosedMarker -PathType Leaf) {
                $pulseState.Count++
            }
        }.GetNewClosure()
        $arguments = @('early-eof', $streamsClosedMarker)
        $startedAt = [datetime]::UtcNow

        $result = Invoke-WingetProcess `
            -ApplicationPath ([System.IO.Path]::GetFullPath($earlyEofExecutable)) `
            -Arguments $arguments `
            -LogsDirectory $logsDirectory `
            -OnPulse $onPulse

        ([datetime]::UtcNow - $startedAt).TotalMilliseconds | Should -BeGreaterThan 1000
        $result.ExitCode | Should -Be 0
        $pulseState.Count | Should -BeGreaterThan 10
    }

    It 'executes read-fault cleanup and reports a guaranteed direct-child stop' -Skip:(-not $script:FakeWingetAvailable) {
        $parameters = @{
            ApplicationPath = [System.IO.Path]::GetFullPath($script:CmdPath)
            Arguments = @('/d', '/c', 'call', [System.IO.Path]::GetFullPath($fakeWingetPath), 'output-then-quiet')
            LogsDirectory = Join-Path $TestDrive 'read-fault-logs'
        }

        InModuleScope WingetUpdater.Core -Parameters $parameters {
            param($ApplicationPath, $Arguments, $LogsDirectory)

            $seam = Get-Command Get-WingetReadTaskResult -ErrorAction SilentlyContinue
            $seam | Should -Not -BeNullOrEmpty
            Mock Get-WingetReadTaskResult { throw 'injected async read failure' }

            $result = Invoke-WingetProcess `
                -ApplicationPath $ApplicationPath `
                -Arguments $Arguments `
                -LogsDirectory $LogsDirectory

            $result.Started | Should -BeTrue
            $result.ExitCode | Should -BeNullOrEmpty
            $result.InfrastructureError | Should -Match 'injected async read failure'
            $result.CleanupGuaranteed | Should -BeTrue
        }
    }

    It 'drains high-volume stdout and stderr concurrently without truncation' -Skip:(-not $script:FakeWingetAvailable) {
        $logsDirectory = Join-Path $TestDrive 'duplex-logs'
        $arguments = @('/d', '/c', 'call', [System.IO.Path]::GetFullPath($fakeWingetPath), 'duplex')

        $result = Invoke-WingetProcess `
            -ApplicationPath ([System.IO.Path]::GetFullPath($script:CmdPath)) `
            -Arguments $arguments `
            -LogsDirectory $logsDirectory

        $result.ExitCode | Should -Be 0
        $result.StandardOutput | Should -Match 'OUT-3000-END'
        $result.StandardError | Should -Match 'ERR-3000-END'
        $logText = [System.IO.File]::ReadAllText($result.LogPath)
        $logText | Should -Match 'OUT-3000-END'
        $logText | Should -Match 'ERR-3000-END'
    }

    It 'returns a not-started infrastructure result without a fabricated exit code' -Skip:(-not $script:FakeWingetAvailable) {
        $logsDirectory = Join-Path $TestDrive 'start-failure-logs'
        $invalidApplication = Join-Path $TestDrive 'not-an-application.txt'
        [System.IO.File]::WriteAllText($invalidApplication, 'not executable')

        $result = Invoke-WingetProcess `
            -ApplicationPath ([System.IO.Path]::GetFullPath($invalidApplication)) `
            -Arguments @() `
            -LogsDirectory $logsDirectory

        $result.Started | Should -BeFalse
        $result.ExitCode | Should -BeNullOrEmpty
        $result.InfrastructureError | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $result.LogPath -PathType Leaf | Should -BeTrue
        [System.IO.File]::ReadAllText($result.LogPath) | Should -Match 'Started: false'
    }
}

Describe 'WingetUpdater step 4 process and UI contract' {
    It 'discovers all candidates and resolves only the canonical Windows AppExecutionAlias for initialization probes' {
        $initializeText = Get-ScriptFunctionText -Name 'Initialize-WingetInfo'

        $initializeText | Should -Match 'Get-Command\s+winget\s+-CommandType\s+Application\s+-All'
        ([regex]::Matches($initializeText, 'Get-Command\s+winget')).Count | Should -Be 1
        $initializeText | Should -Match 'Resolve-WingetApplicationPath\s+-Commands\s+\$commands\s+-LocalAppDataPath\s+\$localAppDataPath'
        $initializeText | Should -Match 'Invoke-Winget\s+-ApplicationPath\s+\$wingetPath\s+-Arguments\s+@\(''--version''\)'
        $initializeText | Should -Match 'Invoke-Winget\s+-ApplicationPath\s+\$wingetPath\s+-Arguments\s+@\(''upgrade'',\s*''--help''\)'
    }

    It 'routes every real winget start through the shared absolute-path process pipeline' {
        $invokeText = Get-ScriptFunctionText -Name 'Invoke-Winget'

        $invokeText | Should -Match 'Invoke-WingetProcess\s+.*-ApplicationPath\s+\$ApplicationPath'
        $scriptSource | Should -Not -Match '(?im)\.FileName\s*=\s*[''"]winget(?:\.exe)?[''"]'
        $scriptSource | Should -Not -Match '(?im)Start-Process\s+.*-FilePath\s+[''"]winget(?:\.exe)?[''"]'
    }

    It 'contains no application-managed elevation, scope probing, or User and Machine batches' {
        foreach ($forbidden in @(
            'Ensure-RunningAsAdministrator',
            'Invoke-WingetElevated',
            'Get-WingetPackageScope',
            '\bRunAs\b',
            'EncodedCommand',
            'WingetElevated_',
            'userScopedRows',
            'machineScopedRows',
            '\[ADMIN\]'
        )) {
            $scriptSource | Should -Not -Match $forbidden
        }
    }

    It 'updates selected packages sequentially through the normal process and verifies with list-only refresh' {
        $updateText = Get-ScriptFunctionText -Name 'Update-SelectedPackages'

        $updateText | Should -Match '(?s)foreach\s*\(\$row\s+in\s+\$rows\).*?Invoke-Winget\s+-Arguments\s+\$arguments\s+-Package\s+\$package\s+-LiveLog'
        ([regex]::Matches($updateText, 'Invoke-Winget\s+-Arguments\s+\$arguments')).Count | Should -Be 1
        $updateText | Should -Match 'Refresh-Packages\s+-PreserveLog\s+-ListOnly\s+-KeepBusy'
        $beforeVerification = $updateText.Substring(0, $updateText.IndexOf('Refresh-Packages'))
        $beforeVerification | Should -Not -Match 'Set-Busy\s+-Busy\s+\$false'
    }

    It 'refreshes sources only for user-visible refresh, then lists, and replaces only a temporary successful model' {
        $refreshText = Get-ScriptFunctionText -Name 'Refresh-Packages'
        $sourceCall = $refreshText.IndexOf('Invoke-WingetSourceUpdate')
        $listCall = $refreshText.IndexOf('New-WingetUpgradeListArguments')

        $refreshText | Should -Match 'param\(\[switch\]\$PreserveLog,\s*\[switch\]\$ListOnly,\s*\[switch\]\$KeepBusy\)'
        $refreshText | Should -Match 'if\s*\(-not\s+\$ListOnly\)'
        $refreshText | Should -Match '(?s)if\s*\(-not\s+\$KeepBusy\).*?Set-Busy\s+-Busy\s+\$true'
        $refreshText | Should -Match '(?s)if\s*\(-not\s+\$KeepBusy\).*?Set-Busy\s+-Busy\s+\$false'
        $sourceCall | Should -BeGreaterOrEqual 0
        $listCall | Should -BeGreaterThan $sourceCall
        $refreshText | Should -Match 'ConvertFrom-WingetUpgradeResult\s+-ExitCode\s+\$result\.ExitCode\s+-StandardOutput\s+\$result\.StandardOutput'
        $refreshText | Should -Match '\$newPackages\s*=\s*New-PackagesTable'
        $refreshText | Should -Match '\$Script:Packages\s*=\s*\$newPackages'
        $refreshText.IndexOf('$Script:Packages = $newPackages') | Should -BeGreaterThan $refreshText.IndexOf('ConvertFrom-WingetUpgradeResult')
        $refreshText | Should -Not -Match '\$Script:Packages\.Clear\(\)'
    }

    It 'has one Refresh control and no separate source-update control or checkbox wiring' {
        $scriptSource | Should -Not -Match 'SourceUpdateButton'
        $scriptSource | Should -Not -Match 'SourceUpdateCheck'
        $scriptSource | Should -Not -Match 'Update-WingetSources'
        ([regex]::Matches($scriptSource, '\$Script:RefreshButton\s*=\s*New-Object\s+System\.Windows\.Forms\.Button')).Count | Should -Be 1
    }

    It 'bounds only the GUI TextBox while keeping process results and logs unbounded' {
        $appendText = Get-ScriptFunctionText -Name 'Append-Log'
        $pipelineCommand = Get-Command Invoke-WingetProcess -Module WingetUpdater.Core -ErrorAction SilentlyContinue

        $appendText | Should -Match 'Limit-LogBoxBuffer'
        $scriptSource | Should -Match '\$Script:MaxLogBoxCharacters\s*=\s*\d+'
        $pipelineCommand | Should -Not -BeNullOrEmpty
        $pipelineText = $pipelineCommand.ScriptBlock.ToString()
        $pipelineText | Should -Not -Match 'Substring\(|Remove\('
        $pipelineText | Should -Match 'FileMode\]::CreateNew'
        $pipelineText.IndexOf('$process.Start()') | Should -BeGreaterThan $pipelineText.IndexOf('[System.IO.FileMode]::CreateNew')
    }

    It 'disables every execution-semantic input before pumping heartbeat events' {
        $busyText = Get-ScriptFunctionText -Name 'Set-Busy'
        $invokeText = Get-ScriptFunctionText -Name 'Invoke-Winget'

        foreach ($controlName in @(
            'RefreshButton', 'UpdateButton', 'SaveButton', 'LoadSkippedButton',
            'UpdateAllButton', 'UpdateNoneButton', 'SkipAllButton', 'SkipNoneButton',
            'CopyMessageButton', 'OpenAiCliButton', 'AgentCombo', 'TestModeCheck',
            'SilentCheck', 'InteractiveCheck', 'IncludeUnknownCheck', 'Grid'
        )) {
            $busyText | Should -Match ("\`$Script:$controlName\.Enabled\s*=\s*-not\s+\`$Busy")
        }
        $busyText | Should -Not -Match 'DoEvents'
        $invokeText | Should -Match '\$pulseCallback\s*='
        $invokeText | Should -Match '-OnPulse\s+\$pulseCallback'
        ([regex]::Matches($scriptSource, 'Application\]::DoEvents\(\)')).Count | Should -Be 1
    }

    It 'uses explicit started and infrastructure failure contracts without exit code 9999' {
        $pipelineText = (Get-Command Invoke-WingetProcess -Module WingetUpdater.Core).ScriptBlock.ToString()
        $sourceText = Get-ScriptFunctionText -Name 'Invoke-WingetSourceUpdate'
        $refreshText = Get-ScriptFunctionText -Name 'Refresh-Packages'
        $updateText = Get-ScriptFunctionText -Name 'Update-SelectedPackages'

        $pipelineText | Should -Match 'Started\s*='
        $pipelineText | Should -Match 'InfrastructureError\s*='
        $pipelineText | Should -Match 'Stop-WingetProcess'
        $pipelineText | Should -Not -Match 'Kill\(\s*(?:true|\$true)\s*\)'
        $pipelineText | Should -Not -Match '\.WaitForExit\(\)'
        $pipelineText | Should -Match '\$abortReads\s*=\s*\$true'
        ($pipelineText + $scriptSource) | Should -Not -Match '\b9999\b'
        $sourceText | Should -Match '\$result\.Started'
        $sourceText | Should -Match '\$result\.InfrastructureError'
        $refreshText | Should -Match '\$result\.Started'
        $refreshText | Should -Match '\$result\.InfrastructureError'
        $updateText | Should -Match '\$result\.Started'
        $updateText | Should -Match '\$result\.InfrastructureError'
    }

    It 'centrally aborts orchestration when direct-child cleanup is not guaranteed' {
        $guardText = Get-ScriptFunctionText -Name 'Assert-WingetCleanupGuaranteed'
        $invokeText = Get-ScriptFunctionText -Name 'Invoke-Winget'
        $mockResultText = Get-ScriptFunctionText -Name 'New-MockWingetResult'
        $sourceText = Get-ScriptFunctionText -Name 'Invoke-WingetSourceUpdate'

        $guardText | Should -Match 'if\s*\(-not\s+\[bool\]\$Result\.CleanupGuaranteed\)'
        $guardText | Should -Match 'Append-Log.*\$\(\$Result\.LogPath\)'
        $guardText | Should -Match 'throw'
        $guardText | Should -Not -Match 'ExitCode'
        ([regex]::Matches($invokeText, 'Assert-WingetCleanupGuaranteed\s+-Result')).Count | Should -Be 2
        $invokeText.IndexOf('Assert-WingetCleanupGuaranteed -Result $mockResult') |
            Should -BeLessThan $invokeText.IndexOf('return $mockResult')
        $invokeText.IndexOf('Assert-WingetCleanupGuaranteed -Result $result') |
            Should -BeLessThan $invokeText.IndexOf('return $result')
        $mockResultText | Should -Match 'CleanupGuaranteed\s*=\s*\$true'
        $sourceText | Should -Not -Match 'catch'
    }

    It 'refuses FormClosing while busy before any close-time mutation' {
        $closeHelperText = Get-ScriptFunctionText -Name 'Test-ShouldCancelFormClose'
        $formClosingIndex = $scriptSource.IndexOf('$Script:Form.Add_FormClosing')
        $formClosingText = $scriptSource.Substring($formClosingIndex)

        $closeHelperText | Should -Match '\$Script:IsBusy'
        $formClosingText | Should -Match '(?s)param\(\$formClosingSender,\s*\$formClosingEventArgs\).*?Test-ShouldCancelFormClose.*?\$formClosingEventArgs\.Cancel\s*=\s*\$true.*?return'
        $formClosingText.IndexOf('$formClosingEventArgs.Cancel = $true') |
            Should -BeLessThan $formClosingText.IndexOf('Save-SkipList -Silent')
    }
}

Describe 'WingetUpdater step 5 consent, cancellation, and lifecycle contract' {
    It 'disposes startup resources independently before releasing the mutex' {
        $disposeText = Get-ScriptFunctionText -Name 'Dispose-WingetUpdaterResource'
        $outerFinally = $scriptSource.Substring($scriptSource.LastIndexOf('finally {'))

        $disposeText | Should -Not -BeNullOrEmpty
        $disposeText | Should -Match '\[System\.IDisposable\]'
        $disposeText | Should -Match '(?s)try\s*\{.*?\.Dispose\(\).*?\}\s*catch'
        $outerFinally | Should -Match '(?s)Dispose-WingetUpdaterResource\s+-Resource\s+\$Script:Form.*?Dispose-WingetUpdaterResource\s+-Resource\s+\$Script:ToolTip.*?Exit-WingetUpdaterSingleInstance'

        if ($null -eq ('WingetUpdater.Tests.ThrowingDisposable' -as [type])) {
            Add-Type -TypeDefinition @'
namespace WingetUpdater.Tests {
    public sealed class ThrowingDisposable : System.IDisposable {
        public bool WasDisposed { get; private set; }

        public void Dispose() {
            WasDisposed = true;
            throw new System.InvalidOperationException("injected dispose failure");
        }
    }
}
'@
        }

        . ([scriptblock]::Create($disposeText))
        $throwing = New-Object WingetUpdater.Tests.ThrowingDisposable
        $stream = New-Object System.IO.MemoryStream

        { Dispose-WingetUpdaterResource -Resource $throwing -ResourceName 'Form' } | Should -Not -Throw
        { Dispose-WingetUpdaterResource -Resource $stream -ResourceName 'ToolTip' } | Should -Not -Throw
        $throwing.WasDisposed | Should -BeTrue
        $stream.CanRead | Should -BeFalse
    }

    It 'recognizes derived WinForms forms but not arbitrary heartbeat fixtures' {
        $heartbeatText = Get-ScriptFunctionText -Name 'Invoke-WingetUiHeartbeat'

        $heartbeatText | Should -Match 'IsInstanceOfType\s*\(\s*\$Script:Form\s*\)'
        $heartbeatText | Should -Not -Match 'GetType\(\)\.FullName'
    }

    It 'cancels a Mock update during its simulated delay before mutating MockState.json' {
        $functionDefinitions = @(
            (Get-ScriptFunctionText -Name 'New-MockWingetResult')
            (Get-ScriptFunctionText -Name 'Invoke-MockWingetDelay')
            (Get-ScriptFunctionText -Name 'Assert-WingetCleanupGuaranteed')
            (Get-ScriptFunctionText -Name 'Invoke-Winget')
        ) -join "`r`n"
        $moduleLiteral = (Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetUpdater.Core.psm1').Replace("'", "''")
        $harnessPath = Join-Path $TestDrive 'mock-cancellation-harness.ps1'
        $harness = @'
Import-Module -Name '__MODULE__' -Force -DisableNameChecking -ErrorAction Stop
Set-StrictMode -Version 2.0
$Script:Paths = [pscustomobject]@{ LogsDirectory = '__LOGS__' }
$Script:MockFile = '__MOCK__'
$Script:TestModeCheck = [pscustomobject]@{ Checked = $true }
$Script:CancellationState = New-WingetUpdaterCancellationState
$Script:LogBox = $null
function Reset-MockState { throw 'The fixture must already exist.' }
function Update-LogLiveLine { param([string]$Spinner, [string]$Progress) }
__FUNCTIONS__
[void](New-Item -ItemType Directory -Path '__LOGS__' -Force)
Write-WingetUpdaterJson -Path '__MOCK__' -Data ([ordered]@{
    'Test.App' = [ordered]@{ Name = 'Test App'; Current = '1.0'; Available = '2.0'; ExitCode = 0; Ghost = $false }
})
$package = [pscustomobject]@{ Id = 'Test.App'; Name = 'Test App'; CurrentVersion = '1.0'; AvailableVersion = '2.0'; Source = 'winget' }
$result = Invoke-Winget -Arguments @('upgrade', '--id', 'Test.App') -Package $package -OnPulse {
    Request-WingetUpdaterCancellation -State $Script:CancellationState
}
$state = Read-WingetUpdaterJson -Path '__MOCK__'
[pscustomobject]@{
    Cancelled = [bool]$result.Cancelled
    ExitCode = $result.ExitCode
    InfrastructureError = [string]$result.InfrastructureError
    Current = [string]$state.'Test.App'.Current
    LogText = [System.IO.File]::ReadAllText($result.LogPath)
} | ConvertTo-Json -Compress
'@
        $harness = $harness.Replace('__MODULE__', $moduleLiteral)
        $harness = $harness.Replace('__LOGS__', (Join-Path $TestDrive 'mock-logs').Replace("'", "''"))
        $harness = $harness.Replace('__MOCK__', (Join-Path $TestDrive 'MockState.json').Replace("'", "''"))
        $harness = $harness.Replace('__FUNCTIONS__', $functionDefinitions)
        [System.IO.File]::WriteAllText($harnessPath, $harness, (New-Object System.Text.UTF8Encoding($false)))

        $output = & pwsh -NoLogo -NoProfile -File $harnessPath 2>&1
        $LASTEXITCODE | Should -Be 0
        $record = (($output | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json
        $record.Cancelled | Should -BeTrue
        $record.ExitCode | Should -BeNullOrEmpty
        $record.InfrastructureError | Should -BeNullOrEmpty
        $record.Current | Should -BeExactly '1.0'
        $record.LogText | Should -Match '(?m)^Cancelled: true\r?$'
        $record.LogText | Should -Match '(?m)^ExitCode:\s*$'
        ([regex]::Matches($record.LogText, '(?m)^Cancelled:')).Count | Should -Be 1
    }

    It 'uses the production Mock live heartbeat when no caller pulse exists' {
        $functionDefinitions = @(
            (Get-ScriptFunctionText -Name 'New-MockWingetResult')
            (Get-ScriptFunctionText -Name 'Invoke-MockWingetDelay')
            (Get-ScriptFunctionText -Name 'Invoke-WingetUiHeartbeat')
            (Get-ScriptFunctionText -Name 'Assert-WingetCleanupGuaranteed')
            (Get-ScriptFunctionText -Name 'Invoke-Winget')
        ) -join "`r`n"
        $moduleLiteral = (Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetUpdater.Core.psm1').Replace("'", "''")
        $harnessPath = Join-Path $TestDrive 'mock-live-heartbeat-harness.ps1'
        $harness = @'
Import-Module -Name '__MODULE__' -Force -DisableNameChecking -ErrorAction Stop
Set-StrictMode -Version 2.0
$Script:Paths = [pscustomobject]@{ LogsDirectory = '__LOGS__' }
$Script:MockFile = '__MOCK__'
$Script:TestModeCheck = [pscustomobject]@{ Checked = $true }
$Script:CancellationState = New-WingetUpdaterCancellationState
$Script:LogBox = $null
$Script:Form = [pscustomobject]@{ NotAWinFormsControl = $true }
$heartbeatState = [pscustomobject]@{ Count = 0 }
$spinnerState = [pscustomobject]@{ Started = $false; StopCount = 0 }
function Reset-MockState { throw 'The fixture must already exist.' }
function Update-LogLiveLine { param([string]$Spinner, [string]$Progress) }
function Append-Log { param([string]$Text) }
function Start-Spinner { $spinnerState.Started = $true }
function Stop-Spinner { $spinnerState.Started = $false; $spinnerState.StopCount++ }
function Step-Spinner {
    $heartbeatState.Count++
    Request-WingetUpdaterCancellation -State $Script:CancellationState
}
__FUNCTIONS__
[void](New-Item -ItemType Directory -Path '__LOGS__' -Force)
Write-WingetUpdaterJson -Path '__MOCK__' -Data ([ordered]@{
    'Test.App' = [ordered]@{ Name = 'Test App'; Current = '1.0'; Available = '2.0'; ExitCode = 0; Ghost = $false }
})
$package = [pscustomobject]@{ Id = 'Test.App'; Name = 'Test App'; CurrentVersion = '1.0'; AvailableVersion = '2.0'; Source = 'winget' }
$result = Invoke-Winget -Arguments @('upgrade', '--id', 'Test.App') -Package $package -LiveLog
$state = Read-WingetUpdaterJson -Path '__MOCK__'
[pscustomobject]@{
    Heartbeats = $heartbeatState.Count
    Cancelled = [bool]$result.Cancelled
    ExitCode = $result.ExitCode
    InfrastructureError = [string]$result.InfrastructureError
    Current = [string]$state.'Test.App'.Current
    SpinnerStarted = [bool]$spinnerState.Started
    SpinnerStopCount = $spinnerState.StopCount
} | ConvertTo-Json -Compress
'@
        $harness = $harness.Replace('__MODULE__', $moduleLiteral)
        $harness = $harness.Replace('__LOGS__', (Join-Path $TestDrive 'mock-live-logs').Replace("'", "''"))
        $harness = $harness.Replace('__MOCK__', (Join-Path $TestDrive 'MockLiveState.json').Replace("'", "''"))
        $harness = $harness.Replace('__FUNCTIONS__', $functionDefinitions)
        [System.IO.File]::WriteAllText($harnessPath, $harness, (New-Object System.Text.UTF8Encoding($false)))

        $output = & pwsh -NoLogo -NoProfile -File $harnessPath 2>&1
        $LASTEXITCODE | Should -Be 0
        $record = (($output | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json
        $record.Heartbeats | Should -BeGreaterThan 0
        $record.Cancelled | Should -BeTrue
        $record.ExitCode | Should -BeNullOrEmpty
        $record.InfrastructureError | Should -BeNullOrEmpty
        $record.Current | Should -BeExactly '1.0'
        $record.SpinnerStarted | Should -BeFalse
        $record.SpinnerStopCount | Should -Be 1
    }

    It 'guards direct busy list and selection calls while allowing explicit internal bypass' {
        $targetDefinitions = @(
            (Get-ScriptFunctionText -Name 'Test-OperationEntryAllowed')
            (Get-ScriptFunctionText -Name 'Save-SkipList')
            (Get-ScriptFunctionText -Name 'Set-AllPackageSelection')
            (Get-ScriptFunctionText -Name 'Apply-SkipListToVisiblePackages')
        ) -join "`r`n"
        $moduleLiteral = (Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetUpdater.Core.psm1').Replace("'", "''")
        $harnessPath = Join-Path $TestDrive 'operation-entry-harness.ps1'
        $harness = @'
Import-Module -Name '__MODULE__' -Force -DisableNameChecking -ErrorAction Stop
Set-StrictMode -Version 2.0
$Script:IsBusy = $true
$Script:SkipFile = '__SKIP__'
$Script:SkippedIds = @{}
$Script:Grid = $null
$Script:StatusLabel = $null
function Commit-GridEdits { }
function Load-SkipList { }
function Append-Log { param([string]$Text) }
function Test-IsGhostPackageRow { param([object]$Row) return $false }
function Get-RowValue { param([object]$Row, [string]$ColumnName) return $Row.Item($ColumnName) }
function Set-RowValue { param([object]$Row, [string]$ColumnName, [object]$Value) $Row.Item($ColumnName) = $Value }
__FUNCTIONS__
$table = New-Object System.Data.DataTable
[void]$table.Columns.Add('Update', [bool])
[void]$table.Columns.Add('Skip', [bool])
[void]$table.Columns.Add('Name', [string])
[void]$table.Columns.Add('Id', [string])
[void]$table.Columns.Add('CurrentVersion', [string])
[void]$table.Columns.Add('AvailableVersion', [string])
[void]$table.Columns.Add('IssueType', [string])
[void]$table.Columns.Add('Source', [string])
[void]$table.Columns.Add('Status', [string])
$row = $table.NewRow()
$row.Update = $true
$row.Skip = $false
$row.Name = 'Test App'
$row.Id = 'Test.App'
$row.CurrentVersion = '1.0'
$row.AvailableVersion = '2.0'
$row.IssueType = ''
$row.Source = 'winget'
$row.Status = ''
[void]$table.Rows.Add($row)
$Script:Packages = $table
$directSave = Save-SkipList -Silent
$directSet = Set-AllPackageSelection -ColumnName Update -Checked $false
$directApply = Apply-SkipListToVisiblePackages -Silent
$directState = [pscustomobject]@{ Save = $directSave; Set = $directSet; Apply = $directApply; Update = [bool]$row.Update; Skip = [bool]$row.Skip }
$Script:SkippedIds['Test.App'] = $true
$row.Skip = $true
$internalSave = Save-SkipList -Silent -BypassBusyGuard
$row.Update = $true
$row.Skip = $false
$internalSet = Set-AllPackageSelection -ColumnName Update -Checked $false -BypassBusyGuard
$internalApply = Apply-SkipListToVisiblePackages -Silent -BypassBusyGuard
[pscustomobject]@{
    Direct = $directState
    InternalSave = $internalSave
    InternalSet = $internalSet
    InternalApply = $internalApply
    InternalUpdate = [bool]$row.Update
    InternalSkip = [bool]$row.Skip
} | ConvertTo-Json -Compress
'@
        $harness = $harness.Replace('__MODULE__', $moduleLiteral)
        $harness = $harness.Replace('__SKIP__', (Join-Path $TestDrive 'skip-list.json').Replace("'", "''"))
        $harness = $harness.Replace('__FUNCTIONS__', $targetDefinitions)
        [System.IO.File]::WriteAllText($harnessPath, $harness, (New-Object System.Text.UTF8Encoding($false)))

        $output = & pwsh -NoLogo -NoProfile -File $harnessPath 2>&1
        $LASTEXITCODE | Should -Be 0
        $record = (($output | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json
        $record.Direct.Save | Should -BeFalse
        $record.Direct.Set | Should -BeFalse
        $record.Direct.Apply | Should -BeFalse
        $record.Direct.Update | Should -BeTrue
        $record.Direct.Skip | Should -BeFalse
        $record.InternalSave | Should -BeTrue
        $record.InternalSet | Should -BeTrue
        $record.InternalApply | Should -BeTrue
        $record.InternalUpdate | Should -BeFalse
        $record.InternalSkip | Should -BeTrue
    }

    It 'keeps Cancel hidden while idle and visible while busy' {
        $busyText = Get-ScriptFunctionText -Name 'Set-Busy'
        $busyText | Should -Match '\.Visible\s*=\s*\$Busy'
        $scriptSource | Should -Match '\$Script:CancelButton\.Visible\s*=\s*\$false'
    }

    It 'owns the AI handoff operations with busy lifecycle cleanup' {
        $copyText = Get-ScriptFunctionText -Name 'Copy-AIFailureContext'
        $openText = Get-ScriptFunctionText -Name 'Open-SelectedAICli'
        $copyText | Should -Match 'Set-Busy\s+-Busy\s+\$true'
        $openText | Should -Match 'Set-Busy\s+-Busy\s+\$true'
        $copyText | Should -Match '(?s)try\s*\{.*?New-WingetUpdaterRepairContextFile.*?finally\s*\{.*?Complete-Operation'
    }

    It 'gates every real Refresh before discovery or process work while Mock bypasses the gate' {
        $consentText = Get-ScriptFunctionText -Name 'Confirm-SourceAgreements'
        $refreshText = Get-ScriptFunctionText -Name 'Refresh-Packages'

        $consentText | Should -Match 'Resolve-WingetUpdaterSourceAgreementConsent'
        $consentText | Should -Match '\$Script:TestModeCheck\.Checked'
        $consentText | Should -Match 'Grant-WingetUpdaterSourceAgreements\s+-Path\s+\$Script:Paths\.SettingsFile'
        $consentText | Should -Match 'pelny dostep.*Odswiez.*Mock'
        $refreshText | Should -Match '(?s)if\s*\(-not\s+\(Confirm-SourceAgreements\)\).*?return'
        $refreshText.IndexOf('Confirm-SourceAgreements') | Should -BeLessThan $refreshText.IndexOf('Initialize-WingetInfo')
        $refreshText.IndexOf('Confirm-SourceAgreements') | Should -BeLessThan $refreshText.IndexOf('Invoke-WingetSourceUpdate')
    }

    It 'loads consent only from settings and never treats the legacy notice marker as acceptance' {
        $scriptSource | Should -Match '\$Script:SourceAgreementsAccepted\s*=\s*\[bool\]\$Script:StorageInitialization\.SourceAgreementsAccepted'
        $scriptSource | Should -Not -Match 'LicenseNoticeFile.*SourceAgreementsAccepted|license-accepted.*SourceAgreementsAccepted'
        $scriptSource | Should -Not -Match 'Grant-WingetUpdaterSourceAgreements[^\r\n]+\$false'
    }

    It 'adds accepted source flags only through capability-gated builders' {
        $sourceText = Get-ScriptFunctionText -Name 'Invoke-WingetSourceUpdate'
        $listText = Get-ScriptFunctionText -Name 'New-WingetUpgradeListArguments'
        $updateText = Get-ScriptFunctionText -Name 'Update-SelectedPackages'

        $sourceText | Should -Match 'New-WingetSourceUpdateArguments.*-SourceAgreementsAccepted\s+\$Script:SourceAgreementsAccepted'
        $listText | Should -Match 'New-WingetUpgradeListArguments.*-SourceAgreementsAccepted\s+\$Script:SourceAgreementsAccepted'
        $updateText | Should -Match '-SourceAgreementsAccepted\s+\$Script:SourceAgreementsAccepted'
        $scriptSource | Should -Not -Match '(?m)^\s*\$arguments\s*\+=\s*''--accept-source-agreements'''
    }

    It 'states package agreement acceptance in confirmation before enabling its gated flag' {
        $confirmationText = Get-ScriptFunctionText -Name 'Confirm-UpdateRows'
        $updateText = Get-ScriptFunctionText -Name 'Update-SelectedPackages'

        $confirmationText | Should -Match '(?i)kontynuujac.*akceptujesz.*umow.*pakiet'
        $updateText.IndexOf('Confirm-UpdateRows') | Should -BeLessThan $updateText.IndexOf('-PackageAgreementsConfirmed $true')
        $updateText | Should -Match '-PackageAgreementsConfirmed\s+\$true'
    }

    It 'guards operation entry points and leaves only visible Cancel enabled while busy' {
        $busyText = Get-ScriptFunctionText -Name 'Set-Busy'
        $refreshText = Get-ScriptFunctionText -Name 'Refresh-Packages'
        $updateText = Get-ScriptFunctionText -Name 'Update-SelectedPackages'
        $copyText = Get-ScriptFunctionText -Name 'Copy-AIFailureContext'
        $openText = Get-ScriptFunctionText -Name 'Open-SelectedAICli'

        foreach ($entryText in @($refreshText, $updateText, $copyText, $openText)) {
            $entryText | Should -Match 'Test-OperationEntryAllowed'
        }
        $busyText | Should -Match 'Set-WingetUpdaterBusyControlState'
        $busyText | Should -Match '\$Script:CancelButton'
        $busyText | Should -Not -Match 'ControlBox\s*=\s*-not\s+\$Busy'
        $scriptSource | Should -Match '\$Script:CancelButton\s*=\s*New-Object\s+System\.Windows\.Forms\.Button'
        $scriptSource | Should -Match '\$Script:CancelButton\.Text\s*=\s*''Anuluj'''
        ([regex]::Matches($scriptSource, '\$Script:CancelButton\.Add_Click')).Count | Should -Be 1
    }

    It 'propagates shared cancellation through the real runner and stops queue and verification continuation' {
        $invokeText = Get-ScriptFunctionText -Name 'Invoke-Winget'
        $sourceText = Get-ScriptFunctionText -Name 'Invoke-WingetSourceUpdate'
        $refreshText = Get-ScriptFunctionText -Name 'Refresh-Packages'
        $updateText = Get-ScriptFunctionText -Name 'Update-SelectedPackages'

        $invokeText | Should -Match 'Invoke-WingetProcess.*-CancellationState\s+\$Script:CancellationState'
        $sourceText | Should -Match '(?s)if\s*\(\$result\.Cancelled\).*?return\s+\$result'
        $refreshText | Should -Match '(?s)\$sourceResult\s*=.*?if\s*\(\$sourceResult\.Cancelled\).*?return'
        $refreshText | Should -Match '(?s)\$result\s*=.*?if\s*\(\$result\.Cancelled\).*?return'
        $updateText | Should -Match '(?s)if\s*\(Test-WingetUpdaterCancellationRequested.*?break'
        $updateText | Should -Match '(?s)if\s*\(\$result\.Cancelled\).*?Anulowano.*?break'
        $verificationIndex = $updateText.IndexOf('Refresh-Packages -PreserveLog -ListOnly -KeepBusy')
        $cancellationGuardIndex = $updateText.LastIndexOf('Test-WingetUpdaterCancellationRequested', $verificationIndex)
        $cancellationGuardIndex | Should -BeGreaterOrEqual 0
        $cancellationGuardIndex | Should -BeLessThan $verificationIndex

        $cancelBranch = $updateText.Substring($updateText.IndexOf('if ($result.Cancelled)'))
        $cancelBranch.Substring(0, $cancelBranch.IndexOf('elseif')) | Should -Not -Match '(?i)AI|agent|napraw'
    }

    It 'warns about independent installers when cancellation is confirmed' {
        $cancelText = Get-ScriptFunctionText -Name 'Confirm-OperationCancellation'

        $cancelText | Should -Match '(?i)niezalezn.*instalator|podniesion.*instalator'
        $cancelText | Should -Match 'Request-WingetUpdaterCancellation'
    }

    It 'defers an accepted busy close and schedules it only after operation cleanup' {
        $completeText = Get-ScriptFunctionText -Name 'Complete-Operation'
        $formClosingIndex = $scriptSource.IndexOf('$Script:Form.Add_FormClosing')
        $formClosingText = $scriptSource.Substring($formClosingIndex)

        $formClosingText | Should -Match 'Resolve-WingetUpdaterCloseRequest'
        $formClosingText | Should -Match '(?s)\$formClosingEventArgs\.Cancel\s*=\s*\$decision\.CancelClose.*?\$Script:ClosePending\s*=\s*\$true.*?Request-WingetUpdaterCancellation'
        $completeText | Should -Match '(?s)Set-Busy\s+-Busy\s+\$false.*?\$Script:ClosePending.*?BeginInvoke.*?\.Close\(\)'
    }

    It 'holds the SID-based Local mutex across startup and form lifetime with finally cleanup' {
        $enterIndex = $scriptSource.IndexOf('Enter-WingetUpdaterSingleInstance')
        $storageIndex = $scriptSource.IndexOf('Initialize-WingetUpdaterStorage')
        $runIndex = $scriptSource.IndexOf('[System.Windows.Forms.Application]::Run')
        $exitIndex = $scriptSource.LastIndexOf('Exit-WingetUpdaterSingleInstance')

        $scriptSource | Should -Match 'Get-WingetUpdaterCurrentUserSid'
        $scriptSource | Should -Match 'druga instancja|inna instancja|juz uruchomion'
        $enterIndex | Should -BeGreaterOrEqual 0
        $enterIndex | Should -BeLessThan $storageIndex
        $runIndex | Should -BeGreaterThan $enterIndex
        $exitIndex | Should -BeGreaterThan $runIndex
        $scriptSource.Substring($runIndex, $exitIndex - $runIndex) | Should -Match 'finally'
        $scriptSource | Should -Match '(?s)finally\s*\{.*?\.Dispose\(\).*?Exit-WingetUpdaterSingleInstance'
    }
}

Describe 'WingetUpdater step 5 Windows lifecycle integration' {
    It 'enforces a real named mutex per current Windows SID and releases it for reuse' -Skip:(-not $script:IsWindowsProcessTest) {
        $sid = Get-WingetUpdaterCurrentUserSid
        $first = $null
        $second = $null
        $third = $null
        try {
            $first = Enter-WingetUpdaterSingleInstance -UserSid $sid
            $second = Enter-WingetUpdaterSingleInstance -UserSid $sid

            $first.IsFirstInstance | Should -BeTrue
            $second.IsFirstInstance | Should -BeFalse

            Exit-WingetUpdaterSingleInstance -Lease $second
            $second = $null
            Exit-WingetUpdaterSingleInstance -Lease $first
            $first = $null

            $third = Enter-WingetUpdaterSingleInstance -UserSid $sid
            $third.IsFirstInstance | Should -BeTrue
        }
        finally {
            if ($null -ne $third) { Exit-WingetUpdaterSingleInstance -Lease $third }
            if ($null -ne $second) { Exit-WingetUpdaterSingleInstance -Lease $second }
            if ($null -ne $first) { Exit-WingetUpdaterSingleInstance -Lease $first }
        }
    }

    It 'applies busy state to real WinForms controls with only Cancel enabled' -Skip:(-not $script:IsWindowsProcessTest) {
        Add-Type -AssemblyName System.Windows.Forms
        $refresh = New-Object System.Windows.Forms.Button
        $mode = New-Object System.Windows.Forms.CheckBox
        $grid = New-Object System.Windows.Forms.DataGridView
        $cancel = New-Object System.Windows.Forms.Button
        try {
            Set-WingetUpdaterBusyControlState `
                -Busy $true `
                -OperationControls @($refresh, $mode, $grid) `
                -CancelControl $cancel

            $refresh.Enabled | Should -BeFalse
            $mode.Enabled | Should -BeFalse
            $grid.Enabled | Should -BeFalse
            $cancel.Enabled | Should -BeTrue
        }
        finally {
            $cancel.Dispose()
            $grid.Dispose()
            $mode.Dispose()
            $refresh.Dispose()
        }
    }
}

Describe 'AI Session Failure Handoff' {
    It 'uses non-elevated AI handoff with privacy warning and clipboard prompt' {
        $copyText = Get-ScriptFunctionText -Name 'Copy-AIFailureContext'
        $openText = Get-ScriptFunctionText -Name 'Open-SelectedAICli'

        $copyText | Should -Match 'Get-WingetUpdaterSessionFailures'
        $copyText | Should -Match 'Ostrzezenie o prywatnosci'
        $copyText | Should -Match 'New-WingetUpdaterRepairContextFile'
        $copyText | Should -Match 'Get-WingetUpdaterAIPrompt'
        $copyText | Should -Match '\[System\.Windows\.Forms\.Clipboard\]::SetText'

        $openText | Should -Match 'Resolve-WingetUpdaterAICliPath'
        $openText | Should -Match 'Start-WingetUpdaterAICliProcess'
        $openText | Should -Not -Match 'Start-Process.*-Verb\s+RunAs'
    }
}

Describe 'Startup file formats' {
    It 'keeps Start.bat ASCII with CRLF line endings' {
        $bytes = [System.IO.File]::ReadAllBytes($launcherPath)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        ($launcherSource -replace "`r`n", '') | Should -Not -Match "[`r`n]"
    }

    It 'keeps WingetUpdater.ps1 UTF-8 BOM with CRLF line endings' {
        $bytes = [System.IO.File]::ReadAllBytes($scriptPath)
        @($bytes[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF)
        $strictUtf8 = New-Object System.Text.UTF8Encoding($true, $true)
        { $strictUtf8.GetString($bytes) } | Should -Not -Throw
        ($scriptSource -replace "`r`n", '') | Should -Not -Match "[`r`n]"
    }
}
