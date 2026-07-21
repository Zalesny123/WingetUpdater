#requires -Version 5.1

Set-StrictMode -Version 2.0

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

function Parse-WingetPackageLine {
    param([string]$Line)

    $lineText = Repair-DisplayText -Text $Line
    if ([string]::IsNullOrWhiteSpace($lineText)) {
        return $null
    }

    # Read from the right because long names can shift fixed-width columns.
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
    param([AllowNull()][AllowEmptyString()][string]$Argument)

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }

    if ($Argument -notmatch '[\s"]') {
        return $Argument
    }

    $quoted = New-Object System.Text.StringBuilder
    [void]$quoted.Append('"')
    $backslashCount = 0

    for ($i = 0; $i -lt $Argument.Length; $i++) {
        $character = $Argument[$i]
        if ($character -eq '\') {
            $backslashCount++
            continue
        }

        if ($character -eq '"') {
            [void]$quoted.Append(('\' * (($backslashCount * 2) + 1)))
            [void]$quoted.Append('"')
        }
        else {
            [void]$quoted.Append(('\' * $backslashCount))
            [void]$quoted.Append($character)
        }
        $backslashCount = 0
    }

    [void]$quoted.Append(('\' * ($backslashCount * 2)))
    [void]$quoted.Append('"')
    return $quoted.ToString()
}

function Join-CommandLineArguments {
    param([string[]]$Arguments)

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($argument in $Arguments) {
        [void]$parts.Add((ConvertTo-CommandLineArgument -Argument $argument))
    }

    return ($parts.ToArray() -join ' ')
}

function Test-WingetCapability {
    param(
        [object]$Capabilities,
        [string]$Name
    )

    if ($null -eq $Capabilities) {
        return $false
    }
    $property = $Capabilities.PSObject.Properties[$Name]
    return ($null -ne $property -and [bool]$property.Value)
}

function New-WingetSourceUpdateArguments {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This pure function only returns a string argument array.')]
    param()

    return @('source', 'update')
}

function New-WingetUpgradeListArguments {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This pure function only returns a string argument array.')]
    param(
        [object]$Capabilities,
        [bool]$SourceAgreementsAccepted = $false,
        [bool]$IncludeUnknown = $false
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('upgrade')
    if ($SourceAgreementsAccepted -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsAcceptSourceAgreements')) {
        [void]$arguments.Add('--accept-source-agreements')
    }
    if (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsDisableInteractivity') {
        [void]$arguments.Add('--disable-interactivity')
    }
    if ($IncludeUnknown -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsIncludeUnknown')) {
        [void]$arguments.Add('--include-unknown')
    }
    return $arguments.ToArray()
}

function Resolve-WingetUpdaterSourceAgreementConsent {
    param(
        [bool]$MockMode,
        [bool]$AlreadyAccepted,
        [scriptblock]$PromptAction,
        [scriptblock]$PersistAcceptanceAction
    )

    if ($MockMode) {
        return [pscustomobject]@{
            Allowed = $true
            Accepted = $AlreadyAccepted
            Prompted = $false
            Persisted = $false
        }
    }
    if ($AlreadyAccepted) {
        return [pscustomobject]@{
            Allowed = $true
            Accepted = $true
            Prompted = $false
            Persisted = $false
        }
    }

    $accepted = [bool](& $PromptAction)
    if (-not $accepted) {
        return [pscustomobject]@{
            Allowed = $false
            Accepted = $false
            Prompted = $true
            Persisted = $false
        }
    }

    & $PersistAcceptanceAction | Out-Null
    return [pscustomobject]@{
        Allowed = $true
        Accepted = $true
        Prompted = $true
        Persisted = $true
    }
}

function New-WingetUpdaterCancellationState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This pure function only returns in-memory operation state.')]
    param()
    return [pscustomobject]@{
        IsCancellationRequested = $false
    }
}

function Request-WingetUpdaterCancellation {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This only changes in-memory operation state.')]
    param([object]$State)

    if ($null -ne $State) {
        $State.IsCancellationRequested = $true
    }
}

function Test-WingetUpdaterCancellationRequested {
    param([object]$State)

    if ($null -eq $State) {
        return $false
    }
    $property = $State.PSObject.Properties['IsCancellationRequested']
    return ($null -ne $property -and [bool]$property.Value)
}

function Get-WingetUpdaterMutexName {
    param([string]$UserSid)

    if ([string]::IsNullOrWhiteSpace($UserSid)) {
        throw 'The Windows user SID is empty.'
    }
    return 'Local\WingetUpdater-' + $UserSid.Trim()
}

function Get-WingetUpdaterCurrentUserSid {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        if ($null -eq $identity.User -or [string]::IsNullOrWhiteSpace($identity.User.Value)) {
            throw 'The current Windows user SID is unavailable.'
        }
        return $identity.User.Value
    }
    finally {
        $identity.Dispose()
    }
}

function Enter-WingetUpdaterSingleInstance {
    param(
        [string]$UserSid,
        [scriptblock]$CreateMutexAction
    )

    $name = Get-WingetUpdaterMutexName -UserSid $UserSid
    $mutex = $null
    $createdNew = $false
    if ($null -ne $CreateMutexAction) {
        $creation = & $CreateMutexAction $name
        $mutex = $creation.Mutex
        $createdNew = [bool]$creation.CreatedNew
    }
    else {
        $mutex = New-Object System.Threading.Mutex($true, $name, [ref]$createdNew)
    }
    if ($null -eq $mutex) {
        throw 'Named mutex creation returned no mutex object.'
    }

    return [pscustomobject]@{
        Name = $name
        Mutex = $mutex
        IsFirstInstance = $createdNew
        OwnsMutex = $createdNew
    }
}

function Exit-WingetUpdaterSingleInstance {
    param([object]$Lease)

    if ($null -eq $Lease -or $null -eq $Lease.Mutex) {
        return
    }
    try {
        if ([bool]$Lease.OwnsMutex) {
            $Lease.Mutex.ReleaseMutex()
            $Lease.OwnsMutex = $false
        }
    }
    finally {
        $Lease.Mutex.Dispose()
        $Lease.Mutex = $null
    }
}

function Set-WingetUpdaterBusyControlState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This helper applies transient UI enabled state.')]
    param(
        [bool]$Busy,
        [object[]]$OperationControls,
        [object]$CancelControl
    )

    foreach ($control in @($OperationControls)) {
        if ($null -ne $control) {
            $control.Enabled = -not $Busy
        }
    }
    if ($null -ne $CancelControl) {
        $CancelControl.Enabled = $Busy
    }
}

function Resolve-WingetUpdaterCloseRequest {
    param(
        [bool]$IsBusy,
        [bool]$CancellationConfirmed,
        [bool]$CancellationAlreadyRequested
    )

    if (-not $IsBusy) {
        return [pscustomobject]@{
            CancelClose = $false
            RequestCancellation = $false
            DeferClose = $false
        }
    }
    if ($CancellationAlreadyRequested) {
        return [pscustomobject]@{
            CancelClose = $true
            RequestCancellation = $false
            DeferClose = $true
        }
    }
    return [pscustomobject]@{
        CancelClose = $true
        RequestCancellation = $CancellationConfirmed
        DeferClose = $CancellationConfirmed
    }
}

function New-WingetPackageUpgradeArguments {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This pure function only returns a string argument array.')]
    param(
        [string]$Id,
        [string]$Source,
        [object]$Capabilities,
        [bool]$SourceAgreementsAccepted = $false,
        [bool]$PackageAgreementsConfirmed = $false,
        [bool]$Interactive = $false,
        [bool]$Silent = $false,
        [bool]$IncludeUnknown = $false
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    [void]$arguments.Add('upgrade')
    [void]$arguments.Add('--id')
    [void]$arguments.Add($Id)

    if (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsExact') {
        [void]$arguments.Add('--exact')
    }
    if (-not [string]::IsNullOrWhiteSpace($Source) -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsSource')) {
        [void]$arguments.Add('--source')
        [void]$arguments.Add($Source)
    }
    if ($SourceAgreementsAccepted -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsAcceptSourceAgreements')) {
        [void]$arguments.Add('--accept-source-agreements')
    }
    if ($PackageAgreementsConfirmed -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsAcceptPackageAgreements')) {
        [void]$arguments.Add('--accept-package-agreements')
    }

    $interactiveSelected = $Interactive
    if ($interactiveSelected) {
        if (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsInteractive') {
            [void]$arguments.Add('--interactive')
        }
    }
    elseif ($Silent -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsSilent')) {
        [void]$arguments.Add('--silent')
    }

    if ($IncludeUnknown -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsIncludeUnknown')) {
        [void]$arguments.Add('--include-unknown')
    }
    if (-not $interactiveSelected -and (Test-WingetCapability -Capabilities $Capabilities -Name 'SupportsDisableInteractivity')) {
        [void]$arguments.Add('--disable-interactivity')
    }

    return $arguments.ToArray()
}

function Resolve-WingetApplicationPath {
    param(
        [AllowNull()][object[]]$Commands,
        [string]$LocalAppDataPath,
        [scriptblock]$GetFileAttributes = { param($Path) [System.IO.File]::GetAttributes($Path) }
    )

    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath) -or -not [System.IO.Path]::IsPathRooted($LocalAppDataPath)) {
        throw "The LocalAppData path must be rooted: $LocalAppDataPath"
    }

    $candidates = @($Commands | Where-Object { $null -ne $_ })
    if ($candidates.Count -eq 0) {
        throw 'Discovery returned no winget command candidates.'
    }

    $applicationCandidates = @($candidates | Where-Object {
        $_.CommandType -eq [System.Management.Automation.CommandTypes]::Application
    })
    if ($applicationCandidates.Count -eq 0) {
        throw 'Discovery returned no Application candidates for winget.'
    }

    $trustedPath = Join-Path $LocalAppDataPath 'Microsoft\WindowsApps\winget.exe'
    $trustedPath = [System.IO.Path]::GetFullPath($trustedPath)
    if (-not (Test-Path -LiteralPath $trustedPath -PathType Leaf)) {
        throw "The trusted winget AppExecutionAlias does not exist: $trustedPath"
    }
    try {
        $trustedAttributes = [System.IO.FileAttributes](& $GetFileAttributes $trustedPath)
    }
    catch {
        throw "The trusted winget AppExecutionAlias attributes could not be read: $($_.Exception.Message)"
    }
    if (($trustedAttributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
        throw "The trusted winget path is not an AppExecutionAlias reparse point: $trustedPath"
    }

    foreach ($candidate in $applicationCandidates) {
        $candidatePath = [string]$candidate.Source
        if ([string]::IsNullOrWhiteSpace($candidatePath) -or -not [System.IO.Path]::IsPathRooted($candidatePath)) {
            continue
        }
        $candidatePath = [System.IO.Path]::GetFullPath($candidatePath)
        if ([string]::Equals($candidatePath, $trustedPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $trustedPath
        }
    }

    throw "No trusted winget Application candidate matched the canonical WindowsApps alias '$trustedPath'."
}

function ConvertFrom-WingetUpgradeResult {
    param(
        [int]$ExitCode,
        [string]$StandardOutput
    )

    if ($ExitCode -ne 0) {
        throw "winget upgrade list failed with exit code $ExitCode."
    }
    return @(Parse-WingetUpgradeOutput -Output $StandardOutput)
}

function Invoke-WingetProcessOutputCallback {
    param(
        [scriptblock]$Callback,
        [string]$Stream,
        [string]$Text
    )

    if ($null -eq $Callback -or [string]::IsNullOrEmpty($Text)) {
        return
    }
    try {
        & $Callback $Stream $Text | Out-Null
    }
    catch {
        Write-Verbose "Winget process display callback failed: $($_.Exception.Message)"
    }
}

function Invoke-WingetProcessPulseCallback {
    param([scriptblock]$Callback)

    if ($null -eq $Callback) {
        return
    }
    try {
        & $Callback | Out-Null
    }
    catch {
        Write-Verbose "Winget process pulse callback failed: $($_.Exception.Message)"
    }
}

function Add-WingetProcessInfrastructureError {
    param(
        [System.Collections.Generic.List[string]]$Errors,
        [string]$Message
    )

    if (-not [string]::IsNullOrWhiteSpace($Message) -and -not $Errors.Contains($Message)) {
        [void]$Errors.Add($Message)
    }
}

function Write-WingetProcessLogText {
    param(
        [object]$State,
        [string]$Text
    )

    if ($null -eq $State.Writer -or $State.Failed) {
        return
    }
    try {
        $State.Writer.Write($Text)
        $State.Writer.Flush()
    }
    catch {
        $State.Failed = $true
        Add-WingetProcessInfrastructureError `
            -Errors $State.Errors `
            -Message "Command log write failed for '$($State.Path)': $($_.Exception.Message)"
    }
}

function Get-WingetReadTaskResult {
    param([object]$Task)

    return [int]$Task.Result
}

function Invoke-WingetTaskkill {
    param(
        [string]$TaskkillPath,
        [int]$ProcessId,
        [int]$WaitTimeoutMilliseconds
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $TaskkillPath
    $startInfo.Arguments = Join-CommandLineArguments -Arguments @('/PID', [string]$ProcessId, '/T', '/F')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $taskkillProcess = New-Object System.Diagnostics.Process
    $taskkillProcess.StartInfo = $startInfo

    try {
        if (-not [bool]$taskkillProcess.Start()) {
            return $false
        }
        if (-not $taskkillProcess.WaitForExit($WaitTimeoutMilliseconds)) {
            try {
                $taskkillProcess.Kill()
                [void]$taskkillProcess.WaitForExit(1000)
            }
            catch {
                Write-Verbose "Timed-out taskkill cleanup failed: $($_.Exception.Message)"
            }
            return $false
        }
        return ($taskkillProcess.ExitCode -eq 0)
    }
    finally {
        $taskkillProcess.Dispose()
    }
}

function Stop-WingetProcess {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This internal cleanup primitive is called only after a process infrastructure failure.')]
    param(
        [object]$Process,
        [string]$SystemRootPath,
        [int]$WaitTimeoutMilliseconds = 5000,
        [scriptblock]$KillAction,
        [scriptblock]$WaitAction,
        [scriptblock]$TaskkillAction
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $usedTaskkill = $false
    if ($null -eq $KillAction) {
        $KillAction = { param($TargetProcess) $TargetProcess.Kill() }
    }
    if ($null -eq $WaitAction) {
        $WaitAction = { param($TargetProcess, $TimeoutMilliseconds) $TargetProcess.WaitForExit($TimeoutMilliseconds) }
    }
    if ($null -eq $TaskkillAction) {
        $TaskkillAction = {
            param($Path, $TargetProcessId, $TimeoutMilliseconds)
            Invoke-WingetTaskkill -TaskkillPath $Path -ProcessId $TargetProcessId -WaitTimeoutMilliseconds $TimeoutMilliseconds
        }
    }

    try {
        if ($Process.HasExited) {
            return [pscustomobject]@{
                GuaranteedStopped = $true
                UsedTaskkill = $false
                InfrastructureError = ''
            }
        }
    }
    catch {
        [void]$errors.Add("Direct child state check failed: $($_.Exception.Message)")
    }

    try {
        & $KillAction $Process | Out-Null
    }
    catch {
        [void]$errors.Add("Direct child Kill failure: $($_.Exception.Message)")
    }

    $stopped = $false
    try {
        $stopped = [bool](& $WaitAction $Process $WaitTimeoutMilliseconds)
    }
    catch {
        [void]$errors.Add("Direct child bounded wait failed: $($_.Exception.Message)")
    }

    if (-not $stopped) {
        $usedTaskkill = $true
        if ([string]::IsNullOrWhiteSpace($SystemRootPath) -or -not [System.IO.Path]::IsPathRooted($SystemRootPath)) {
            [void]$errors.Add("SystemRoot is unavailable or not rooted; taskkill fallback cannot be trusted: $SystemRootPath")
        }
        else {
            $taskkillPath = [System.IO.Path]::GetFullPath((Join-Path $SystemRootPath 'System32\taskkill.exe'))
            if (-not (Test-Path -LiteralPath $taskkillPath -PathType Leaf)) {
                [void]$errors.Add("Trusted taskkill fallback does not exist: $taskkillPath")
            }
            else {
                try {
                    if (-not [bool](& $TaskkillAction $taskkillPath ([int]$Process.Id) $WaitTimeoutMilliseconds)) {
                        [void]$errors.Add('Trusted taskkill fallback reported failure.')
                    }
                }
                catch {
                    [void]$errors.Add("Trusted taskkill fallback failure: $($_.Exception.Message)")
                }
            }
        }

        try {
            $stopped = [bool](& $WaitAction $Process $WaitTimeoutMilliseconds)
        }
        catch {
            [void]$errors.Add("Direct child post-taskkill bounded wait failed: $($_.Exception.Message)")
        }
    }

    if (-not $stopped) {
        [void]$errors.Add('Direct child termination could not be guaranteed.')
    }

    return [pscustomobject]@{
        GuaranteedStopped = $stopped
        UsedTaskkill = $usedTaskkill
        InfrastructureError = $errors.ToArray() -join ' | '
    }
}

function Stop-WingetProcessTree {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'This is the bounded cancellation cleanup primitive for the current child process tree.')]
    param(
        [object]$Process,
        [string]$SystemRootPath,
        [int]$WaitTimeoutMilliseconds = 5000,
        [scriptblock]$KillAction,
        [scriptblock]$WaitAction,
        [scriptblock]$TaskkillAction
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $usedTaskkill = $false
    $usedDirectKillFallback = $false
    if ($null -eq $KillAction) {
        $KillAction = { param($TargetProcess) $TargetProcess.Kill() }
    }
    if ($null -eq $WaitAction) {
        $WaitAction = { param($TargetProcess, $TimeoutMilliseconds) $TargetProcess.WaitForExit($TimeoutMilliseconds) }
    }
    if ($null -eq $TaskkillAction) {
        $TaskkillAction = {
            param($Path, $TargetProcessId, $TimeoutMilliseconds)
            Invoke-WingetTaskkill -TaskkillPath $Path -ProcessId $TargetProcessId -WaitTimeoutMilliseconds $TimeoutMilliseconds
        }
    }

    try {
        if ($Process.HasExited) {
            return [pscustomobject]@{
                GuaranteedStopped = $true
                UsedTaskkill = $false
                UsedDirectKillFallback = $false
                InfrastructureError = ''
            }
        }
    }
    catch {
        [void]$errors.Add("Direct child state check failed: $($_.Exception.Message)")
    }

    $stopped = $false
    if ([string]::IsNullOrWhiteSpace($SystemRootPath) -or -not [System.IO.Path]::IsPathRooted($SystemRootPath)) {
        [void]$errors.Add("SystemRoot is unavailable or not rooted; taskkill fallback cannot be trusted: $SystemRootPath")
    }
    else {
        $taskkillPath = [System.IO.Path]::GetFullPath((Join-Path $SystemRootPath 'System32\taskkill.exe'))
        if (-not (Test-Path -LiteralPath $taskkillPath -PathType Leaf)) {
            [void]$errors.Add("Trusted taskkill fallback does not exist: $taskkillPath")
        }
        else {
            $usedTaskkill = $true
            try {
                if (-not [bool](& $TaskkillAction $taskkillPath ([int]$Process.Id) $WaitTimeoutMilliseconds)) {
                    [void]$errors.Add('Trusted taskkill fallback reported failure.')
                }
            }
            catch {
                [void]$errors.Add("Trusted taskkill fallback failure: $($_.Exception.Message)")
            }
        }
    }

    try {
        $stopped = [bool](& $WaitAction $Process $WaitTimeoutMilliseconds)
    }
    catch {
        [void]$errors.Add("Direct child post-taskkill bounded wait failed: $($_.Exception.Message)")
    }

    if (-not $stopped) {
        $usedDirectKillFallback = $true
        try {
            & $KillAction $Process | Out-Null
        }
        catch {
            [void]$errors.Add("Direct child Kill fallback failure: $($_.Exception.Message)")
        }
        try {
            $stopped = [bool](& $WaitAction $Process $WaitTimeoutMilliseconds)
        }
        catch {
            [void]$errors.Add("Direct child fallback bounded wait failed: $($_.Exception.Message)")
        }
    }

    if (-not $stopped) {
        [void]$errors.Add('Direct child termination could not be guaranteed.')
    }
    return [pscustomobject]@{
        GuaranteedStopped = $stopped
        UsedTaskkill = $usedTaskkill
        UsedDirectKillFallback = $usedDirectKillFallback
        InfrastructureError = $errors.ToArray() -join ' | '
    }
}

function Invoke-WingetProcess {
    param(
        [string]$ApplicationPath,
        [string[]]$Arguments,
        [string]$LogsDirectory,
        [AllowNull()][object]$Package,
        [scriptblock]$OnOutput,
        [scriptblock]$OnPulse,
        [object]$CancellationState
    )

    if ([string]::IsNullOrWhiteSpace($ApplicationPath) -or -not [System.IO.Path]::IsPathRooted($ApplicationPath)) {
        throw "The winget process path must be absolute: $ApplicationPath"
    }
    $canonicalPath = [System.IO.Path]::GetFullPath($ApplicationPath)
    if (-not (Test-Path -LiteralPath $canonicalPath -PathType Leaf)) {
        throw "The winget process path does not exist: $canonicalPath"
    }
    if ([string]::IsNullOrWhiteSpace($LogsDirectory)) {
        throw 'The winget process logs directory is empty.'
    }
    if (Test-Path -LiteralPath $LogsDirectory) {
        if (-not (Test-Path -LiteralPath $LogsDirectory -PathType Container)) {
            throw "The winget process logs directory is not a directory: $LogsDirectory"
        }
    }
    else {
        [void](New-Item -ItemType Directory -Path $LogsDirectory -Force -ErrorAction Stop)
    }

    $argumentCopy = [string[]]@($Arguments)
    $displayCommand = Join-CommandLineArguments -Arguments @($canonicalPath)
    if ($argumentCopy.Count -gt 0) {
        $displayCommand += ' ' + (Join-CommandLineArguments -Arguments $argumentCopy)
    }

    $packageId = ''
    $packageName = ''
    $currentVersion = ''
    $availableVersion = ''
    $source = ''
    if ($null -ne $Package) {
        foreach ($metadataName in @('Id', 'Name', 'CurrentVersion', 'AvailableVersion', 'Source')) {
            $property = $Package.PSObject.Properties[$metadataName]
            if ($null -eq $property) {
                continue
            }
            switch ($metadataName) {
                'Id' { $packageId = [string]$property.Value }
                'Name' { $packageName = [string]$property.Value }
                'CurrentVersion' { $currentVersion = [string]$property.Value }
                'AvailableVersion' { $availableVersion = [string]$property.Value }
                'Source' { $source = [string]$property.Value }
            }
        }
    }

    $logStem = if ([string]::IsNullOrWhiteSpace($packageId)) { 'winget' } else { $packageId }
    $safeLogStem = [regex]::Replace($logStem, '[^A-Za-z0-9._-]', '_')
    $logName = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + $safeLogStem + '-' + [guid]::NewGuid().ToString('N') + '.log'
    $logPath = Join-Path $LogsDirectory $logName
    $startedAtUtc = [datetime]::UtcNow
    $endedAtUtc = $startedAtUtc
    $standardOutput = New-Object System.Text.StringBuilder
    $standardError = New-Object System.Text.StringBuilder
    $combinedOutput = New-Object System.Text.StringBuilder
    $infrastructureErrors = New-Object System.Collections.Generic.List[string]
    $process = $null
    $stdoutTask = $null
    $stderrTask = $null
    $started = $false
    $terminatedForInfrastructure = $false
    $cancelled = $false
    $abortReads = $false
    $cleanupState = [pscustomobject]@{ Guaranteed = $true }
    $exitCode = $null
    $logStream = $null
    $logWriter = $null
    $logState = $null

    try {
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        $logStream = New-Object System.IO.FileStream(
            $logPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        $logWriter = New-Object System.IO.StreamWriter($logStream, $utf8)
        $logWriter.AutoFlush = $true
        $logWriter.WriteLine("Log: $logPath")
        $logWriter.WriteLine("Application: $canonicalPath")
        $logWriter.WriteLine("Command: $displayCommand")
        $logWriter.WriteLine("StartedAtUtc: $($startedAtUtc.ToString('o'))")
        $logWriter.Flush()
        if (-not $logStream.CanWrite -or -not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
            throw 'The command log stream is not writable after creation.'
        }
        $logState = [pscustomobject]@{
            Writer = $logWriter
            Path = $logPath
            Errors = $infrastructureErrors
            Failed = $false
        }
    }
    catch {
        $preflightError = $_
        if ($null -ne $logWriter) {
            $logWriter.Dispose()
        }
        elseif ($null -ne $logStream) {
            $logStream.Dispose()
        }
        throw "Command log preflight failed for '$logPath': $($preflightError.Exception.Message)"
    }

    $stopProcess = {
        if ($null -eq $process -or -not $started) {
            return
        }
        $cleanupResult = Stop-WingetProcess `
            -Process $process `
            -SystemRootPath $env:SystemRoot `
            -WaitTimeoutMilliseconds 5000
        $cleanupState.Guaranteed = [bool]$cleanupResult.GuaranteedStopped
        if (-not [string]::IsNullOrWhiteSpace($cleanupResult.InfrastructureError)) {
            Add-WingetProcessInfrastructureError `
                -Errors $infrastructureErrors `
                -Message $cleanupResult.InfrastructureError
        }
    }

    $observeReadTask = {
        param(
            [object]$Task,
            [string]$StreamName
        )

        if ($null -eq $Task) {
            return
        }
        try {
            if (-not $Task.IsCompleted -and -not $Task.Wait(5000)) {
                Add-WingetProcessInfrastructureError `
                    -Errors $infrastructureErrors `
                    -Message "$StreamName read task did not complete during cleanup."
            }
            if ($Task.IsFaulted -and $null -ne $Task.Exception) {
                Add-WingetProcessInfrastructureError `
                    -Errors $infrastructureErrors `
                    -Message "$StreamName read task faulted: $($Task.Exception.GetBaseException().Message)"
            }
        }
        catch {
            Add-WingetProcessInfrastructureError `
                -Errors $infrastructureErrors `
                -Message "$StreamName read task cleanup failed: $($_.Exception.Message)"
        }
    }

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $canonicalPath
        $startInfo.Arguments = Join-CommandLineArguments -Arguments $argumentCopy
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        try {
            $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        }
        catch {
            Write-Verbose "Runtime ignored explicit process stream encoding: $($_.Exception.Message)"
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        $started = [bool]$process.Start()
        if (-not $started) {
            throw 'Process.Start returned false.'
        }
        Write-WingetProcessLogText -State $logState -Text "Started: true`r`n"

        $stdoutChars = New-Object 'char[]' 4096
        $stderrChars = New-Object 'char[]' 4096
        $stdoutTask = $process.StandardOutput.ReadAsync($stdoutChars, 0, $stdoutChars.Length)
        $stderrTask = $process.StandardError.ReadAsync($stderrChars, 0, $stderrChars.Length)
        $stdoutDone = $false
        $stderrDone = $false
        $processExited = $false
        $nextPulseUtc = [datetime]::UtcNow

        while (-not ($processExited -and $stdoutDone -and $stderrDone)) {
            try {
                $processExited = [bool]$process.HasExited
            }
            catch {
                $abortReads = $true
                $terminatedForInfrastructure = $true
                Add-WingetProcessInfrastructureError `
                    -Errors $infrastructureErrors `
                    -Message "Direct child state poll failed: $($_.Exception.Message)"
                & $stopProcess | Out-Null
            }

            if (-not $stdoutDone -and $stdoutTask.IsCompleted) {
                try {
                    $read = Get-WingetReadTaskResult -Task $stdoutTask
                    if ($read -le 0) {
                        $stdoutDone = $true
                    }
                    else {
                        $text = New-Object string($stdoutChars, 0, $read)
                        [void]$standardOutput.Append($text)
                        [void]$combinedOutput.Append($text)
                        Write-WingetProcessLogText -State $logState -Text ("`r`n[stdout-chunk]`r`n" + $text)
                        Invoke-WingetProcessOutputCallback -Callback $OnOutput -Stream 'stdout' -Text $text
                        $stdoutTask = $process.StandardOutput.ReadAsync($stdoutChars, 0, $stdoutChars.Length)
                    }
                }
                catch {
                    $stdoutDone = $true
                    $abortReads = $true
                    $terminatedForInfrastructure = $true
                    Add-WingetProcessInfrastructureError `
                        -Errors $infrastructureErrors `
                        -Message "stdout read failed: $($_.Exception.Message)"
                    & $stopProcess | Out-Null
                }
            }

            if (-not $stderrDone -and $stderrTask.IsCompleted) {
                try {
                    $read = Get-WingetReadTaskResult -Task $stderrTask
                    if ($read -le 0) {
                        $stderrDone = $true
                    }
                    else {
                        $text = New-Object string($stderrChars, 0, $read)
                        [void]$standardError.Append($text)
                        [void]$combinedOutput.Append($text)
                        Write-WingetProcessLogText -State $logState -Text ("`r`n[stderr-chunk]`r`n" + $text)
                        Invoke-WingetProcessOutputCallback -Callback $OnOutput -Stream 'stderr' -Text $text
                        $stderrTask = $process.StandardError.ReadAsync($stderrChars, 0, $stderrChars.Length)
                    }
                }
                catch {
                    $stderrDone = $true
                    $abortReads = $true
                    $terminatedForInfrastructure = $true
                    Add-WingetProcessInfrastructureError `
                        -Errors $infrastructureErrors `
                        -Message "stderr read failed: $($_.Exception.Message)"
                    & $stopProcess | Out-Null
                }
            }

            if ($abortReads) {
                $stdoutDone = $true
                $stderrDone = $true
                break
            }

            if (-not ($processExited -and $stdoutDone -and $stderrDone)) {
                $nowUtc = [datetime]::UtcNow
                if ($nowUtc -ge $nextPulseUtc) {
                    Invoke-WingetProcessPulseCallback -Callback $OnPulse
                    if (-not $cancelled -and (Test-WingetUpdaterCancellationRequested -State $CancellationState)) {
                        $cancelled = $true
                        $cancellationResult = Stop-WingetProcessTree `
                            -Process $process `
                            -SystemRootPath $env:SystemRoot `
                            -WaitTimeoutMilliseconds 5000
                        $cleanupState.Guaranteed = [bool]$cancellationResult.GuaranteedStopped
                        if (-not [string]::IsNullOrWhiteSpace($cancellationResult.InfrastructureError)) {
                            Add-WingetProcessInfrastructureError `
                                -Errors $infrastructureErrors `
                                -Message $cancellationResult.InfrastructureError
                        }
                    }
                    $nextPulseUtc = $nowUtc.AddMilliseconds(50)
                }
                Start-Sleep -Milliseconds 10
            }
        }

        if (-not $terminatedForInfrastructure -and -not $cancelled) {
            $exitCode = $process.ExitCode
        }
    }
    catch {
        Add-WingetProcessInfrastructureError `
            -Errors $infrastructureErrors `
            -Message "Process infrastructure failure: $($_.Exception.Message)"
        if ($started) {
            $terminatedForInfrastructure = $true
            & $stopProcess | Out-Null
        }
    }
    finally {
        if ($started -and $null -ne $process) {
            try {
                if (-not $process.HasExited) {
                    $terminatedForInfrastructure = $true
                    & $stopProcess | Out-Null
                }
            }
            catch {
                $terminatedForInfrastructure = $true
                Add-WingetProcessInfrastructureError `
                    -Errors $infrastructureErrors `
                    -Message "Direct child state check failed: $($_.Exception.Message)"
                & $stopProcess | Out-Null
            }
        }
        & $observeReadTask $stdoutTask 'stdout' | Out-Null
        & $observeReadTask $stderrTask 'stderr' | Out-Null
        $endedAtUtc = [datetime]::UtcNow
        if ($null -ne $process) {
            $process.Dispose()
        }
    }

    $exitCodeText = if ($null -eq $exitCode) { '<none>' } else { [string]$exitCode }
    $infrastructureText = $infrastructureErrors.ToArray() -join ' | '
    $finalLog = New-Object System.Text.StringBuilder
    [void]$finalLog.AppendLine('')
    [void]$finalLog.AppendLine('[result]')
    [void]$finalLog.AppendLine("Started: $($started.ToString().ToLowerInvariant())")
    [void]$finalLog.AppendLine("EndedAtUtc: $($endedAtUtc.ToString('o'))")
    [void]$finalLog.AppendLine("ExitCode: $exitCodeText")
    [void]$finalLog.AppendLine("Cancelled: $($cancelled.ToString().ToLowerInvariant())")
    [void]$finalLog.AppendLine("InfrastructureError: $infrastructureText")
    if (-not [string]::IsNullOrWhiteSpace($packageId)) {
        [void]$finalLog.AppendLine("PackageId: $packageId")
        [void]$finalLog.AppendLine("PackageName: $packageName")
        [void]$finalLog.AppendLine("CurrentVersion: $currentVersion")
        [void]$finalLog.AppendLine("AvailableVersion: $availableVersion")
        [void]$finalLog.AppendLine("Source: $source")
    }
    [void]$finalLog.AppendLine('[stdout]')
    [void]$finalLog.AppendLine($standardOutput.ToString())
    [void]$finalLog.AppendLine('[stderr]')
    [void]$finalLog.AppendLine($standardError.ToString())
    [void]$finalLog.AppendLine('[combined]')
    [void]$finalLog.Append($combinedOutput.ToString())
    Write-WingetProcessLogText -State $logState -Text $finalLog.ToString()

    try {
        $logWriter.Dispose()
    }
    catch {
        Add-WingetProcessInfrastructureError `
            -Errors $infrastructureErrors `
            -Message "Command log cleanup failed for '$logPath': $($_.Exception.Message)"
    }
    $infrastructureText = $infrastructureErrors.ToArray() -join ' | '

    return [pscustomobject][ordered]@{
        ApplicationPath = $canonicalPath
        Arguments = $argumentCopy
        DisplayCommand = $displayCommand
        Package = $Package
        PackageId = $packageId
        PackageName = $packageName
        CurrentVersion = $currentVersion
        AvailableVersion = $availableVersion
        Source = $source
        StartedAtUtc = $startedAtUtc
        EndedAtUtc = $endedAtUtc
        Started = $started
        InfrastructureError = $infrastructureText
        CleanupGuaranteed = [bool]$cleanupState.Guaranteed
        ExitCode = $exitCode
        Cancelled = $cancelled
        StandardOutput = $standardOutput.ToString()
        StandardError = $standardError.ToString()
        CombinedOutput = $combinedOutput.ToString()
        LogPath = $logPath
    }
}

function Get-WingetUpdaterPaths {
    param(
        [string]$LocalAppDataPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    )

    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
        throw 'The LocalAppData path is empty.'
    }

    $root = Join-Path $LocalAppDataPath 'WingetUpdater'
    $mockDirectory = Join-Path $root 'mock'
    return [pscustomobject][ordered]@{
        Root = $root
        SettingsFile = Join-Path $root 'settings.json'
        SkipListFile = Join-Path $root 'skip-list.json'
        LicenseNoticeFile = Join-Path $root '.license-notice-shown'
        LogsDirectory = Join-Path $root 'logs'
        RepairContextsDirectory = Join-Path $root 'repair-contexts'
        MockDirectory = $mockDirectory
        MockStateFile = Join-Path $mockDirectory 'MockState.json'
    }
}

function Read-WingetUpdaterJson {
    param([string]$Path)

    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }

    try {
        return ConvertFrom-Json -InputObject $raw -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON file '$Path': $($_.Exception.Message)"
    }
}

