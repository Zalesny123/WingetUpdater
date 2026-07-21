#requires -Version 5.1
<#
.SYNOPSIS
    WingetUpdater - Narzędzie ułatwiające aktualizację pakietów za pomocą winget.
.AUTHOR
    Zalesny123
.COPYRIGHT
    Copyright (c) 2026 Zalesny123. Udostępniane na licencji MIT.
#>
# Dziala w Windows PowerShell 5.1 oraz PowerShell 7+ na Windows.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification = 'Private WinForms event helpers use application-oriented names.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This script is an interactive GUI; confirmation is handled by dialogs and winget installers.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Private helpers intentionally use collection-oriented names.')]
param (
    [switch]$LaunchedFromStartBat
)

Set-StrictMode -Version 2.0

if (-not $LaunchedFromStartBat) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Ten program musi byc uruchamiany wylacznie za pomoca pliku Start.bat.",
        "Blad uruchamiania",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$scriptPath = $null
$command = $MyInvocation.MyCommand
if ($null -ne $command -and ($command.PSObject.Properties.Name -contains 'Path')) {
    $scriptPath = $command.Path
}
if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    $scriptPath = Get-Variable -Name PSCommandPath -ValueOnly -ErrorAction SilentlyContinue
}
if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    $scriptPath = Join-Path (Get-Location) 'WingetUpdater.ps1'
}

$Script:AppDir = Split-Path -Parent $scriptPath
Import-Module -Name (Join-Path $Script:AppDir 'WingetUpdater.Core.psm1') -Force -DisableNameChecking -ErrorAction Stop
$Script:MutexLease = $null
$Script:ToolTip = $null
$Script:Form = $null
$Script:ClosePending = $false
$Script:CancellationState = New-WingetUpdaterCancellationState
$Script:CurrentWingetProcess = $null
$Script:SourceAgreementsAccepted = $false

function Dispose-WingetUpdaterResource {
    param(
        [AllowNull()][object]$Resource,
        [string]$ResourceName
    )

    if ($null -eq $Resource -or $Resource -isnot [System.IDisposable]) {
        return
    }

    try {
        $Resource.Dispose()
    }
    catch {
        Write-Verbose "Disposing $ResourceName failed: $($_.Exception.Message)"
    }
}

