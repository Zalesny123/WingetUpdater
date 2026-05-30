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

param (
    [string]$LauncherSecret = ''
)

Set-StrictMode -Version 2.0

if ($LauncherSecret -ne 'StartBat123') {
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
$Script:SkipFile = Join-Path $Script:AppDir 'skip-list.json'
$Script:RepairDir = Join-Path $Script:AppDir 'repair-contexts'
$Script:SkippedIds = @{}
$Script:AttemptedUpdates = @{}
$Script:WingetInfo = $null
$Script:MinimumWingetVersion = [version]'1.4.0'
$Script:RefreshButton = $null
$Script:UpdateButton = $null
$Script:SaveButton = $null
$Script:LoadSkippedButton = $null
$Script:UpdateAllButton = $null
$Script:UpdateNoneButton = $null
$Script:SkipAllButton = $null
$Script:SkipNoneButton = $null
$Script:RepairButton = $null
$Script:SourceUpdateButton = $null
$Script:SilentCheck = $null
$Script:InteractiveCheck = $null
$Script:IncludeUnknownCheck = $null
$Script:SourceUpdateCheck = $null
$Script:TerminalCombo = $null
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
$Script:Form = $null
$Script:TestModeCheck = $null
$Script:MockFile = Join-Path $Script:AppDir 'MockState.json'

function Reset-MockState {
    $data = [ordered]@{
        'Test.UserOK' = @{ Name = 'Aplikacja Zwykla (User)'; Current = '1.0'; Available = '2.0'; Scope = 'User'; ExitCode = 0; AdminExitCode = 0; Ghost = $false }
        'Test.MachineOK' = @{ Name = 'Aplikacja Systemowa (Admin)'; Current = '1.0'; Available = '2.0'; Scope = 'Machine'; ExitCode = 0; AdminExitCode = 0; Ghost = $false }
        'Test.SpotifyLike' = @{ Name = 'Aplikacja Spotify-podobna'; Current = '1.0'; Available = '2.0'; Scope = 'User'; ExitCode = 0; AdminExitCode = -1978335146; Ghost = $false }
        'Test.OperaLike' = @{ Name = 'Aplikacja Opera-podobna'; Current = '1.0'; Available = '2.0'; Scope = 'Machine'; ExitCode = -1978335212; AdminExitCode = -1978335212; Ghost = $false }
        'Test.Uparty' = @{ Name = 'Aplikacja Uparta (Ghost)'; Current = '1.0'; Available = '2.0'; Scope = 'Machine'; ExitCode = 0; AdminExitCode = 0; Ghost = $true }
        'Test.UnknownVer' = @{ Name = 'Aplikacja Unknown'; Current = 'Unknown'; Available = '2.0'; Scope = 'User'; ExitCode = 0; AdminExitCode = 0; Ghost = $false }
    }
    $data | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Script:MockFile -Encoding UTF8
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
    Write-Output -NoEnumerate $table
}

$Script:Packages = New-PackagesTable

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-RunningAsAdministrator {
    if (Test-IsAdministrator) {
        return
    }

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Program musi byc uruchomiony jako administrator, ale nie udalo sie odnalezc pliku skryptu: $scriptPath"
    }

    $hostPath = (Get-Process -Id $PID).Path
    if ([string]::IsNullOrWhiteSpace($hostPath)) {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            $hostPath = 'pwsh.exe'
        }
        else {
            $hostPath = 'powershell.exe'
        }
    }

    try {
        Start-Process `
            -FilePath $hostPath `
            -Verb RunAs `
            -WorkingDirectory ([Environment]::GetFolderPath('UserProfile')) `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $scriptPath)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Nie udalo sie uruchomic programu jako administrator.`r`n$($_.Exception.Message)",
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }

    exit 0
}

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

