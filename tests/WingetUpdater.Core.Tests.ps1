#requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester setup variables are consumed by It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Injected test callbacks must retain production-compatible signatures.')]
param()

BeforeAll {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetUpdater.Core.psm1'
    Import-Module -Name $modulePath -Force -DisableNameChecking -ErrorAction Stop

    function Write-TestJson {
        param(
            [string]$Path,
            [object]$Data
        )

        $parent = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $parent)) {
            [void](New-Item -ItemType Directory -Path $parent -Force)
        }
        ConvertTo-Json -InputObject $Data -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

Describe 'Parse-WingetUpgradeOutput' {
    It 'parses an English winget upgrade table' {
        $output = @'
Name                           Id                  Version Available Source
----------------------------------------------------------------------------
Microsoft PowerToys (Preview) Microsoft.PowerToys 0.80.1  0.81.0    winget
Git                            Git.Git             2.45.1  2.46.0    winget
'@

        $packages = @(Parse-WingetUpgradeOutput -Output $output)

        $packages.Count | Should -Be 2
        $packages[0].Name | Should -Be 'Microsoft PowerToys (Preview)'
        $packages[0].Id | Should -Be 'Microsoft.PowerToys'
        $packages[0].CurrentVersion | Should -Be '0.80.1'
        $packages[0].AvailableVersion | Should -Be '0.81.0'
        $packages[0].Source | Should -Be 'winget'
        $packages[1].Id | Should -Be 'Git.Git'
    }

    It 'parses a Polish winget upgrade table' {
        $polishName = [string]::Concat('Narz', [char]0x0119, 'dzie ', [char]0x017C, [char]0x00F3, [char]0x0142, 'te')
        $availableHeader = [string]::Concat('Dost', [char]0x0119, 'pne')
        $sourceHeader = [string]::Concat([char]0x0179, 'r', [char]0x00F3, 'd', [char]0x0142, 'o')
        $output = @(
            "Nazwa Id Wersja $availableHeader $sourceHeader"
            '------------------------------------------------'
            "$polishName Vendor.Tool 1.0 2.0 winget"
        ) -join "`r`n"

        $packages = @(Parse-WingetUpgradeOutput -Output $output)

        $packages.Count | Should -Be 1
        $packages[0].Name | Should -Be $polishName
        $packages[0].Id | Should -Be 'Vendor.Tool'
        $packages[0].CurrentVersion | Should -Be '1.0'
        $packages[0].AvailableVersion | Should -Be '2.0'
    }

    It 'parses a long name ending in an ellipsis from columns on the right' {
        $displayName = 'Contoso Application With A Very Long Display Name' + [char]0x2026
        $output = @(
            'Name Id Version Available Source'
            '------------------------------------------------'
            "$displayName Contoso.LongApp < 1.0 2.0 winget"
        ) -join "`r`n"

        $packages = @(Parse-WingetUpgradeOutput -Output $output)

        $packages.Count | Should -Be 1
        $packages[0].Name | Should -Be 'Contoso Application With A Very Long Display Name...'
        $packages[0].Id | Should -Be 'Contoso.LongApp'
        $packages[0].CurrentVersion | Should -Be '< 1.0'
        $packages[0].AvailableVersion | Should -Be '2.0'
        $packages[0].Source | Should -Be 'winget'
    }

    It 'ignores malformed table rows' {
        $output = @'
Name Id Version Available Source
--------------------------------
Malformed row only
Still malformed
'@

        @(Parse-WingetUpgradeOutput -Output $output).Count | Should -Be 0
    }

    It 'keeps only the first row for a duplicate package Id' {
        $output = @'
Name Id Version Available Source
--------------------------------
Contoso First Contoso.App 1.0 2.0 winget
Contoso Duplicate Contoso.App 1.1 2.1 winget
'@

        $packages = @(Parse-WingetUpgradeOutput -Output $output)

        $packages.Count | Should -Be 1
        $packages[0].Name | Should -Be 'Contoso First'
        $packages[0].CurrentVersion | Should -Be '1.0'
        $packages[0].AvailableVersion | Should -Be '2.0'
    }

    It 'returns no packages for null, empty, or whitespace output' {
        foreach ($output in @($null, '', " `r`n`t ")) {
            @(Parse-WingetUpgradeOutput -Output $output).Count | Should -Be 0
        }
    }
}