function Write-WingetUpdaterJson {
    param(
        [string]$Path,
        [object]$Data
    )

    $directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($directory)) {
        throw "JSON destination has no parent directory: $Path"
    }
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop)
    }

    $json = ConvertTo-Json -InputObject $Data -Depth 20
    $tempPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backupPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.bak')
    $stream = $null
    $writer = $null
    $destinationValidated = $false
    $replacedExistingDestination = $false

    try {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $stream = New-Object System.IO.FileStream(
            $tempPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $writer = New-Object System.IO.StreamWriter($stream, $encoding)
        $writer.Write($json)
        $writer.Flush()
        $stream.Flush($true)
        $writer.Dispose()
        $writer = $null
        $stream = $null

        [void](Read-WingetUpdaterJson -Path $tempPath)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($tempPath, $Path, $backupPath)
            $replacedExistingDestination = $true
        }
        else {
            [System.IO.File]::Move($tempPath, $Path)
        }
        [void](Read-WingetUpdaterJson -Path $Path)
        $destinationValidated = $true
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            try {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
            }
            catch {
                # The destination is committed and validated; a stale backup is safer than a false write failure.
                Write-Verbose "Validated JSON backup cleanup failed for '$backupPath': $($_.Exception.Message)"
            }
        }
    }
    catch {
        $writeError = $_
        if ($replacedExistingDestination -and -not $destinationValidated -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            $failedReplacementPath = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.failed')
            try {
                [System.IO.File]::Replace($backupPath, $Path, $failedReplacementPath)
                if (Test-Path -LiteralPath $failedReplacementPath -PathType Leaf) {
                    try {
                        Remove-Item -LiteralPath $failedReplacementPath -Force -ErrorAction Stop
                    }
                    catch {
                        # Keep the failed replacement for diagnostics if cleanup is unavailable.
                        Write-Verbose "Failed JSON replacement cleanup failed for '$failedReplacementPath': $($_.Exception.Message)"
                    }
                }
            }
            catch {
                throw "JSON write failed for '$Path' and restoring the previous destination also failed: $($_.Exception.Message)"
            }
        }
        throw $writeError
    }
    finally {
        if ($null -ne $writer) {
            $writer.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if ($destinationValidated -and (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
            try {
                Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
            }
            catch {
                # Backup cleanup is best-effort after a validated commit.
                Write-Verbose "Validated JSON backup cleanup retry failed for '$backupPath': $($_.Exception.Message)"
            }
        }
    }
}

function Get-WingetUpdaterObjectProperty {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function ConvertTo-WingetUpdaterSkipIds {
    param(
        [object]$Data,
        [string]$SourceDescription
    )

    $values = $null
    if ($Data -is [System.Array]) {
        $values = @($Data)
    }
    else {
        $property = $Data.PSObject.Properties['skippedIds']
        if ($null -eq $property) {
            $property = $Data.PSObject.Properties['SkippedIds']
        }
        if ($null -eq $property) {
            throw "Skip data has no skippedIds array: $SourceDescription"
        }
        $values = @($property.Value)
    }

    $unique = @{}
    foreach ($value in $values) {
        if (-not ($value -is [string])) {
            throw "Skip data contains a non-string ID: $SourceDescription"
        }
        $id = $value.Trim()
        if ($id.Length -eq 0) {
            throw "Skip data contains an empty ID: $SourceDescription"
        }
        $unique[$id] = $true
    }

    return @($unique.Keys | Sort-Object)
}

function Read-WingetUpdaterSkipIds {
    param([string]$Path)

    $raw = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }

    $trimmed = $raw.TrimStart()
    if ($trimmed.StartsWith('[')) {
        try {
            $data = ConvertFrom-Json -InputObject ('{"skippedIds":' + $raw + '}') -ErrorAction Stop
        }
        catch {
            throw "Invalid JSON file '$Path': $($_.Exception.Message)"
        }
    }
    elseif ($trimmed.StartsWith('{')) {
        $data = Read-WingetUpdaterJson -Path $Path
    }
    else {
        [void](Read-WingetUpdaterJson -Path $Path)
        throw "Skip data root must be an array or object: $Path"
    }

    return @(ConvertTo-WingetUpdaterSkipIds -Data $data -SourceDescription $Path)
}

function Write-WingetUpdaterSkipList {
    param(
        [string]$Path,
        [string[]]$SkippedIds
    )

    $ids = @(ConvertTo-WingetUpdaterSkipIds -Data @($SkippedIds) -SourceDescription 'skip-list input')
    $data = [ordered]@{
        skippedIds = $ids
        updatedAt = (Get-Date).ToString('o')
    }
    Write-WingetUpdaterJson -Path $Path -Data $data
    return $ids
}

function Grant-WingetUpdaterSourceAgreements {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The GUI has already confirmed the source agreement before calling this atomic settings update.')]
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Settings path is empty.'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Settings file does not exist: $Path"
    }

    $settings = Read-WingetUpdaterJson -Path $Path
    $schemaVersion = Get-WingetUpdaterObjectProperty -InputObject $settings -Name 'schemaVersion'
    $migrationVersion = Get-WingetUpdaterObjectProperty -InputObject $settings -Name 'migrationVersion'
    if ($schemaVersion -ne 1 -or $migrationVersion -notin @(0, 1)) {
        throw "Unsupported settings schema: $Path"
    }

    $updatedSettings = [ordered]@{}
    foreach ($property in $settings.PSObject.Properties) {
        $updatedSettings[$property.Name] = $property.Value
    }
    $updatedSettings['sourceAgreementsAccepted'] = $true
    Write-WingetUpdaterJson -Path $Path -Data ([pscustomobject]$updatedSettings)
    return $true
}