function Load-SkipList {
    $Script:SkippedIds = @{}

    if (-not (Test-Path -LiteralPath $Script:SkipFile)) {
        return
    }

    try {
        $raw = Get-Content -LiteralPath $Script:SkipFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return
        }

        $data = $raw | ConvertFrom-Json
        $ids = @()

        if ($data -is [array]) {
            $ids = $data
        }
        elseif ($null -ne $data.skippedIds) {
            $ids = $data.skippedIds
        }
        elseif ($null -ne $data.SkippedIds) {
            $ids = $data.SkippedIds
        }

        foreach ($id in $ids) {
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

function ConvertTo-PlainText {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $escape = [regex]::Escape([string][char]27)
    $withoutAnsi = [regex]::Replace($Text, "$escape\[[0-?]*[ -/]*[@-~]", '')
    $plain = ($withoutAnsi -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    return Repair-DisplayText -Text $plain
}

function Repair-DisplayText {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $value = [string]$Text
    $value = $value.Replace([string][char]0x2026, '...')
    $ellipsisForms = @(
        ([string]::Concat([char]0x00D4, [char]0x00C7, [char]0x00AA)),
        ([string]::Concat([char]0x00D4, [char]0x00C7, [char]0x017D)),
        ([string]::Concat([char]0x0393, [char]0x00C7, [char]0x00AA)),
        ([string]::Concat([char]0x00E2, [char]0x20AC, [char]0x00A6))
    )
    foreach ($form in $ellipsisForms) {
        $value = $value.Replace($form, '...')
    }

    $dashForms = @(
        ([string]::Concat([char]0x00D4, [char]0x00C7, [char]0x00F4)),
        ([string]::Concat([char]0x0393, [char]0x00C7, [char]0x00F4)),
        ([string]::Concat([char]0x00E2, [char]0x20AC, [char]0x201C)),
        ([string]::Concat([char]0x00D4, [char]0x00C7, [char]0x00F6)),
        ([string]::Concat([char]0x0393, [char]0x00C7, [char]0x00F6)),
        ([string]::Concat([char]0x00E2, [char]0x20AC, [char]0x201D))
    )
    foreach ($form in $dashForms) {
        $value = $value.Replace($form, '-')
    }

    return $value.Trim()
}

function Parse-WingetPackageLine {
    param([string]$Line)

    $lineText = Repair-DisplayText -Text $Line
    if ([string]::IsNullOrWhiteSpace($lineText)) {
        return $null
    }

    # Read from the right side. Long names can contain a display ellipsis and
    # shift fixed-width columns, but Source, Available, Version, and Id remain
    # the last four whitespace-separated tokens.
    $match = [regex]::Match($lineText, '^\s*(?<name>.+?)\s+(?<id>\S+)\s+(?<current>(?:[<>]\s+)?\S+)\s+(?<available>\S+)\s+(?<source>\S+)\s*$')
    if (-not $match.Success) {
        return $null
    }

    $id = Repair-DisplayText -Text $match.Groups['id'].Value
    $available = Repair-DisplayText -Text $match.Groups['available'].Value
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($available)) {
        return $null
    }

    return [pscustomobject]@{
        Name = Repair-DisplayText -Text $match.Groups['name'].Value
        Id = $id
        CurrentVersion = Repair-DisplayText -Text $match.Groups['current'].Value
        AvailableVersion = $available
        Source = Repair-DisplayText -Text $match.Groups['source'].Value
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

    $Script:LogBox.SelectionStart = $Script:LogBox.TextLength
    $Script:LogBox.ScrollToCaret()
    $Script:LogBox.ResumeLayout()
}

function Parse-WingetUpgradeOutput {
    param([string]$Output)

    $text = ConvertTo-PlainText $Output
    $lines = $text -split "`r?`n"
    $packages = New-Object System.Collections.Generic.List[object]
    $seenIds = @{}

    for ($scan = 0; $scan -lt $lines.Count; $scan++) {
        if ($lines[$scan] -notmatch '^\s*-{5,}\s*$' -and $lines[$scan] -notmatch '^\s*-{2,}(\s+-{2,}){3,}\s*$') {
            continue
        }

        $seenRowsInTable = $false
        for ($i = $scan + 1; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]

            if ([string]::IsNullOrWhiteSpace($line)) {
                if ($seenRowsInTable) {
                    break
                }
                continue
            }

            if ($line -match '^\s*-{5,}\s*$' -or $line -match '^\s*-{2,}(\s+-{2,}){3,}\s*$') {
                break
            }

            $package = Parse-WingetPackageLine -Line $line
            if ($null -eq $package) {
                continue
            }

            $id = $package.Id
            $available = $package.AvailableVersion
            if ($id -eq 'Id' -or $available -eq 'Available' -or $seenIds.ContainsKey($id)) {
                continue
            }

            $seenIds[$id] = $true
            $seenRowsInTable = $true
            [void]$packages.Add($package)
        }

        $scan = $i
    }

    return $packages.ToArray()
}

function ConvertTo-CommandLineArgument {
    param([string]$Argument)

    if ($null -eq $Argument) {
        return '""'
    }

    if ($Argument.Length -eq 0) {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    return '"' + ($Argument -replace '"', '\"') + '"'
}

function Join-CommandLineArguments {
    param([string[]]$Arguments)

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($argument in $Arguments) {
        [void]$parts.Add((ConvertTo-CommandLineArgument -Argument $argument))
    }

    return ($parts.ToArray() -join ' ')
}

function Invoke-Winget {
    param(
        [string[]]$Arguments,
        [switch]$LiveLog
    )

    # --- POCZĄTEK: PRZECHWYCENIE WINGET DLA TRYBU TESTOWEGO ---
    if ($null -ne $Script:TestModeCheck -and $Script:TestModeCheck.Checked) {
        if (-not (Test-Path $Script:MockFile)) { Reset-MockState }
        if ($Arguments -contains '--version') { return [pscustomobject]@{ Output = "v1.9.0-mock"; ExitCode = 0 } }
        if ($Arguments -contains '--help') { return [pscustomobject]@{ Output = "--include-unknown --exact --accept-package-agreements --accept-source-agreements --disable-interactivity --silent --source"; ExitCode = 0 } }
        if ($Arguments -contains 'source' -and $Arguments -contains 'update') { return [pscustomobject]@{ Output = "Source updated"; ExitCode = 0 } }
        
        $mock = Get-Content $Script:MockFile | ConvertFrom-Json
        
        # Symulacja wyszukiwania aktualizacji
        if ($Arguments -contains 'upgrade' -and $Arguments -notmatch '--id') {
            $out = "Name Id Version Available Source`n"
            $out += "---- -- ------- --------- ------`n"
            foreach ($key in $mock.PSObject.Properties.Name) {
                $pkg = $mock.$key
                if ($pkg.Current -ne $pkg.Available) {
                    $out += "$($pkg.Name) $key $($pkg.Current) $($pkg.Available) winget`n"
                }
            }
            if ($LiveLog) { Start-Sleep -Milliseconds 500 }
            return [pscustomobject]@{ Output = $out; ExitCode = 0 }
        }
        
        # Symulacja instalacji User
        if ($Arguments -contains 'upgrade' -and $Arguments -contains '--id') {
            $idIdx = [array]::IndexOf($Arguments, '--id') + 1
            $id = $Arguments[$idIdx]
            $pkg = $mock.$id
            
            if ($LiveLog) {
                Update-LogLiveLine -Spinner "-"
                Start-Sleep -Milliseconds 300
                Update-LogLiveLine -Progress "50%"
                Start-Sleep -Milliseconds 300
                Update-LogLiveLine -Progress "100%"
            }
            
            if ($pkg.ExitCode -ne 0) { return [pscustomobject]@{ Output = "Error"; ExitCode = $pkg.ExitCode } }
            if (-not $pkg.Ghost) {
                $pkg.Current = $pkg.Available
                $mock | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Script:MockFile -Encoding UTF8
            }
            return [pscustomobject]@{ Output = "Success"; ExitCode = 0 }
        }
        return [pscustomobject]@{ Output = ""; ExitCode = 0 }
    }
    # --- KONIEC: PRZECHWYCENIE WINGET DLA TRYBU TESTOWEGO ---

    $outputBuilder = New-Object System.Text.StringBuilder
    $process = $null
    $cr = [char]13
    $lf = [char]10

    $processOutputLine = {
        param(
            [string]$RawLine,
            [bool]$IsTransient
        )

        if ($null -eq $RawLine) {
            return
        }

        $line = ConvertTo-PlainText $RawLine
        if ($IsTransient -and [string]::IsNullOrWhiteSpace($line)) {
            return
        }

        [void]$outputBuilder.AppendLine($line)
        if (Test-IsWingetSpinnerLine -Line $line) {
            if ($LiveLog) {
                Step-Spinner
                Update-LogLiveLine -Spinner $line
            }
            return
        }

        $progressText = Get-WingetProgressText -Line $line
        if ($LiveLog -and -not [string]::IsNullOrWhiteSpace($progressText)) {
            Update-LogLiveLine -Progress $progressText
            return
        }

        if ($LiveLog -and $IsTransient) {
            Update-LogLiveLine -Progress $line
            return
        }

        if ($LiveLog -and $Script:LogSpinnerActive -and [string]::IsNullOrWhiteSpace($line)) {
            return
        }

        if ($LiveLog) {
            Append-Log $line
        }
    }

    $newReadState = {
        [pscustomobject]@{
            Buffer = New-Object System.Text.StringBuilder
            PendingCr = $false
            PendingCrLine = ''
        }
    }

    $processOutputText = {
        param(
            [object]$State,
            [string]$Text
        )

        if ([string]::IsNullOrEmpty($Text)) {
            return
        }

        for ($index = 0; $index -lt $Text.Length; $index++) {
            $ch = $Text[$index]

            if ($State.PendingCr) {
                if ($ch -eq $lf) {
                    & $processOutputLine $State.PendingCrLine $false
                    $State.PendingCr = $false
                    $State.PendingCrLine = ''
                    continue
                }

                & $processOutputLine $State.PendingCrLine $true
                $State.PendingCr = $false
                $State.PendingCrLine = ''
            }

            if ($ch -eq $cr) {
                $State.PendingCrLine = $State.Buffer.ToString()
                [void]$State.Buffer.Clear()
                $State.PendingCr = $true
                continue
            }

            if ($ch -eq $lf) {
                & $processOutputLine $State.Buffer.ToString() $false
                [void]$State.Buffer.Clear()
                continue
            }

            [void]$State.Buffer.Append($ch)
        }
    }

    $flushOutputState = {
        param([object]$State)

        if ($State.PendingCr) {
            & $processOutputLine $State.PendingCrLine $true
            $State.PendingCr = $false
            $State.PendingCrLine = ''
        }

        if ($State.Buffer.Length -gt 0) {
            & $processOutputLine $State.Buffer.ToString() $false
            [void]$State.Buffer.Clear()
        }
    }

    try {
        if ($LiveLog) {
            Start-Spinner
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'winget'
        $psi.Arguments = Join-CommandLineArguments -Arguments $Arguments
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        try {
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        }
        catch {
            # Older runtimes can ignore explicit stream encoding.
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi

        [void]$process.Start()

        $stdoutDone = $false
        $stderrDone = $false
        $stdoutState = & $newReadState
        $stderrState = & $newReadState
        $stdoutChars = New-Object 'char[]' 2048
        $stderrChars = New-Object 'char[]' 2048
        $stdoutTask = $process.StandardOutput.ReadAsync($stdoutChars, 0, $stdoutChars.Length)
        $stderrTask = $process.StandardError.ReadAsync($stderrChars, 0, $stderrChars.Length)

        while (-not ($stdoutDone -and $stderrDone)) {
            if (-not $stdoutDone -and $stdoutTask.IsCompleted) {
                try {
                    $read = [int]$stdoutTask.Result
                    if ($read -le 0) {
                        $stdoutDone = $true
                    }
                    else {
                        $text = [string]::new($stdoutChars, 0, $read)
                        & $processOutputText $stdoutState $text
                        $stdoutTask = $process.StandardOutput.ReadAsync($stdoutChars, 0, $stdoutChars.Length)
                    }
                }
                catch {
                    & $processOutputLine $_.Exception.Message $false
                    $stdoutDone = $true
                }
            }

            if (-not $stderrDone -and $stderrTask.IsCompleted) {
                try {
                    $read = [int]$stderrTask.Result
                    if ($read -le 0) {
                        $stderrDone = $true
                    }
                    else {
                        $text = [string]::new($stderrChars, 0, $read)
                        & $processOutputText $stderrState $text
                        $stderrTask = $process.StandardError.ReadAsync($stderrChars, 0, $stderrChars.Length)
                    }
                }
                catch {
                    & $processOutputLine $_.Exception.Message $false
                    $stderrDone = $true
                }
            }

            Start-Sleep -Milliseconds 35
            if ($LiveLog) {
                Step-Spinner
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        & $flushOutputState $stdoutState
        & $flushOutputState $stderrState
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
    catch {
        [void]$outputBuilder.AppendLine($_.Exception.Message)
        if ($LiveLog) {
            Append-Log $_.Exception.Message
        }
        $exitCode = 9999
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
        if ($LiveLog) {
            Stop-Spinner
        }
    }

    return [pscustomobject]@{
        Output = $outputBuilder.ToString()
        ExitCode = $exitCode
    }
}

function Initialize-WingetInfo {
    $command = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'Nie znaleziono winget w PATH.'
    }

    $versionResult = Invoke-Winget -Arguments @('--version')
    $helpResult = Invoke-Winget -Arguments @('upgrade', '--help')
    $versionText = (ConvertTo-PlainText $versionResult.Output).Trim()
    $helpText = ConvertTo-PlainText $helpResult.Output
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
        Path = [string]$command.Source
        VersionText = $versionText
        Version = $version
        SupportsAcceptSourceAgreements = Test-WingetHelpOption -HelpText $helpText -Option '--accept-source-agreements'
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
        $Script:IncludeUnknownCheck.Enabled = [bool]($Script:WingetInfo.SupportsIncludeUnknown)
        if (-not [bool]($Script:WingetInfo.SupportsIncludeUnknown)) {
            $Script:IncludeUnknownCheck.Checked = $false
        }
    }
}

function New-WingetUpgradeListArguments {
    $arguments = @('upgrade')

    if ($null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsAcceptSourceAgreements)) {
        $arguments += '--accept-source-agreements'
    }
    if ($null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsDisableInteractivity)) {
        $arguments += '--disable-interactivity'
    }
    if ($null -ne $Script:IncludeUnknownCheck -and $Script:IncludeUnknownCheck.Checked -and $null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsIncludeUnknown)) {
        $arguments += '--include-unknown'
    }

    return $arguments
}

function New-WingetPackageUpgradeArguments {
    param(
        [string]$Id,
        [string]$Source
    )

    $arguments = @('upgrade', '--id', $Id)

    if ($null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsAcceptPackageAgreements)) {
        $arguments += '--accept-package-agreements'
    }
    if ($null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsAcceptSourceAgreements)) {
        $arguments += '--accept-source-agreements'
    }
    if (-not [string]::IsNullOrWhiteSpace($Source) -and $null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsSource)) {
        $arguments += @('--source', $Source)
    }
    
    if ($null -ne $Script:InteractiveCheck -and $Script:InteractiveCheck.Checked -and $null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsInteractive)) {
        $arguments += '--interactive'
    }
    elseif ($null -ne $Script:SilentCheck -and $Script:SilentCheck.Checked -and $null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsSilent)) {
        $arguments += '--silent'
    }

    if ($null -ne $Script:IncludeUnknownCheck -and $Script:IncludeUnknownCheck.Checked -and $null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsIncludeUnknown)) {
        $arguments += '--include-unknown'
    }

    return $arguments
}