Describe 'Join-CommandLineArguments' {
    It 'quotes <Label> correctly for Windows process arguments' -TestCases @(
        @{ Label = 'spaces'; Argument = 'two words'; Expected = '"two words"' }
        @{ Label = 'an empty string'; Argument = ''; Expected = '""' }
        @{ Label = 'embedded quotes'; Argument = 'say "hello"'; Expected = '"say \"hello\""' }
        @{ Label = 'a quoted trailing backslash'; Argument = 'C:\Program Files\Vendor\'; Expected = '"C:\Program Files\Vendor\\"' }
        @{ Label = 'an apostrophe'; Argument = "O'Brien"; Expected = "O'Brien" }
        @{ Label = 'a semicolon'; Argument = 'alpha;beta'; Expected = 'alpha;beta' }
        @{ Label = 'an ampersand'; Argument = 'alpha&beta'; Expected = 'alpha&beta' }
    ) {
        param($Argument, $Expected)

        Join-CommandLineArguments -Arguments @($Argument) | Should -BeExactly $Expected
    }

    It 'escapes a backslash immediately before an embedded quote' {
        $argument = 'C:\path\"quoted"'
        $expected = '"C:\path' + ('\' * 3) + '"quoted\""'

        Join-CommandLineArguments -Arguments @($argument) | Should -BeExactly $expected
    }

    It 'preserves an unquoted trailing backslash' {
        Join-CommandLineArguments -Arguments @('C:\Tools\') | Should -BeExactly 'C:\Tools\'
    }

    It 'preserves Unicode without shell quoting' {
        $argument = [string]::Concat('Za', [char]0x017C, [char]0x00F3, [char]0x0142, [char]0x0107)

        Join-CommandLineArguments -Arguments @($argument) | Should -BeExactly $argument
    }
}

Describe 'New-WingetPackageUpgradeArguments' {
    BeforeEach {
        $allCapabilities = [pscustomobject]@{
            SupportsExact = $true
            SupportsSource = $true
            SupportsAcceptSourceAgreements = $true
            SupportsAcceptPackageAgreements = $true
            SupportsInteractive = $true
            SupportsSilent = $true
            SupportsIncludeUnknown = $true
            SupportsDisableInteractivity = $true
        }
    }

    It 'builds a confirmed interactive package command and gives interactive precedence over silent' {
        $arguments = @(New-WingetPackageUpgradeArguments `
            -Id 'Contoso App' `
            -Source 'private source' `
            -Capabilities $allCapabilities `
            -SourceAgreementsAccepted $true `
            -PackageAgreementsConfirmed $true `
            -Interactive $true `
            -Silent $true `
            -IncludeUnknown $true)

        ($arguments -join '|') | Should -BeExactly 'upgrade|--id|Contoso App|--exact|--source|private source|--accept-source-agreements|--accept-package-agreements|--interactive|--include-unknown'
        $arguments | Should -Not -Contain '--silent'
        $arguments | Should -Not -Contain '--disable-interactivity'
    }

    It 'defaults to capability-gated noninteractive mode without accepting unconfirmed agreements' {
        $arguments = @(New-WingetPackageUpgradeArguments `
            -Id 'Contoso.App' `
            -Source 'winget' `
            -Capabilities $allCapabilities `
            -SourceAgreementsAccepted $false `
            -PackageAgreementsConfirmed $false `
            -IncludeUnknown $true)

        ($arguments -join '|') | Should -BeExactly 'upgrade|--id|Contoso.App|--exact|--source|winget|--include-unknown|--disable-interactivity'
        $arguments | Should -Not -Contain '--accept-source-agreements'
        $arguments | Should -Not -Contain '--accept-package-agreements'
    }

    It 'combines silent mode with the default noninteractive guard' {
        $arguments = @(New-WingetPackageUpgradeArguments `
            -Id 'Contoso.App' `
            -Capabilities $allCapabilities `
            -Silent $true)

        ($arguments -join '|') | Should -BeExactly 'upgrade|--id|Contoso.App|--exact|--silent|--disable-interactivity'
    }

    It 'does not fall back to silent or default noninteractive flags when interactive was selected but is unsupported' {
        $allCapabilities.SupportsInteractive = $false

        $arguments = @(New-WingetPackageUpgradeArguments `
            -Id 'Contoso.App' `
            -Capabilities $allCapabilities `
            -Interactive $true `
            -Silent $true)

        ($arguments -join '|') | Should -BeExactly 'upgrade|--id|Contoso.App|--exact'
    }

    It 'omits every optional argument when its capability is unavailable' {
        $noCapabilities = [pscustomobject]@{
            SupportsExact = $false
            SupportsSource = $false
            SupportsAcceptSourceAgreements = $false
            SupportsAcceptPackageAgreements = $false
            SupportsInteractive = $false
            SupportsSilent = $false
            SupportsIncludeUnknown = $false
            SupportsDisableInteractivity = $false
        }

        $arguments = @(New-WingetPackageUpgradeArguments `
            -Id 'Contoso.App' `
            -Source 'winget' `
            -Capabilities $noCapabilities `
            -SourceAgreementsAccepted $true `
            -PackageAgreementsConfirmed $true `
            -Interactive $true `
            -Silent $true `
            -IncludeUnknown $true)

        ($arguments -join '|') | Should -BeExactly 'upgrade|--id|Contoso.App'
    }
}

Describe 'Source agreement command arguments' {
    BeforeEach {
        $capabilities = [pscustomobject]@{
            SupportsAcceptSourceAgreements = $true
            SupportsSourceUpdateAcceptSourceAgreements = $true
            SupportsDisableInteractivity = $true
            SupportsIncludeUnknown = $true
        }
    }

    It 'never passes upgrade-only agreement flags to source update but uses them for listing after consent' {
        @(New-WingetSourceUpdateArguments) |
            Should -BeExactly @('source', 'update')
        @(New-WingetUpgradeListArguments `
            -Capabilities $capabilities `
            -SourceAgreementsAccepted $true `
            -IncludeUnknown $true) |
            Should -BeExactly @('upgrade', '--accept-source-agreements', '--disable-interactivity', '--include-unknown')
    }

    It 'omits source acceptance before consent and when each command capability is unavailable' {
        @(New-WingetSourceUpdateArguments) |
            Should -BeExactly @('source', 'update')
        @(New-WingetUpgradeListArguments -Capabilities $capabilities -SourceAgreementsAccepted $false) |
            Should -Not -Contain '--accept-source-agreements'

        $capabilities.SupportsAcceptSourceAgreements = $false
        @(New-WingetSourceUpdateArguments) |
            Should -Not -Contain '--accept-source-agreements'
        @(New-WingetUpgradeListArguments -Capabilities $capabilities -SourceAgreementsAccepted $true) |
            Should -Not -Contain '--accept-source-agreements'
    }
}

Describe 'Source agreement consent policy' {
    It 'does not persist a refusal and prompts again on the next real request' {
        $state = [pscustomobject]@{ Prompts = 0; Persists = 0; RealStarts = 0 }
        $prompt = { $state.Prompts++; return $false }.GetNewClosure()
        $persist = { $state.Persists++ }.GetNewClosure()

        foreach ($attempt in 1..2) {
            $decision = Resolve-WingetUpdaterSourceAgreementConsent `
                -MockMode $false `
                -AlreadyAccepted $false `
                -PromptAction $prompt `
                -PersistAcceptanceAction $persist
            if ($decision.Allowed) {
                $state.RealStarts++
            }
            $decision.Allowed | Should -BeFalse
            $decision.Prompted | Should -BeTrue
            $decision.Persisted | Should -BeFalse
        }

        $state.Prompts | Should -Be 2
        $state.Persists | Should -Be 0
        $state.RealStarts | Should -Be 0
    }

    It 'persists an acceptance once and allows the protected real request' {
        $state = [pscustomobject]@{ Prompts = 0; Persists = 0 }
        $prompt = { $state.Prompts++; return $true }.GetNewClosure()
        $persist = { $state.Persists++ }.GetNewClosure()

        $decision = Resolve-WingetUpdaterSourceAgreementConsent `
            -MockMode $false `
            -AlreadyAccepted $false `
            -PromptAction $prompt `
            -PersistAcceptanceAction $persist

        $decision.Allowed | Should -BeTrue
        $decision.Accepted | Should -BeTrue
        $decision.Prompted | Should -BeTrue
        $decision.Persisted | Should -BeTrue
        $state.Prompts | Should -Be 1
        $state.Persists | Should -Be 1
    }

    It 'bypasses prompts and persistence for Mock' {
        $state = [pscustomobject]@{ Prompts = 0; Persists = 0 }
        $prompt = { $state.Prompts++; return $false }.GetNewClosure()
        $persist = { $state.Persists++ }.GetNewClosure()

        $decision = Resolve-WingetUpdaterSourceAgreementConsent `
            -MockMode $true `
            -AlreadyAccepted $false `
            -PromptAction $prompt `
            -PersistAcceptanceAction $persist

        $decision.Allowed | Should -BeTrue
        $decision.Accepted | Should -BeFalse
        $decision.Prompted | Should -BeFalse
        $decision.Persisted | Should -BeFalse
        $state.Prompts | Should -Be 0
        $state.Persists | Should -Be 0
    }
}

Describe 'WingetUpdater cancellation state and process-tree cleanup' {
    It 'shares an idempotent cancellation request across operation layers' {
        $state = New-WingetUpdaterCancellationState

        Test-WingetUpdaterCancellationRequested -State $state | Should -BeFalse
        Request-WingetUpdaterCancellation -State $state
        Request-WingetUpdaterCancellation -State $state
        Test-WingetUpdaterCancellationRequested -State $state | Should -BeTrue
    }

    It 'uses trusted taskkill tree termination first and confirms bounded cleanup' {
        $systemRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $systemDirectory = Join-Path $systemRoot 'System32'
        $taskkillPath = Join-Path $systemDirectory 'taskkill.exe'
        [void](New-Item -ItemType Directory -Path $systemDirectory -Force)
        [System.IO.File]::WriteAllText($taskkillPath, 'fixture')
        $fakeProcess = [pscustomobject]@{ Id = 5252; HasExited = $false }
        $state = [pscustomobject]@{ TaskkillCalled = $false; TaskkillPath = ''; TaskkillId = 0; KillCalls = 0 }

        $result = Stop-WingetProcessTree `
            -Process $fakeProcess `
            -SystemRootPath $systemRoot `
            -WaitTimeoutMilliseconds 250 `
            -TaskkillAction {
                param($Path, $ProcessId, $TimeoutMilliseconds)
                $state.TaskkillCalled = $true
                $state.TaskkillPath = $Path
                $state.TaskkillId = $ProcessId
                return $true
            } `
            -WaitAction { param($Process, $TimeoutMilliseconds) return $state.TaskkillCalled } `
            -KillAction { param($Process) $state.KillCalls++ }

        $result.GuaranteedStopped | Should -BeTrue
        $result.UsedTaskkill | Should -BeTrue
        $result.UsedDirectKillFallback | Should -BeFalse
        $result.InfrastructureError | Should -BeNullOrEmpty
        $state.TaskkillPath | Should -BeExactly ([System.IO.Path]::GetFullPath($taskkillPath))
        $state.TaskkillId | Should -Be 5252
        $state.KillCalls | Should -Be 0
    }

    It 'falls back to a PS5-compatible direct kill when trusted taskkill fails' {
        $systemRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $systemDirectory = Join-Path $systemRoot 'System32'
        [void](New-Item -ItemType Directory -Path $systemDirectory -Force)
        [System.IO.File]::WriteAllText((Join-Path $systemDirectory 'taskkill.exe'), 'fixture')
        $fakeProcess = [pscustomobject]@{ Id = 6262; HasExited = $false }
        $state = [pscustomobject]@{ Killed = $false }

        $result = Stop-WingetProcessTree `
            -Process $fakeProcess `
            -SystemRootPath $systemRoot `
            -WaitTimeoutMilliseconds 250 `
            -TaskkillAction { param($Path, $ProcessId, $TimeoutMilliseconds) return $false } `
            -WaitAction { param($Process, $TimeoutMilliseconds) return $state.Killed } `
            -KillAction { param($Process) $state.Killed = $true }

        $result.GuaranteedStopped | Should -BeTrue
        $result.UsedTaskkill | Should -BeTrue
        $result.UsedDirectKillFallback | Should -BeTrue
        $result.InfrastructureError | Should -Match 'taskkill fallback reported failure'
    }
}

Describe 'Single-instance and lifecycle policy helpers' {
    It 'builds a stable Local mutex identity from the Windows user SID' {
        Get-WingetUpdaterMutexName -UserSid 'S-1-5-21-100-200-300-1001' |
            Should -BeExactly 'Local\WingetUpdater-S-1-5-21-100-200-300-1001'
        Get-WingetUpdaterMutexName -UserSid 'S-1-5-21-100-200-300-1002' |
            Should -Not -BeExactly (Get-WingetUpdaterMutexName -UserSid 'S-1-5-21-100-200-300-1001')
    }

    It 'leaves only Cancel enabled while busy and disables Cancel when idle' {
        $first = [pscustomobject]@{ Enabled = $true }
        $second = [pscustomobject]@{ Enabled = $true }
        $cancel = [pscustomobject]@{ Enabled = $false }

        Set-WingetUpdaterBusyControlState -Busy $true -OperationControls @($first, $second) -CancelControl $cancel
        $first.Enabled | Should -BeFalse
        $second.Enabled | Should -BeFalse
        $cancel.Enabled | Should -BeTrue

        Set-WingetUpdaterBusyControlState -Busy $false -OperationControls @($first, $second) -CancelControl $cancel
        $first.Enabled | Should -BeTrue
        $second.Enabled | Should -BeTrue
        $cancel.Enabled | Should -BeFalse
    }

    It 'defers an accepted busy close until cancellation cleanup and refuses a declined close' {
        $declined = Resolve-WingetUpdaterCloseRequest -IsBusy $true -CancellationConfirmed $false -CancellationAlreadyRequested $false
        $declined.CancelClose | Should -BeTrue
        $declined.RequestCancellation | Should -BeFalse
        $declined.DeferClose | Should -BeFalse

        $accepted = Resolve-WingetUpdaterCloseRequest -IsBusy $true -CancellationConfirmed $true -CancellationAlreadyRequested $false
        $accepted.CancelClose | Should -BeTrue
        $accepted.RequestCancellation | Should -BeTrue
        $accepted.DeferClose | Should -BeTrue

        $pending = Resolve-WingetUpdaterCloseRequest -IsBusy $true -CancellationConfirmed $false -CancellationAlreadyRequested $true
        $pending.CancelClose | Should -BeTrue
        $pending.RequestCancellation | Should -BeFalse
        $pending.DeferClose | Should -BeTrue
    }
}

Describe 'Resolve-WingetApplicationPath' {
    BeforeEach {
        Get-Command Resolve-WingetApplicationPath -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
        $localAppData = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $trustedDirectory = Join-Path $localAppData 'Microsoft\WindowsApps'
        $trustedPath = Join-Path $trustedDirectory 'winget.exe'
        $decoyPath = Join-Path $TestDrive 'winget-decoy.exe'
    }

    It 'accepts the canonical Windows AppExecutionAlias when its attributes identify a reparse point' {
        [void](New-Item -ItemType Directory -Path $trustedDirectory -Force)
        [System.IO.File]::WriteAllBytes($trustedPath, (New-Object byte[] 0))
        $command = [pscustomobject]@{
            CommandType = [System.Management.Automation.CommandTypes]::Application
            Source = $trustedPath
        }

        Resolve-WingetApplicationPath `
            -Commands @($command) `
            -LocalAppDataPath $localAppData `
            -GetFileAttributes { param($Path) [System.IO.FileAttributes]::ReparsePoint } |
            Should -BeExactly ([System.IO.Path]::GetFullPath($trustedPath))
    }

    It 'rejects a zero-byte regular file at the canonical alias path' {
        [void](New-Item -ItemType Directory -Path $trustedDirectory -Force)
        [System.IO.File]::WriteAllBytes($trustedPath, (New-Object byte[] 0))
        $command = [pscustomobject]@{
            CommandType = [System.Management.Automation.CommandTypes]::Application
            Source = $trustedPath
        }

        { Resolve-WingetApplicationPath -Commands @($command) -LocalAppDataPath $localAppData } |
            Should -Throw '*not an AppExecutionAlias reparse point*'
    }

    It 'rejects an ordinary copied executable at the canonical alias path' {
        [void](New-Item -ItemType Directory -Path $trustedDirectory -Force)
        [System.IO.File]::WriteAllText($trustedPath, 'ordinary executable copy')
        $command = [pscustomobject]@{
            CommandType = [System.Management.Automation.CommandTypes]::Application
            Source = $trustedPath
        }

        { Resolve-WingetApplicationPath -Commands @($command) -LocalAppDataPath $localAppData } |
            Should -Throw '*not an AppExecutionAlias reparse point*'
    }

    It 'selects the canonical alias when an untrusted decoy is discovered first' {
        [void](New-Item -ItemType Directory -Path $trustedDirectory -Force)
        [System.IO.File]::WriteAllBytes($trustedPath, (New-Object byte[] 0))
        [System.IO.File]::WriteAllText($decoyPath, 'decoy')
        $commands = @(
            [pscustomobject]@{
                CommandType = [System.Management.Automation.CommandTypes]::Application
                Source = $decoyPath
            }
            [pscustomobject]@{
                CommandType = [System.Management.Automation.CommandTypes]::Application
                Source = $trustedPath
            }
        )

        Resolve-WingetApplicationPath `
            -Commands $commands `
            -LocalAppDataPath $localAppData `
            -GetFileAttributes { param($Path) [System.IO.FileAttributes]::ReparsePoint } |
            Should -BeExactly ([System.IO.Path]::GetFullPath($trustedPath))
    }

    It 'rejects a lone arbitrary PATH or current-directory decoy' {
        [void](New-Item -ItemType Directory -Path $trustedDirectory -Force)
        [System.IO.File]::WriteAllBytes($trustedPath, (New-Object byte[] 0))
        [System.IO.File]::WriteAllText($decoyPath, 'decoy')
        $command = [pscustomobject]@{
            CommandType = [System.Management.Automation.CommandTypes]::Application
            Source = $decoyPath
        }

        { Resolve-WingetApplicationPath `
            -Commands @($command) `
            -LocalAppDataPath $localAppData `
            -GetFileAttributes { param($Path) [System.IO.FileAttributes]::ReparsePoint } } |
            Should -Throw '*trusted*WindowsApps*winget.exe*'
    }

    It 'fails clearly when discovery returns no candidate' {
        { Resolve-WingetApplicationPath -Commands @() -LocalAppDataPath $localAppData } |
            Should -Throw '*no winget command candidates*'
    }

    It 'rejects a non-Application candidate even at the trusted path' {
        [void](New-Item -ItemType Directory -Path $trustedDirectory -Force)
        [System.IO.File]::WriteAllBytes($trustedPath, (New-Object byte[] 0))
        $command = [pscustomobject]@{
            CommandType = [System.Management.Automation.CommandTypes]::Function
            Source = $trustedPath
        }

        { Resolve-WingetApplicationPath -Commands @($command) -LocalAppDataPath $localAppData } |
            Should -Throw '*no Application candidates*'
    }

    It 'requires rooted LocalAppData and an existing canonical alias' {
        $command = [pscustomobject]@{
            CommandType = [System.Management.Automation.CommandTypes]::Application
            Source = $trustedPath
        }

        { Resolve-WingetApplicationPath -Commands @($command) -LocalAppDataPath 'relative-local-app-data' } |
            Should -Throw '*LocalAppData*rooted*'
        { Resolve-WingetApplicationPath -Commands @($command) -LocalAppDataPath $localAppData } |
            Should -Throw '*trusted*does not exist*'
    }
}

Describe 'Stop-WingetProcess' {
    BeforeEach {
        Get-Command Stop-WingetProcess -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty

        $systemRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $systemDirectory = Join-Path $systemRoot 'System32'
        $taskkillPath = Join-Path $systemDirectory 'taskkill.exe'
        [void](New-Item -ItemType Directory -Path $systemDirectory -Force)
        [System.IO.File]::WriteAllText($taskkillPath, 'fixture')
        $fakeProcess = [pscustomobject]@{
            Id = 4242
            HasExited = $false
        }
    }

    It 'uses the canonical taskkill fallback after Kill fails and confirms bounded cleanup' {
        $state = [pscustomobject]@{
            TaskkillCalled = $false
            TaskkillPath = ''
            TaskkillId = 0
            WaitCalls = 0
        }

        $result = Stop-WingetProcess `
            -Process $fakeProcess `
            -SystemRootPath $systemRoot `
            -WaitTimeoutMilliseconds 250 `
            -KillAction { param($Process) throw 'injected Kill failure' } `
            -WaitAction {
                param($Process, $TimeoutMilliseconds)
                $state.WaitCalls++
                return $state.TaskkillCalled
            } `
            -TaskkillAction {
                param($Path, $ProcessId, $TimeoutMilliseconds)
                $state.TaskkillCalled = $true
                $state.TaskkillPath = $Path
                $state.TaskkillId = $ProcessId
                return $true
            }

        $result.GuaranteedStopped | Should -BeTrue
        $result.UsedTaskkill | Should -BeTrue
        $state.TaskkillPath | Should -BeExactly ([System.IO.Path]::GetFullPath($taskkillPath))
        $state.TaskkillId | Should -Be 4242
        $state.WaitCalls | Should -Be 2
    }

    It 'returns promptly with an explicit warning when Kill and taskkill cannot guarantee termination' {
        $startedAt = [datetime]::UtcNow

        $result = Stop-WingetProcess `
            -Process $fakeProcess `
            -SystemRootPath $systemRoot `
            -WaitTimeoutMilliseconds 50 `
            -KillAction { param($Process) throw 'injected Kill failure' } `
            -WaitAction { param($Process, $TimeoutMilliseconds) return $false } `
            -TaskkillAction { param($Path, $ProcessId, $TimeoutMilliseconds) throw 'injected taskkill failure' }

        ([datetime]::UtcNow - $startedAt).TotalSeconds | Should -BeLessThan 1
        $result.GuaranteedStopped | Should -BeFalse
        $result.InfrastructureError | Should -Match 'Kill failure'
        $result.InfrastructureError | Should -Match 'taskkill failure'
        $result.InfrastructureError | Should -Match 'could not be guaranteed'
    }
}

Describe 'ConvertFrom-WingetUpgradeResult' {
    BeforeEach {
        Get-Command ConvertFrom-WingetUpgradeResult -ErrorAction SilentlyContinue |
            Should -Not -BeNullOrEmpty
    }

    It 'rejects a nonzero list exit code instead of parsing its output' {
        $failedOutput = @'
Name Id Version Available Source
--------------------------------
Stale Package Contoso.Stale 1.0 2.0 winget
'@

        { ConvertFrom-WingetUpgradeResult -ExitCode 5 -StandardOutput $failedOutput } |
            Should -Throw '*exit code 5*'
    }

    It 'parses packages only after a successful list result' {
        $output = @'
Name Id Version Available Source
--------------------------------
Contoso Package Contoso.App 1.0 2.0 winget
'@

        $packages = @(ConvertFrom-WingetUpgradeResult -ExitCode 0 -StandardOutput $output)

        $packages.Count | Should -Be 1
        $packages[0].Id | Should -BeExactly 'Contoso.App'
    }
}

Describe 'WingetUpdater LocalAppData storage' {
    BeforeEach {
        $caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $localAppData = Join-Path $caseRoot 'local-app-data'
        $legacyApp = Join-Path $caseRoot 'legacy-app'
        [void](New-Item -ItemType Directory -Path $legacyApp -Force)
        $paths = Get-WingetUpdaterPaths -LocalAppDataPath $localAppData
    }

    It 'defines and initializes the complete LocalAppData path model' {
        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        $paths.Root | Should -BeExactly (Join-Path $localAppData 'WingetUpdater')
        $paths.SettingsFile | Should -BeExactly (Join-Path $paths.Root 'settings.json')
        $paths.SkipListFile | Should -BeExactly (Join-Path $paths.Root 'skip-list.json')
        $paths.LicenseNoticeFile | Should -BeExactly (Join-Path $paths.Root '.license-notice-shown')
        $paths.LogsDirectory | Should -BeExactly (Join-Path $paths.Root 'logs')
        $paths.RepairContextsDirectory | Should -BeExactly (Join-Path $paths.Root 'repair-contexts')
        $paths.MockDirectory | Should -BeExactly (Join-Path $paths.Root 'mock')
        $paths.MockStateFile | Should -BeExactly (Join-Path $paths.MockDirectory 'MockState.json')

        foreach ($directory in @($paths.Root, $paths.LogsDirectory, $paths.RepairContextsDirectory, $paths.MockDirectory)) {
            Test-Path -LiteralPath $directory -PathType Container | Should -BeTrue
        }
        Test-Path -LiteralPath $paths.SettingsFile -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $paths.SkipListFile -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $paths.LicenseNoticeFile | Should -BeFalse
        Test-Path -LiteralPath $paths.MockStateFile | Should -BeFalse

        $settings = Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json
        $settings.schemaVersion | Should -Be 1
        $settings.migrationVersion | Should -Be 1
        @($settings.PSObject.Properties.Name) | Should -Not -Contain 'sourceAgreementAccepted'
        @($result.Warnings).Count | Should -Be 0
    }

    It 'can repeat a completed migration without changing destination data' {
        Write-TestJson -Path (Join-Path $legacyApp 'skip-list.json') -Data @{
            skippedIds = @('Contoso.One')
        }
        [void](New-Item -ItemType File -Path (Join-Path $legacyApp '.license-accepted'))
        $legacyContexts = Join-Path $legacyApp 'repair-contexts'
        [void](New-Item -ItemType Directory -Path $legacyContexts)
        [System.IO.File]::WriteAllText((Join-Path $legacyContexts 'context.txt'), 'context data')
        Write-TestJson -Path (Join-Path $legacyApp 'Tests/MockState.json') -Data @{
            Version = 'legacy'
        }

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null
        $skipAfterFirstRun = Get-Content -LiteralPath $paths.SkipListFile -Raw
        $settingsAfterFirstRun = Get-Content -LiteralPath $paths.SettingsFile -Raw
        $mockAfterFirstRun = Get-Content -LiteralPath $paths.MockStateFile -Raw

        $secondResult = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        (Get-Content -LiteralPath $paths.SkipListFile -Raw) | Should -BeExactly $skipAfterFirstRun
        (Get-Content -LiteralPath $paths.SettingsFile -Raw) | Should -BeExactly $settingsAfterFirstRun
        (Get-Content -LiteralPath $paths.MockStateFile -Raw) | Should -BeExactly $mockAfterFirstRun
        @(Get-ChildItem -LiteralPath $paths.RepairContextsDirectory -File).Count | Should -Be 1
        @($secondResult.Warnings).Count | Should -Be 0
    }

    It 'does not migrate destination data when the legacy app directory aliases the storage root' {
        [void](New-Item -ItemType Directory -Path $paths.RepairContextsDirectory -Force)
        Write-TestJson -Path $paths.SkipListFile -Data @{ skippedIds = @('Keep.This') }
        $contextPath = Join-Path $paths.RepairContextsDirectory 'keep-context.txt'
        [System.IO.File]::WriteAllText($contextPath, 'keep context')

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $paths.Root

        (@(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile) -join '|') | Should -BeExactly 'Keep.This'
        Test-Path -LiteralPath $paths.RepairContextsDirectory -PathType Container | Should -BeTrue
        Test-Path -LiteralPath $contextPath -PathType Leaf | Should -BeTrue
        [System.IO.File]::ReadAllText($contextPath) | Should -BeExactly 'keep context'
        @($result.Warnings).Count | Should -Be 0
    }

    It 'merges valid legacy and destination skip IDs without loss' {
        Write-TestJson -Path $paths.SkipListFile -Data @{
            skippedIds = @('Destination.App', 'Shared.App')
        }
        Write-TestJson -Path (Join-Path $legacyApp 'skip-list.json') -Data @(
            'Legacy.App'
            'Shared.App'
        )

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        (@(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile) -join '|') |
            Should -BeExactly 'Destination.App|Legacy.App|Shared.App'
        Test-Path -LiteralPath (Join-Path $legacyApp 'skip-list.json') | Should -BeFalse
    }

    It 'preserves an empty top-level JSON array when reading skip IDs' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        [System.IO.File]::WriteAllText($paths.SkipListFile, '[]')

        @(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile).Count | Should -Be 0
    }

    It 'preserves a single-element top-level JSON array when reading skip IDs' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        [System.IO.File]::WriteAllText($paths.SkipListFile, '["Only.App"]')

        (@(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile) -join '|') | Should -BeExactly 'Only.App'
    }

    It 'does not quarantine a valid <Label> when JSON conversion uses PS5 pipeline semantics' -TestCases @(
        @{ Label = 'empty array root'; Json = '[]' }
        @{ Label = 'singleton array root'; Json = '["Only.App"]' }
    ) {
        param($Json)

        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        [System.IO.File]::WriteAllText($paths.SkipListFile, $Json)
        $skipPath = $paths.SkipListFile
        Mock -CommandName Read-WingetUpdaterJson -ModuleName WingetUpdater.Core -MockWith {
            if (-not (Test-Path -LiteralPath $Path)) {
                return $null
            }
            $raw = [System.IO.File]::ReadAllText($Path)
            if ($raw -eq '[]') {
                return $null
            }
            if ($raw -like '*Only.App*') {
                return 'Only.App'
            }
            return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
        }

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        [System.IO.File]::ReadAllText($paths.SkipListFile) | Should -BeExactly $Json
        @(Get-ChildItem -LiteralPath $paths.Root -Filter 'skip-list.recovery-*.json' -File).Count | Should -Be 0
        (@($result.Warnings) -join "`n") | Should -Not -Match 'Corrupt destination skip-list'
    }

    It 'rejects a scalar JSON root as skip data' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        [System.IO.File]::WriteAllText($paths.SkipListFile, '"Only.App"')

        { Read-WingetUpdaterSkipIds -Path $paths.SkipListFile } | Should -Throw
    }

    It 'rejects null members in a top-level skip array' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        [System.IO.File]::WriteAllText($paths.SkipListFile, '["Valid.App",null]')

        { Read-WingetUpdaterSkipIds -Path $paths.SkipListFile } | Should -Throw '*non-string ID*'
    }

    It 'exports the validated JSON reader for Mock state consumers' {
        Write-TestJson -Path $paths.MockStateFile -Data @{ Version = 'valid' }

        (Read-WingetUpdaterJson -Path $paths.MockStateFile).Version | Should -BeExactly 'valid'
        [System.IO.File]::WriteAllText($paths.MockStateFile, '{ broken mock')
        { Read-WingetUpdaterJson -Path $paths.MockStateFile } | Should -Throw '*Invalid JSON file*'
    }

    It 'copies colliding repair contexts without overwriting either file' {
        [void](New-Item -ItemType Directory -Path $paths.RepairContextsDirectory -Force)
        $legacyContexts = Join-Path $legacyApp 'repair-contexts'
        [void](New-Item -ItemType Directory -Path $legacyContexts)
        [System.IO.File]::WriteAllText((Join-Path $paths.RepairContextsDirectory 'failure.txt'), 'destination data')
        [System.IO.File]::WriteAllText((Join-Path $legacyContexts 'failure.txt'), 'legacy data')

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        [System.IO.File]::ReadAllText((Join-Path $paths.RepairContextsDirectory 'failure.txt')) |
            Should -BeExactly 'destination data'
        $contextContents = @(Get-ChildItem -LiteralPath $paths.RepairContextsDirectory -File | ForEach-Object {
            [System.IO.File]::ReadAllText($_.FullName)
        })
        $contextContents | Should -Contain 'destination data'
        $contextContents | Should -Contain 'legacy data'
        $contextContents.Count | Should -Be 2
        Test-Path -LiteralPath (Join-Path $legacyContexts 'failure.txt') | Should -BeFalse
    }

    It 'keeps a newer destination Mock state when both files exist' {
        $legacyMock = Join-Path $legacyApp 'Tests/MockState.json'
        Write-TestJson -Path $legacyMock -Data @{ Version = 'legacy-older' }
        Write-TestJson -Path $paths.MockStateFile -Data @{ Version = 'destination-newer' }
        [System.IO.File]::SetLastWriteTimeUtc($legacyMock, [datetime]::UtcNow.AddMinutes(-10))
        [System.IO.File]::SetLastWriteTimeUtc($paths.MockStateFile, [datetime]::UtcNow)

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        $mock = Get-Content -LiteralPath $paths.MockStateFile -Raw | ConvertFrom-Json
        $mock.Version | Should -BeExactly 'destination-newer'
        Test-Path -LiteralPath $legacyMock | Should -BeFalse
    }

    It 'replaces an older destination with a strictly newer legacy Mock state' {
        $legacyMock = Join-Path $legacyApp 'Tests/MockState.json'
        Write-TestJson -Path $legacyMock -Data @{ Version = 'legacy-newer' }
        Write-TestJson -Path $paths.MockStateFile -Data @{ Version = 'destination-older' }
        [System.IO.File]::SetLastWriteTimeUtc($paths.MockStateFile, [datetime]::UtcNow.AddMinutes(-10))
        [System.IO.File]::SetLastWriteTimeUtc($legacyMock, [datetime]::UtcNow)

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        $mock = Get-Content -LiteralPath $paths.MockStateFile -Raw | ConvertFrom-Json
        $mock.Version | Should -BeExactly 'legacy-newer'
        Test-Path -LiteralPath $legacyMock | Should -BeFalse
    }

    It 'preserves both Mock states when equal timestamps have different contents' {
        $legacyMock = Join-Path $legacyApp 'Tests/MockState.json'
        Write-TestJson -Path $legacyMock -Data @{ Version = 'legacy-different' }
        Write-TestJson -Path $paths.MockStateFile -Data @{ Version = 'destination-different' }
        $equalTime = [datetime]::UtcNow.AddMinutes(-5)
        [System.IO.File]::SetLastWriteTimeUtc($legacyMock, $equalTime)
        [System.IO.File]::SetLastWriteTimeUtc($paths.MockStateFile, $equalTime)

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        (Get-Content -LiteralPath $paths.MockStateFile -Raw | ConvertFrom-Json).Version |
            Should -BeExactly 'destination-different'
        (Get-Content -LiteralPath $legacyMock -Raw | ConvertFrom-Json).Version |
            Should -BeExactly 'legacy-different'
        (@($result.Warnings) -join "`n") | Should -Match 'equal timestamps.*different contents.*preserved'
        (Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json).migrationVersion | Should -Be 0
    }

    It 'preserves malformed legacy JSON and records an incomplete migration warning' {
        $legacySkip = Join-Path $legacyApp 'skip-list.json'
        [System.IO.File]::WriteAllText($legacySkip, '{ malformed json')

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        Test-Path -LiteralPath $legacySkip -PathType Leaf | Should -BeTrue
        @(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile).Count | Should -Be 0
        (@($result.Warnings) -join "`n") | Should -Match 'skip-list\.json'
        $settings = Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json
        $settings.migrationVersion | Should -Be 0
    }

    It 'preserves corrupt destination settings and reinitializes safe settings' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        $corruptSettings = '{ broken settings'
        [System.IO.File]::WriteAllText($paths.SettingsFile, $corruptSettings)
        $firstRecovery = Join-Path $paths.Root 'settings.recovery-1.json'
        [System.IO.File]::WriteAllText($firstRecovery, 'existing recovery')

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        $settings = Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json
        $settings.schemaVersion | Should -Be 1
        $settings.migrationVersion | Should -Be 1
        [System.IO.File]::ReadAllText($firstRecovery) | Should -BeExactly 'existing recovery'
        $recoveries = @(Get-ChildItem -LiteralPath $paths.Root -Filter 'settings.recovery-*.json' -File)
        $recoveries.Count | Should -Be 2
        @($recoveries | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) |
            Should -Contain $corruptSettings
        (@($result.Warnings) -join "`n") | Should -Match 'settings.*preserved.*recovery'
    }

    It 'preserves corrupt destination skip data and reinitializes a safe skip list' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        $corruptSkip = '{"skippedIds":[42]}'
        [System.IO.File]::WriteAllText($paths.SkipListFile, $corruptSkip)
        $firstRecovery = Join-Path $paths.Root 'skip-list.recovery-1.json'
        [System.IO.File]::WriteAllText($firstRecovery, 'existing recovery')

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        @(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile).Count | Should -Be 0
        [System.IO.File]::ReadAllText($firstRecovery) | Should -BeExactly 'existing recovery'
        $recoveries = @(Get-ChildItem -LiteralPath $paths.Root -Filter 'skip-list.recovery-*.json' -File)
        $recoveries.Count | Should -Be 2
        @($recoveries | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) |
            Should -Contain $corruptSkip
        (@($result.Warnings) -join "`n") | Should -Match 'skip-list.*preserved.*recovery'
    }

    It 'treats failed legacy cleanup as a warning after destination validation' {
        $legacySkip = Join-Path $legacyApp 'skip-list.json'
        Write-TestJson -Path $legacySkip -Data @{ skippedIds = @('Legacy.ReadOnly') }
        Mock -CommandName Remove-Item -ModuleName WingetUpdater.Core -ParameterFilter {
            $LiteralPath -eq $legacySkip
        } -MockWith {
            throw 'simulated read-only cleanup failure'
        }

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp

        (@(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile) -join '|') |
            Should -BeExactly 'Legacy.ReadOnly'
        Test-Path -LiteralPath $legacySkip -PathType Leaf | Should -BeTrue
        (@($result.Warnings) -join "`n") | Should -Match 'simulated read-only cleanup failure'
        $settings = Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json
        $settings.migrationVersion | Should -Be 1
    }

    It 'recovers a partially copied migration without duplicating data' {
        Write-TestJson -Path $paths.SettingsFile -Data @{
            schemaVersion = 1
            migrationVersion = 0
        }
        Write-TestJson -Path $paths.SkipListFile -Data @{ skippedIds = @('Already.Copied') }
        Write-TestJson -Path (Join-Path $legacyApp 'skip-list.json') -Data @{ skippedIds = @('Already.Copied') }
        [void](New-Item -ItemType Directory -Path $paths.RepairContextsDirectory -Force)
        $legacyContexts = Join-Path $legacyApp 'repair-contexts'
        [void](New-Item -ItemType Directory -Path $legacyContexts)
        [System.IO.File]::WriteAllText((Join-Path $paths.RepairContextsDirectory 'partial.txt'), 'same content')
        [System.IO.File]::WriteAllText((Join-Path $legacyContexts 'partial.txt'), 'same content')

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        (@(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile) -join '|') |
            Should -BeExactly 'Already.Copied'
        @(Get-ChildItem -LiteralPath $paths.RepairContextsDirectory -File).Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $legacyApp 'skip-list.json') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $legacyContexts 'partial.txt') | Should -BeFalse
        $settings = Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json
        $settings.migrationVersion | Should -Be 1
    }

    It 'converts the legacy license marker only to a notice marker' {
        $legacyMarker = Join-Path $legacyApp '.license-accepted'
        [void](New-Item -ItemType File -Path $legacyMarker)

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        Test-Path -LiteralPath $paths.LicenseNoticeFile -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $legacyMarker | Should -BeFalse
        $settings = Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json
        @($settings.PSObject.Properties.Name) | Should -Not -Contain 'sourceAgreementAccepted'
        @($settings.PSObject.Properties.Name) | Should -Not -Contain 'sourceAgreementsAccepted'
    }

    It 'persists source agreement acceptance only in schema-versioned atomic settings' {
        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        Grant-WingetUpdaterSourceAgreements -Path $paths.SettingsFile | Out-Null

        $settings = Get-Content -LiteralPath $paths.SettingsFile -Raw | ConvertFrom-Json
        $settings.schemaVersion | Should -Be 1
        $settings.migrationVersion | Should -Be 1
        $settings.sourceAgreementsAccepted | Should -BeTrue
        @(Get-ChildItem -LiteralPath $paths.Root -Filter '*.tmp' -File).Count | Should -Be 0

        $result = Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp
        $result.SourceAgreementsAccepted | Should -BeTrue
    }

    It 'prunes log and repair-context files older than 30 days' {
        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null
        $oldLog = Join-Path $paths.LogsDirectory 'old.log'
        $newLog = Join-Path $paths.LogsDirectory 'new.log'
        $oldContext = Join-Path $paths.RepairContextsDirectory 'old.txt'
        $newContext = Join-Path $paths.RepairContextsDirectory 'new.txt'
        foreach ($file in @($oldLog, $newLog, $oldContext, $newContext)) {
            [System.IO.File]::WriteAllText($file, 'data')
        }
        foreach ($file in @($oldLog, $oldContext)) {
            [System.IO.File]::SetLastWriteTimeUtc($file, [datetime]::UtcNow.AddDays(-31))
        }

        Initialize-WingetUpdaterStorage -Paths $paths -LegacyAppDirectory $legacyApp | Out-Null

        Test-Path -LiteralPath $oldLog | Should -BeFalse
        Test-Path -LiteralPath $oldContext | Should -BeFalse
        Test-Path -LiteralPath $newLog -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $newContext -PathType Leaf | Should -BeTrue
    }

    It 'atomically replaces JSON state without leaving a temporary file' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        Write-TestJson -Path $paths.SkipListFile -Data @{ skippedIds = @('Old.App') }

        Write-WingetUpdaterJson -Path $paths.SkipListFile -Data @{ skippedIds = @('New.App') }

        (@(Read-WingetUpdaterSkipIds -Path $paths.SkipListFile) -join '|') |
            Should -BeExactly 'New.App'
        @(Get-ChildItem -LiteralPath $paths.Root -Filter '*.tmp' -File).Count | Should -Be 0
    }

    It 'does not report an atomic write failure only because backup cleanup fails' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        Write-TestJson -Path $paths.SkipListFile -Data @{ skippedIds = @('Old.App') }
        Mock -CommandName Remove-Item -ModuleName WingetUpdater.Core -ParameterFilter {
            $LiteralPath -like '*.bak'
        } -MockWith {
            throw 'simulated backup cleanup failure'
        }

        { Write-WingetUpdaterJson -Path $paths.SkipListFile -Data @{ skippedIds = @('New.App') } } |
            Should -Not -Throw
        (Get-Content -LiteralPath $paths.SkipListFile -Raw | ConvertFrom-Json).skippedIds |
            Should -BeExactly 'New.App'
    }

    It 'restores the prior destination after post-replacement validation fails' {
        [void](New-Item -ItemType Directory -Path $paths.Root -Force)
        Write-TestJson -Path $paths.SkipListFile -Data @{ skippedIds = @('Old.App') }
        $destinationPath = $paths.SkipListFile
        Mock -CommandName Read-WingetUpdaterJson -ModuleName WingetUpdater.Core -ParameterFilter {
            $Path -eq $destinationPath -or $Path -like "$destinationPath*" -or $Path -like "*skip-list.json*"
        } -MockWith {
            throw 'simulated post-replacement validation failure'
        }

        { Write-WingetUpdaterJson -Path $destinationPath -Data @{ skippedIds = @('New.App') } } |
            Should -Throw '*simulated post-replacement validation failure*'
        (Get-Content -LiteralPath $destinationPath -Raw | ConvertFrom-Json).skippedIds |
            Should -BeExactly 'Old.App'
    }
}