function Add-WingetUpdaterWarning {
    param(
        [object]$Warnings,
        [string]$Message
    )

    [void]$Warnings.Add($Message)
}

function Test-WingetUpdaterPathsEqual {
    param(
        [string]$FirstPath,
        [string]$SecondPath
    )

    $trimCharacters = [char[]]@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $firstCanonical = [System.IO.Path]::GetFullPath($FirstPath).TrimEnd($trimCharacters)
    $secondCanonical = [System.IO.Path]::GetFullPath($SecondPath).TrimEnd($trimCharacters)
    return [string]::Equals($firstCanonical, $secondCanonical, [System.StringComparison]::OrdinalIgnoreCase)
}

function Move-WingetUpdaterFileToRecovery {
    param([string]$Path)

    $directory = Split-Path -Parent $Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)
    $number = 1
    do {
        $recoveryPath = Join-Path $directory ($name + '.recovery-' + $number + $extension)
        $number++
    } while (Test-Path -LiteralPath $recoveryPath)

    [System.IO.File]::Move($Path, $recoveryPath)
    return $recoveryPath
}

function Invoke-WingetUpdaterLegacyItemCleanup {
    param(
        [string]$Path,
        [object]$Warnings
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    try {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    }
    catch {
        Add-WingetUpdaterWarning -Warnings $Warnings -Message "Legacy cleanup failed for '$Path': $($_.Exception.Message)"
    }
}

function Invoke-WingetUpdaterEmptyLegacyDirectoryCleanup {
    param(
        [string]$Path,
        [object]$Warnings
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }
    try {
        if (@(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop).Count -eq 0) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
    }
    catch {
        Add-WingetUpdaterWarning -Warnings $Warnings -Message "Legacy directory cleanup failed for '$Path': $($_.Exception.Message)"
    }
}

function Test-WingetUpdaterFilesEqual {
    param(
        [string]$FirstPath,
        [string]$SecondPath
    )

    $first = [System.IO.File]::ReadAllBytes($FirstPath)
    $second = [System.IO.File]::ReadAllBytes($SecondPath)
    if ($first.Length -ne $second.Length) {
        return $false
    }
    for ($index = 0; $index -lt $first.Length; $index++) {
        if ($first[$index] -ne $second[$index]) {
            return $false
        }
    }
    return $true
}

function Get-WingetUpdaterContextDestination {
    param(
        [string]$SourcePath,
        [string]$DestinationDirectory
    )

    $name = [System.IO.Path]::GetFileName($SourcePath)
    $directPath = Join-Path $DestinationDirectory $name
    if (-not (Test-Path -LiteralPath $directPath -PathType Leaf)) {
        return $directPath
    }
    if (Test-WingetUpdaterFilesEqual -FirstPath $SourcePath -SecondPath $directPath) {
        return $directPath
    }

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $extension = [System.IO.Path]::GetExtension($name)
    $collisionPattern = '^' + [regex]::Escape($baseName) + '-migrated-(?<number>\d+)' + [regex]::Escape($extension) + '$'
    foreach ($file in @(Get-ChildItem -LiteralPath $DestinationDirectory -File -ErrorAction Stop)) {
        if ($file.Name -match $collisionPattern -and (Test-WingetUpdaterFilesEqual -FirstPath $SourcePath -SecondPath $file.FullName)) {
            return $file.FullName
        }
    }

    $number = 1
    do {
        $candidate = Join-Path $DestinationDirectory ($baseName + '-migrated-' + $number + $extension)
        $number++
    } while (Test-Path -LiteralPath $candidate)
    return $candidate
}

function Copy-WingetUpdaterContextFile {
    param(
        [string]$SourcePath,
        [string]$DestinationDirectory
    )

    $destinationPath = Get-WingetUpdaterContextDestination -SourcePath $SourcePath -DestinationDirectory $DestinationDirectory
    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        if (-not (Test-WingetUpdaterFilesEqual -FirstPath $SourcePath -SecondPath $destinationPath)) {
            throw "Repair context collision could not be resolved: $SourcePath"
        }
        return $destinationPath
    }

    $tempPath = Join-Path $DestinationDirectory ('.context.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::Copy($SourcePath, $tempPath, $false)
        if (-not (Test-WingetUpdaterFilesEqual -FirstPath $SourcePath -SecondPath $tempPath)) {
            throw "Repair context copy validation failed: $SourcePath"
        }
        [System.IO.File]::Move($tempPath, $destinationPath)
        [System.IO.File]::SetLastWriteTimeUtc($destinationPath, [System.IO.File]::GetLastWriteTimeUtc($SourcePath))
        if (-not (Test-WingetUpdaterFilesEqual -FirstPath $SourcePath -SecondPath $destinationPath)) {
            throw "Repair context destination validation failed: $destinationPath"
        }
        return $destinationPath
    }
    finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WingetUpdaterMarkerCreation {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return
    }
    $directory = Split-Path -Parent $Path
    $tempPath = Join-Path $directory ('.marker.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $stream = $null
    try {
        $stream = New-Object System.IO.FileStream(
            $tempPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $stream.Flush($true)
        $stream.Dispose()
        $stream = $null
        [System.IO.File]::Move($tempPath, $Path)
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-WingetUpdaterExpiredFileCleanup {
    param(
        [string]$Directory,
        [datetime]$CutoffUtc,
        [object]$Warnings
    )

    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Recurse -ErrorAction Stop)) {
        if ($file.LastWriteTimeUtc -ge $CutoffUtc) {
            continue
        }
        try {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
        }
        catch {
            Add-WingetUpdaterWarning -Warnings $Warnings -Message "Expired file cleanup failed for '$($file.FullName)': $($_.Exception.Message)"
        }
    }
}

function Initialize-WingetUpdaterStorage {
    param(
        [object]$Paths,
        [string]$LegacyAppDirectory,
        [int]$RetentionDays = 30
    )

    if ($RetentionDays -lt 1) {
        throw 'RetentionDays must be at least 1.'
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($directory in @($Paths.Root, $Paths.LogsDirectory, $Paths.RepairContextsDirectory, $Paths.MockDirectory)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            [void](New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop)
        }
    }

    $settings = $null
    $settingsExisted = Test-Path -LiteralPath $Paths.SettingsFile -PathType Leaf
    if ($settingsExisted) {
        try {
            $settings = Read-WingetUpdaterJson -Path $Paths.SettingsFile
            $schemaVersion = Get-WingetUpdaterObjectProperty -InputObject $settings -Name 'schemaVersion'
            $migrationVersion = Get-WingetUpdaterObjectProperty -InputObject $settings -Name 'migrationVersion'
            if ($schemaVersion -ne 1 -or $null -eq $migrationVersion -or $migrationVersion -notin @(0, 1)) {
                throw "Unsupported settings schema: $($Paths.SettingsFile)"
            }
        }
        catch {
            $settingsRecovery = Move-WingetUpdaterFileToRecovery -Path $Paths.SettingsFile
            Add-WingetUpdaterWarning -Warnings $warnings -Message "Corrupt destination settings were preserved in recovery file '$settingsRecovery'; safe settings were reinitialized."
            $settingsExisted = $false
        }
    }
    if (-not $settingsExisted) {
        $settings = [pscustomobject][ordered]@{
            schemaVersion = 1
            migrationVersion = 0
        }
    }

    if (-not (Test-Path -LiteralPath $Paths.SkipListFile -PathType Leaf)) {
        [void](Write-WingetUpdaterSkipList -Path $Paths.SkipListFile -SkippedIds @())
    }
    else {
        try {
            [void](Read-WingetUpdaterSkipIds -Path $Paths.SkipListFile)
        }
        catch {
            $skipRecovery = Move-WingetUpdaterFileToRecovery -Path $Paths.SkipListFile
            Add-WingetUpdaterWarning -Warnings $warnings -Message "Corrupt destination skip-list data were preserved in recovery file '$skipRecovery'; a safe skip-list was reinitialized."
            [void](Write-WingetUpdaterSkipList -Path $Paths.SkipListFile -SkippedIds @())
        }
    }

    $migrationDataComplete = $true
    $legacySkip = Join-Path $LegacyAppDirectory 'skip-list.json'
    $legacySkipAliasesDestination = Test-WingetUpdaterPathsEqual -FirstPath $legacySkip -SecondPath $Paths.SkipListFile
    if (-not $legacySkipAliasesDestination -and (Test-Path -LiteralPath $legacySkip -PathType Leaf)) {
        try {
            $destinationIds = @(Read-WingetUpdaterSkipIds -Path $Paths.SkipListFile)
            $legacyIds = @(Read-WingetUpdaterSkipIds -Path $legacySkip)
            $merged = @($destinationIds + $legacyIds | Sort-Object -Unique)
            [void](Write-WingetUpdaterSkipList -Path $Paths.SkipListFile -SkippedIds $merged)
            $validatedIds = @(Read-WingetUpdaterSkipIds -Path $Paths.SkipListFile)
            if (($validatedIds -join "`n") -ne ($merged -join "`n")) {
                throw 'Merged skip-list destination validation failed.'
            }
            Invoke-WingetUpdaterLegacyItemCleanup -Path $legacySkip -Warnings $warnings
        }
        catch {
            $migrationDataComplete = $false
            Add-WingetUpdaterWarning -Warnings $warnings -Message "Legacy skip-list migration failed for '$legacySkip': $($_.Exception.Message)"
        }
    }

    $legacyContexts = Join-Path $LegacyAppDirectory 'repair-contexts'
    $legacyContextsAliasDestination = Test-WingetUpdaterPathsEqual -FirstPath $legacyContexts -SecondPath $Paths.RepairContextsDirectory
    if (-not $legacyContextsAliasDestination -and (Test-Path -LiteralPath $legacyContexts -PathType Container)) {
        foreach ($sourceFile in @(Get-ChildItem -LiteralPath $legacyContexts -File -ErrorAction Stop)) {
            try {
                [void](Copy-WingetUpdaterContextFile -SourcePath $sourceFile.FullName -DestinationDirectory $Paths.RepairContextsDirectory)
                Invoke-WingetUpdaterLegacyItemCleanup -Path $sourceFile.FullName -Warnings $warnings
            }
            catch {
                $migrationDataComplete = $false
                Add-WingetUpdaterWarning -Warnings $warnings -Message "Legacy repair context migration failed for '$($sourceFile.FullName)': $($_.Exception.Message)"
            }
        }
        Invoke-WingetUpdaterEmptyLegacyDirectoryCleanup -Path $legacyContexts -Warnings $warnings
    }

    $legacyMockDirectory = Join-Path $LegacyAppDirectory 'Tests'
    $legacyMock = Join-Path $legacyMockDirectory 'MockState.json'
    if (Test-Path -LiteralPath $legacyMock -PathType Leaf) {
        try {
            $cleanupLegacyMock = $true
            $useLegacy = -not (Test-Path -LiteralPath $Paths.MockStateFile -PathType Leaf)
            if (-not $useLegacy) {
                [void](Read-WingetUpdaterJson -Path $Paths.MockStateFile)
                $legacyWriteTime = [System.IO.File]::GetLastWriteTimeUtc($legacyMock)
                $destinationWriteTime = [System.IO.File]::GetLastWriteTimeUtc($Paths.MockStateFile)
                $useLegacy = $legacyWriteTime -gt $destinationWriteTime
                if ($legacyWriteTime -eq $destinationWriteTime -and -not (Test-WingetUpdaterFilesEqual -FirstPath $legacyMock -SecondPath $Paths.MockStateFile)) {
                    $cleanupLegacyMock = $false
                    $migrationDataComplete = $false
                    Add-WingetUpdaterWarning -Warnings $warnings -Message "Legacy and destination Mock states have equal timestamps but different contents; both files were preserved for recovery."
                }
            }
            if ($useLegacy) {
                $legacyMockData = Read-WingetUpdaterJson -Path $legacyMock
                $legacyWriteTime = [System.IO.File]::GetLastWriteTimeUtc($legacyMock)
                Write-WingetUpdaterJson -Path $Paths.MockStateFile -Data $legacyMockData
                [System.IO.File]::SetLastWriteTimeUtc($Paths.MockStateFile, $legacyWriteTime)
            }
            [void](Read-WingetUpdaterJson -Path $Paths.MockStateFile)
            if ($cleanupLegacyMock) {
                Invoke-WingetUpdaterLegacyItemCleanup -Path $legacyMock -Warnings $warnings
            }
        }
        catch {
            $migrationDataComplete = $false
            Add-WingetUpdaterWarning -Warnings $warnings -Message "Legacy Mock migration failed for '$legacyMock': $($_.Exception.Message)"
        }
        Invoke-WingetUpdaterEmptyLegacyDirectoryCleanup -Path $legacyMockDirectory -Warnings $warnings
    }

    $legacyLicenseMarker = Join-Path $LegacyAppDirectory '.license-accepted'
    if (Test-Path -LiteralPath $legacyLicenseMarker -PathType Leaf) {
        try {
            Invoke-WingetUpdaterMarkerCreation -Path $Paths.LicenseNoticeFile
            if (-not (Test-Path -LiteralPath $Paths.LicenseNoticeFile -PathType Leaf)) {
                throw 'License notice marker validation failed.'
            }
            Invoke-WingetUpdaterLegacyItemCleanup -Path $legacyLicenseMarker -Warnings $warnings
        }
        catch {
            $migrationDataComplete = $false
            Add-WingetUpdaterWarning -Warnings $warnings -Message "Legacy license marker migration failed for '$legacyLicenseMarker': $($_.Exception.Message)"
        }
    }

    $targetMigrationVersion = if ($migrationDataComplete) { 1 } else { 0 }
    $currentMigrationVersion = Get-WingetUpdaterObjectProperty -InputObject $settings -Name 'migrationVersion'
    if (-not $settingsExisted -or $currentMigrationVersion -ne $targetMigrationVersion) {
        $settings.migrationVersion = $targetMigrationVersion
        Write-WingetUpdaterJson -Path $Paths.SettingsFile -Data $settings
    }

    $cutoffUtc = [datetime]::UtcNow.AddDays(-$RetentionDays)
    Invoke-WingetUpdaterExpiredFileCleanup -Directory $Paths.LogsDirectory -CutoffUtc $cutoffUtc -Warnings $warnings
    Invoke-WingetUpdaterExpiredFileCleanup -Directory $Paths.RepairContextsDirectory -CutoffUtc $cutoffUtc -Warnings $warnings

    $sourceAgreementsAccepted = [bool](Get-WingetUpdaterObjectProperty -InputObject $settings -Name 'sourceAgreementsAccepted')

    return [pscustomobject]@{
        Paths = $Paths
        MigrationVersion = $targetMigrationVersion
        SourceAgreementsAccepted = $sourceAgreementsAccepted
        Warnings = [string[]]$warnings.ToArray()
    }
}

function New-WingetUpdaterSessionFailureRegistry {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates and returns only an in-memory dictionary.')]
    param()

    return [ordered]@{}
}

function Get-WingetUpdaterPackageKey {
    param(
        [string]$Id,
        [string]$Source
    )
    if ([string]::IsNullOrWhiteSpace($Source)) {
        return [string]$Id
    }
    return "$Id|$Source"
}

function Add-WingetUpdaterSessionFailure {
    param(
        [System.Collections.IDictionary]$Registry,
        [object]$Package,
        [object]$Result,
        [string]$FailureType = 'PackageUpgradeFailure',
        [AllowNull()][Nullable[int]]$AttemptCountOverride
    )

    if ($null -eq $Registry -or $null -eq $Package) {
        return
    }
    if ($null -ne $Result -and $Result.PSObject.Properties['Cancelled'] -and [bool]$Result.Cancelled) {
        return
    }

    $id = if ($Package.PSObject.Properties['Id']) { [string]$Package.Id } else { '' }
    $source = if ($Package.PSObject.Properties['Source']) { [string]$Package.Source } else { '' }
    if ([string]::IsNullOrWhiteSpace($id)) {
        return
    }

    $key = Get-WingetUpdaterPackageKey -Id $id -Source $source
    $previousAttemptCount = 0
    if ($Registry.Contains($key)) {
        $previousAttemptCount = [int]$Registry[$key].AttemptCount
    }

    $attemptCount = if ($null -ne $AttemptCountOverride) {
        if ([int]$AttemptCountOverride -lt 1) {
            throw 'Attempt count override must be greater than zero.'
        }
        [int]$AttemptCountOverride
    }
    else {
        $previousAttemptCount + 1
    }

    $name = if ($Package.PSObject.Properties['Name']) { [string]$Package.Name } else { '' }
    $currentVersion = if ($Package.PSObject.Properties['CurrentVersion']) { [string]$Package.CurrentVersion } else { '' }
    $availableVersion = if ($Package.PSObject.Properties['AvailableVersion']) { [string]$Package.AvailableVersion } else { '' }
    $scope = if ($Package.PSObject.Properties['Scope']) { [string]$Package.Scope } else { 'User' }

    $exitCode = $null
    $displayArguments = ''
    $standardOutput = ''
    $standardError = ''
    $combinedOutput = ''
    $logPath = ''
    $startedAtUtc = $null
    $endedAtUtc = $null

    if ($null -ne $Result) {
        if ($Result.PSObject.Properties['ExitCode']) { $exitCode = $Result.ExitCode }
        if ($Result.PSObject.Properties['DisplayCommand']) {
            $displayArguments = [string]$Result.DisplayCommand
        }
        elseif ($Result.PSObject.Properties['DisplayArguments']) {
            $displayArguments = [string]$Result.DisplayArguments
        }
        if ($Result.PSObject.Properties['StartedAtUtc'] -and $null -ne $Result.StartedAtUtc) { $startedAtUtc = [datetime]$Result.StartedAtUtc }
        if ($Result.PSObject.Properties['EndedAtUtc'] -and $null -ne $Result.EndedAtUtc) { $endedAtUtc = [datetime]$Result.EndedAtUtc }
        if ($Result.PSObject.Properties['StandardOutput']) { $standardOutput = [string]$Result.StandardOutput }
        if ($Result.PSObject.Properties['StandardError']) { $standardError = [string]$Result.StandardError }
        if ($Result.PSObject.Properties['CombinedOutput']) { $combinedOutput = [string]$Result.CombinedOutput }
        if ($Result.PSObject.Properties['LogPath']) { $logPath = [string]$Result.LogPath }
    }

    $record = [pscustomobject]@{
        Key = $key
        Id = $id
        Name = $name
        CurrentVersion = $currentVersion
        AvailableVersion = $availableVersion
        Source = $source
        Scope = $scope
        FailureType = $FailureType
        AttemptCount = $attemptCount
        TimestampUtc = [datetime]::UtcNow
        StartedAtUtc = $startedAtUtc
        EndedAtUtc = $endedAtUtc
        ExitCode = $exitCode
        DisplayArguments = $displayArguments
        StandardOutput = $standardOutput
        StandardError = $standardError
        CombinedOutput = $combinedOutput
        LogPath = $logPath
    }

    $Registry[$key] = $record
}

function Get-WingetUpdaterSessionFailure {
    param(
        [System.Collections.IDictionary]$Registry,
        [string]$Id,
        [string]$Source
    )

    if ($null -eq $Registry -or [string]::IsNullOrWhiteSpace($Id)) {
        return $null
    }

    $key = Get-WingetUpdaterPackageKey -Id $Id -Source $Source
    if ($Registry.Contains($key)) {
        return $Registry[$key]
    }
    return $null
}

function Remove-WingetUpdaterSessionFailure {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Mutates only the caller-owned in-memory session registry.')]
    param(
        [System.Collections.IDictionary]$Registry,
        [string]$Id,
        [string]$Source
    )
    if ($null -eq $Registry -or [string]::IsNullOrWhiteSpace($Id)) {
        return
    }
    $key = Get-WingetUpdaterPackageKey -Id $Id -Source $Source
    if ($Registry.Contains($key)) {
        $Registry.Remove($key)
    }
}

function Get-WingetUpdaterSessionFailures {
    param(
        [System.Collections.IDictionary]$Registry,
        [object[]]$SelectedPackages = @()
    )

    if ($null -eq $Registry -or $Registry.Count -eq 0) {
        return @()
    }

    if ($null -ne $SelectedPackages -and $SelectedPackages.Count -gt 0) {
        $selectedKeys = @()
        foreach ($pkg in $SelectedPackages) {
            if ($null -ne $pkg -and $pkg.PSObject.Properties['Id']) {
                $id = [string]$pkg.Id
                $src = if ($pkg.PSObject.Properties['Source']) { [string]$pkg.Source } else { '' }
                $selectedKeys += Get-WingetUpdaterPackageKey -Id $id -Source $src
            }
        }
        $matching = @()
        foreach ($key in $selectedKeys) {
            if ($Registry.Contains($key)) {
                $matching += $Registry[$key]
            }
        }
        if ($matching.Count -gt 0) {
            return $matching
        }
    }

    return @($Registry.Values)
}

function New-WingetUpdaterRepairContextFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Directory,
        [object[]]$Failures
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) {
        throw 'Context directory cannot be empty.'
    }
    if ($null -eq $Failures -or $Failures.Count -eq 0) {
        throw 'No failures provided for context generation.'
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $filename = "repair-context-$stamp-$([guid]::NewGuid().ToString('N')).txt"
    $filePath = Join-Path $Directory $filename
    if (-not $PSCmdlet.ShouldProcess($filePath, 'Create AI repair context')) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('=== WingetUpdater AI Repair Context ===')
    [void]$lines.Add("Generated: $([datetime]::UtcNow.ToString('o'))")
    [void]$lines.Add("Failures Count: $($Failures.Count)")
    [void]$lines.Add('')

    foreach ($f in $Failures) {
        [void]$lines.Add("--- Package: $($f.Name) ($($f.Id)) ---")
        [void]$lines.Add("Source: $($f.Source)")
        [void]$lines.Add("Current Version: $($f.CurrentVersion)")
        [void]$lines.Add("Available Version: $($f.AvailableVersion)")
        [void]$lines.Add("Failure Type: $($f.FailureType)")
        [void]$lines.Add("Attempt Count: $($f.AttemptCount)")
        $startedAtText = if ($null -ne $f.StartedAtUtc) { ([datetime]$f.StartedAtUtc).ToString('o') } else { '' }
        $endedAtText = if ($null -ne $f.EndedAtUtc) { ([datetime]$f.EndedAtUtc).ToString('o') } else { '' }
        [void]$lines.Add("Started At UTC: $startedAtText")
        [void]$lines.Add("Ended At UTC: $endedAtText")
        [void]$lines.Add("Exit Code: $($f.ExitCode)")
        [void]$lines.Add("Command Line: $($f.DisplayArguments)")
        [void]$lines.Add("Log File: $($f.LogPath)")
        [void]$lines.Add('')
        [void]$lines.Add('STDOUT:')
        [void]$lines.Add([string]$f.StandardOutput)
        [void]$lines.Add('')
        [void]$lines.Add('STDERR:')
        [void]$lines.Add([string]$f.StandardError)
        [void]$lines.Add('')
    }

    $lines | Set-Content -LiteralPath $filePath -Encoding UTF8
    return $filePath
}

function Get-WingetUpdaterAIPrompt {
    param(
        [string]$ContextFilePath
    )
    return "Analizuję błąd aktualizacji pakietu w WingetUpdater. Szczegółowy kontekst i błędy są w pliku: '$ContextFilePath'. Przeanalizuj błąd i podaj przyczyny oraz bezpieczne kroki naprawy."
}

function Resolve-WingetUpdaterAICliPath {
    param(
        [string]$CliName
    )

    if ($CliName -notin @('codex', 'agy')) {
        throw "Unsupported AI CLI: $CliName"
    }

    $commands = @(Get-Command -Name $CliName -All -ErrorAction SilentlyContinue)
    foreach ($cmd in $commands) {
        if ($null -eq $cmd -or [string]$cmd.CommandType -ne 'Application') {
            continue
        }

        $source = [string]$cmd.Source
        $isAbsolute = [System.IO.Path]::IsPathRooted($source) -or $source -match '^[A-Za-z]:[\\/]'
        $extension = [System.IO.Path]::GetExtension($source).ToLowerInvariant()
        if (-not $isAbsolute -or $extension -notin @('.exe', '.cmd')) {
            continue
        }
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            return $source
        }
    }

    return $null
}