function Add-PackageRow {
    param([pscustomobject]$Package)

    $isSkipped = $Script:SkippedIds.ContainsKey($Package.Id)
    $isGhost = $Script:AttemptedUpdates.ContainsKey($Package.Id) -and $Script:AttemptedUpdates[$Package.Id] -eq $Package.AvailableVersion

    $row = $Script:Packages.NewRow()
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
    Set-RowValue -Row $row -ColumnName 'Status' -Value $(if ($isSkipped) { 'Pominiete' } elseif ($isGhost) { 'Blad (Ghost)' } else { '' })
    
    [void]$Script:Packages.Rows.Add($row)
}

function Commit-GridEdits {
    if ($null -ne $Script:Grid) {
        [void]$Script:Grid.EndEdit()
    }
}

function Save-SkipList {
    param([switch]$Silent)

    Commit-GridEdits

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
    $data = [ordered]@{
        skippedIds = $ids
        updatedAt = (Get-Date).ToString('o')
    }

    $data | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Script:SkipFile -Encoding UTF8

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
    if ($null -ne $Script:RepairButton) {
        $Script:RepairButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:SourceUpdateButton) {
        $Script:SourceUpdateButton.Enabled = -not $Busy
    }
    if ($null -ne $Script:SourceUpdateCheck) {
        $Script:SourceUpdateCheck.Enabled = -not $Busy
    }
    if ($null -ne $Script:TerminalCombo) {
        $Script:TerminalCombo.Enabled = -not $Busy
    }
    if ($null -ne $Script:AgentCombo) {
        $Script:AgentCombo.Enabled = -not $Busy
    }
    $Script:Grid.Enabled = -not $Busy
    $Script:Form.Cursor = if ($Busy) {
        [System.Windows.Forms.Cursors]::WaitCursor
    }
    else {
        [System.Windows.Forms.Cursors]::Default
    }
    $Script:StatusLabel.Text = $Message
    if (-not $Busy) {
        Stop-Spinner
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-WingetSourceUpdate {
    param([switch]$ContinueOnError)

    $arguments = @('source', 'update')
    Append-Log "> winget $($arguments -join ' ')"
    $result = Invoke-Winget -Arguments $arguments -LiveLog

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

function Update-WingetSources {
    Save-SkipList -Silent
    Set-Busy -Busy $true -Message 'Odswiezanie bazy winget...'

    try {
        Initialize-WingetInfo
        Sync-WingetUiCapabilities
        Append-Log "Runtime: $(Get-PowerShellRuntimeText)"
        Append-Log "winget: $($Script:WingetInfo.VersionText) ($($Script:WingetInfo.Path))"
        Invoke-WingetSourceUpdate | Out-Null
        $Script:StatusLabel.Text = 'Baza winget odswiezona.'
        Refresh-Packages -PreserveLog
    }
    catch {
        Append-Log $_.Exception.Message
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            'Blad podczas odswiezania bazy winget',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    finally {
        Set-Busy -Busy $false -Message $Script:StatusLabel.Text
    }
}

function Refresh-Packages {
    param([switch]$PreserveLog)

    Save-SkipList -Silent
    Set-Busy -Busy $true -Message 'Sprawdzanie aktualizacji winget...'

    try {
        $Script:Packages.Clear()
        if ($PreserveLog) {
            Append-Log ''
            Append-Log '--- Odswiezanie listy po aktualizacji ---'
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

        if ($null -ne $Script:SourceUpdateCheck -and $Script:SourceUpdateCheck.Checked) {
            $Script:StatusLabel.Text = 'Odswiezanie bazy winget...'
            Invoke-WingetSourceUpdate -ContinueOnError | Out-Null
            $Script:StatusLabel.Text = 'Sprawdzanie aktualizacji winget...'
        }

        $arguments = @(New-WingetUpgradeListArguments)
        Append-Log "> winget $($arguments -join ' ')"
        $result = Invoke-Winget -Arguments $arguments -LiveLog

        $packages = @(Parse-WingetUpgradeOutput -Output $result.Output)
        foreach ($package in $packages) {
            Add-PackageRow -Package $package
        }

        # Apply visual lock for Ghost Updates in the grid
        if ($null -ne $Script:Grid) {
            foreach ($gridRow in $Script:Grid.Rows) {
                $status = [string]$gridRow.Cells['Status'].Value
                if ($status -eq 'Blad (Ghost)') {
                    $gridRow.Cells['Update'].ReadOnly = $true
                    $gridRow.Cells['Update'].Style.BackColor = [System.Drawing.Color]::LightGray
                }
            }
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

        if ($packages.Count -eq 0) {
            $Script:StatusLabel.Text = 'Brak dostepnych aktualizacji albo winget nie zwrocil tabeli pakietow.'
        }
        else {
            $Script:StatusLabel.Text = "Znaleziono aktualizacje: $($packages.Count). Unknown: $unknownVisible. Pominiete: $skippedVisible."
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
        Set-Busy -Busy $false -Message $Script:StatusLabel.Text
    }
}

function Get-SelectedUpdateRows {
    Commit-GridEdits

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $Script:Packages.Rows) {
        if (-not ($row -is [System.Data.DataRow])) {
            continue
        }

        if ([bool](Get-RowValue -Row $row -ColumnName 'Update') -and -not [bool](Get-RowValue -Row $row -ColumnName 'Skip')) {
            [void]$rows.Add($row)
        }
    }
    Write-Output -NoEnumerate $rows
}

function Set-AllPackageSelection {
    param(
        [ValidateSet('Update', 'Skip')]
        [string]$ColumnName,
        [bool]$Checked
    )

    Commit-GridEdits

    foreach ($row in $Script:Packages.Rows) {
        if (-not ($row -is [System.Data.DataRow])) {
            continue
        }

        if ($ColumnName -eq 'Update') {
            if ($Checked -and [bool](Get-RowValue -Row $row -ColumnName 'Skip')) {
                continue
            }
            Set-RowValue -Row $row -ColumnName 'Update' -Value $Checked
        }
        else {
            Set-RowValue -Row $row -ColumnName 'Skip' -Value $Checked
            if ($Checked) {
                Set-RowValue -Row $row -ColumnName 'Update' -Value $false
                Set-RowValue -Row $row -ColumnName 'Status' -Value 'Pominiete'
            }
            elseif ([string](Get-RowValue -Row $row -ColumnName 'Status') -eq 'Pominiete') {
                Set-RowValue -Row $row -ColumnName 'Status' -Value ''
            }
        }
    }

    if ($null -ne $Script:Grid) {
        [void]$Script:Grid.Refresh()
    }
}

function Apply-SkipListToVisiblePackages {
    param([switch]$Silent)

    Commit-GridEdits
    Load-SkipList

    $matched = 0
    foreach ($row in $Script:Packages.Rows) {
        if (-not ($row -is [System.Data.DataRow])) {
            continue
        }

        $id = ([string](Get-RowValue -Row $row -ColumnName 'Id')).Trim()
        $isSkipped = $id.Length -gt 0 -and $Script:SkippedIds.ContainsKey($id)

        Set-RowValue -Row $row -ColumnName 'Skip' -Value $isSkipped
        if ($isSkipped) {
            Set-RowValue -Row $row -ColumnName 'Update' -Value $false
            Set-RowValue -Row $row -ColumnName 'Status' -Value 'Pominiete'
            $matched++
        }
        elseif ([string](Get-RowValue -Row $row -ColumnName 'Status') -eq 'Pominiete') {
            Set-RowValue -Row $row -ColumnName 'Status' -Value ''
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
    $label.Text = "Zostana zaktualizowane wszystkie ponizsze pakiety: $($Rows.Count)"
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

function Get-WingetPackageScope {
    param(
        [string]$Id,
        [string]$Source
    )

    $arguments = @('show', '--id', $Id)
    if ($null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsAcceptSourceAgreements)) {
        $arguments += '--accept-source-agreements'
    }
    if (-not [string]::IsNullOrWhiteSpace($Source) -and $null -ne $Script:WingetInfo -and [bool]($Script:WingetInfo.SupportsSource)) {
        $arguments += @('--source', $Source)
    }

    $result = Invoke-Winget -Arguments $arguments -LiveLog:$false
    if ($result.ExitCode -ne 0) {
        return 'Unknown'
    }

    $lines = $result.Output -split "`r?`n"
    foreach ($line in $lines) {
        if ($line -match '^\s*Zakres(?: instalatora)?\s*:\s*(User|Machine|Uzytkownik|Maszyna|MachineOrUser)\s*$' -or $line -match '^\s*Installer(?: )?Scope\s*:\s*(User|Machine|MachineOrUser)\s*$') {
            $scope = $matches[1]
            if ($scope -match 'User|Uzytkownik') { return 'User' }
            if ($scope -match 'Machine|Maszyna') { return 'Machine' }
            return 'Unknown'
        }
    }
    return 'Unknown'
}

function Invoke-WingetElevated {
    param(
        [string[]]$Arguments
    )

    # --- POCZĄTEK: PRZECHWYCENIE WINGET ELEVATED DLA TRYBU TESTOWEGO ---
    if ($null -ne $Script:TestModeCheck -and $Script:TestModeCheck.Checked) {
        if ($Arguments -contains 'upgrade' -and $Arguments -contains '--id') {
            $idIdx = [array]::IndexOf($Arguments, '--id') + 1
            $id = $Arguments[$idIdx]
            
            $mock = Get-Content $Script:MockFile | ConvertFrom-Json
            $pkg = $mock.$id

            Append-Log "[MOCK UAC] Proba aktualizacji $id z uprawnieniami..."
            Start-Spinner
            for ($i=0; $i -lt 10; $i++) {
                Step-Spinner
                Update-LogLiveLine -Progress "$($i*10)% Pobieranie..."
                Start-Sleep -Milliseconds 150
                [System.Windows.Forms.Application]::DoEvents()
            }
            Stop-Spinner
            
            if ($pkg.AdminExitCode -ne 0) { 
                Append-Log "[MOCK UAC] Odmowa instalatora (zwrocono blad $($pkg.AdminExitCode))."
                return $pkg.AdminExitCode 
            }
            if (-not $pkg.Ghost) {
                $pkg.Current = $pkg.Available
                $mock | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Script:MockFile -Encoding UTF8
            }
            Append-Log "[MOCK UAC] Zainstalowano."
            return 0
        }
    }
    # --- KONIEC: PRZECHWYCENIE WINGET ELEVATED DLA TRYBU TESTOWEGO ---

    $tempLog = Join-Path $env:TEMP "WingetElevated_$([guid]::NewGuid().ToString().Substring(0,8)).log"
    
    # Przekazanie złączonych argumentów. Argumenty zawierają apostrofy/cudzysłowy,
    # więc bezpieczniej przekazać je przez Base64.
    $argsJoined = $Arguments -join ' '
    
    $scriptBlock = @"
`$psi = New-Object System.Diagnostics.ProcessStartInfo
`$psi.FileName = 'winget'
`$psi.Arguments = '$argsJoined'
`$psi.RedirectStandardOutput = `$true
`$psi.RedirectStandardError = `$true
`$psi.UseShellExecute = `$false
`$psi.CreateNoWindow = `$true
`$psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
`$proc = [System.Diagnostics.Process]::Start(`$psi)

`$fs = [System.IO.File]::Open('$tempLog', 'Create', 'Write', 'Read')
`$writer = New-Object System.IO.StreamWriter(`$fs, [System.Text.Encoding]::UTF8)
`$writer.AutoFlush = `$true

`$reader = `$proc.StandardOutput
`$buffer = New-Object System.Text.StringBuilder

while (-not `$proc.HasExited -or -not `$reader.EndOfStream) {
    `$chInt = `$reader.Read()
    if (`$chInt -lt 0) { break }
    `$ch = [char]`$chInt

    if (`$chInt -eq 13 -or `$chInt -eq 8) { # Carriage Return (\r) lub Backspace (\b)
        if (`$buffer.Length -gt 0) {
            `$writer.WriteLine("[T]" + `$buffer.ToString())
            `$buffer.Clear() | Out-Null
        }
    } elseif (`$chInt -eq 10) { # Line Feed (\n)
        `$writer.WriteLine("[L]" + `$buffer.ToString())
        `$buffer.Clear() | Out-Null
    } else {
        `$buffer.Append(`$ch) | Out-Null
    }
}
if (`$buffer.Length -gt 0) {
    `$writer.WriteLine("[L]" + `$buffer.ToString())
}
`$writer.WriteLine("[E]" + `$proc.ExitCode)
`$writer.Close()
"@
    
    $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptBlock))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
    $psi.UseShellExecute = $true
    $psi.Verb = 'RunAs'
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $exitCode = -1
    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        Start-Spinner

        $lastPos = 0
        $chunkBuffer = ""
        $keepReading = $true
        
        while ($keepReading) {
            $hasData = $false
            if (Test-Path $tempLog) {
                try {
                    $fs = [System.IO.File]::Open($tempLog, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $len = $fs.Length
                    if ($len -gt $lastPos) {
                        $fs.Position = $lastPos
                        $bytes = New-Object byte[] ($len - $lastPos)
                        $fs.Read($bytes, 0, $bytes.Length) | Out-Null
                        $lastPos = $fs.Position
                        $chunkBuffer += [System.Text.Encoding]::UTF8.GetString($bytes)
                        $hasData = $true
                    }
                    $fs.Close()
                    
                    if ($hasData) {
                        while ($chunkBuffer -match "(?s)^(.*?)\r?\n(.*)$") {
                            $line = $matches[1]
                            $chunkBuffer = $matches[2]
                            
                            if ($line.StartsWith('[T]')) {
                                $content = (ConvertTo-PlainText $line.Substring(3)).Trim()
                                if (Test-IsWingetSpinnerLine -Line $content) {
                                    Step-Spinner
                                    Update-LogLiveLine -Spinner $content
                                } else {
                                    $prog = Get-WingetProgressText -Line $content
                                    if ([string]::IsNullOrWhiteSpace($prog)) { $prog = $content }
                                    Update-LogLiveLine -Progress $prog
                                }
                            } elseif ($line.StartsWith('[L]')) {
                                Append-Log (ConvertTo-PlainText $line.Substring(3))
                            } elseif ($line.StartsWith('[E]')) {
                                $exitCode = [int]$line.Substring(3)
                                $keepReading = $false
                            }
                        }
                    }
                } catch { }
            }
            
            if ($keepReading) {
                if ($process.HasExited -and -not $hasData) {
                    $keepReading = $false
                } else {
                    Start-Sleep -Milliseconds 50
                    Step-Spinner
                    [System.Windows.Forms.Application]::DoEvents()
                }
            }
        }
    }
    catch {
        Append-Log "Odrzucono UAC lub blad: $($_.Exception.Message)"
        return -1
    }
    finally {
        Stop-Spinner
        try { Remove-Item -Path $tempLog -Force -ErrorAction SilentlyContinue } catch { }
    }
    return $exitCode
}

function Update-SelectedPackages {
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

    Save-SkipList -Silent
    Set-Busy -Busy $true -Message "Skanowanie uprawnien dla pakietow: $($rows.Count)..."

    try {
        Initialize-WingetInfo
        Sync-WingetUiCapabilities

        foreach ($row in $rows) {
            Set-RowValue -Row $row -ColumnName 'Status' -Value 'Skanowanie...'
        }
        [System.Windows.Forms.Application]::DoEvents()

        $userScopedRows = @()
        $machineScopedRows = @()

        Append-Log ''
        Append-Log '== Grupowanie pakietow wedlug wymagan uprawnien =='

        foreach ($row in $rows) {
            $id = [string](Get-RowValue -Row $row -ColumnName 'Id')
            $source = ([string](Get-RowValue -Row $row -ColumnName 'Source')).Trim()
            $scope = Get-WingetPackageScope -Id $id -Source $source
            
            if ($scope -eq 'User') {
                $userScopedRows += $row
                Append-Log "Pakiet [USER]: $id (Nie wymaga uprawnien Administratora)"
            } else {
                $machineScopedRows += $row
                Append-Log "Pakiet [MACHINE]: $id (Wymaga potwierdzenia UAC)"
            }
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($userScopedRows.Count -gt 0) {
            Append-Log ''
            Append-Log '========================================'
            Append-Log "Aktualizacja cicha (User-Scoped): $($userScopedRows.Count)"
            Append-Log '========================================'
            foreach ($row in $userScopedRows) {
                $id = [string](Get-RowValue -Row $row -ColumnName 'Id')
                $source = ([string](Get-RowValue -Row $row -ColumnName 'Source')).Trim()
                Set-RowValue -Row $row -ColumnName 'Status' -Value 'Aktualizacja (User)...'
                [System.Windows.Forms.Application]::DoEvents()

                $arguments = @(New-WingetPackageUpgradeArguments -Id $id -Source $source)
                Append-Log "> winget $($arguments -join ' ')"
                $result = Invoke-Winget -Arguments $arguments -LiveLog

                if ($result.ExitCode -eq 0) {
                    Set-RowValue -Row $row -ColumnName 'Status' -Value 'OK'
                    $Script:AttemptedUpdates[$id] = [string](Get-RowValue -Row $row -ColumnName 'AvailableVersion')
                } else {
                    Set-RowValue -Row $row -ColumnName 'Status' -Value "Blad: $($result.ExitCode)"
                }
            }
        }

        if ($machineScopedRows.Count -gt 0) {
            Append-Log ''
            Append-Log '========================================'
            Append-Log "Aktualizacja administracyjna (Machine-Scoped): $($machineScopedRows.Count)"
            Append-Log 'Wyswietlam powiadomienie UAC (Zaakceptuj)...'
            Append-Log '========================================'
            
            foreach ($row in $machineScopedRows) {
                $id = [string](Get-RowValue -Row $row -ColumnName 'Id')
                $source = ([string](Get-RowValue -Row $row -ColumnName 'Source')).Trim()
                Set-RowValue -Row $row -ColumnName 'Status' -Value 'Aktualizacja (UAC)...'
                [System.Windows.Forms.Application]::DoEvents()

                $arguments = @(New-WingetPackageUpgradeArguments -Id $id -Source $source)
                Append-Log "> [ADMIN] winget $($arguments -join ' ')"
                
                $exitCode = Invoke-WingetElevated -Arguments $arguments
                
                if ($exitCode -eq 0) {
                    Set-RowValue -Row $row -ColumnName 'Status' -Value 'Zakonczono'
                    $Script:AttemptedUpdates[$id] = [string](Get-RowValue -Row $row -ColumnName 'AvailableVersion')
                } else {
                    Set-RowValue -Row $row -ColumnName 'Status' -Value 'Anulowano/Blad'
                }
            }
        }

        Set-Busy -Busy $false -Message 'Aktualizacja zakonczona. Odwiezenie listy...'
        Refresh-Packages -PreserveLog
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
        Set-Busy -Busy $false -Message $Script:StatusLabel.Text
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

    Write-Output -NoEnumerate $rows
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

function New-RepairContextFile {
    param(
        [object[]]$Rows,
        [string]$Agent,
        [string]$Terminal
    )

    if (-not (Test-Path -LiteralPath $Script:RepairDir)) {
        [void](New-Item -ItemType Directory -Force -Path $Script:RepairDir)
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $Script:RepairDir "unknown-packages-$stamp.txt"
    $lines = New-Object System.Collections.Generic.List[string]

    [void]$lines.Add('ZADANIE DLA AGENTA CLI')
    [void]$lines.Add('')
    [void]$lines.Add('Masz pomoc naprawic pakiety winget, ktore maja obecna wersje Unknown albo pojawiaja sie po winget upgrade --include-unknown / -u.')
    [void]$lines.Add('Najpierw zrob research: sprawdz dokumentacje winget, znane problemy pakietow, zrodla producenta oraz sensowna przyczyne rozjazdu wersji.')
    [void]$lines.Add('')
    [void]$lines.Add('Zasady bezpieczenstwa:')
    [void]$lines.Add('1. Nie wykonuj zadnych zmian bez jasnego potwierdzenia uzytkownika.')
    [void]$lines.Add('2. Przed kazda zmiana przedstaw diagnoze, plan i dokladne komendy, ktore chcesz uruchomic.')
    [void]$lines.Add('3. Za zmiany uznaj zwlaszcza: upgrade, install, uninstall, repair, modyfikacje rejestru, kasowanie plikow/katalogow, zmiany PATH i zmiany konfiguracji aplikacji.')
    [void]$lines.Add('4. Komendy tylko odczytowe i diagnostyczne mozesz proponowac najpierw, ale nadal pokaz uzytkownikowi co uruchamiasz i po co.')
    [void]$lines.Add('5. Po diagnostyce podsumuj przyczyne oraz zaproponuj najbezpieczniejszy sposob naprawy dla kazdego pakietu osobno.')
    [void]$lines.Add('')
    [void]$lines.Add("Agent wybrany w programie: $Agent")
    [void]$lines.Add("Terminal wybrany w programie: $Terminal")
    [void]$lines.Add("Katalog roboczy terminala: $([Environment]::GetFolderPath('UserProfile'))")
    [void]$lines.Add("Runtime programu: $(Get-PowerShellRuntimeText)")
    if ($null -ne $Script:WingetInfo) {
        [void]$lines.Add("winget path: $($Script:WingetInfo.Path)")
        [void]$lines.Add("winget version: $($Script:WingetInfo.VersionText)")
        [void]$lines.Add("winget supports --include-unknown: $($Script:WingetInfo.SupportsIncludeUnknown)")
    }
    [void]$lines.Add('')
    [void]$lines.Add('Pakiety do sprawdzenia:')
    [void]$lines.Add('Name | Id | CurrentVersion | AvailableVersion | Source')
    [void]$lines.Add('-----|----|----------------|------------------|-------')

    foreach ($row in $Rows) {
        $name = ConvertTo-CellText (Get-RowValue -Row $row -ColumnName 'Name')
        $id = ConvertTo-CellText (Get-RowValue -Row $row -ColumnName 'Id')
        $current = ConvertTo-CellText (Get-RowValue -Row $row -ColumnName 'CurrentVersion')
        $available = ConvertTo-CellText (Get-RowValue -Row $row -ColumnName 'AvailableVersion')
        $source = ConvertTo-CellText (Get-RowValue -Row $row -ColumnName 'Source')
        [void]$lines.Add("$name | $id | $current | $available | $source")
    }

    [void]$lines.Add('')
    [void]$lines.Add('Przydatne komendy diagnostyczne do rozwazenia dla kazdego ID:')
    [void]$lines.Add('winget list --id <ID> --exact')
    [void]$lines.Add('winget show --id <ID> --exact')
    [void]$lines.Add('winget upgrade --id <ID> --exact --include-unknown')
    [void]$lines.Add('winget pin list')
    [void]$lines.Add('')
    [void]$lines.Add('Wazne: uzytkownik chce konsultacji i potwierdzenia przed wszystkimi zmianami.')

    $lines | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function New-RepairPowerShellLauncher {
    param(
        [string]$PromptPath,
        [string]$Agent
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $Script:RepairDir "launch-repair-$stamp.ps1"
    $prompt = "Przeczytaj plik kontekstu: $PromptPath. To zadanie dotyczy naprawy pakietow winget z wersja Unknown / --include-unknown. Najpierw zrob research i diagnostyke. Nie wykonuj zmian bez jasnego potwierdzenia uzytkownika."
    $promptLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Text $prompt
    $promptPathLiteral = ConvertTo-PowerShellSingleQuotedLiteral -Text $PromptPath

    $cli = if ($Agent -match 'Gemini') { 'gemini' } else { 'codex' }
    $content = New-Object System.Collections.Generic.List[string]
    [void]$content.Add('$ErrorActionPreference = ''Stop''')
    [void]$content.Add('Set-Location -LiteralPath ([Environment]::GetFolderPath(''UserProfile''))')
    [void]$content.Add('$promptPath = ' + $promptPathLiteral)
    [void]$content.Add('$agentPrompt = ' + $promptLiteral)
    [void]$content.Add('Write-Host "Kontekst naprawy: $promptPath"')
    [void]$content.Add("if (-not (Get-Command $cli -ErrorAction SilentlyContinue)) { Write-Host 'Nie znaleziono $cli w PATH.'; return }")
    if ($cli -eq 'gemini') {
        [void]$content.Add('& gemini --approval-mode default --prompt-interactive $agentPrompt')
    }
    else {
        [void]$content.Add('& codex --cd ([Environment]::GetFolderPath(''UserProfile'')) --ask-for-approval on-request --search $agentPrompt')
    }

    $content | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function New-RepairCmdLauncher {
    param(
        [string]$PromptPath,
        [string]$Agent
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $path = Join-Path $Script:RepairDir "launch-repair-$stamp.cmd"
    $prompt = "Przeczytaj plik kontekstu: $PromptPath. To zadanie dotyczy naprawy pakietow winget z wersja Unknown / --include-unknown. Najpierw zrob research i diagnostyke. Nie wykonuj zmian bez jasnego potwierdzenia uzytkownika."
    $cli = if ($Agent -match 'Gemini') { 'gemini' } else { 'codex' }
    $content = New-Object System.Collections.Generic.List[string]
    [void]$content.Add('@echo off')
    [void]$content.Add('cd /d "%USERPROFILE%"')
    [void]$content.Add("set ""AGENT_PROMPT=$prompt""")
    [void]$content.Add("echo Kontekst naprawy: $PromptPath")
    [void]$content.Add("where $cli >nul 2>nul")
    [void]$content.Add('if errorlevel 1 (')
    [void]$content.Add("  echo Nie znaleziono $cli w PATH.")
    [void]$content.Add('  goto :eof')
    [void]$content.Add(')')
    if ($cli -eq 'gemini') {
        [void]$content.Add('gemini --approval-mode default --prompt-interactive "%AGENT_PROMPT%"')
    }
    else {
        [void]$content.Add('codex --cd "%USERPROFILE%" --ask-for-approval on-request --search "%AGENT_PROMPT%"')
    }

    $content | Set-Content -LiteralPath $path -Encoding ASCII
    return $path
}

function Start-UnknownRepairSession {
    Commit-GridEdits

    $rows = Get-UnknownPackageRows
    if ($rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            'Nie ma teraz pakietow z wersja Unknown. Najpierw kliknij Odswiez z wlaczona opcja --include-unknown.',
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    [void](Assert-PackageRows -Rows $rows -Operation 'Naprawa Unknown')

    $agent = [string]$Script:AgentCombo.SelectedItem
    if ([string]::IsNullOrWhiteSpace($agent)) {
        $agent = 'Codex CLI'
    }

    $terminal = [string]$Script:TerminalCombo.SelectedItem
    if ([string]::IsNullOrWhiteSpace($terminal)) {
        $terminal = 'PowerShell 7 admin'
    }

    $cli = if ($agent -match 'Gemini') { 'gemini' } else { 'codex' }
    if ($null -eq (Get-Command $cli -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Nie znaleziono $cli w PATH.",
            'Winget Updater',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    try {
        Initialize-WingetInfo
        Sync-WingetUiCapabilities
    }
    catch {
        Append-Log "UWAGA: nie udalo sie odswiezyc informacji winget przed naprawa: $($_.Exception.Message)"
    }

    $promptPath = New-RepairContextFile -Rows $rows -Agent $agent -Terminal $terminal
    $userProfile = [Environment]::GetFolderPath('UserProfile')

    if ($terminal -match '^CMD') {
        $launcher = New-RepairCmdLauncher -PromptPath $promptPath -Agent $agent
        Start-Process -FilePath 'cmd.exe' -ArgumentList "/k ""$launcher""" -WorkingDirectory $userProfile -Verb RunAs
    }
    elseif ($terminal -match 'PowerShell 5') {
        $launcher = New-RepairPowerShellLauncher -PromptPath $promptPath -Agent $agent
        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoExit -ExecutionPolicy Bypass -File ""$launcher""" -WorkingDirectory $userProfile -Verb RunAs
    }
    else {
        $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($null -eq $pwsh) {
            [System.Windows.Forms.MessageBox]::Show(
                'Nie znaleziono PowerShell 7 (pwsh). Wybierz PowerShell 5 albo CMD.',
                'Winget Updater',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
            return
        }

        $launcher = New-RepairPowerShellLauncher -PromptPath $promptPath -Agent $agent
        Start-Process -FilePath $pwsh.Source -ArgumentList "-NoExit -ExecutionPolicy Bypass -File ""$launcher""" -WorkingDirectory $userProfile -Verb RunAs
    }

    Append-Log "Utworzono kontekst naprawy: $promptPath"
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

# Usunięto wywołanie Ensure-RunningAsAdministrator - program używa Smart Batching i samodzielnie prosi o UAC podczas instalacji.
Load-SkipList

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({
    param($sender, $eventArgs)
    Show-AppError -ErrorRecord $eventArgs.Exception -Title 'Blad aplikacji'
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
Set-ControlToolTip -Control $Script:RefreshButton -Text 'Sprawdza dostepne aktualizacje przez winget upgrade i odswieza tabele. Gdy zaznaczono Baza przed sprawdz., najpierw uruchamia winget source update.'

$Script:SourceUpdateButton = New-Object System.Windows.Forms.Button
$Script:SourceUpdateButton.Text = 'Aktualizuj baze'
$Script:SourceUpdateButton.Width = 120
$Script:SourceUpdateButton.Height = 28
$Script:SourceUpdateButton.Add_Click({ try { Update-WingetSources } catch { Show-AppError -ErrorRecord $_ -Title 'Blad podczas odswiezania bazy winget' } })
Set-ControlToolTip -Control $Script:SourceUpdateButton -Text 'Uruchamia recznie winget source update, czyli odswieza baze/listy pakietow winget bez aktualizacji programow.'

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

$Script:SourceUpdateCheck = New-Object System.Windows.Forms.CheckBox
$Script:SourceUpdateCheck.Text = 'Baza przed sprawdz.'
$Script:SourceUpdateCheck.Width = 145
$Script:SourceUpdateCheck.Height = 28
$Script:SourceUpdateCheck.Checked = $true
Set-ControlToolTip -Control $Script:SourceUpdateCheck -Text 'Domyslnie przed kazdym odswiezeniem listy uruchamia winget source update, zeby odswiezyc baze/listy pakietow.'

$Script:TerminalCombo = New-Object System.Windows.Forms.ComboBox
$Script:TerminalCombo.DropDownStyle = 'DropDownList'
$Script:TerminalCombo.Width = 145
$Script:TerminalCombo.Height = 28
[void]$Script:TerminalCombo.Items.AddRange([object[]]@('PowerShell 7 admin', 'PowerShell 5 admin', 'CMD admin'))
if ($null -ne (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    $Script:TerminalCombo.SelectedItem = 'PowerShell 7 admin'
}
else {
    $Script:TerminalCombo.SelectedItem = 'PowerShell 5 admin'
}
Set-ControlToolTip -Control $Script:TerminalCombo -Text 'Wybiera terminal administratora uzywany przez Napraw Unknown.'

$Script:AgentCombo = New-Object System.Windows.Forms.ComboBox
$Script:AgentCombo.DropDownStyle = 'DropDownList'
$Script:AgentCombo.Width = 95
$Script:AgentCombo.Height = 28
[void]$Script:AgentCombo.Items.AddRange([object[]]@('Codex CLI', 'Gemini CLI'))
if ($null -ne (Get-Command codex -ErrorAction SilentlyContinue)) {
    $Script:AgentCombo.SelectedItem = 'Codex CLI'
}
else {
    $Script:AgentCombo.SelectedItem = 'Gemini CLI'
}
Set-ControlToolTip -Control $Script:AgentCombo -Text 'Wybiera CLI, ktore dostanie kontekst diagnostyczny dla pakietow Unknown.'

$Script:RepairButton = New-Object System.Windows.Forms.Button
$Script:RepairButton.Text = 'Napraw Unknown'
$Script:RepairButton.Width = 125
$Script:RepairButton.Height = 28
$Script:RepairButton.Add_Click({ try { Start-UnknownRepairSession } catch { Show-AppError -ErrorRecord $_ -Title 'Blad podczas naprawy Unknown' } })
Set-ControlToolTip -Control $Script:RepairButton -Text 'Tworzy kontekst diagnostyczny dla pakietow Unknown i uruchamia wybrany CLI jako administrator.'

$adminText = if (Test-IsAdministrator) { 'Administrator: tak' } else { 'Administrator: nie' }
$Script:StatusLabel = New-Object System.Windows.Forms.Label
$Script:StatusLabel.Text = "$adminText. $(Get-PowerShellRuntimeText). Gotowe."
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
[void]$topPanel.Controls.Add($Script:SourceUpdateButton)
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
[void]$topPanel.Controls.Add($Script:SourceUpdateCheck)

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

[void]$topPanel.Controls.Add($Script:TerminalCombo)
[void]$topPanel.Controls.Add($Script:AgentCombo)
[void]$topPanel.Controls.Add($Script:RepairButton)
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
    param($sender, $eventArgs)

    if ($eventArgs.RowIndex -lt 0 -or $eventArgs.ColumnIndex -lt 0) {
        return
    }

    $columnName = $Script:Grid.Columns[$eventArgs.ColumnIndex].Name
    $row = $Script:Grid.Rows[$eventArgs.RowIndex]

    if ($columnName -eq 'Skip' -and [bool]($row.Cells['Skip'].Value)) {
        $row.Cells['Update'].Value = $false
        $row.Cells['Status'].Value = 'Pominiete'
    }
    elseif ($columnName -eq 'Update' -and [bool]($row.Cells['Update'].Value)) {
        $row.Cells['Skip'].Value = $false
        if ([string]($row.Cells['Status'].Value) -eq 'Pominiete') {
            $row.Cells['Status'].Value = ''
        }
    }
    elseif ($columnName -eq 'Skip' -and -not [bool]($row.Cells['Skip'].Value)) {
        if ([string]($row.Cells['Status'].Value) -eq 'Pominiete') {
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
    try {
        Save-SkipList -Silent
    }
    catch {
        # Closing should not be blocked by a save error.
    }
})

$Script:Form.Add_Shown({ Refresh-Packages })

[void][System.Windows.Forms.Application]::Run($Script:Form)