try {
    $currentUserSid = Get-WingetUpdaterCurrentUserSid
    $Script:MutexLease = Enter-WingetUpdaterSingleInstance -UserSid $currentUserSid
    if (-not $Script:MutexLease.IsFirstInstance) {
        [System.Windows.Forms.MessageBox]::Show(
            'Inna instancja programu jest juz uruchomiona dla tego uzytkownika.',
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        exit 0
    }

    $Script:Paths = Get-WingetUpdaterPaths
    $Script:StorageInitialization = Initialize-WingetUpdaterStorage -Paths $Script:Paths -LegacyAppDirectory $Script:AppDir
    $Script:StartupWarnings = @($Script:StorageInitialization.Warnings)
    $Script:SourceAgreementsAccepted = [bool]$Script:StorageInitialization.SourceAgreementsAccepted
    $Script:SkipFile = $Script:Paths.SkipListFile
    $Script:RepairDir = $Script:Paths.RepairContextsDirectory
    $Script:SkippedIds = @{}
    $Script:AttemptedUpdates = @{}
    $Script:UnresolvedFailures = New-WingetUpdaterSessionFailureRegistry
    $Script:SuccessfulAttemptResults = @{}
    $Script:WingetInfo = $null
    $Script:MinimumWingetVersion = [version]'1.4.0'
    $Script:IsBusy = $false
$Script:RefreshButton = $null
$Script:UpdateButton = $null
$Script:SaveButton = $null
$Script:LoadSkippedButton = $null
$Script:UpdateAllButton = $null
$Script:UpdateNoneButton = $null
$Script:SkipAllButton = $null
$Script:SkipNoneButton = $null
$Script:CopyMessageButton = $null
$Script:OpenAiCliButton = $null
$Script:CancelButton = $null
$Script:SilentCheck = $null
$Script:InteractiveCheck = $null
$Script:IncludeUnknownCheck = $null
$Script:AgentCombo = $null
$Script:ToolTip = $null
$Script:StatusLabel = $null
$Script:SpinnerLabel = $null
$Script:SpinnerFrames = @('-', '\', '|', '/')
$Script:SpinnerIndex = 0
$Script:LastSpinnerStep = [datetime]::MinValue
$Script:LogSpinnerActive = $false
$Script:LogLiveSpinner = ''
$Script:LogLiveProgress = ''
$Script:LogLiveLineStart = -1
$Script:LogLiveRenderedText = ''
$Script:LastLogLiveUpdate = [datetime]::MinValue
$Script:Grid = $null
$Script:LogBox = $null
$Script:MaxLogBoxCharacters = 200000
$Script:Form = $null
$Script:TestModeCheck = $null
$Script:TestDir = $Script:Paths.MockDirectory
$Script:MockFile = $Script:Paths.MockStateFile

function Reset-MockState {
    $data = [ordered]@{
        'Test.FirstOK' = @{ Name = 'Aplikacja Pierwsza'; Current = '1.0'; Available = '2.0'; ExitCode = 0; Ghost = $false }
        'Test.SecondOK' = @{ Name = 'Aplikacja Druga'; Current = '1.0'; Available = '2.0'; ExitCode = 0; Ghost = $false }
        'Test.SpotifyLike' = @{ Name = 'Aplikacja Spotify-podobna'; Current = '1.0'; Available = '2.0'; ExitCode = -1978335146; Ghost = $false }
        'Test.OperaLike' = @{ Name = 'Aplikacja Opera-podobna'; Current = '1.0'; Available = '2.0'; ExitCode = -1978335212; Ghost = $false }
        'Test.Uparty' = @{ Name = 'Aplikacja Uparta (Ghost)'; Current = '1.0'; Available = '2.0'; ExitCode = 0; Ghost = $true }
        'Test.UnknownVer' = @{ Name = 'Aplikacja Unknown'; Current = 'Unknown'; Available = '2.0'; ExitCode = 0; Ghost = $false }
    }
    if (-not (Test-Path -LiteralPath $Script:TestDir)) {
        [void](New-Item -ItemType Directory -Path $Script:TestDir -Force)
    }
    Write-WingetUpdaterJson -Path $Script:MockFile -Data $data
}

function New-PackagesTable {
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
    return ,$table
}

$Script:Packages = New-PackagesTable

function Get-PowerShellRuntimeText {
    $edition = 'Desktop'
    if ($PSVersionTable.ContainsKey('PSEdition')) {
        $edition = [string]$PSVersionTable.PSEdition
    }

    return "PowerShell $($PSVersionTable.PSVersion) ($edition)"
}

function ConvertTo-WingetVersion {
    param([string]$Text)

    $match = [regex]::Match([string]$Text, '\d+(\.\d+){0,3}')
    if (-not $match.Success) {
        return $null
    }

    $versionText = $match.Value
    while (($versionText -split '\.').Count -lt 2) {
        $versionText += '.0'
    }

    try {
        return [version]$versionText
    }
    catch {
        return $null
    }
}

function Test-WingetHelpOption {
    param(
        [string]$HelpText,
        [string]$Option
    )

    if ([string]::IsNullOrWhiteSpace($HelpText)) {
        return $false
    }

    return ($HelpText -match [regex]::Escape($Option))
}

function Test-IsUnknownVersionText {
    param([string]$Text)

    $value = ([string]$Text).Trim()
    if ($value.Length -eq 0) {
        return $true
    }

    return ($value -match '(?i)^(unknown|nieznan.*|n/a|not available)$')
}

function Get-PackageIssueType {
    param([pscustomobject]$Package)

    if (Test-IsUnknownVersionText -Text $Package.CurrentVersion) {
        return 'Unknown (-u)'
    }

    return ''
}

function Get-PackageAttemptKey {
    param(
        [string]$Id,
        [string]$Source
    )

    return $Id.Trim() + [char]0 + $Source.Trim()
}

function Load-SkipList {
    $Script:SkippedIds = @{}

    if (-not (Test-Path -LiteralPath $Script:SkipFile)) {
        return
    }

    try {
        foreach ($id in @(Read-WingetUpdaterSkipIds -Path $Script:SkipFile)) {
            $idText = ([string]$id).Trim()
            if ($idText.Length -gt 0) {
                $Script:SkippedIds[$idText] = $true
            }
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Nie udalo sie odczytac skip-list.json.`r`n$($_.Exception.Message)",
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
    }
}

function Test-IsWingetSpinnerLine {
    param([string]$Line)

    $value = ([string]$Line).Trim()
    return ($value -eq '-' -or $value -eq '\' -or $value -eq '|' -or $value -eq '/')
}

function Test-IsWingetProgressLine {
    param([string]$Line)

    return (-not [string]::IsNullOrWhiteSpace((Get-WingetProgressText -Line $Line)))
}

function Get-WingetProgressText {
    param([string]$Line)

    $value = (ConvertTo-PlainText ([string]$Line)).Trim()
    if ($value.Length -eq 0) {
        return ''
    }

    $sizePattern = '(?<progress>\d+(\.\d+)?\s*(B|KB|KiB|MB|MiB|GB|GiB|TB|TiB)\s*/\s*\d+(\.\d+)?\s*(B|KB|KiB|MB|MiB|GB|GiB|TB|TiB))'
    $sizeMatch = [regex]::Match($value, $sizePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($sizeMatch.Success) {
        return $sizeMatch.Groups['progress'].Value
    }

    $percentMatch = [regex]::Match($value, '(?<progress>\d{1,3}\s*%)\s*$')
    if ($percentMatch.Success) {
        return $percentMatch.Groups['progress'].Value
    }

    return ''
}

function ConvertTo-WingetByteCount {
    param(
        [string]$Number,
        [string]$Unit
    )

    try {
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $value = [double]::Parse($Number, $culture)
    }
    catch {
        return $null
    }

    switch -Regex ($Unit.ToUpperInvariant()) {
        '^B$' { return $value }
        '^K(I)?B$' { return ($value * 1024) }
        '^M(I)?B$' { return ($value * 1024 * 1024) }
        '^G(I)?B$' { return ($value * 1024 * 1024 * 1024) }
        '^T(I)?B$' { return ($value * 1024 * 1024 * 1024 * 1024) }
        default { return $null }
    }
}

function Get-WingetProgressPercent {
    param([string]$Line)

    $value = (ConvertTo-PlainText ([string]$Line)).Trim()
    if ($value.Length -eq 0) {
        return $null
    }

    $percentMatch = [regex]::Match($value, '(?<percent>\d{1,3})\s*%\s*$')
    if ($percentMatch.Success) {
        $percent = [double]$percentMatch.Groups['percent'].Value
        return [math]::Min(100, [math]::Max(0, $percent))
    }

    $sizePattern = '(?<current>\d+([.,]\d+)?)\s*(?<currentUnit>B|KB|KiB|MB|MiB|GB|GiB|TB|TiB)\s*/\s*(?<total>\d+([.,]\d+)?)\s*(?<totalUnit>B|KB|KiB|MB|MiB|GB|GiB|TB|TiB)'
    $sizeMatch = [regex]::Match($value, $sizePattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $sizeMatch.Success) {
        return $null
    }

    $currentBytes = ConvertTo-WingetByteCount -Number $sizeMatch.Groups['current'].Value -Unit $sizeMatch.Groups['currentUnit'].Value
    $totalBytes = ConvertTo-WingetByteCount -Number $sizeMatch.Groups['total'].Value -Unit $sizeMatch.Groups['totalUnit'].Value
    if ($null -eq $currentBytes -or $null -eq $totalBytes -or $totalBytes -le 0) {
        return $null
    }

    $percent = ($currentBytes / $totalBytes) * 100
    return [math]::Min(100, [math]::Max(0, $percent))
}

function New-ProgressBarText {
    param(
        [double]$Percent,
        [int]$Width = 24
    )

    $safePercent = [math]::Min(100, [math]::Max(0, $Percent))
    $filledCount = [int][math]::Round(($safePercent / 100) * $Width)
    $emptyCount = [math]::Max(0, $Width - $filledCount)
    $filled = [string][char]0x2588
    $empty = [string][char]0x2591

    return '[' + ($filled * $filledCount) + ($empty * $emptyCount) + ']'
}

function Format-LogLiveLine {
    $parts = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($Script:LogLiveSpinner)) {
        [void]$parts.Add($Script:LogLiveSpinner)
    }

    if (-not [string]::IsNullOrWhiteSpace($Script:LogLiveProgress)) {
        $percent = Get-WingetProgressPercent -Line $Script:LogLiveProgress
        if ($null -ne $percent) {
            [void]$parts.Add((New-ProgressBarText -Percent $percent))
        }
        [void]$parts.Add($Script:LogLiveProgress)
    }

    return ($parts.ToArray() -join ' ')
}

function Set-SpinnerText {
    param([string]$Text)

    if ($null -eq $Script:SpinnerLabel) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($Text)) {
        $Script:SpinnerLabel.Text = ''
    }
    else {
        $Script:SpinnerLabel.Text = $Text
    }
    $Script:SpinnerLabel.Refresh()
}

function Start-Spinner {
    $Script:SpinnerIndex = 0
    $Script:LastSpinnerStep = [datetime]::MinValue
    Reset-LogLiveLine
    Set-SpinnerText -Text $Script:SpinnerFrames[0]
}

function Step-Spinner {
    if ($null -eq $Script:SpinnerLabel) {
        return
    }

    $now = Get-Date
    if (($now - $Script:LastSpinnerStep).TotalMilliseconds -lt 150) {
        return
    }

    $Script:LastSpinnerStep = $now
    $frameIndex = $Script:SpinnerIndex % $Script:SpinnerFrames.Count
    Set-SpinnerText -Text $Script:SpinnerFrames[$frameIndex]
    $Script:SpinnerIndex++
}

function Stop-Spinner {
    Set-SpinnerText -Text ''
}

function Reset-LogLiveLine {
    $Script:LogSpinnerActive = $false
    $Script:LogLiveSpinner = ''
    $Script:LogLiveProgress = ''
    $Script:LogLiveLineStart = -1
    $Script:LogLiveRenderedText = ''
}

function Update-LogLiveLine {
    param(
        [string]$Spinner,
        [string]$Progress
    )

    if ($null -eq $Script:LogBox) {
        return
    }

    if ($PSBoundParameters.ContainsKey('Spinner')) {
        $cleanSpinner = (Repair-DisplayText -Text $Spinner).Trim()
        if (-not [string]::IsNullOrWhiteSpace($cleanSpinner)) {
            $Script:LogLiveSpinner = $cleanSpinner
        }
    }

    if ($PSBoundParameters.ContainsKey('Progress')) {
        $cleanProgress = (Repair-DisplayText -Text $Progress).Trim()
        $progressText = Get-WingetProgressText -Line $cleanProgress
        if ([string]::IsNullOrWhiteSpace($progressText)) {
            $progressText = $cleanProgress
        }
        if (-not [string]::IsNullOrWhiteSpace($progressText)) {
            $Script:LogLiveProgress = $progressText
        }
    }

    if ([string]::IsNullOrWhiteSpace($Script:LogLiveSpinner) -and [string]::IsNullOrWhiteSpace($Script:LogLiveProgress)) {
        return
    }

    $liveLine = Format-LogLiveLine
    if ([string]::IsNullOrWhiteSpace($liveLine)) {
        return
    }

    if ($liveLine -eq $Script:LogLiveRenderedText) {
        return
    }

    $now = Get-Date
    if (($now - $Script:LastLogLiveUpdate).TotalMilliseconds -lt 100) {
        $percent = Get-WingetProgressPercent -Line $liveLine
        if ($percent -ne 100 -and $percent -ne 0 -and $null -ne $percent) {
            return
        }
    }
    $Script:LastLogLiveUpdate = $now

    $replacement = $liveLine + "`r`n"
    $Script:LogBox.SuspendLayout()
    if ($Script:LogSpinnerActive -and $Script:LogBox.TextLength -gt 0) {
        if ($Script:LogLiveLineStart -ge 0 -and $Script:LogLiveLineStart -le $Script:LogBox.TextLength) {
            $Script:LogBox.Select($Script:LogLiveLineStart, $Script:LogBox.TextLength - $Script:LogLiveLineStart)
            $Script:LogBox.SelectedText = $replacement
        }
        else {
            $Script:LogLiveLineStart = $Script:LogBox.TextLength
            $Script:LogBox.AppendText($replacement)
        }
    }
    else {
        if ($Script:LogBox.TextLength -gt 0 -and -not ([string]$Script:LogBox.Text).EndsWith("`r`n")) {
            $Script:LogBox.AppendText("`r`n")
        }
        $Script:LogLiveLineStart = $Script:LogBox.TextLength
        $Script:LogBox.AppendText($replacement)
        $Script:LogSpinnerActive = $true
    }
    $Script:LogLiveRenderedText = $liveLine

    Limit-LogBoxBuffer
    $Script:LogBox.SelectionStart = $Script:LogBox.TextLength
    $Script:LogBox.ScrollToCaret()
    $Script:LogBox.ResumeLayout()
}

function New-MockWingetResult {
    param(
        [string[]]$Arguments,
        [string]$StandardOutput,
        [string]$StandardError,
        [AllowNull()][Nullable[int]]$ExitCode,
        [AllowNull()][object]$Package,
        [bool]$Cancelled = $false
    )

    $startedAtUtc = [datetime]::UtcNow
    $displayCommand = 'mock-winget'
    if ($Arguments.Count -gt 0) {
        $displayCommand += ' ' + (Join-CommandLineArguments -Arguments $Arguments)
    }
    $logPath = Join-Path $Script:Paths.LogsDirectory ([datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-mock-' + [guid]::NewGuid().ToString('N') + '.log')
    $combinedOutput = [string]$StandardOutput + [string]$StandardError
    $packageId = if ($null -ne $Package) { [string]$Package.Id } else { '' }
    $packageName = if ($null -ne $Package) { [string]$Package.Name } else { '' }
    $currentVersion = if ($null -ne $Package) { [string]$Package.CurrentVersion } else { '' }
    $availableVersion = if ($null -ne $Package) { [string]$Package.AvailableVersion } else { '' }
    $source = if ($null -ne $Package) { [string]$Package.Source } else { '' }
    $endedAtUtc = [datetime]::UtcNow
    $exitCodeText = if ($null -eq $ExitCode) { '' } else { [string]$ExitCode }
    $logText = @(
        "Log: $logPath"
        'Application: mock-winget'
        "Command: $displayCommand"
        "StartedAtUtc: $($startedAtUtc.ToString('o'))"
        "EndedAtUtc: $($endedAtUtc.ToString('o'))"
        "ExitCode: $exitCodeText"
        "Cancelled: $($Cancelled.ToString().ToLowerInvariant())"
        "PackageId: $packageId"
        "PackageName: $packageName"
        "CurrentVersion: $currentVersion"
        "AvailableVersion: $availableVersion"
        "Source: $source"
        ''
        '[stdout]'
        [string]$StandardOutput
        '[stderr]'
        [string]$StandardError
        '[combined]'
        $combinedOutput
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($logPath, $logText, (New-Object System.Text.UTF8Encoding($false)))

    return [pscustomobject][ordered]@{
        ApplicationPath = 'mock-winget'
        Arguments = [string[]]@($Arguments)
        DisplayCommand = $displayCommand
        Package = $Package
        PackageId = $packageId
        PackageName = $packageName
        CurrentVersion = $currentVersion
        AvailableVersion = $availableVersion
        Source = $source
        StartedAtUtc = $startedAtUtc
        EndedAtUtc = $endedAtUtc
        Started = $true
        InfrastructureError = ''
        CleanupGuaranteed = $true
        ExitCode = $ExitCode
        Cancelled = $Cancelled
        StandardOutput = [string]$StandardOutput
        StandardError = [string]$StandardError
        CombinedOutput = $combinedOutput
        LogPath = $logPath
    }
}

function Invoke-WingetUiHeartbeat {
    Step-Spinner
    $formType = 'System.Windows.Forms.Form' -as [type]
    if ($null -eq $Script:Form -or $null -eq $formType -or -not $formType.IsInstanceOfType($Script:Form)) {
        return
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Assert-WingetCleanupGuaranteed {
    param([object]$Result)

    if (-not [bool]$Result.CleanupGuaranteed) {
        Append-Log "BLAD BEZPIECZENSTWA PROCESU: nie potwierdzono zakonczenia procesu potomnego. Polecenie: $($Result.DisplayCommand). Log: $($Result.LogPath)"
        throw "Nie potwierdzono zakonczenia procesu winget. Dalsze polecenia zostaly przerwane. Log: $($Result.LogPath)"
    }
}

function Invoke-MockWingetDelay {
    param(
        [int]$Milliseconds,
        [scriptblock]$OnPulse,
        [object]$CancellationState
    )

    $remaining = [Math]::Max(0, $Milliseconds)
    while ($remaining -gt 0) {
        if (Test-WingetUpdaterCancellationRequested -State $CancellationState) {
            return $false
        }
        if ($null -ne $OnPulse) {
            & $OnPulse
        }
        if (Test-WingetUpdaterCancellationRequested -State $CancellationState) {
            return $false
        }

        $slice = [Math]::Min(50, $remaining)
        Start-Sleep -Milliseconds $slice
        $remaining -= $slice
    }

    if ($null -ne $OnPulse) {
        & $OnPulse
    }
    return (-not (Test-WingetUpdaterCancellationRequested -State $CancellationState))
}

function Invoke-Winget {
    param(
        [string]$ApplicationPath,
        [string[]]$Arguments,
        [AllowNull()][object]$Package,
        [switch]$LiveLog,
        [scriptblock]$OnPulse
    )

    if ($null -ne $Script:TestModeCheck -and $Script:TestModeCheck.Checked) {
        if (-not (Test-Path -LiteralPath $Script:MockFile)) { Reset-MockState }
        $mockPulseCallback = $OnPulse
        $mockSpinnerStarted = $false
        if ($LiveLog -and $null -eq $mockPulseCallback) {
            Start-Spinner
            $mockSpinnerStarted = $true
            $mockPulseCallback = { Invoke-WingetUiHeartbeat }
        }

        try {
        $standardOutput = ''
        $standardError = ''
        $exitCode = 0

        if ($Arguments -contains '--version') {
            $standardOutput = 'v1.9.0-mock'
        }
        elseif ($Arguments -contains '--help') {
            $standardOutput = '--include-unknown --exact --accept-package-agreements --accept-source-agreements --disable-interactivity --interactive --silent --source'
        }
        elseif ($Arguments -contains 'source' -and $Arguments -contains 'update') {
            $standardOutput = 'Source updated'
        }
        elseif ($Arguments -contains 'upgrade' -and $Arguments -notcontains '--id') {
            $mock = Read-WingetUpdaterJson -Path $Script:MockFile
            $standardOutput = "Name Id Version Available Source`n"
            $standardOutput += "---- -- ------- --------- ------`n"
            foreach ($key in $mock.PSObject.Properties.Name) {
                $pkg = $mock.$key
                if ($pkg.Current -ne $pkg.Available) {
                    $standardOutput += "$($pkg.Name) $key $($pkg.Current) $($pkg.Available) winget`n"
                }
            }
            if ($LiveLog -or $null -ne $mockPulseCallback) {
                [void](Invoke-MockWingetDelay -Milliseconds 500 -OnPulse $mockPulseCallback -CancellationState $Script:CancellationState)
            }
        }
        elseif ($Arguments -contains 'upgrade' -and $Arguments -contains '--id') {
            $mock = Read-WingetUpdaterJson -Path $Script:MockFile
            $idIdx = [array]::IndexOf($Arguments, '--id') + 1
            $id = $Arguments[$idIdx]
            $pkg = $mock.$id
            if ($null -eq $pkg) {
                $standardError = "Mock package not found: $id"
                $exitCode = 1
            }
            $delayCompleted = $true
            if ($LiveLog -or $null -ne $mockPulseCallback) {
                $delayCompleted = Invoke-MockWingetDelay -Milliseconds 300 -OnPulse $mockPulseCallback -CancellationState $Script:CancellationState
            }
            if ($delayCompleted -and $LiveLog) {
                Update-LogLiveLine -Spinner "-"
                Update-LogLiveLine -Progress "50%"
                $delayCompleted = Invoke-MockWingetDelay -Milliseconds 300 -OnPulse $mockPulseCallback -CancellationState $Script:CancellationState
                if ($delayCompleted) {
                    Update-LogLiveLine -Progress "100%"
                }
            }

            if ($delayCompleted -and $null -ne $pkg -and $pkg.ExitCode -ne 0) {
                $standardError = 'Error'
                $exitCode = [int]$pkg.ExitCode
            }
            elseif ($delayCompleted -and $null -ne $pkg -and -not $pkg.Ghost) {
                if (-not (Test-WingetUpdaterCancellationRequested -State $Script:CancellationState)) {
                    $pkg.Current = $pkg.Available
                    if (-not (Test-WingetUpdaterCancellationRequested -State $Script:CancellationState)) {
                        Write-WingetUpdaterJson -Path $Script:MockFile -Data $mock
                        $standardOutput = 'Success'
                    }
                }
            }
            elseif ($delayCompleted -and $null -ne $pkg) {
                $standardOutput = 'Success'
            }
        }

        $mockCancelled = Test-WingetUpdaterCancellationRequested -State $Script:CancellationState
        $mockExitCode = if ($mockCancelled) { $null } else { $exitCode }
        $mockResult = New-MockWingetResult `
            -Arguments $Arguments `
            -StandardOutput $standardOutput `
            -StandardError $standardError `
            -ExitCode $mockExitCode `
            -Package $Package `
            -Cancelled $mockCancelled
        Assert-WingetCleanupGuaranteed -Result $mockResult
        if ($LiveLog) {
            if (-not [string]::IsNullOrWhiteSpace($mockResult.CombinedOutput)) {
                Append-Log $mockResult.CombinedOutput
            }
            Append-Log "Log: $($mockResult.LogPath)"
        }
        return $mockResult
        }
        finally {
            if ($mockSpinnerStarted) {
                Stop-Spinner
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($ApplicationPath)) {
        if ($null -eq $Script:WingetInfo -or [string]::IsNullOrWhiteSpace([string]$Script:WingetInfo.Path)) {
            throw 'The absolute winget Application path has not been initialized.'
        }
        $ApplicationPath = [string]$Script:WingetInfo.Path
    }

    $displayCallback = $null
    $pulseCallback = $null
    if ($LiveLog) {
        Start-Spinner
        $displayCallback = {
            param($streamName, $text)

            $displayText = ConvertTo-PlainText -Text $text
            if (-not [string]::IsNullOrWhiteSpace($displayText)) {
                if ($streamName -eq 'stderr') {
                    Append-Log "STDERR: $displayText"
                }
                else {
                    Append-Log $displayText
                }
            }
        }
        $pulseCallback = {
            Invoke-WingetUiHeartbeat
        }
    }

    try {
        $Script:CurrentWingetProcess = $true
        $result = Invoke-WingetProcess -ApplicationPath $ApplicationPath -Arguments $Arguments -LogsDirectory $Script:Paths.LogsDirectory -Package $Package -OnOutput $displayCallback -OnPulse $pulseCallback -CancellationState $Script:CancellationState
        Assert-WingetCleanupGuaranteed -Result $result
        if ($LiveLog) {
            Append-Log "Log: $($result.LogPath)"
        }
        return $result
    }
    finally {
        $Script:CurrentWingetProcess = $null
        if ($LiveLog) {
            Stop-Spinner
        }
    }
}

function Initialize-WingetInfo {
    $usingMock = ($null -ne $Script:TestModeCheck -and $Script:TestModeCheck.Checked)
    if ($usingMock) {
        $wingetPath = 'mock-winget'
    }
    else {
        $localAppDataPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $commands = @(Get-Command winget -CommandType Application -All -ErrorAction SilentlyContinue)
        $wingetPath = Resolve-WingetApplicationPath -Commands $commands -LocalAppDataPath $localAppDataPath
    }

    $versionResult = Invoke-Winget -ApplicationPath $wingetPath -Arguments @('--version')
    $helpResult = Invoke-Winget -ApplicationPath $wingetPath -Arguments @('upgrade', '--help')
    if (-not $versionResult.Started -or -not [string]::IsNullOrWhiteSpace($versionResult.InfrastructureError)) {
        throw "Nie udalo sie uruchomic winget --version: $($versionResult.InfrastructureError)"
    }
    if (-not $helpResult.Started -or -not [string]::IsNullOrWhiteSpace($helpResult.InfrastructureError)) {
        throw "Nie udalo sie uruchomic winget upgrade --help: $($helpResult.InfrastructureError)"
    }
    $versionText = (ConvertTo-PlainText $versionResult.StandardOutput).Trim()
    $helpText = ConvertTo-PlainText $helpResult.StandardOutput
    $version = ConvertTo-WingetVersion -Text $versionText
    $warnings = New-Object System.Collections.Generic.List[string]

    if ($versionResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($versionText)) {
        [void]$warnings.Add('Nie udalo sie jednoznacznie odczytac wersji winget.')
    }
    elseif ($null -eq $version) {
        [void]$warnings.Add("Nie udalo sie sparsowac wersji winget: $versionText")
    }
    elseif ($version -lt $Script:MinimumWingetVersion) {
        [void]$warnings.Add("Wersja winget $versionText jest starsza niz zalecane minimum $Script:MinimumWingetVersion.")
    }

    if ($helpResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($helpText)) {
        [void]$warnings.Add('Nie udalo sie odczytac "winget upgrade --help"; program bedzie uzywal tylko podstawowych opcji.')
    }

    $supportsIncludeUnknown = (Test-WingetHelpOption -HelpText $helpText -Option '--include-unknown') -or (Test-WingetHelpOption -HelpText $helpText -Option '--unknown')

    $Script:WingetInfo = [pscustomobject]@{
        Path = $wingetPath
        VersionText = $versionText
        Version = $version
        SupportsAcceptSourceAgreements = Test-WingetHelpOption -HelpText $helpText -Option '--accept-source-agreements'
        SupportsSourceUpdateAcceptSourceAgreements = Test-WingetHelpOption -HelpText $helpText -Option '--accept-source-agreements'
        SupportsAcceptPackageAgreements = Test-WingetHelpOption -HelpText $helpText -Option '--accept-package-agreements'
        SupportsDisableInteractivity = Test-WingetHelpOption -HelpText $helpText -Option '--disable-interactivity'
        SupportsIncludeUnknown = $supportsIncludeUnknown
        SupportsExact = Test-WingetHelpOption -HelpText $helpText -Option '--exact'
        SupportsSilent = Test-WingetHelpOption -HelpText $helpText -Option '--silent'
        SupportsInteractive = Test-WingetHelpOption -HelpText $helpText -Option '--interactive'
        SupportsSource = Test-WingetHelpOption -HelpText $helpText -Option '--source'
        Warnings = $warnings.ToArray()
    }
}

function Sync-WingetUiCapabilities {
    if ($null -ne $Script:IncludeUnknownCheck -and $null -ne $Script:WingetInfo) {
        $Script:IncludeUnknownCheck.Enabled = -not $Script:IsBusy -and [bool]($Script:WingetInfo.SupportsIncludeUnknown)
        if (-not [bool]($Script:WingetInfo.SupportsIncludeUnknown)) {
            $Script:IncludeUnknownCheck.Checked = $false
        }
    }
}

function New-WingetUpgradeListArguments {
    return @(WingetUpdater.Core\New-WingetUpgradeListArguments -Capabilities $Script:WingetInfo -SourceAgreementsAccepted $Script:SourceAgreementsAccepted -IncludeUnknown ($null -ne $Script:IncludeUnknownCheck -and $Script:IncludeUnknownCheck.Checked))
}

function Add-PackageRow {
    param(
        [pscustomobject]$Package,
        [System.Data.DataTable]$Table = $Script:Packages
    )

    $isSkipped = $Script:SkippedIds.ContainsKey($Package.Id)
    $attemptKey = Get-PackageAttemptKey -Id $Package.Id -Source $Package.Source
    $isGhost = $Script:AttemptedUpdates.ContainsKey($attemptKey) -and $Script:AttemptedUpdates[$attemptKey] -eq $Package.AvailableVersion

    if ($isGhost) {
        $storedResult = if ($Script:SuccessfulAttemptResults.ContainsKey($attemptKey)) { $Script:SuccessfulAttemptResults[$attemptKey] } else { $null }
        Add-WingetUpdaterSessionFailure -Registry $Script:UnresolvedFailures -Package $Package -Result $storedResult -FailureType 'PostVerificationFailure'
    }

    $row = $Table.NewRow()
    Set-RowValue -Row $row -ColumnName 'Update' -Value (-not $isSkipped -and -not $isGhost)
    Set-RowValue -Row $row -ColumnName 'Skip' -Value $isSkipped
    Set-RowValue -Row $row -ColumnName 'Name' -Value $Package.Name
    Set-RowValue -Row $row -ColumnName 'Id' -Value $Package.Id
    Set-RowValue -Row $row -ColumnName 'CurrentVersion' -Value $Package.CurrentVersion
    Set-RowValue -Row $row -ColumnName 'AvailableVersion' -Value $Package.AvailableVersion

    $issue = Get-PackageIssueType -Package $Package
    if ($isGhost) {
        $issue = 'Aplikacja samoaktualizujaca'
    }
    Set-RowValue -Row $row -ColumnName 'IssueType' -Value $issue
    Set-RowValue -Row $row -ColumnName 'Source' -Value $Package.Source

    $status = ''
    if ($isSkipped) {
        $status = 'Pominiete'
    }
    elseif ($isGhost) {
        $status = 'Blad (Ghost)'
    }
    Set-RowValue -Row $row -ColumnName 'Status' -Value $status

    [void]$Table.Rows.Add($row)
}

function Commit-GridEdits {
    if ($null -ne $Script:Grid) {
        [void]$Script:Grid.EndEdit()
    }
}

function Save-SkipList {
    param(
        [switch]$Silent,
        [switch]$BypassBusyGuard
    )

    if ($Script:IsBusy -and -not $BypassBusyGuard) {
        return $false
    }

    [void](Commit-GridEdits)

    $merged = @{}
    foreach ($key in $Script:SkippedIds.Keys) {
        $merged[$key] = $true
    }

    foreach ($row in $Script:Packages.Rows) {
        $id = ([string](Get-RowValue -Row $row -ColumnName 'Id')).Trim()
        if ($id.Length -eq 0) {
            continue
        }

        if ([bool](Get-RowValue -Row $row -ColumnName 'Skip')) {
            $merged[$id] = $true
        }
        elseif ($merged.ContainsKey($id)) {
            [void]$merged.Remove($id)
        }
    }

    $ids = @($merged.Keys | Sort-Object)
    [void](Write-WingetUpdaterSkipList -Path $Script:SkipFile -SkippedIds $ids)

    $Script:SkippedIds = @{}
    foreach ($id in $ids) {
        $Script:SkippedIds[$id] = $true
    }

    if (-not $Silent) {
        [System.Windows.Forms.MessageBox]::Show(
            "Zapisano liste pomijanych pakietow: $($ids.Count)",
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    return $true
}

function Limit-LogBoxBuffer {
    if ($null -eq $Script:LogBox -or $Script:LogBox.TextLength -le $Script:MaxLogBoxCharacters) {
        return
    }

    $charactersToRemove = $Script:LogBox.TextLength - $Script:MaxLogBoxCharacters
    $lineEnd = $Script:LogBox.Text.IndexOf("`n", $charactersToRemove)
    if ($lineEnd -ge 0) {
        $charactersToRemove = $lineEnd + 1
    }
    $Script:LogBox.Select(0, $charactersToRemove)
    $Script:LogBox.SelectedText = ''
    Reset-LogLiveLine
}

function Append-Log {
    param([string]$Text)

    if ($null -eq $Script:LogBox) {
        return
    }

    Reset-LogLiveLine
    $cleanText = Repair-DisplayText -Text $Text
    $Script:LogBox.AppendText($cleanText)
    if (-not $cleanText.EndsWith("`r`n")) {
        $Script:LogBox.AppendText("`r`n")
    }
    Limit-LogBoxBuffer
    $Script:LogBox.SelectionStart = $Script:LogBox.TextLength
    $Script:LogBox.ScrollToCaret()
}

function Show-AppError {
    param(
        [object]$ErrorRecord,
        [string]$Title = 'Winget Updater'
    )

    $message = [string]$ErrorRecord
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord] -and $null -ne $ErrorRecord.Exception) {
        $message = $ErrorRecord.Exception.Message
    }
    elseif ($ErrorRecord -is [System.Exception]) {
        $message = $ErrorRecord.Message
    }
    elseif ($null -ne $ErrorRecord -and ($ErrorRecord.PSObject.Properties.Name -contains 'Exception') -and $null -ne $ErrorRecord.Exception) {
        $message = $ErrorRecord.Exception.Message
    }

    Append-Log "BLAD: $message"
    if ($ErrorRecord -is [System.Management.Automation.ErrorRecord] -and -not [string]::IsNullOrWhiteSpace($ErrorRecord.ScriptStackTrace)) {
        Append-Log $ErrorRecord.ScriptStackTrace
    }

    [System.Windows.Forms.MessageBox]::Show(
        $message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Set-Busy {
    param(
        [bool]$Busy,
        [string]$Message
    )

    $Script:IsBusy = $Busy
    Set-WingetUpdaterBusyControlState -Busy $Busy -OperationControls @(
        $Script:RefreshButton,
        $Script:UpdateButton,
        $Script:SaveButton,
        $Script:LoadSkippedButton,
        $Script:UpdateAllButton,
        $Script:UpdateNoneButton,
        $Script:SkipAllButton,
        $Script:SkipNoneButton,
        $Script:CopyMessageButton,
        $Script:OpenAiCliButton,
        $Script:AgentCombo,
        $Script:TestModeCheck,
        $Script:SilentCheck,
        $Script:InteractiveCheck,
        $Script:IncludeUnknownCheck,
        $Script:Grid
    ) -CancelControl $Script:CancelButton
    $Script:RefreshButton.Enabled = -not $Busy
    $Script:UpdateButton.Enabled = -not $Busy
    $Script:SaveButton.Enabled = -not $Busy
    if ($null -ne $Script:LoadSkippedButton) {
        $Script:LoadSkippedButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:UpdateAllButton) {
        $Script:UpdateAllButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:UpdateNoneButton) {
        $Script:UpdateNoneButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:SkipAllButton) {
        $Script:SkipAllButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:SkipNoneButton) {
        $Script:SkipNoneButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:CopyMessageButton) {
        $Script:CopyMessageButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:OpenAiCliButton) {
        $Script:OpenAiCliButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:AgentCombo) {
        $Script:AgentCombo.Enabled = -not $Busy
    }
    if ($null -ne $Script:TestModeCheck) {
        $Script:TestModeCheck.Enabled = -not $Busy
    }
    if ($null -ne $Script:SilentCheck) {
        $Script:SilentCheck.Enabled = -not $Busy
    }
    if ($null -ne $Script:InteractiveCheck) {
        $Script:InteractiveCheck.Enabled = -not $Busy
    }
    if ($null -ne $Script:IncludeUnknownCheck) {
        $Script:IncludeUnknownCheck.Enabled = -not $Busy
    }
    if ($null -ne $Script:Grid) {
        $Script:Grid.Enabled = -not $Busy
    }
    if ($null -ne $Script:CancelButton) {
        $Script:CancelButton.Enabled = $Busy
        $Script:CancelButton.Visible = $Busy
    }
    $Script:Form.Cursor = if ($Busy) {
        [System.Windows.Forms.Cursors]::WaitCursor
    }
    else {
        [System.Windows.Forms.Cursors]::Default
    }
    $Script:StatusLabel.Text = $Message
    if (-not $Busy) {
        Stop-Spinner
        Sync-WingetUiCapabilities
    }
}

function Test-ShouldCancelFormClose {
    return [bool]$Script:IsBusy
}

function Test-OperationEntryAllowed {
    return (-not [bool]$Script:IsBusy)
}

function Confirm-SourceAgreements {
    if ($null -ne $Script:TestModeCheck -and $Script:TestModeCheck.Checked) {
        return $true
    }
    if ($Script:SourceAgreementsAccepted) {
        return $true
    }

    $promptAction = {
        $message = "Pelny dostep do winget wymaga zgody na umowy metadanych zrodel.`r`n`r`nOpcja --accept-source-agreements pozwala zaakceptowac te umowy przed pobraniem metadanych.`r`n`r`nOdmowa pozostawi GUI otwarte, z dostepnym trybem Mock. Pelny dostep wymaga ponownego uzycia Odswiez."
        $choice = [System.Windows.Forms.MessageBox]::Show(
            $message,
            'Zgoda na umowy zrodel',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return ($choice -eq [System.Windows.Forms.DialogResult]::Yes)
    }.GetNewClosure()
    $persistAction = {
        Grant-WingetUpdaterSourceAgreements -Path $Script:Paths.SettingsFile | Out-Null
        $Script:SourceAgreementsAccepted = $true
    }.GetNewClosure()
    $decision = Resolve-WingetUpdaterSourceAgreementConsent `
        -MockMode $false `
        -AlreadyAccepted $Script:SourceAgreementsAccepted `
        -PromptAction $promptAction `
        -PersistAcceptanceAction $persistAction
    if (-not $decision.Allowed) {
        if ($null -ne $Script:StatusLabel) {
            $Script:StatusLabel.Text = 'Odmowa umow zrodel. Pelny dostep wymaga ponownego uzycia Odswiez; tryb Mock pozostaje dostepny.'
        }
        return $false
    }
    return $true
}

function Confirm-OperationCancellation {
    $choice = [System.Windows.Forms.MessageBox]::Show(
        'Biezaca operacja moze uruchomic niezalezny instalator lub podniesiony instalator. Anulowanie zatrzyma proces winget, ale taki instalator moze jeszcze wymagac osobnego zamkniecia.',
        'Anuluj operacje',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
        Request-WingetUpdaterCancellation -State $Script:CancellationState
        return $true
    }
    return $false
}

function Complete-Operation {
    param([string]$Message)

    Set-Busy -Busy $false -Message $Message
    if ($Script:ClosePending) {
        $Script:ClosePending = $false
        if ($null -ne $Script:Form) {
            [void]$Script:Form.BeginInvoke([Action]{ $Script:Form.Close() })
        }
    }
}

function Invoke-WingetSourceUpdate {
    param([switch]$ContinueOnError)

    $arguments = @(New-WingetSourceUpdateArguments -Capabilities $Script:WingetInfo -SourceAgreementsAccepted $Script:SourceAgreementsAccepted)
    $result = Invoke-Winget -Arguments $arguments -LiveLog

    if ($result.Cancelled) {
        return $result
    }

    if (-not $result.Started -or -not [string]::IsNullOrWhiteSpace($result.InfrastructureError)) {
        $message = "winget source update nie zostal poprawnie uruchomiony: $($result.InfrastructureError)"
        if ($ContinueOnError) {
            Append-Log "UWAGA: $message Kontynuuje sprawdzanie aktualizacji."
            return $result
        }
        throw $message
    }

    if ($result.ExitCode -ne 0) {
        $message = "winget source update zakonczyl sie kodem $($result.ExitCode)."
        if ($ContinueOnError) {
            Append-Log "UWAGA: $message Kontynuuje sprawdzanie aktualizacji."
            return $result
        }

        throw $message
    }

    return $result
}

function Refresh-Packages {
    param([switch]$PreserveLog, [switch]$ListOnly, [switch]$KeepBusy)

    if (-not (Test-OperationEntryAllowed) -and -not $KeepBusy) {
        return
    }
    if (-not (Confirm-SourceAgreements)) {
        return
    }
    Save-SkipList -Silent -BypassBusyGuard
    if (-not $KeepBusy) {
        Set-Busy -Busy $true -Message 'Sprawdzanie aktualizacji winget...'
        $Script:CancellationState = New-WingetUpdaterCancellationState
    }

    try {
        if ($PreserveLog) {
            Append-Log ''
            Append-Log '--- Odswiezanie listy ---'
        }
        else {
            $Script:LogBox.Clear()
            Reset-LogLiveLine
        }

        Initialize-WingetInfo
        Sync-WingetUiCapabilities

        Append-Log "Runtime: $(Get-PowerShellRuntimeText)"
        Append-Log "winget: $($Script:WingetInfo.VersionText) ($($Script:WingetInfo.Path))"
        foreach ($warning in $Script:WingetInfo.Warnings) {
            Append-Log "UWAGA: $warning"
        }

        $sourceUpdateWarning = ''
        if (-not $ListOnly) {
            $Script:StatusLabel.Text = 'Odswiezanie bazy winget...'
            $sourceResult = Invoke-WingetSourceUpdate -ContinueOnError
            if ($sourceResult.Cancelled) {
                $Script:StatusLabel.Text = 'Anulowano.'
                return
            }
            if (-not $sourceResult.Started -or -not [string]::IsNullOrWhiteSpace($sourceResult.InfrastructureError)) {
                $sourceUpdateWarning = "Odswiezenie zrodel nie zostalo uruchomione: $($sourceResult.InfrastructureError) Lista zostala sprawdzona mimo bledu."
            }
            elseif ($sourceResult.ExitCode -ne 0) {
                $sourceUpdateWarning = "Odswiezenie zrodel nie powiodlo sie (kod $($sourceResult.ExitCode)); lista zostala sprawdzona mimo bledu."
            }
            $Script:StatusLabel.Text = 'Sprawdzanie aktualizacji winget...'
        }

        $arguments = @(New-WingetUpgradeListArguments)
        $result = Invoke-Winget -Arguments $arguments -LiveLog
        if ($result.Cancelled) {
            $Script:StatusLabel.Text = 'Anulowano.'
            return
        }
        if (-not $result.Started) {
            throw "winget upgrade nie zostal uruchomiony: $($result.InfrastructureError)"
        }
        if (-not [string]::IsNullOrWhiteSpace($result.InfrastructureError)) {
            throw "winget upgrade zakonczyl sie bledem infrastruktury: $($result.InfrastructureError)"
        }
        $packages = @(ConvertFrom-WingetUpgradeResult -ExitCode $result.ExitCode -StandardOutput $result.StandardOutput)
        $newPackages = New-PackagesTable
        foreach ($package in $packages) {
            Add-PackageRow -Package $package -Table $newPackages
        }

        $Script:Packages = $newPackages

        if ($null -ne $Script:Grid) {
            $Script:Grid.DataSource = $Script:Packages
            foreach ($gridRow in $Script:Grid.Rows) {
                $isGhostRow = Test-IsGhostPackageRow -Row $gridRow
                $gridRow.Cells['Update'].ReadOnly = $isGhostRow
                $gridRow.Cells['Update'].Style.BackColor = if ($isGhostRow) {
                    [System.Drawing.Color]::LightGray
                }
                else {
                    [System.Drawing.Color]::Empty
                }
                if ($isGhostRow) {
                    $gridRow.Cells['Update'].Value = $false
                }
            }
            $Script:Grid.ClearSelection()
        }

        $skippedVisible = 0
        $unknownVisible = 0
        foreach ($row in $Script:Packages.Rows) {
            if ([bool](Get-RowValue -Row $row -ColumnName 'Skip')) {
                $skippedVisible++
            }
            if (Test-IsUnknownVersionText -Text ([string](Get-RowValue -Row $row -ColumnName 'CurrentVersion'))) {
                $unknownVisible++
            }
        }

        $listStatus = ''
        if ($packages.Count -eq 0) {
            $listStatus = 'Brak dostepnych aktualizacji albo winget nie zwrocil tabeli pakietow.'
        }
        else {
            $listStatus = "Znaleziono aktualizacje: $($packages.Count). Unknown: $unknownVisible. Pominiete: $skippedVisible."
        }
        if ([string]::IsNullOrWhiteSpace($sourceUpdateWarning)) {
            $Script:StatusLabel.Text = $listStatus
        }
        else {
            Append-Log "UWAGA: $sourceUpdateWarning"
            $Script:StatusLabel.Text = "UWAGA: $sourceUpdateWarning $listStatus"
        }
    }
    catch {
        Append-Log $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Blad podczas sprawdzania',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        if (-not $KeepBusy) {
            Set-Busy -Busy $false -Message $Script:StatusLabel.Text
            Complete-Operation -Message $Script:StatusLabel.Text
        }
    }
}

function Test-IsGhostPackageRow {
    param([object]$Row)

    if ($null -eq $Row) {
        return $false
    }

    $issue = [string](Get-RowValue -Row $Row -ColumnName 'IssueType')
    $status = [string](Get-RowValue -Row $Row -ColumnName 'Status')
    return ($issue -eq 'Aplikacja samoaktualizujaca' -or $status -eq 'Blad (Ghost)')
}

function Get-SelectedUpdateRows {
    Commit-GridEdits

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Script:Packages.Rows) {
        if (-not ($row -is [System.Data.DataRow])) {
            continue
        }

        if ((Test-IsGhostPackageRow -Row $row) -and [bool](Get-RowValue -Row $row -ColumnName 'Update')) {
            Set-RowValue -Row $row -ColumnName 'Update' -Value $false
            Set-RowValue -Row $row -ColumnName 'Status' -Value 'Blad (Ghost)'
            continue
        }

        if ([bool](Get-RowValue -Row $row -ColumnName 'Update') -and -not [bool](Get-RowValue -Row $row -ColumnName 'Skip')) {
            [void]$rows.Add($row)
        }
    }
    return ,$rows
}

function Set-AllPackageSelection {
    param(
        [ValidateSet('Update', 'Skip')]
        [string]$ColumnName,
        [bool]$Checked,
        [switch]$BypassBusyGuard
    )

    if ($Script:IsBusy -and -not $BypassBusyGuard) {
        return $false
    }

    [void](Commit-GridEdits)

    foreach ($row in $Script:Packages.Rows) {
        if (-not ($row -is [System.Data.DataRow])) {
            continue
        }

        if ($ColumnName -eq 'Update') {
            if (Test-IsGhostPackageRow -Row $row) {
                [void](Set-RowValue -Row $row -ColumnName 'Update' -Value $false)
                if (-not [bool](Get-RowValue -Row $row -ColumnName 'Skip')) {
                    [void](Set-RowValue -Row $row -ColumnName 'Status' -Value 'Blad (Ghost)')
                }
                continue
            }
            if ($Checked -and [bool](Get-RowValue -Row $row -ColumnName 'Skip')) {
                continue
            }
            [void](Set-RowValue -Row $row -ColumnName 'Update' -Value $Checked)
        }
        else {
            [void](Set-RowValue -Row $row -ColumnName 'Skip' -Value $Checked)
            if ($Checked) {
                [void](Set-RowValue -Row $row -ColumnName 'Update' -Value $false)
                [void](Set-RowValue -Row $row -ColumnName 'Status' -Value 'Pominiete')
            }
            elseif (Test-IsGhostPackageRow -Row $row) {
                [void](Set-RowValue -Row $row -ColumnName 'Update' -Value $false)
                [void](Set-RowValue -Row $row -ColumnName 'Status' -Value 'Blad (Ghost)')
            }
            elseif ([string](Get-RowValue -Row $row -ColumnName 'Status') -eq 'Pominiete') {
                [void](Set-RowValue -Row $row -ColumnName 'Status' -Value '')
            }
        }
    }

    if ($null -ne $Script:Grid) {
        [void]$Script:Grid.Refresh()
    }
    return $true
}

function Apply-SkipListToVisiblePackages {
    param(
        [switch]$Silent,
        [switch]$BypassBusyGuard
    )

    if ($Script:IsBusy -and -not $BypassBusyGuard) {
        return $false
    }

    [void](Commit-GridEdits)
    [void](Load-SkipList)

    $matched = 0
    foreach ($row in $Script:Packages.Rows) {
        if (-not ($row -is [System.Data.DataRow])) {
            continue
        }

        $id = ([string](Get-RowValue -Row $row -ColumnName 'Id')).Trim()
        $isSkipped = $id.Length -gt 0 -and $Script:SkippedIds.ContainsKey($id)

        [void](Set-RowValue -Row $row -ColumnName 'Skip' -Value $isSkipped)
        if ($isSkipped) {
            [void](Set-RowValue -Row $row -ColumnName 'Update' -Value $false)
            [void](Set-RowValue -Row $row -ColumnName 'Status' -Value 'Pominiete')
            $matched++
        }
        elseif (Test-IsGhostPackageRow -Row $row) {
            [void](Set-RowValue -Row $row -ColumnName 'Update' -Value $false)
            [void](Set-RowValue -Row $row -ColumnName 'Status' -Value 'Blad (Ghost)')
        }
        elseif ([string](Get-RowValue -Row $row -ColumnName 'Status') -eq 'Pominiete') {
            [void](Set-RowValue -Row $row -ColumnName 'Status' -Value '')
        }
    }

    if ($null -ne $Script:Grid) {
        [void]$Script:Grid.Refresh()
    }

    $message = "Wczytano liste pomijanych. Dopasowano widoczne pakiety: $matched."
    if ($null -ne $Script:StatusLabel) {
        $Script:StatusLabel.Text = $message
    }
    Append-Log $message

    if (-not $Silent) {
        [System.Windows.Forms.MessageBox]::Show(
            $message,
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    return $true
}

function Confirm-UpdateRows {
    param([object]$Rows)

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Potwierdz aktualizacje'
    $dialog.StartPosition = 'CenterParent'
    $dialog.Size = New-Object System.Drawing.Size(820, 520)
    $dialog.MinimumSize = New-Object System.Drawing.Size(680, 400)
    $dialog.ShowInTaskbar = $false

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 1
    $layout.RowCount = 3
    $layout.Padding = New-Object System.Windows.Forms.Padding(10)
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 46)))

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Zostana zaktualizowane wszystkie ponizsze pakiety: $($Rows.Count). Kontynuujac, akceptujesz umowy pakietow dla tych instalatorow."
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleLeft'

    $list = New-Object System.Windows.Forms.ListView
    $list.Dock = 'Fill'
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.GridLines = $true
    $list.HideSelection = $false
    [void]$list.Columns.Add('ID', 260)
    [void]$list.Columns.Add('Nazwa', 270)
    [void]$list.Columns.Add('Obecna', 100)
    [void]$list.Columns.Add('Dostepna', 100)

    foreach ($row in $Rows) {
        $id = [string](Get-RowValue -Row $row -ColumnName 'Id')
        $name = [string](Get-RowValue -Row $row -ColumnName 'Name')
        $current = [string](Get-RowValue -Row $row -ColumnName 'CurrentVersion')
        $available = [string](Get-RowValue -Row $row -ColumnName 'AvailableVersion')

        $item = New-Object System.Windows.Forms.ListViewItem($id)
        [void]$item.SubItems.Add($name)
        [void]$item.SubItems.Add($current)
        [void]$item.SubItems.Add($available)
        [void]$list.Items.Add($item)
    }

    $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonPanel.Dock = 'Fill'
    $buttonPanel.FlowDirection = 'RightToLeft'
    $buttonPanel.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)

    $updateButton = New-Object System.Windows.Forms.Button
    $updateButton.Text = 'Aktualizuj'
    $updateButton.Width = 110
    $updateButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Set-ControlToolTip -Control $updateButton -Text 'Potwierdza aktualizacje wszystkich pakietow widocznych w tym oknie.'

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Anuluj'
    $cancelButton.Width = 90
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Set-ControlToolTip -Control $cancelButton -Text 'Zamyka okno bez uruchamiania aktualizacji.'

    [void]$buttonPanel.Controls.Add($updateButton)
    [void]$buttonPanel.Controls.Add($cancelButton)
    [void]$layout.Controls.Add($label, 0, 0)
    [void]$layout.Controls.Add($list, 0, 1)
    [void]$layout.Controls.Add($buttonPanel, 0, 2)
    [void]$dialog.Controls.Add($layout)

    $dialog.AcceptButton = $updateButton
    $dialog.CancelButton = $cancelButton

    try {
        $result = $dialog.ShowDialog($Script:Form)
        return ($result -eq [System.Windows.Forms.DialogResult]::OK)
    }
    finally {
        $dialog.Dispose()
    }
}

function Update-SelectedPackages {
    if (-not (Test-OperationEntryAllowed)) {
        return
    }
    $rows = Get-SelectedUpdateRows
    if ($rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'Nie zaznaczono zadnych pakietow do aktualizacji.',
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    [void](Assert-PackageRows -Rows $rows -Operation 'Aktualizacja')

    if (-not (Confirm-UpdateRows -Rows $rows)) {
        return
    }
    if (-not (Confirm-SourceAgreements)) {
        return
    }

    Save-SkipList -Silent -BypassBusyGuard
    Set-Busy -Busy $true -Message "Aktualizowanie pakietow: $($rows.Count)..."
    $Script:CancellationState = New-WingetUpdaterCancellationState

    try {
        Initialize-WingetInfo
        Sync-WingetUiCapabilities

        Append-Log ''
        Append-Log "== Aktualizacja wybranych pakietow: $($rows.Count) =="

        foreach ($row in $rows) {
            if (Test-WingetUpdaterCancellationRequested -State $Script:CancellationState) {
                break
            }
            $id = [string](Get-RowValue -Row $row -ColumnName 'Id')
            $source = ([string](Get-RowValue -Row $row -ColumnName 'Source')).Trim()
            $package = [pscustomobject]@{
                Id = $id
                Name = [string](Get-RowValue -Row $row -ColumnName 'Name')
                CurrentVersion = [string](Get-RowValue -Row $row -ColumnName 'CurrentVersion')
                AvailableVersion = [string](Get-RowValue -Row $row -ColumnName 'AvailableVersion')
                Source = $source
            }
            Set-RowValue -Row $row -ColumnName 'Status' -Value 'Aktualizacja...'

            $arguments = @(New-WingetPackageUpgradeArguments `
                -Id $id `
                -Source $source `
                -Capabilities $Script:WingetInfo `
                -SourceAgreementsAccepted $Script:SourceAgreementsAccepted `
                -PackageAgreementsConfirmed $true `
                -Interactive ($null -ne $Script:InteractiveCheck -and $Script:InteractiveCheck.Checked) `
                -Silent ($null -ne $Script:SilentCheck -and $Script:SilentCheck.Checked) `
                -IncludeUnknown ($null -ne $Script:IncludeUnknownCheck -and $Script:IncludeUnknownCheck.Checked))
            $result = Invoke-Winget -Arguments $arguments -Package $package -LiveLog

            if ($result.Cancelled) {
                Set-RowValue -Row $row -ColumnName 'Status' -Value 'Anulowano'
                Append-Log "Anulowano [$id]"
                break
            }
            elseif (-not $result.Started) {
                Set-RowValue -Row $row -ColumnName 'Status' -Value 'Blad uruchomienia'
                Append-Log "BLAD INFRASTRUKTURY [$id]: proces nie zostal uruchomiony. $($result.InfrastructureError)"
            }
            elseif (-not [string]::IsNullOrWhiteSpace($result.InfrastructureError)) {
                Set-RowValue -Row $row -ColumnName 'Status' -Value 'Blad infrastruktury'
                Append-Log "BLAD INFRASTRUKTURY [$id]: $($result.InfrastructureError)"
            }
            elseif ($result.ExitCode -eq 0) {
                Set-RowValue -Row $row -ColumnName 'Status' -Value 'OK'
                $attemptKey = Get-PackageAttemptKey -Id $id -Source $source
                $Script:AttemptedUpdates[$attemptKey] = [string](Get-RowValue -Row $row -ColumnName 'AvailableVersion')
                $Script:SuccessfulAttemptResults[$attemptKey] = $result
                Remove-WingetUpdaterSessionFailure -Registry $Script:UnresolvedFailures -Id $id -Source $source
            }
            else {
                Set-RowValue -Row $row -ColumnName 'Status' -Value "Blad: $($result.ExitCode)"
                Add-WingetUpdaterSessionFailure -Registry $Script:UnresolvedFailures -Package $package -Result $result -FailureType 'PackageUpgradeFailure'
            }
        }

        if (-not (Test-WingetUpdaterCancellationRequested -State $Script:CancellationState)) {
            $Script:StatusLabel.Text = 'Aktualizacja zakonczona. Odwiezenie listy...'
            Refresh-Packages -PreserveLog -ListOnly -KeepBusy
        }
        else {
            $Script:StatusLabel.Text = 'Anulowano.'
        }
    }
    catch {
        Append-Log $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Blad podczas aktualizacji',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
      finally {
        Complete-Operation -Message $Script:StatusLabel.Text
      }
}

function Get-UnknownPackageRows {
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Script:Packages.Rows) {
        if (-not ($row -is [System.Data.DataRow])) {
            continue
        }

        if (Test-IsUnknownVersionText -Text ([string](Get-RowValue -Row $row -ColumnName 'CurrentVersion'))) {
            [void]$rows.Add($row)
        }
    }

    return ,$rows
}

function ConvertTo-CellText {
    param([object]$Value)

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return ''
    }

    return ([string]$Value).Trim()
}

function Get-RowValue {
    param(
        [object]$Row,
        [string]$ColumnName
    )

    if ($null -eq $Row) {
        return $null
    }

    if ($Row -is [System.Data.DataRow]) {
        return $Row.Item($ColumnName)
    }

    if ($Row -is [System.Windows.Forms.DataGridViewRow]) {
        return $Row.Cells[$ColumnName].Value
    }

    throw "Nieprawidlowy typ wiersza tabeli: $($Row.GetType().FullName). Oczekiwano System.Data.DataRow."
}

function Test-IsPackageRow {
    param([object]$Row)

    return ($Row -is [System.Data.DataRow])
}

function Assert-PackageRows {
    param(
        [object]$Rows,
        [string]$Operation
    )

    foreach ($row in $Rows) {
        if (-not (Test-IsPackageRow -Row $row)) {
            throw "${Operation}: nieprawidlowy element listy pakietow: $($row.GetType().FullName)."
        }
    }

    return $true
}

function Set-RowValue {
    param(
        [object]$Row,
        [string]$ColumnName,
        [object]$Value
    )

    if ($Row -is [System.Data.DataRow]) {
        $Row.Item($ColumnName) = $Value
        return
    }

    if ($Row -is [System.Windows.Forms.DataGridViewRow]) {
        $Row.Cells[$ColumnName].Value = $Value
        return
    }

    throw "Nieprawidlowy typ wiersza tabeli: $($Row.GetType().FullName). Oczekiwano System.Data.DataRow."
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([string]$Text)

    return "'" + (([string]$Text) -replace "'", "''") + "'"
}

function Get-SelectedFailedPackageRows {
    if ($null -eq $Script:Grid) {
        return @()
    }
    $selectedRows = New-Object System.Collections.Generic.List[object]
    foreach ($gridRow in $Script:Grid.SelectedRows) {
        $status = [string](Get-RowValue -Row $gridRow -ColumnName 'Status')
        $issue = [string](Get-RowValue -Row $gridRow -ColumnName 'IssueType')
        if ($status -match '^Blad' -or $issue -eq 'Aplikacja samoaktualizujaca') {
            $id = [string](Get-RowValue -Row $gridRow -ColumnName 'Id')
            $source = [string](Get-RowValue -Row $gridRow -ColumnName 'Source')
            $name = [string](Get-RowValue -Row $gridRow -ColumnName 'Name')
            $currentVersion = [string](Get-RowValue -Row $gridRow -ColumnName 'CurrentVersion')
            $availableVersion = [string](Get-RowValue -Row $gridRow -ColumnName 'AvailableVersion')
            [void]$selectedRows.Add([pscustomobject]@{
                Id = $id
                Source = $source
                Name = $name
                CurrentVersion = $currentVersion
                AvailableVersion = $availableVersion
            })
        }
    }
    return ,$selectedRows.ToArray()
}

function Copy-AIFailureContext {
    if (-not (Test-OperationEntryAllowed)) {
        return
    }
    Set-Busy -Busy $true -Message 'Przygotowywanie informacji dla AI...'

    try {
        Commit-GridEdits

        $selectedPackages = Get-SelectedFailedPackageRows
        $failures = @(Get-WingetUpdaterSessionFailures -Registry $Script:UnresolvedFailures -SelectedPackages $selectedPackages)

        if ($failures.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show(
                'Brak zarejestrowanych błędów aktualizacji w tej sesji.',
                'Winget Updater',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            return
        }

        $warningMsg = "Ostrzezenie o prywatnosci: Plik kontekstu diagnostycznego oraz logi wyjsciowe moga zawierac lokalne sciezki lub dane systemowe.`r`n`r`nCzy chcesz utworzyc plik kontekstu i skopiowac tresc promptu do schowka?"
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            $warningMsg,
            'Ostrzezenie o prywatnosci - Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
            return
        }

        $contextPath = New-WingetUpdaterRepairContextFile -Directory $Script:Paths.RepairContextsDirectory -Failures $failures
        $promptText = Get-WingetUpdaterAIPrompt -ContextFilePath $contextPath

        [System.Windows.Forms.Clipboard]::SetText($promptText)

        Append-Log "Utworzono plik kontekstu diagnostycznego: $contextPath"
        Append-Log "Skopiowano tresc promptu AI do schowka."
        $Script:StatusLabel.Text = "Skopiowano tresc promptu AI do schowka."
    }
    finally {
        Complete-Operation -Message $Script:StatusLabel.Text
    }
}

function Open-SelectedAICli {
    if (-not (Test-OperationEntryAllowed)) {
        return
    }
    Set-Busy -Busy $true -Message 'Uruchamianie CLI AI...'

    try {
        $selectedItem = [string]$Script:AgentCombo.SelectedItem
        $cliName = if ($selectedItem -match 'agy') { 'agy' } else { 'codex' }

        $resolvedPath = Resolve-WingetUpdaterAICliPath -CliName $cliName
        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Nie znaleziono $cliName w PATH.",
                'Winget Updater',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }

        Start-WingetUpdaterAICliProcess -CliPath $resolvedPath
        Append-Log "Uruchomiono interaktywny CLI: $cliName ($resolvedPath)"
    }
    finally {
        Complete-Operation -Message $Script:StatusLabel.Text
    }
}

function Add-TextColumn {
    param(
        [string]$Name,
        [string]$Header,
        [int]$Width,
        [string]$Property
    )

    $column = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $column.Name = $Name
    $column.HeaderText = $Header
    $column.DataPropertyName = $Property
    $column.Width = $Width
    $column.ReadOnly = $true
    [void]$Script:Grid.Columns.Add($column)
}

function Set-ControlToolTip {
    param(
        [System.Windows.Forms.Control]$Control,
        [string]$Text
    )

    if ($null -ne $Script:ToolTip -and $null -ne $Control) {
        $Script:ToolTip.SetToolTip($Control, $Text)
    }
}

Load-SkipList

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($threadSender, $threadEventArgs)
    $null = $threadSender
    Show-AppError -ErrorRecord $threadEventArgs.Exception -Title 'Blad aplikacji'
})

$Script:ToolTip = New-Object System.Windows.Forms.ToolTip
$Script:ToolTip.AutoPopDelay = 12000
$Script:ToolTip.InitialDelay = 500
$Script:ToolTip.ReshowDelay = 100
$Script:ToolTip.ShowAlways = $true

$Script:Form = New-Object System.Windows.Forms.Form
$Script:Form.Text = 'WingetUpdater by Zalesny123'
$workingArea = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
$windowMargin = 24
$desiredWidth = 1220
$desiredHeight = 700
$maxWidth = [Math]::Max(760, $workingArea.Width - $windowMargin)
$maxHeight = [Math]::Max(520, $workingArea.Height - $windowMargin)
$formWidth = [Math]::Min($desiredWidth, $maxWidth)
$formHeight = [Math]::Min($desiredHeight, $maxHeight)
$formX = $workingArea.Left + [Math]::Max(0, [int](($workingArea.Width - $formWidth) / 2))
$formY = $workingArea.Top + [Math]::Max(0, [int](($workingArea.Height - $formHeight) / 2))
$Script:Form.StartPosition = 'Manual'
$Script:Form.Bounds = New-Object System.Drawing.Rectangle($formX, $formY, $formWidth, $formHeight)
$Script:Form.MinimumSize = New-Object System.Drawing.Size(
    ([Math]::Min(980, $formWidth)),
    ([Math]::Min(560, $formHeight))
)

$layout = New-Object System.Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.ColumnCount = 1
$layout.RowCount = 4
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 118)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 205)))
[void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))

$topPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$topPanel.Dock = 'Fill'
$topPanel.Padding = New-Object System.Windows.Forms.Padding(8, 8, 8, 4)
$topPanel.WrapContents = $true

$Script:RefreshButton = New-Object System.Windows.Forms.Button
$Script:RefreshButton.Text = 'Odswiez'
$Script:RefreshButton.Width = 90
$Script:RefreshButton.Height = 28
$Script:RefreshButton.Add_Click({ try { Refresh-Packages } catch { Show-AppError -ErrorRecord $_ -Title 'Blad podczas odswiezania' } })
Set-ControlToolTip -Control $Script:RefreshButton -Text 'Najpierw odswieza zrodla przez winget source update, a potem sprawdza aktualizacje i bezpiecznie zastepuje tabele.'

$Script:UpdateButton = New-Object System.Windows.Forms.Button
$Script:UpdateButton.Text = 'Aktualizuj zaznaczone'
$Script:UpdateButton.Width = 150
$Script:UpdateButton.Height = 28
$Script:UpdateButton.Add_Click({ try { Update-SelectedPackages } catch { Show-AppError -ErrorRecord $_ -Title 'Blad podczas aktualizacji' } })
Set-ControlToolTip -Control $Script:UpdateButton -Text 'Pokazuje pelna liste zaznaczonych pakietow i po potwierdzeniu aktualizuje tylko te, ktore nie sa oznaczone jako Pomijaj.'

$Script:SaveButton = New-Object System.Windows.Forms.Button
$Script:SaveButton.Text = 'Zapisz pomijane'
$Script:SaveButton.Width = 120
$Script:SaveButton.Height = 28
$Script:SaveButton.Add_Click({ try { Save-SkipList } catch { Show-AppError -ErrorRecord $_ -Title 'Blad podczas zapisu' } })
Set-ControlToolTip -Control $Script:SaveButton -Text 'Zapisuje aktualnie zaznaczone pakiety Pomijaj do pliku skip-list.json.'

$Script:LoadSkippedButton = New-Object System.Windows.Forms.Button
$Script:LoadSkippedButton.Text = 'Wczytaj pomijane'
$Script:LoadSkippedButton.Width = 125
$Script:LoadSkippedButton.Height = 28
$Script:LoadSkippedButton.Add_Click({ try { Apply-SkipListToVisiblePackages } catch { Show-AppError -ErrorRecord $_ -Title 'Blad wczytywania pomijanych' } })
Set-ControlToolTip -Control $Script:LoadSkippedButton -Text 'Wczytuje skip-list.json i oznacza widoczne pakiety zapisane jako Pomijaj.'

$Script:UpdateAllButton = New-Object System.Windows.Forms.Button
$Script:UpdateAllButton.Text = 'Akt: wszystkie'
$Script:UpdateAllButton.Width = 105
$Script:UpdateAllButton.Height = 28
$Script:UpdateAllButton.Add_Click({ try { Set-AllPackageSelection -ColumnName 'Update' -Checked $true } catch { Show-AppError -ErrorRecord $_ -Title 'Blad wyboru pakietow' } })
Set-ControlToolTip -Control $Script:UpdateAllButton -Text 'Zaznacza wszystkie widoczne pakiety w kolumnie Aktualizuj. Nie odznacza Pomijaj.'

$Script:UpdateNoneButton = New-Object System.Windows.Forms.Button
$Script:UpdateNoneButton.Text = 'Akt: nic'
$Script:UpdateNoneButton.Width = 80
$Script:UpdateNoneButton.Height = 28
$Script:UpdateNoneButton.Add_Click({ try { Set-AllPackageSelection -ColumnName 'Update' -Checked $false } catch { Show-AppError -ErrorRecord $_ -Title 'Blad wyboru pakietow' } })
Set-ControlToolTip -Control $Script:UpdateNoneButton -Text 'Odznacza wszystkie widoczne pakiety w kolumnie Aktualizuj.'

$Script:SkipAllButton = New-Object System.Windows.Forms.Button
$Script:SkipAllButton.Text = 'Pom: wszystkie'
$Script:SkipAllButton.Width = 110
$Script:SkipAllButton.Height = 28
$Script:SkipAllButton.Add_Click({ try { Set-AllPackageSelection -ColumnName 'Skip' -Checked $true } catch { Show-AppError -ErrorRecord $_ -Title 'Blad wyboru pakietow' } })
Set-ControlToolTip -Control $Script:SkipAllButton -Text 'Zaznacza wszystkie widoczne pakiety jako Pomijaj i odznacza im Aktualizuj.'

$Script:SkipNoneButton = New-Object System.Windows.Forms.Button
$Script:SkipNoneButton.Text = 'Pom: nic'
$Script:SkipNoneButton.Width = 80
$Script:SkipNoneButton.Height = 28
$Script:SkipNoneButton.Add_Click({ try { Set-AllPackageSelection -ColumnName 'Skip' -Checked $false } catch { Show-AppError -ErrorRecord $_ -Title 'Blad wyboru pakietow' } })
Set-ControlToolTip -Control $Script:SkipNoneButton -Text 'Odznacza wszystkie widoczne pakiety w kolumnie Pomijaj.'

$Script:SilentCheck = New-Object System.Windows.Forms.CheckBox
$Script:SilentCheck.Text = 'Tryb cichy'
$Script:SilentCheck.Width = 85
$Script:SilentCheck.Height = 28
$Script:SilentCheck.Checked = $false
Set-ControlToolTip -Control $Script:SilentCheck -Text 'Dodaje --silent do aktualizacji. Instalatory sprobuja dzialac bez okien i pytan, ale nie kazdy pakiet to obsluguje.'

$Script:InteractiveCheck = New-Object System.Windows.Forms.CheckBox
$Script:InteractiveCheck.Text = 'Wymus UI (--interactive)'
$Script:InteractiveCheck.Width = 145
$Script:InteractiveCheck.Height = 28
$Script:InteractiveCheck.Checked = $false
Set-ControlToolTip -Control $Script:InteractiveCheck -Text 'Dodaje --interactive. Wymusza pokazanie kreatora instalacji. Przydatne, gdy instalator cichy zacina sie w tle.'

$Script:IncludeUnknownCheck = New-Object System.Windows.Forms.CheckBox
$Script:IncludeUnknownCheck.Text = 'Uwzglednij Unknown (-u)'
$Script:IncludeUnknownCheck.Width = 165
$Script:IncludeUnknownCheck.Height = 28
$Script:IncludeUnknownCheck.Checked = $true
Set-ControlToolTip -Control $Script:IncludeUnknownCheck -Text 'Dodaje --include-unknown. Pokazuje i pozwala aktualizowac pakiety, dla ktorych winget nie zna obecnej wersji.'


$Script:CopyMessageButton = New-Object System.Windows.Forms.Button
$Script:CopyMessageButton.Text = 'Kopiuj wiadomość AI'
$Script:CopyMessageButton.Width = 140
$Script:CopyMessageButton.Height = 28
$Script:CopyMessageButton.Add_Click({ try { Copy-AIFailureContext } catch { Show-AppError -ErrorRecord $_ -Title 'Błąd kopiowania wiadomości AI' } })
Set-ControlToolTip -Control $Script:CopyMessageButton -Text 'Tworzy plik kontekstu z zarejestrowanymi błędami i kopiuje tresc promptu dla AI do schowka.'

$Script:AgentCombo = New-Object System.Windows.Forms.ComboBox
$Script:AgentCombo.DropDownStyle = 'DropDownList'
$Script:AgentCombo.Width = 95
$Script:AgentCombo.Height = 28
[void]$Script:AgentCombo.Items.AddRange([object[]]@('Codex CLI', 'agy CLI'))
if ($null -ne (Get-Command codex -ErrorAction SilentlyContinue)) {
    $Script:AgentCombo.SelectedItem = 'Codex CLI'
}
else {
    $Script:AgentCombo.SelectedItem = 'agy CLI'
}
Set-ControlToolTip -Control $Script:AgentCombo -Text 'Wybiera CLI AI do uruchomienia w osobnym konsolowym oknie.'

$Script:OpenAiCliButton = New-Object System.Windows.Forms.Button
$Script:OpenAiCliButton.Text = 'Otwórz CLI AI'
$Script:OpenAiCliButton.Width = 105
$Script:OpenAiCliButton.Height = 28
$Script:OpenAiCliButton.Add_Click({ try { Open-SelectedAICli } catch { Show-AppError -ErrorRecord $_ -Title 'Błąd uruchamiania CLI AI' } })
Set-ControlToolTip -Control $Script:OpenAiCliButton -Text 'Otwiera wybrany interaktywny CLI (Codex lub agy) w nowym oknie konsoli bez podnoszenia uprawnien.'

$Script:CancelButton = New-Object System.Windows.Forms.Button
$Script:CancelButton.Text = 'Anuluj'
$Script:CancelButton.Width = 90
$Script:CancelButton.Height = 28
$Script:CancelButton.Enabled = $false
$Script:CancelButton.Visible = $false
$Script:CancelButton.Add_Click({
    if ($Script:IsBusy) {
        [void](Confirm-OperationCancellation)
    }
})
Set-ControlToolTip -Control $Script:CancelButton -Text 'Zatrzymuje biezacy proces winget i pomija pozostale pakiety.'

$Script:StatusLabel = New-Object System.Windows.Forms.Label
$Script:StatusLabel.Text = "$(Get-PowerShellRuntimeText). Gotowe."
$Script:StatusLabel.AutoSize = $true
$Script:StatusLabel.Margin = New-Object System.Windows.Forms.Padding(12, 7, 3, 3)
Set-ControlToolTip -Control $Script:StatusLabel -Text 'Biezacy stan programu.'

$Script:SpinnerLabel = New-Object System.Windows.Forms.Label
$Script:SpinnerLabel.Text = ''
$Script:SpinnerLabel.Width = 28
$Script:SpinnerLabel.Height = 28
$Script:SpinnerLabel.TextAlign = 'MiddleCenter'
$Script:SpinnerLabel.Font = New-Object System.Drawing.Font('Consolas', 12)
$Script:SpinnerLabel.Margin = New-Object System.Windows.Forms.Padding(8, 2, 0, 0)
Set-ControlToolTip -Control $Script:SpinnerLabel -Text 'Spinner pracy winget. Obraca sie w czasie sprawdzania lub aktualizacji.'

[void]$topPanel.Controls.Add($Script:RefreshButton)
[void]$topPanel.Controls.Add($Script:UpdateButton)
[void]$topPanel.Controls.Add($Script:SaveButton)
[void]$topPanel.Controls.Add($Script:LoadSkippedButton)
[void]$topPanel.Controls.Add($Script:UpdateAllButton)
[void]$topPanel.Controls.Add($Script:UpdateNoneButton)
[void]$topPanel.Controls.Add($Script:SkipAllButton)
[void]$topPanel.Controls.Add($Script:SkipNoneButton)
[void]$topPanel.Controls.Add($Script:SilentCheck)
[void]$topPanel.Controls.Add($Script:InteractiveCheck)
[void]$topPanel.Controls.Add($Script:IncludeUnknownCheck)

# --- POCZĄTEK: UI TRYBU TESTOWEGO ---
$Script:TestModeCheck = New-Object System.Windows.Forms.CheckBox
$Script:TestModeCheck.Text = 'TRYB TESTOWY (Mock)'
$Script:TestModeCheck.Width = 150
$Script:TestModeCheck.Height = 28
$Script:TestModeCheck.Checked = $false
$Script:TestModeCheck.ForeColor = [System.Drawing.Color]::Red
Set-ControlToolTip -Control $Script:TestModeCheck -Text 'Symuluje dzialanie wingeta za pomoca wirtualnych pakietow. Nie modyfikuje systemu.'
[void]$topPanel.Controls.Add($Script:TestModeCheck)
# --- KONIEC: UI TRYBU TESTOWEGO ---

[void]$topPanel.Controls.Add($Script:CopyMessageButton)
[void]$topPanel.Controls.Add($Script:AgentCombo)
[void]$topPanel.Controls.Add($Script:OpenAiCliButton)
[void]$topPanel.Controls.Add($Script:CancelButton)
[void]$topPanel.Controls.Add($Script:SpinnerLabel)
[void]$topPanel.Controls.Add($Script:StatusLabel)

$Script:Grid = New-Object System.Windows.Forms.DataGridView
$Script:Grid.Dock = 'Fill'
$Script:Grid.AutoGenerateColumns = $false
$Script:Grid.AllowUserToAddRows = $false
$Script:Grid.AllowUserToDeleteRows = $false
$Script:Grid.SelectionMode = 'FullRowSelect'
$Script:Grid.MultiSelect = $true
$Script:Grid.RowHeadersVisible = $false
$Script:Grid.AutoSizeRowsMode = 'None'
$Script:Grid.DataSource = $Script:Packages

$updateColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$updateColumn.Name = 'Update'
$updateColumn.HeaderText = 'Aktualizuj'
$updateColumn.DataPropertyName = 'Update'
$updateColumn.Width = 80
[void]$Script:Grid.Columns.Add($updateColumn)

$skipColumn = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$skipColumn.Name = 'Skip'
$skipColumn.HeaderText = 'Pomijaj'
$skipColumn.DataPropertyName = 'Skip'
$skipColumn.Width = 70
[void]$Script:Grid.Columns.Add($skipColumn)

Add-TextColumn -Name 'Name' -Header 'Nazwa' -Width 250 -Property 'Name'
Add-TextColumn -Name 'Id' -Header 'ID' -Width 250 -Property 'Id'
Add-TextColumn -Name 'CurrentVersion' -Header 'Obecna' -Width 110 -Property 'CurrentVersion'
Add-TextColumn -Name 'AvailableVersion' -Header 'Dostepna' -Width 110 -Property 'AvailableVersion'
Add-TextColumn -Name 'IssueType' -Header 'Problem' -Width 105 -Property 'IssueType'
Add-TextColumn -Name 'Source' -Header 'Zrodlo' -Width 80 -Property 'Source'
Add-TextColumn -Name 'Status' -Header 'Status' -Width 130 -Property 'Status'

$Script:Grid.Add_CurrentCellDirtyStateChanged({
    if ($Script:Grid.IsCurrentCellDirty) {
        [void]$Script:Grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

$Script:Grid.Add_CellValueChanged({
    param($gridSender, $cellEventArgs)
    $null = $gridSender

    if ($cellEventArgs.RowIndex -lt 0 -or $cellEventArgs.ColumnIndex -lt 0) {
        return
    }

    $columnName = $Script:Grid.Columns[$cellEventArgs.ColumnIndex].Name
    $row = $Script:Grid.Rows[$cellEventArgs.RowIndex]

    if ($columnName -eq 'Skip' -and [bool]($row.Cells['Skip'].Value)) {
        $row.Cells['Update'].Value = $false
        $row.Cells['Status'].Value = 'Pominiete'
    }
    elseif ($columnName -eq 'Update' -and [bool]($row.Cells['Update'].Value)) {
        if (Test-IsGhostPackageRow -Row $row) {
            $row.Cells['Update'].Value = $false
            $row.Cells['Status'].Value = 'Blad (Ghost)'
            return
        }
        $row.Cells['Skip'].Value = $false
        if ([string]($row.Cells['Status'].Value) -eq 'Pominiete') {
            $row.Cells['Status'].Value = ''
        }
    }
    elseif ($columnName -eq 'Skip' -and -not [bool]($row.Cells['Skip'].Value)) {
        if (Test-IsGhostPackageRow -Row $row) {
            $row.Cells['Update'].Value = $false
            $row.Cells['Status'].Value = 'Blad (Ghost)'
        }
        elseif ([string]($row.Cells['Status'].Value) -eq 'Pominiete') {
            $row.Cells['Status'].Value = ''
        }
    }
})

$Script:LogBox = New-Object System.Windows.Forms.TextBox
$Script:LogBox.Dock = 'Fill'
$Script:LogBox.Multiline = $true
$Script:LogBox.ReadOnly = $true
$Script:LogBox.ScrollBars = 'Vertical'
$Script:LogBox.Font = New-Object System.Drawing.Font('Consolas', 9)

$bottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
$bottomPanel.Dock = 'Fill'
$bottomPanel.ColumnCount = 2
$bottomPanel.RowCount = 1
$bottomPanel.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$bottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
[void]$bottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))

$Script:VersionLabel = New-Object System.Windows.Forms.Label
$Script:VersionLabel.Text = 'Wersja 1.0'
$Script:VersionLabel.Dock = 'Fill'
$Script:VersionLabel.TextAlign = 'MiddleLeft'
$Script:VersionLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$Script:VersionLabel.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)

$Script:CopyrightLabel = New-Object System.Windows.Forms.Label
$Script:CopyrightLabel.Text = 'Copyright © 2026 Zalesny123'
$Script:CopyrightLabel.Dock = 'Fill'
$Script:CopyrightLabel.TextAlign = 'MiddleRight'
$Script:CopyrightLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$Script:CopyrightLabel.Padding = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)

[void]$bottomPanel.Controls.Add($Script:VersionLabel, 0, 0)
[void]$bottomPanel.Controls.Add($Script:CopyrightLabel, 1, 0)

[void]$layout.Controls.Add($topPanel, 0, 0)
[void]$layout.Controls.Add($Script:Grid, 0, 1)
[void]$layout.Controls.Add($Script:LogBox, 0, 2)
[void]$layout.Controls.Add($bottomPanel, 0, 3)
[void]$Script:Form.Controls.Add($layout)

$Script:Form.Add_FormClosing({
    param($formClosingSender, $formClosingEventArgs)
    $null = $formClosingSender

    $shouldCancelClose = Test-ShouldCancelFormClose
    if ($shouldCancelClose) {
        $formClosingEventArgs.Cancel = $true
    }
    $decision = Resolve-WingetUpdaterCloseRequest `
        -IsBusy $Script:IsBusy `
        -CancellationConfirmed $false `
        -CancellationAlreadyRequested (Test-WingetUpdaterCancellationRequested -State $Script:CancellationState)
    if ($Script:IsBusy) {
        if (-not $decision.DeferClose) {
            $choice = [System.Windows.Forms.MessageBox]::Show(
                'Operacja jest w toku. Czy anulowac ja i zamknac program po zakonczeniu sprzatania?',
                'Zamknij Winget Updater',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            $decision = Resolve-WingetUpdaterCloseRequest `
                -IsBusy $Script:IsBusy `
                -CancellationConfirmed ($choice -eq [System.Windows.Forms.DialogResult]::Yes) `
                -CancellationAlreadyRequested (Test-WingetUpdaterCancellationRequested -State $Script:CancellationState)
        }
        $formClosingEventArgs.Cancel = $decision.CancelClose
        if ($decision.DeferClose) {
            $Script:ClosePending = $true
        }
        if ($decision.RequestCancellation) {
            Request-WingetUpdaterCancellation -State $Script:CancellationState
        }
        return
    }

    try {
        Save-SkipList -Silent
    }
    catch {
        Write-Verbose "Closing skip-list save failed: $($_.Exception.Message)"
    }
})

$Script:Form.Add_Shown({
    $preserveStartupWarnings = $false
    foreach ($warning in $Script:StartupWarnings) {
        Append-Log "UWAGA: $warning"
        $preserveStartupWarnings = $true
    }
    Refresh-Packages -PreserveLog:$preserveStartupWarnings
})

[void][System.Windows.Forms.Application]::Run($Script:Form)
}
finally {
    Dispose-WingetUpdaterResource -Resource $Script:Form -ResourceName 'Form'
    $Script:Form = $null
    Dispose-WingetUpdaterResource -Resource $Script:ToolTip -ResourceName 'ToolTip'
    $Script:ToolTip = $null
    if ($null -ne $Script:MutexLease) {
        Exit-WingetUpdaterSingleInstance -Lease $Script:MutexLease
        $Script:MutexLease = $null
    }
}