function Start-WingetUpdaterAICliProcess {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CliPath,
        [string]$CommandProcessorPath
    )

    if ([string]::IsNullOrWhiteSpace($CliPath)) {
        throw 'CLI executable path cannot be empty.'
    }

    $isAbsolute = [System.IO.Path]::IsPathRooted($CliPath) -or $CliPath -match '^[A-Za-z]:[\\/]'
    $extension = [System.IO.Path]::GetExtension($CliPath).ToLowerInvariant()
    if (-not $isAbsolute -or $extension -notin @('.exe', '.cmd') -or -not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
        throw "CLI path must be an existing absolute .exe or .cmd file: $CliPath"
    }

    $userProfile = [Environment]::GetFolderPath('UserProfile')
    if ($extension -eq '.exe') {
        if ($PSCmdlet.ShouldProcess($CliPath, 'Open AI CLI in a normal-privilege console')) {
            Start-Process -FilePath $CliPath -WorkingDirectory $userProfile
        }
        return
    }

    if ([string]::IsNullOrWhiteSpace($CommandProcessorPath)) {
        $systemRoot = [Environment]::GetEnvironmentVariable('SystemRoot')
        if ([string]::IsNullOrWhiteSpace($systemRoot)) {
            throw 'SystemRoot is unavailable; cannot resolve the command processor.'
        }
        $CommandProcessorPath = Join-Path $systemRoot 'System32\cmd.exe'
    }
    $isCommandProcessorAbsolute = [System.IO.Path]::IsPathRooted($CommandProcessorPath) -or $CommandProcessorPath -match '^[A-Za-z]:[\\/]'
    if (-not $isCommandProcessorAbsolute -or -not (Test-Path -LiteralPath $CommandProcessorPath -PathType Leaf)) {
        throw "Trusted command processor was not found: $CommandProcessorPath"
    }

    $arguments = "/d /c start `"`" `"$CliPath`""
    if ($PSCmdlet.ShouldProcess($CliPath, 'Open AI CLI command shim in a normal-privilege console')) {
        Start-Process -FilePath $CommandProcessorPath -ArgumentList $arguments -WorkingDirectory $userProfile
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-PlainText'
    'Repair-DisplayText'
    'Parse-WingetUpgradeOutput'
    'Join-CommandLineArguments'
    'New-WingetSourceUpdateArguments'
    'New-WingetUpgradeListArguments'
    'New-WingetPackageUpgradeArguments'
    'Resolve-WingetUpdaterSourceAgreementConsent'
    'New-WingetUpdaterCancellationState'
    'Request-WingetUpdaterCancellation'
    'Test-WingetUpdaterCancellationRequested'
    'Stop-WingetProcessTree'
    'Get-WingetUpdaterMutexName'
    'Get-WingetUpdaterCurrentUserSid'
    'Enter-WingetUpdaterSingleInstance'
    'Exit-WingetUpdaterSingleInstance'
    'Set-WingetUpdaterBusyControlState'
    'Resolve-WingetUpdaterCloseRequest'
    'Resolve-WingetApplicationPath'
    'ConvertFrom-WingetUpgradeResult'
    'Invoke-WingetProcess'
    'Stop-WingetProcess'
    'Get-WingetUpdaterPaths'
    'Initialize-WingetUpdaterStorage'
    'Read-WingetUpdaterJson'
    'Read-WingetUpdaterSkipIds'
    'Write-WingetUpdaterJson'
    'Write-WingetUpdaterSkipList'
    'Grant-WingetUpdaterSourceAgreements'
    'New-WingetUpdaterSessionFailureRegistry'
    'Get-WingetUpdaterPackageKey'
    'Add-WingetUpdaterSessionFailure'
    'Get-WingetUpdaterSessionFailure'
    'Remove-WingetUpdaterSessionFailure'
    'Get-WingetUpdaterSessionFailures'
    'New-WingetUpdaterRepairContextFile'
    'Get-WingetUpdaterAIPrompt'
    'Resolve-WingetUpdaterAICliPath'
    'Start-WingetUpdaterAICliProcess'
)