Describe 'WingetUpdater Session Failure Registry & AI Handoff' {
    BeforeEach {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) ("winget-test-" + [guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $testDir -Force)
    }
    AfterEach {
        if (Test-Path -LiteralPath $testDir) {
            Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates and manages unresolved package upgrade failures' {
        $registry = New-WingetUpdaterSessionFailureRegistry
        $pkg = [pscustomobject]@{ Id = 'Vendor.App'; Source = 'winget'; Name = 'Vendor App'; CurrentVersion = '1.0'; AvailableVersion = '2.0'; Scope = 'User' }
        $startedAtUtc = [datetime]'2026-07-21T10:00:00Z'
        $endedAtUtc = [datetime]'2026-07-21T10:00:05Z'
        $res1 = [pscustomobject]@{ ExitCode = 1; DisplayCommand = 'winget upgrade --id Vendor.App'; StartedAtUtc = $startedAtUtc; EndedAtUtc = $endedAtUtc; StandardOutput = 'out1'; StandardError = 'err1'; CombinedOutput = 'out1err1'; LogPath = 'C:\log1.log' }

        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg -Result $res1 -FailureType 'PackageUpgradeFailure'

        $failures = @(Get-WingetUpdaterSessionFailures -Registry $registry)
        $failures.Count | Should -Be 1
        $failures[0].Id | Should -Be 'Vendor.App'
        $failures[0].AttemptCount | Should -Be 1
        $failures[0].ExitCode | Should -Be 1
        $failures[0].FailureType | Should -Be 'PackageUpgradeFailure'
        $failures[0].DisplayArguments | Should -BeExactly 'winget upgrade --id Vendor.App'
        $failures[0].StartedAtUtc | Should -Be $startedAtUtc
        $failures[0].EndedAtUtc | Should -Be $endedAtUtc

        # Retry failure increments attempt count
        $res2 = [pscustomobject]@{ ExitCode = 2; DisplayCommand = 'winget upgrade --id Vendor.App --exact'; StartedAtUtc = $startedAtUtc.AddMinutes(1); EndedAtUtc = $endedAtUtc.AddMinutes(1); StandardOutput = 'out2'; StandardError = 'err2'; CombinedOutput = 'out2err2'; LogPath = 'C:\log2.log' }
        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg -Result $res2 -FailureType 'PackageUpgradeFailure'

        $failures2 = @(Get-WingetUpdaterSessionFailures -Registry $registry)
        $failures2.Count | Should -Be 1
        $failures2[0].AttemptCount | Should -Be 2
        $failures2[0].ExitCode | Should -Be 2
        $failures2[0].DisplayArguments | Should -BeExactly 'winget upgrade --id Vendor.App --exact'

        # Success removes package from registry
        Remove-WingetUpdaterSessionFailure -Registry $registry -Id 'Vendor.App' -Source 'winget'
        @(Get-WingetUpdaterSessionFailures -Registry $registry).Count | Should -Be 0
    }

    It 'keeps an explicit Ghost attempt count stable across repeated verification refreshes' {
        $registry = New-WingetUpdaterSessionFailureRegistry
        $pkg = [pscustomobject]@{ Id = 'Ghost.App'; Source = 'winget'; Name = 'Ghost App'; CurrentVersion = '1.0'; AvailableVersion = '2.0' }
        $firstResult = [pscustomobject]@{ ExitCode = 0; DisplayCommand = 'winget upgrade --id Ghost.App'; StandardOutput = 'success-one'; StandardError = ''; LogPath = 'C:\ghost1.log' }
        $secondResult = [pscustomobject]@{ ExitCode = 0; DisplayCommand = 'winget upgrade --id Ghost.App'; StandardOutput = 'success-two'; StandardError = ''; LogPath = 'C:\ghost2.log' }

        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg -Result $firstResult -FailureType 'PostVerificationFailure' -AttemptCountOverride 1
        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg -Result $firstResult -FailureType 'PostVerificationFailure' -AttemptCountOverride 1

        $afterRefresh = @(Get-WingetUpdaterSessionFailures -Registry $registry)
        $afterRefresh.Count | Should -Be 1
        $afterRefresh[0].AttemptCount | Should -Be 1

        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg -Result $secondResult -FailureType 'PostVerificationFailure' -AttemptCountOverride 2
        $afterRetry = @(Get-WingetUpdaterSessionFailures -Registry $registry)
        $afterRetry[0].AttemptCount | Should -Be 2
        $afterRetry[0].StandardOutput | Should -BeExactly 'success-two'
    }

    It 'never registers a user-cancelled package operation as an AI failure' {
        $registry = New-WingetUpdaterSessionFailureRegistry
        $pkg = [pscustomobject]@{ Id = 'Cancelled.App'; Source = 'winget'; Name = 'Cancelled App' }
        $result = [pscustomobject]@{ Cancelled = $true; ExitCode = $null; StandardOutput = ''; StandardError = '' }

        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg -Result $result

        @(Get-WingetUpdaterSessionFailures -Registry $registry).Count | Should -Be 0
    }

    It 'filters session failures by selected packages when provided' {
        $registry = New-WingetUpdaterSessionFailureRegistry
        $pkg1 = [pscustomobject]@{ Id = 'App1'; Source = 'winget'; Name = 'App 1' }
        $pkg2 = [pscustomobject]@{ Id = 'App2'; Source = 'winget'; Name = 'App 2' }
        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg1 -Result ([pscustomobject]@{ ExitCode = 1 })
        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg2 -Result ([pscustomobject]@{ ExitCode = 2 })

        $selected = @([pscustomobject]@{ Id = 'App2'; Source = 'winget' })
        $filtered = @(Get-WingetUpdaterSessionFailures -Registry $registry -SelectedPackages $selected)
        $filtered.Count | Should -Be 1
        $filtered[0].Id | Should -Be 'App2'
    }

    It 'generates a UTF-8 repair context file and prompt' {
        $registry = New-WingetUpdaterSessionFailureRegistry
        $pkg = [pscustomobject]@{ Id = 'Fail.App'; Source = 'winget'; Name = 'Failing App'; CurrentVersion = '1.0'; AvailableVersion = '2.0'; Scope = 'User' }
        $startedAtUtc = [datetime]'2026-07-21T12:00:00Z'
        $endedAtUtc = [datetime]'2026-07-21T12:00:08Z'
        $res = [pscustomobject]@{ ExitCode = 123; DisplayCommand = 'winget upgrade --id Fail.App --exact'; StartedAtUtc = $startedAtUtc; EndedAtUtc = $endedAtUtc; StandardOutput = 'Mock stdout'; StandardError = 'Mock stderr'; LogPath = 'C:\log.txt' }
        Add-WingetUpdaterSessionFailure -Registry $registry -Package $pkg -Result $res

        $failures = Get-WingetUpdaterSessionFailures -Registry $registry
        $contextFile = New-WingetUpdaterRepairContextFile -Directory $testDir -Failures $failures

        (Test-Path -LiteralPath $contextFile -PathType Leaf) | Should -BeTrue
        $content = Get-Content -LiteralPath $contextFile -Raw -Encoding UTF8
        $content | Should -Match 'Fail\.App'
        $content | Should -Match 'Command Line: winget upgrade --id Fail\.App --exact'
        $content | Should -Match ([regex]::Escape($startedAtUtc.ToString('o')))
        $content | Should -Match ([regex]::Escape($endedAtUtc.ToString('o')))
        $content | Should -Match 'Mock stdout'
        $content | Should -Match 'Mock stderr'

        $prompt = Get-WingetUpdaterAIPrompt -ContextFilePath $contextFile
        $prompt.Contains($contextFile) | Should -BeTrue
    }

    It 'resolves only an existing absolute Application path for supported AI CLIs' {
        Mock -CommandName Get-Command -ModuleName WingetUpdater.Core -MockWith {
            @(
                [pscustomobject]@{ CommandType = 'ExternalScript'; Source = 'C:\Tools\codex.ps1' },
                [pscustomobject]@{ CommandType = 'Application'; Source = 'C:\Tools\codex.cmd' }
            )
        }
        Mock -CommandName Test-Path -ModuleName WingetUpdater.Core -MockWith { $true }

        Resolve-WingetUpdaterAICliPath -CliName 'codex' | Should -BeExactly 'C:\Tools\codex.cmd'
    }

    It 'rejects relative, missing, and unsupported AI CLI command paths' {
        Mock -CommandName Get-Command -ModuleName WingetUpdater.Core -MockWith {
            [pscustomobject]@{ CommandType = 'Application'; Source = 'codex.cmd' }
        }
        Mock -CommandName Test-Path -ModuleName WingetUpdater.Core -MockWith { $false }

        Resolve-WingetUpdaterAICliPath -CliName 'codex' | Should -BeNullOrEmpty
        { Resolve-WingetUpdaterAICliPath -CliName 'gemini' } | Should -Throw '*Unsupported AI CLI*'
    }

    It 'opens a cmd shim through a trusted command processor with an empty start title' {
        Mock -CommandName Test-Path -ModuleName WingetUpdater.Core -MockWith { $true }
        Mock -CommandName Start-Process -ModuleName WingetUpdater.Core -MockWith { }

        Start-WingetUpdaterAICliProcess `
            -CliPath 'C:\Tools & Apps\codex.cmd' `
            -CommandProcessorPath 'C:\Windows\System32\cmd.exe'

        Should -Invoke -CommandName Start-Process -ModuleName WingetUpdater.Core -Times 1 -ParameterFilter {
            $FilePath -eq 'C:\Windows\System32\cmd.exe' -and
            $ArgumentList -match '/d\s+/c\s+start\s+""\s+"C:\\Tools & Apps\\codex\.cmd"' -and
            -not $PSBoundParameters.ContainsKey('Verb')
        }
    }

    It 'opens an executable AI CLI directly without an intermediate command string' {
        Mock -CommandName Test-Path -ModuleName WingetUpdater.Core -MockWith { $true }
        Mock -CommandName Start-Process -ModuleName WingetUpdater.Core -MockWith { }

        Start-WingetUpdaterAICliProcess -CliPath 'C:\Tools\agy.exe'

        Should -Invoke -CommandName Start-Process -ModuleName WingetUpdater.Core -Times 1 -ParameterFilter {
            $FilePath -eq 'C:\Tools\agy.exe' -and -not $PSBoundParameters.ContainsKey('Verb')
        }
    }
}

Describe 'WingetUpdater.ps1 storage integration' {
    BeforeAll {
        $scriptFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetUpdater.ps1'
        $scriptText = [System.IO.File]::ReadAllText($scriptFile)
    }

    It 'initializes and uses the shared LocalAppData path model' {
        $scriptText | Should -Match '\$Script:Paths\s*=\s*Get-WingetUpdaterPaths'
        $scriptText | Should -Match '\$Script:StorageInitialization\s*=\s*Initialize-WingetUpdaterStorage'
        $scriptText | Should -Match '\$Script:SkipFile\s*=\s*\$Script:Paths\.SkipListFile'
        $scriptText | Should -Match 'New-WingetUpdaterRepairContextFile\s+-Directory\s+\$Script:Paths\.RepairContextsDirectory'
        $scriptText | Should -Match '\$Script:MockFile\s*=\s*\$Script:Paths\.MockStateFile'
        $scriptText | Should -Not -Match 'Join-Path \$Script:AppDir ''skip-list\.json'''
        $scriptText | Should -Not -Match 'Join-Path \$Script:AppDir ''repair-contexts'''
    }

    It 'routes skip-list and Mock JSON writes through atomic core persistence' {
        $scriptText | Should -Match 'Write-WingetUpdaterSkipList\s+-Path\s+\$Script:SkipFile'
        $scriptText | Should -Match 'Write-WingetUpdaterJson\s+-Path\s+\$Script:MockFile'
        $scriptText | Should -Not -Match 'Set-Content\s+-LiteralPath\s+\$Script:SkipFile'
        $scriptText | Should -Not -Match 'Set-Content\s+-LiteralPath\s+\$Script:MockFile'
    }

    It 'uses the validated JSON reader for every Mock state read' {
        ([regex]::Matches($scriptText, 'Read-WingetUpdaterJson\s+-Path\s+\$Script:MockFile')).Count |
            Should -Be 2
        $scriptText | Should -Not -Match 'Get-Content\s+-LiteralPath\s+\$Script:MockFile'
    }
}

Describe 'Release Package Manifest' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $releaseWorkflowPath = Join-Path $root '.github/workflows/release.yml'
        $ciWorkflowPath = Join-Path $root '.github/workflows/ci.yml'
        $releaseWorkflow = [System.IO.File]::ReadAllText($releaseWorkflowPath)
        $ciWorkflow = [System.IO.File]::ReadAllText($ciWorkflowPath)
        $whitelist = @(
            'Start.bat',
            'WingetUpdater.ps1',
            'WingetUpdater.Core.psm1',
            'README.md',
            'CHANGELOG.md',
            'LICENSE'
        )
        $getYamlBlocks = {
            param(
                [string]$Text,
                [int]$Indent,
                [string]$Key
            )

            $pattern = '(?m)^' + (' ' * $Indent) + [regex]::Escape($Key) +
                ':[^\r\n]*(?:\r?\n(?:' + (' ' * ($Indent + 2)) + '[^\r\n]*|[ \t]*$))*'
            [regex]::Matches($Text, $pattern) | ForEach-Object { $_ }
        }
        $getYamlChildBlocks = {
            param(
                [string]$Text,
                [int]$Indent
            )

            $pattern = '(?m)^' + (' ' * $Indent) + '(?<key>[A-Za-z_][A-Za-z0-9_-]*)' +
                ':[^\r\n]*(?:\r?\n(?:' + (' ' * ($Indent + 2)) + '[^\r\n]*|[ \t]*$))*'
            [regex]::Matches($Text, $pattern) | ForEach-Object { $_ }
        }
        $getWorkflowSteps = {
            param([string]$Text)

            foreach ($jobsBlock in @(& $getYamlBlocks $Text 0 'jobs')) {
                foreach ($stepsBlock in @(& $getYamlBlocks $jobsBlock.Value 4 'steps')) {
                    [regex]::Matches(
                        $stepsBlock.Value,
                        '(?m)^ {6}-[^\r\n]*(?:\r?\n(?: {8,}[^\r\n]*|[ \t]*$))*'
                    ) | ForEach-Object { $_ }
                }
            }
        }
        $getRunCommandText = {
            param([System.Text.RegularExpressions.Match]$RunBlock)

            $lines = [regex]::Split($RunBlock.Value, '\r?\n')
            $header = [regex]::Match($lines[0], '^ {8}run:[ \t]*(?<value>.*)$')
            $value = $header.Groups['value'].Value.Trim()
            if ($value -match '^[|>][+-]?(?:[ \t]+#.*)?$') {
                $bodyLines = @(
                    foreach ($line in @($lines | Select-Object -Skip 1)) {
                        if ($line.StartsWith('          ')) {
                            $line.Substring(10)
                        }
                        else {
                            $line
                        }
                    }
                )
                return ($bodyLines -join "`n")
            }

            if ($value.Length -ge 2 -and $value[0] -eq "'" -and $value[$value.Length - 1] -eq "'") {
                return $value.Substring(1, $value.Length - 2).Replace("''", "'")
            }
            if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') {
                return $value.Substring(1, $value.Length - 2).Replace('\"', '"')
            }
            return $value
        }
        $getTagAssignments = {
            param([string]$CommandText)

            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseInput(
                $CommandText,
                [ref]$tokens,
                [ref]$parseErrors
            )
            $ast.FindAll({
                param($node)

                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Operator -eq [System.Management.Automation.Language.TokenKind]::Equals -and
                    $node.Left.Extent.Text.Trim() -ieq '$tag' -and
                    $node.Right.Extent.Text.Trim() -ieq '$env:RELEASE_TAG'
            }, $true)
        }
    }

    It 'builds a release ZIP containing exactly the required root entries' {
        $root = Split-Path -Parent $PSScriptRoot
        foreach ($file in $whitelist) {
            $path = Join-Path $root $file
            (Test-Path -LiteralPath $path -PathType Leaf) | Should -BeTrue
        }

        $manifestMatch = [regex]::Match($releaseWorkflow, '(?s)\$files\s*=\s*@\((?<body>.*?)\r?\n\s*\)')
        $manifestMatch.Success | Should -BeTrue
        $workflowFiles = @([regex]::Matches($manifestMatch.Groups['body'].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $workflowFiles | Should -Be $whitelist

        $staging = Join-Path $TestDrive 'release-staging'
        [void](New-Item -ItemType Directory -Path $staging -Force)
        foreach ($file in $workflowFiles) {
            Copy-Item -LiteralPath (Join-Path $root $file) -Destination $staging
        }
        $zipPath = Join-Path $TestDrive 'WingetUpdater-v1.1.0.zip'
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -Force
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $entries = @($archive.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | ForEach-Object FullName | Sort-Object)
        }
        finally {
            $archive.Dispose()
        }
        $entries | Should -Be @($whitelist | Sort-Object)
        @($entries | Where-Object { $_ -match '(^|/)(tests?|logs?|repair-contexts|\.kilo)(/|$)' }).Count | Should -Be 0
    }

    It 'pins modules, imports Pester explicitly, and runs both analysis and tests in both Windows shells' {
        $ciWorkflow | Should -Match 'shell:\s*\[pwsh, powershell\]'
        $ciWorkflow | Should -Match 'Pester\s+-RequiredVersion\s+6\.0\.1'
        $ciWorkflow | Should -Match 'PSScriptAnalyzer\s+-RequiredVersion\s+1\.25\.0'
        $ciWorkflow | Should -Match 'Import-Module\s+Pester\s+-RequiredVersion\s+6\.0\.1'
        $ciWorkflow | Should -Match 'Import-Module\s+PSScriptAnalyzer\s+-RequiredVersion\s+1\.25\.0'
        $ciWorkflow | Should -Match 'Invoke-ScriptAnalyzer'
        $ciWorkflow | Should -Match 'Invoke-Pester'
    }

    It 'requires an annotated SemVer tag, version consistency, complete gates, and provenance before publishing' {
        $releaseWorkflow | Should -Match "\^v\(\[0-9\]\+\)\\\.\(\[0-9\]\+\)\\\.\(\[0-9\]\+\)\$"
        $releaseWorkflow | Should -Match 'git\s+cat-file\s+-t'
        $releaseWorkflow | Should -Match "-ne\s+'tag'"
        $releaseWorkflow | Should -Match 'git\s+fetch\s+--no-tags\s+origin\s+main:refs/remotes/origin/main'
        $releaseWorkflow | Should -Match 'git\s+merge-base\s+--is-ancestor\s+\$tagCommit\s+origin/main'
        $releaseWorkflow | Should -Match 'README\.md'
        $releaseWorkflow | Should -Match 'CHANGELOG\.md'
        $releaseWorkflow | Should -Match 'WingetUpdater\.ps1'
        $releaseWorkflow | Should -Match '\\d\{4\}-\\d\{2\}-\\d\{2\}'
        $releaseWorkflow | Should -Match 'matrix:'
        $releaseWorkflow | Should -Match 'shell:\s*\[pwsh, powershell\]'
        $releaseWorkflow | Should -Match 'Invoke-ScriptAnalyzer'
        $releaseWorkflow | Should -Match 'Invoke-Pester'
        $releaseSteps = @(& $getWorkflowSteps $releaseWorkflow)
        $releaseActionReferences = @(
            foreach ($step in $releaseSteps) {
                [regex]::Matches(
                    $step.Value,
                    '(?m)^(?: {6}-[ \t]*| {8})uses:[ \t]*(?<reference>[^\s#]+)(?:[ \t]+#.*)?[ \t]*$'
                ) | ForEach-Object { $_ }
            }
        )
        @($releaseActionReferences | Where-Object {
            $_.Groups['reference'].Value -match '^actions/attest@[0-9a-f]{40}$'
        }).Count | Should -Be 1
        @($releaseActionReferences | Where-Object {
            $_.Groups['reference'].Value -match '^actions/attest-build-provenance@'
        }).Count | Should -Be 0
        $releaseWorkflow | Should -Match 'attestations:\s*write'
        $releaseWorkflow | Should -Match 'id-token:\s*write'

        $jobsBlocks = @(& $getYamlBlocks $releaseWorkflow 0 'jobs')
        $jobsBlocks.Count | Should -Be 1
        $publishJobs = @(& $getYamlBlocks $jobsBlocks[0].Value 2 'publish')
        $publishJobs.Count | Should -Be 1
        $publishPermissions = @(& $getYamlBlocks $publishJobs[0].Value 4 'permissions')
        $publishPermissions.Count | Should -Be 1
        $artifactMetadata = [regex]::Matches(
            $publishPermissions[0].Value,
            '(?m)^ {6}artifact-metadata[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
        )
        $artifactMetadata.Count | Should -Be 1
        $artifactMetadata[0].Groups['value'].Value.Trim() | Should -Be 'write'
    }

    It 'builds the ZIP with deterministic entry order and tag-derived timestamps' {
        $releaseWorkflow | Should -Not -Match 'Compress-Archive'
        $releaseWorkflow | Should -Match 'ZipArchiveMode\]::Create'
        $releaseWorkflow | Should -Match 'git\s+show\s+-s\s+--format=%ct\s+HEAD'
        $releaseWorkflow | Should -Match '\.LastWriteTime\s*=\s*\$releaseTimestamp'
        $releaseWorkflow | Should -Match '\$files\s*\|\s*Sort-Object'
    }

    It 'uploads all assets to a draft before publishing the immutable release' {
        $draftIndex = $releaseWorkflow.IndexOf('draft: true')
        $publishIndex = $releaseWorkflow.IndexOf('gh release edit')

        $draftIndex | Should -BeGreaterOrEqual 0
        $publishIndex | Should -BeGreaterThan $draftIndex
        $releaseWorkflow | Should -Match 'gh\s+release\s+edit[^\r\n]+--draft=false[^\r\n]+--latest'
        $releaseWorkflow | Should -Match 'GH_TOKEN:\s*\$\{\{\s*github\.token\s*\}\}'
    }

    It 'inspects release state before mutating immutable publication' {
        $releaseSteps = @(& $getWorkflowSteps $releaseWorkflow)
        $releaseStateSteps = @($releaseSteps | Where-Object {
            $_.Value -match '(?m)^ {8}id:[ \t]*release-state[ \t]*$'
        })
        $releaseStateSteps.Count | Should -Be 1
        $releaseStateSteps[0].Value | Should -Match '(?m)^ {6}-[ \t]*name:[ \t]*Inspect existing release[ \t]*$'
        $releaseStateEnvBlocks = @(& $getYamlBlocks $releaseStateSteps[0].Value 8 'env')
        $releaseStateEnvBlocks.Count | Should -Be 1
        foreach ($expectedEnvironment in @(
            [pscustomobject]@{ Name = 'GH_TOKEN'; Value = '${{ github.token }}' },
            [pscustomobject]@{ Name = 'RELEASE_TAG'; Value = '${{ github.ref_name }}' },
            [pscustomobject]@{ Name = 'REPOSITORY'; Value = '${{ github.repository }}' }
        )) {
            $declarations = [regex]::Matches(
                $releaseStateEnvBlocks[0].Value,
                ('(?m)^ {10}' + [regex]::Escape($expectedEnvironment.Name) +
                    '[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$')
            )
            $declarations.Count | Should -Be 1
            $declarations[0].Groups['value'].Value.Trim() | Should -Be $expectedEnvironment.Value
        }

        $releaseStateIndex = $releaseWorkflow.IndexOf($releaseStateSteps[0].Value)
        foreach ($stepName in @(
            'Attest release artifacts',
            'Upload draft release assets',
            'Publish immutable GitHub Release'
        )) {
            $gatedSteps = @($releaseSteps | Where-Object {
                $_.Value -match ('(?m)^ {6}-[ \t]*name:[ \t]*' + [regex]::Escape($stepName) + '[ \t]*$')
            })
            $gatedSteps.Count | Should -Be 1
            $releaseWorkflow.IndexOf($gatedSteps[0].Value) | Should -BeGreaterThan $releaseStateIndex
            $ifDeclarations = [regex]::Matches(
                $gatedSteps[0].Value,
                '(?m)^ {8}if:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
            )
            $ifDeclarations.Count | Should -Be 1
            $ifDeclarations[0].Groups['value'].Value.Trim() |
                Should -Be "steps.release-state.outputs.state != 'published'"
        }

        $releaseActionSteps = @($releaseSteps | Where-Object {
            $_.Value -match '(?m)^(?: {6}-[ \t]*| {8})uses:[ \t]*softprops/action-gh-release@'
        })
        $releaseActionSteps.Count | Should -Be 1
        $releaseActionWithBlocks = @(& $getYamlBlocks $releaseActionSteps[0].Value 8 'with')
        $releaseActionWithBlocks.Count | Should -Be 1
        $releaseNoteSettings = [regex]::Matches(
            $releaseActionWithBlocks[0].Value,
            '(?m)^ {10}generate_release_notes[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
        )
        $releaseNoteSettings.Count | Should -Be 1
        $releaseNoteSettings[0].Groups['value'].Value.Trim() |
            Should -Be "`${{ steps.release-state.outputs.state == 'missing' }}"
    }

    It 'verifies an existing published release before treating publication as complete' {
        $releaseSteps = @(& $getWorkflowSteps $releaseWorkflow)
        $releaseStateSteps = @($releaseSteps | Where-Object {
            $_.Value -match '(?m)^ {8}id:[ \t]*release-state[ \t]*$'
        })
        $releaseStateSteps.Count | Should -Be 1
        $runBlocks = @(& $getYamlBlocks $releaseStateSteps[0].Value 8 'run')
        $runBlocks.Count | Should -Be 1
        $commandText = & $getRunCommandText $runBlocks[0]

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $commandText,
            [ref]$tokens,
            [ref]$parseErrors
        )
        @($parseErrors).Count | Should -Be 0
        $commands = @($ast.FindAll({
            param($node)

            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true))
        $commandLines = @($commands | ForEach-Object { $_.Extent.Text.Trim() })

        $tagQueries = @($commandLines | Where-Object {
            $_ -match '(?i)^gh(?:\.exe)?[ \t]+api\b' -and
                $_ -match 'repos/\$env:REPOSITORY/releases/tags/\$env:RELEASE_TAG'
        })
        $tagQueries.Count | Should -Be 1
        $draftQueries = @($commandLines | Where-Object {
            $_ -match '(?i)^gh(?:\.exe)?[ \t]+api\b' -and
                $_ -match '--paginate\b' -and
                $_ -match 'repos/\$env:REPOSITORY/releases\?per_page=100'
        })
        $draftQueries.Count | Should -Be 1
        $commandText | Should -Match '(?i)HTTP[ \t]+404'
        $commandText | Should -Match '(?i)Not[ \t]+Found'
        $commandText | Should -Match '(?i)throw\b'
        $commandText | Should -Match '(?i)\$release\.draft\s*-eq\s*\$true'

        $stateWrites = @($commandLines | Where-Object {
            $_ -match '(?i)^Add-Content\b' -and $_ -match '\$env:GITHUB_OUTPUT\b'
        })
        $stateWrites.Count | Should -Be 3
        $states = @(
            foreach ($stateWrite in $stateWrites) {
                $stateMatch = [regex]::Match($stateWrite, '(?i)state=(?<state>missing|draft|published)')
                $stateMatch.Success | Should -BeTrue
                $stateMatch.Groups['state'].Value.ToLowerInvariant()
            }
        )
        @($states | Sort-Object) | Should -Be @('draft', 'missing', 'published')

        $downloads = @($commandLines | Where-Object {
            $_ -match '(?i)^gh(?:\.exe)?[ \t]+release[ \t]+download\b'
        })
        $downloads.Count | Should -Be 1
        $downloads[0] | Should -Match '\$env:RELEASE_TAG\b'
        $downloads[0] | Should -Match '--repo[ \t]+\$env:REPOSITORY\b'
        $downloads[0] | Should -Match '--dir[ \t]+\$verificationDirectory\b'
        $downloads[0] | Should -Match '--clobber\b'
        ([regex]::Matches($downloads[0], '--pattern\b')).Count | Should -Be 2
        $downloads[0] | Should -Match '--pattern[ \t]+(?:''|")?SHA256SUMS(?:''|")?\b'
        $downloads[0] | Should -Match '--pattern[ \t]+\$expectedZip\b'

        $commandText | Should -Match '\$env:RUNNER_TEMP\b'
        $commandText | Should -Match '(?i)New-Item\b[^\r\n]*-ItemType[ \t]+Directory'
        $commandText | Should -Match '(?i)Compare-Object\b[^\r\n]*-ReferenceObject[ \t]+\$expectedNames\b[^\r\n]*-DifferenceObject[ \t]+\$releaseAssetNames\b'
        $commandText | Should -Match '(?i)Compare-Object\b[^\r\n]*-ReferenceObject[ \t]+\$expectedNames\b[^\r\n]*-DifferenceObject[ \t]+\$downloadedNames\b'
        $commandText | Should -Match '\[0-9a-fA-F\]\{64\}'
        $commandText | Should -Match '(?i)\$checksumMatch\.Groups\[[''"]filename[''"]\]\.Value\s*-cne\s*\$expectedZip'
        $commandText | Should -Match '(?i)Get-FileHash\b[^\r\n]*-Algorithm[ \t]+SHA256'

        $downloadIndex = $commandText.IndexOf($downloads[0])
        $hashIndex = $commandText.IndexOf('Get-FileHash')
        $publishedIndex = $commandText.IndexOf('state=published')
        $downloadIndex | Should -BeGreaterOrEqual 0
        $hashIndex | Should -BeGreaterThan $downloadIndex
        $publishedIndex | Should -BeGreaterThan $hashIndex
    }

    It 'normalizes both published release hashes before checksum comparison' {
        $releaseSteps = @(& $getWorkflowSteps $releaseWorkflow)
        $releaseStateSteps = @($releaseSteps | Where-Object {
            $_.Value -match '(?m)^ {8}id:[ \t]*release-state[ \t]*$'
        })
        $releaseStateSteps.Count | Should -Be 1
        $runBlocks = @(& $getYamlBlocks $releaseStateSteps[0].Value 8 'run')
        $runBlocks.Count | Should -Be 1
        $commandText = & $getRunCommandText $runBlocks[0]

        $commandText | Should -Match '(?m)^[ \t]*\$expectedHash\s*=\s*\$checksumMatch\.Groups\[[''"]hash[''"]\]\.Value\.ToLowerInvariant\(\)[ \t]*$'
        $commandText | Should -Match '(?m)^[ \t]*\$actualHash\s*=\s*\(Get-FileHash\b[^\r\n]*-Algorithm[ \t]+SHA256\)\.Hash\.ToLowerInvariant\(\)[ \t]*$'
        $hashComparisons = [regex]::Matches(
            $commandText,
            '(?mi)^[ \t]*if[ \t]*\([ \t]*\$actualHash[ \t]+-ne[ \t]+\$expectedHash[ \t]*\)[ \t]*\{'
        )
        $hashComparisons.Count | Should -Be 1
        $commandText | Should -Not -Match '(?i)\$actualHash\s+-cne\s+'
        $commandText.IndexOf('state=published') | Should -BeGreaterThan $hashComparisons[0].Index
    }

    It 'matches both published assets to the current validated release bundle' {
        $releaseSteps = @(& $getWorkflowSteps $releaseWorkflow)
        $releaseStateSteps = @($releaseSteps | Where-Object {
            $_.Value -match '(?m)^ {8}id:[ \t]*release-state[ \t]*$'
        })
        $releaseStateSteps.Count | Should -Be 1
        $runBlocks = @(& $getYamlBlocks $releaseStateSteps[0].Value 8 'run')
        $runBlocks.Count | Should -Be 1
        $commandText = & $getRunCommandText $runBlocks[0]

        $commandText | Should -Match '(?m)^[ \t]*\$currentZipPath\s*=\s*Join-Path[ \t]+release[ \t]+\$expectedZip[ \t]*$'
        $commandText | Should -Match '(?m)^[ \t]*\$currentZipHash\s*=\s*\(Get-FileHash[ \t]+-LiteralPath[ \t]+\$currentZipPath[ \t]+-Algorithm[ \t]+SHA256\)\.Hash\.ToLowerInvariant\(\)[ \t]*$'
        $zipComparisons = [regex]::Matches(
            $commandText,
            '(?mi)^[ \t]*if[ \t]*\([ \t]*\$actualHash[ \t]+-ne[ \t]+\$currentZipHash[ \t]*\)[ \t]*\{'
        )
        $zipComparisons.Count | Should -Be 1

        $commandText | Should -Match '(?m)^[ \t]*\$currentChecksumPath\s*=\s*Join-Path[ \t]+release[ \t]+(?:''|")SHA256SUMS(?:''|")[ \t]*$'
        $commandText | Should -Match '(?m)^[ \t]*\$currentChecksumHash\s*=\s*\(Get-FileHash[ \t]+-LiteralPath[ \t]+\$currentChecksumPath[ \t]+-Algorithm[ \t]+SHA256\)\.Hash\.ToLowerInvariant\(\)[ \t]*$'
        $commandText | Should -Match '(?m)^[ \t]*\$publishedChecksumHash\s*=\s*\(Get-FileHash[ \t]+-LiteralPath[ \t]+\$checksumPath[ \t]+-Algorithm[ \t]+SHA256\)\.Hash\.ToLowerInvariant\(\)[ \t]*$'
        $checksumComparisons = [regex]::Matches(
            $commandText,
            '(?mi)^[ \t]*if[ \t]*\([ \t]*\$publishedChecksumHash[ \t]+-ne[ \t]+\$currentChecksumHash[ \t]*\)[ \t]*\{'
        )
        $checksumComparisons.Count | Should -Be 1

        $publishedIndex = $commandText.IndexOf('state=published')
        $publishedIndex | Should -BeGreaterThan $zipComparisons[0].Index
        $publishedIndex | Should -BeGreaterThan $checksumComparisons[0].Index
    }

    It 'keeps every GitHub Action pinned to a full commit SHA' {
        $actionReferences = [regex]::Matches($ciWorkflow + "`n" + $releaseWorkflow, 'uses:\s*[^\s]+@(?<ref>[^\s#]+)')
        $actionReferences.Count | Should -BeGreaterThan 0
        foreach ($reference in $actionReferences) {
            $reference.Groups['ref'].Value | Should -Match '^[0-9a-f]{40}$'
        }
    }

    It 'pins the current Node.js 24 release actions to verified commits' {
        $expectedActions = @(
            [pscustomobject]@{
                Name = 'actions/upload-artifact'
                Reference = 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a'
            },
            [pscustomobject]@{
                Name = 'actions/download-artifact'
                Reference = 'actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c'
            },
            [pscustomobject]@{
                Name = 'actions/attest'
                Reference = 'actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6'
            },
            [pscustomobject]@{
                Name = 'softprops/action-gh-release'
                Reference = 'softprops/action-gh-release@3d0d9888cb7fd7b750713d6e236d1fcb99157228'
            }
        )
        $releaseSteps = @(& $getWorkflowSteps $releaseWorkflow)
        $releaseActionReferences = @(
            foreach ($step in $releaseSteps) {
                [regex]::Matches(
                    $step.Value,
                    '(?m)^(?: {6}-[ \t]*| {8})uses:[ \t]*(?<reference>[^\s#]+)(?:[ \t]+#.*)?[ \t]*$'
                ) | ForEach-Object { $_ }
            }
        )

        foreach ($action in $expectedActions) {
            $occurrences = @($releaseActionReferences | Where-Object {
                $_.Groups['reference'].Value -match ('^' + [regex]::Escape($action.Name) + '@')
            })
            $occurrences.Count | Should -Be 1
            $occurrences[0].Groups['reference'].Value | Should -Be $action.Reference
        }
    }

    It 'bounds workflow execution and does not persist checkout credentials' {
        $workflowExpectations = @(
            [pscustomobject]@{ Text = $ciWorkflow; CancelInProgress = 'true' },
            [pscustomobject]@{ Text = $releaseWorkflow; CancelInProgress = 'false' }
        )
        foreach ($workflow in $workflowExpectations) {
            $concurrencyBlocks = [regex]::Matches(
                $workflow.Text,
                '(?m)^concurrency:[^\r\n]*(?:\r?\n(?:[ \t]+[^\r\n]*|[ \t]*$))*'
            )
            $concurrencyBlocks.Count | Should -Be 1
            $cancelDeclarations = [regex]::Matches(
                $concurrencyBlocks[0].Value,
                '(?m)^  cancel-in-progress[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
            )
            $cancelDeclarations.Count | Should -Be 1
            $cancelDeclarations[0].Groups['value'].Value.Trim() | Should -Be $workflow.CancelInProgress
        }

        $ciJobsBlocks = @(& $getYamlBlocks $ciWorkflow 0 'jobs')
        $ciJobsBlocks.Count | Should -Be 1
        $ciJobs = @(& $getYamlChildBlocks $ciJobsBlocks[0].Value 2)
        $ciJobs.Count | Should -BeGreaterThan 0
        foreach ($ciJob in $ciJobs) {
            $ciTimeouts = [regex]::Matches(
                $ciJob.Value,
                '(?m)^ {4}timeout-minutes[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
            )
            $ciTimeouts.Count | Should -Be 1
            $ciTimeouts[0].Groups['value'].Value.Trim() | Should -Be '20'
        }

        $releaseJobsBlocks = @(& $getYamlBlocks $releaseWorkflow 0 'jobs')
        $releaseJobsBlocks.Count | Should -Be 1
        $releaseJobs = @(& $getYamlChildBlocks $releaseJobsBlocks[0].Value 2)
        $releaseJobs.Count | Should -BeGreaterThan 0
        foreach ($releaseJob in $releaseJobs) {
            $jobTimeouts = [regex]::Matches(
                $releaseJob.Value,
                '(?m)^ {4}timeout-minutes[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
            )
            $jobTimeouts.Count | Should -Be 1
            $jobTimeouts[0].Groups['value'].Value.Trim() | Should -Match '^(10|20)$'
        }

        foreach ($workflow in @($ciWorkflow, $releaseWorkflow)) {
            $stepBlocks = @(& $getWorkflowSteps $workflow)
            $checkoutSteps = @($stepBlocks | Where-Object {
                $_.Value -match '(?m)^(?: {6}-[ \t]*| {8})uses:[ \t]*actions/checkout@'
            })
            $checkoutSteps.Count | Should -BeGreaterThan 0
            foreach ($checkoutStep in $checkoutSteps) {
                $withBlocks = @(& $getYamlBlocks $checkoutStep.Value 8 'with')
                $withBlocks.Count | Should -Be 1
                $credentialDeclarations = [regex]::Matches(
                    $withBlocks[0].Value,
                    '(?m)^ {10}persist-credentials[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
                )
                $credentialDeclarations.Count | Should -Be 1
                $credentialDeclarations[0].Groups['value'].Value.Trim() |
                    Should -Match '^(?i:false|''false''|"false")$'
            }
        }
    }

    It 'isolates GitHub context from release PowerShell scripts and validates asset globs' {
        $releaseSteps = @(& $getWorkflowSteps $releaseWorkflow)
        $releaseSteps.Count | Should -BeGreaterThan 0
        $releaseRunBlocks = @(
            foreach ($step in $releaseSteps) {
                @(& $getYamlBlocks $step.Value 8 'run')
            }
        )
        $releaseRunBlocks.Count | Should -BeGreaterThan 0
        foreach ($runBlock in $releaseRunBlocks) {
            $runBlock.Value | Should -Not -Match '\$\{\{[ \t]*github\.(?:ref_name|repository)[ \t]*\}\}'
        }
        $tagAssignments = @(
            foreach ($runBlock in $releaseRunBlocks) {
                $commandText = & $getRunCommandText $runBlock
                @(& $getTagAssignments $commandText)
            }
        )
        $tagAssignments.Count | Should -Be 2

        $releaseEnvBlocks = @(
            foreach ($step in $releaseSteps) {
                @(& $getYamlBlocks $step.Value 8 'env')
            }
        )
        $releaseTagDeclarations = @(
            foreach ($envBlock in $releaseEnvBlocks) {
                [regex]::Matches(
                    $envBlock.Value,
                    '(?m)^ {10}RELEASE_TAG[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
                ) | ForEach-Object { $_ }
            }
        )
        $repositoryDeclarations = @(
            foreach ($envBlock in $releaseEnvBlocks) {
                [regex]::Matches(
                    $envBlock.Value,
                    '(?m)^ {10}REPOSITORY[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
                ) | ForEach-Object { $_ }
            }
        )
        $releaseTagDeclarations.Count | Should -Be 4
        $repositoryDeclarations.Count | Should -Be 2
        foreach ($declaration in $releaseTagDeclarations) {
            $declaration.Groups['value'].Value.Trim() | Should -Be '${{ github.ref_name }}'
        }
        $repositoryDeclarations[0].Groups['value'].Value.Trim() |
            Should -Be '${{ github.repository }}'

        foreach ($stepName in @(
            'Verify annotated tag and version consistency',
            'Build and verify release archive'
        )) {
            $tagSteps = @($releaseSteps | Where-Object {
                $_.Value -match ('(?m)^ {6}-[ \t]*name:[ \t]*' + [regex]::Escape($stepName) + '[ \t]*$')
            })
            $tagSteps.Count | Should -Be 1
            $tagRunBlocks = @(& $getYamlBlocks $tagSteps[0].Value 8 'run')
            $tagRunBlocks.Count | Should -Be 1
            $tagCommandText = & $getRunCommandText $tagRunBlocks[0]
            @(& $getTagAssignments $tagCommandText).Count | Should -Be 1
            $tagEnvBlocks = @(& $getYamlBlocks $tagSteps[0].Value 8 'env')
            $tagEnvBlocks.Count | Should -Be 1
            $tagEnvDeclarations = [regex]::Matches(
                $tagEnvBlocks[0].Value,
                '(?m)^ {10}RELEASE_TAG[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
            )
            $tagEnvDeclarations.Count | Should -Be 1
            $tagEnvDeclarations[0].Groups['value'].Value.Trim() |
                Should -Be '${{ github.ref_name }}'
        }

        $publishSteps = @($releaseSteps | Where-Object {
            $_.Value -match '(?m)^ {6}-[ \t]*name:[ \t]*Publish immutable GitHub Release[ \t]*$'
        })
        $publishSteps.Count | Should -Be 1
        $publishRunBlocks = @(& $getYamlBlocks $publishSteps[0].Value 8 'run')
        $publishRunBlocks.Count | Should -Be 1
        $publishEnvBlocks = @(& $getYamlBlocks $publishSteps[0].Value 8 'env')
        $publishEnvBlocks.Count | Should -Be 1
        $publishTagDeclarations = [regex]::Matches(
            $publishEnvBlocks[0].Value,
            '(?m)^ {10}RELEASE_TAG[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
        )
        $publishTagDeclarations.Count | Should -Be 1
        $publishTagDeclarations[0].Groups['value'].Value.Trim() |
            Should -Be '${{ github.ref_name }}'
        $publishRepositoryDeclarations = [regex]::Matches(
            $publishEnvBlocks[0].Value,
            '(?m)^ {10}REPOSITORY[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
        )
        $publishRepositoryDeclarations.Count | Should -Be 1
        $publishRepositoryDeclarations[0].Groups['value'].Value.Trim() |
            Should -Be '${{ github.repository }}'
        $publishCommandText = & $getRunCommandText $publishRunBlocks[0]
        $publishCommand = [regex]::Match(
            $publishCommandText,
            '(?mi)^[ \t]*(?:&[ \t]+)?gh(?:\.exe)?[ \t]+release[ \t]+edit\b[^\r\n]*$'
        )
        $publishCommand.Success | Should -BeTrue
        $publishCommand.Value | Should -Match '\$env:RELEASE_TAG\b'
        $publishCommand.Value | Should -Match '\$env:REPOSITORY\b'

        $releaseActionSteps = @($releaseSteps | Where-Object {
            $_.Value -match '(?m)^(?: {6}-[ \t]*| {8})uses:[ \t]*softprops/action-gh-release@'
        })
        $releaseActionSteps.Count | Should -Be 1
        $releaseActionWithBlocks = @(& $getYamlBlocks $releaseActionSteps[0].Value 8 'with')
        $releaseActionWithBlocks.Count | Should -Be 1
        $unmatchedFileSettings = [regex]::Matches(
            $releaseActionWithBlocks[0].Value,
            '(?m)^ {10}fail_on_unmatched_files[ \t]*:[ \t]*(?<value>[^#\r\n]*?)(?:[ \t]*#.*)?$'
        )
        $unmatchedFileSettings.Count | Should -Be 1
        $unmatchedFileSettings[0].Groups['value'].Value.Trim() | Should -Be 'true'
    }

    It 'pins the native Node.js 24 checkout action to the verified v7 commit' {
        $verifiedCheckout = 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
        $ciWorkflow | Should -Match ([regex]::Escape($verifiedCheckout))
        ([regex]::Matches($releaseWorkflow, [regex]::Escape($verifiedCheckout))).Count | Should -Be 2
    }
}

Describe 'Public project metadata consistency' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $readmeText = [System.IO.File]::ReadAllText((Join-Path $root 'README.md'))
        $contributingText = [System.IO.File]::ReadAllText((Join-Path $root 'CONTRIBUTING.md'))
        $releasingText = [System.IO.File]::ReadAllText((Join-Path $root 'RELEASING.md'))
        $changelogText = [System.IO.File]::ReadAllText((Join-Path $root 'CHANGELOG.md'))
        $bugReportText = [System.IO.File]::ReadAllText((Join-Path $root '.github/ISSUE_TEMPLATE/bug_report.yml'))
        $editorConfigText = [System.IO.File]::ReadAllText((Join-Path $root '.editorconfig'))
        $gitAttributesText = [System.IO.File]::ReadAllText((Join-Path $root '.gitattributes'))
    }

    It 'documents the same pinned test and analyzer versions as CI' {
        foreach ($text in @($readmeText, $contributingText, $releasingText)) {
            $text | Should -Match 'Pester[^\r\n]*6\.0\.1'
            $text | Should -Match 'PSScriptAnalyzer[^\r\n]*1\.25\.0'
        }
    }

    It 'documents protected tags and immutable release publication' {
        $releasingText | Should -Match '(?i)release tags?.*protected|protected.*release tags?'
        $releasingText | Should -Match '(?i)immutable release'
        $releasingText | Should -Match '(?i)draft.*assets.*publish'
    }

    It 'keeps v1.1.0 as the current development or dated release section' {
        $changelogText | Should -Match '(?m)^## \[1\.1\.0\] - (?:Unreleased|\d{4}-\d{2}-\d{2})$'
    }

    It 'preserves published v1.0.1 and v1.0.2 history before v1.0.0' {
        $v11 = [regex]::Match($changelogText, '(?m)^## \[1\.1\.0\] - (?:Unreleased|\d{4}-\d{2}-\d{2})$').Index
        $v102 = $changelogText.IndexOf('## [1.0.2] - 2026-07-21')
        $v101 = $changelogText.IndexOf('## [1.0.1] - 2026-07-21')
        $v100 = $changelogText.IndexOf('## [1.0.0] - 2026-05-30')
        $v11 | Should -BeGreaterOrEqual 0
        $v102 | Should -BeGreaterThan $v11
        $v101 | Should -BeGreaterThan $v102
        $v100 | Should -BeGreaterThan $v101
        $changelogText | Should -Match '(?ms)^## \[1\.1\.0\].*?^### Improved$'
        $changelogText | Should -Match '(?ms)^## \[1\.1\.0\].*?^### Fixed$'
    }

    It 'does not instruct editors to rewrite the ASCII batch launcher as UTF-8' {
        $batchSection = [regex]::Match($editorConfigText, '(?ms)^\[\*\.\{bat,cmd\}\]\s*(?<body>.*?)(?=^\[|\z)')
        $batchSection.Success | Should -BeTrue
        $batchSection.Groups['body'].Value | Should -Not -Match '(?m)^charset\s*='
        $gitAttributesText | Should -Match '(?m)^\*\.bat\s+text\s+eol=crlf$'
        $gitAttributesText | Should -Match '(?m)^\*\.cmd\s+text\s+eol=crlf$'
    }

    It 'keeps every PowerShell source and test file as UTF-8 BOM with CRLF endings' {
        $powerShellFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
            $_.Extension -in @('.ps1', '.psm1', '.psd1')
        })
        $powerShellFiles.Count | Should -BeGreaterThan 0

        foreach ($file in $powerShellFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            @($bytes[0..2]) | Should -Be @(0xEF, 0xBB, 0xBF) -Because $file.FullName
            $text = (New-Object System.Text.UTF8Encoding($true, $true)).GetString($bytes)
            ($text -replace "`r`n", '') | Should -Not -Match "[`r`n]" -Because $file.FullName
        }
    }

    It 'collects bug reports only for the supported Windows 10 release line' {
        $bugReportText | Should -Match 'Windows 10'
        $bugReportText | Should -Not -Match 'Windows 11'
    }
}
