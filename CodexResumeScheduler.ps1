# Codex Resume Scheduler — Windows PowerShell 7 / Windows Forms
# Single-file UI and scheduled-task runner. No external modules or services.
# v1.11.0: WPF compositor-driven moving shine on all usage and countdown bars.
[CmdletBinding()]
param(
    [switch]$RunJob,
    [string]$JobFile
)

$ErrorActionPreference = 'Stop'
# A hidden GUI host must still report startup errors visibly, rather than failing silently.
trap {
    if (-not $RunJob) {
        $problem = "Codex Resume Scheduler could not start: $($_.Exception.Message)"
        try {
            $errorDir = Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
            [void](New-Item -ItemType Directory -Path $errorDir -Force)
            Add-Content -LiteralPath (Join-Path $errorDir 'gui-startup.log') -Value "$(Get-Date -Format o) $problem"
        } catch { }
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show($problem,'Scheduler startup error') | Out-Null
        } catch { }
    }
    exit 1
}
$appDir = Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
$sessionIdPattern = '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$script:appSourcePath = $PSCommandPath
. (Join-Path $PSScriptRoot 'CodexData.ps1')



function Get-RepositoryBranch {
    param([string]$Path)
    $branch = & git -C $Path branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branch) { throw 'Unable to identify a Git branch (detached HEAD is not supported).' }
    return ([string]($branch | Select-Object -First 1)).Trim()
}

function Get-CodexCliJs {
    $shim = (Get-Command codex.cmd -ErrorAction Stop).Source
    $entry = Join-Path (Split-Path -Parent $shim) 'node_modules\@openai\codex\bin\codex.js'
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'Cannot locate npm Codex App Server entrypoint.' }
    return $entry
}

function Read-UsageState {
    param([string]$Model)
    $helper = Join-Path $PSScriptRoot 'CodexUsage.js'
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'CodexUsage.js missing.' }
    $cli = Get-CodexCliJs
    $params = @($helper,'--cli-js',$cli,'--rates-only')
    if ($Model) { $params += @('--model',$Model) }
    $response = & node @params
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Codex usage.' }
    $state = ($response | Select-Object -Last 1) | ConvertFrom-Json
    if (-not $state.ok) { throw 'Codex rate-limit response unavailable.' }
    return $state
}

# Legacy settings.json files contain only lastAccess. A draft is optional.
$script:uiSettings = Read-CodexUiSettings $appDir
$script:savedDraft = if ($script:uiSettings -and $script:uiSettings.draft) { $script:uiSettings.draft } else { $null }
$script:preferredSessionId = if ($script:savedDraft) { [string]$script:savedDraft.sessionId } else { '' }
$script:preferredModelId = if ($script:savedDraft) { [string]$script:savedDraft.model } else { '' }
$script:preferredEffort = if ($script:savedDraft) { [string]$script:savedDraft.effort } else { '' }
$script:startupSavedSessionId = $script:preferredSessionId
$script:startupSavedModelId = $script:preferredModelId
$script:repoSelectionSessionId = ''
$script:settingsReady = $false

function Get-SavedAccessPreference {
    if ($script:savedDraft -and $script:savedDraft.access -in @('workspace-write','yolo','read-only')) { return [string]$script:savedDraft.access }
    if ($script:uiSettings -and $script:uiSettings.lastAccess -in @('workspace-write','yolo','read-only')) { return [string]$script:uiSettings.lastAccess }
    return 'workspace-write'
}

function Assert-ModelEffortSupported {
    param([object[]]$Models, [string]$Model, [string]$Effort)
    $entry = @($Models | Where-Object { $_.id -ceq $Model }) | Select-Object -First 1
    if (-not $entry) { throw "Model '$Model' is not in the currently available Codex catalog. Refresh models." }
    $allowed = @($entry.efforts | Where-Object { $_ -is [string] -and $_ -ne 'ultra' })
    if ($allowed.Count -eq 0 -or $allowed -cnotcontains $Effort) {
        throw "Model '$Model' does not advertise reasoning effort '$Effort'. Supported: $($allowed -join ', ')."
    }
}

function Read-CodexModelCatalog {
    $helper = Join-Path $PSScriptRoot 'CodexUsage.js'
    $cli = Get-CodexCliJs
    $lines = & node $helper --cli-js $cli --models-only
    if ($LASTEXITCODE -ne 0 -or -not $lines) { throw 'Could not verify current Codex model capabilities.' }
    $state = ($lines | Select-Object -Last 1) | ConvertFrom-Json
    if (-not $state.ok -or -not $state.models -or $state.models.Count -eq 0) { throw 'Codex model catalog unavailable.' }
    return @($state.models)
}

function Schedule-LimitRetry {
    param($Job, [long]$ResetAt, [long]$RunAt, [string]$BucketId)
    $attempt = [int]$Job.retryAttempt + 1
    if ($attempt -gt 4) { Write-Host 'Automatic resume stopped: maximum four attempts reached.' -ForegroundColor Yellow; return }
    $when = [DateTimeOffset]::FromUnixTimeSeconds($RunAt).LocalDateTime
    $rounded = [datetime]::new($when.Year,$when.Month,$when.Day,$when.Hour,$when.Minute,0)
    if ($when -gt $rounded) { $rounded = $rounded.AddMinutes(1) }
    $when = $rounded
    if ($when -le (Get-Date).AddSeconds(60)) { Write-Host 'Reset time is not safely in the future; no retry scheduled.' -ForegroundColor Yellow; return }
    $name = 'CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
    $jobFile = Join-Path $appDir ($name + '.json')
    $next = [pscustomobject]@{ sessionId=$Job.sessionId; repo=$Job.repo; branch=$Job.branch; model=$Job.model;
        effort=$Job.effort; access=$Job.access; message=$Job.message; autoResume=$true;
        createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); accountId=$Job.accountId; retryAttempt=$attempt; previousResetAt=$ResetAt;
        log=(Join-Path $appDir ($name + '.log')) }
    $next | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jobFile -Encoding utf8
    # Run the saved job through the signed Windows Script Host, not a custom executable.
    $runnerScript = Join-Path $appDir 'CodexRunJob.vbs'
    if (-not (Test-Path -LiteralPath $runnerScript -PathType Leaf)) { throw 'CodexRunJob.vbs missing; install the complete release.' }
    $arguments = '//B //Nologo "' + $runnerScript + '" "' + $jobFile + '"'
    $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\wscript.exe') -Argument $arguments -WorkingDirectory $Job.repo
    $trigger = New-ScheduledTaskTrigger -Once -At $when
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    try {
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable) -ErrorAction Stop | Out-Null
        Write-Host "Confirmed quota '$BucketId' blocked; attempt $attempt/4 scheduled for $($when.ToString('yyyy-MM-dd HH:mm:ss zzz')) (local), after reported reset $([DateTimeOffset]::FromUnixTimeSeconds($ResetAt).LocalDateTime)." -ForegroundColor Yellow
    } catch {
        Remove-Item -LiteralPath $jobFile -ErrorAction SilentlyContinue
        throw
    }
}

if ($RunJob) {
    $transcribing = $false
    try {
        if (-not $JobFile -or -not (Test-Path -LiteralPath $JobFile -PathType Leaf)) { throw 'Scheduled job file is missing.' }
        $job = Get-Content -LiteralPath $JobFile -Raw | ConvertFrom-Json
        if ($job.sessionId -notmatch $sessionIdPattern) { throw 'Invalid saved session ID.' }
        if ($job.effort -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$') { throw 'Invalid reasoning effort.' }
        if ($job.model -and $job.model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$') { throw 'Invalid model identifier.' }
        if ($job.access -notin @('read-only','workspace-write','yolo')) { throw 'Invalid saved access setting.' }
        if (-not (Test-Path -LiteralPath $job.repo -PathType Container)) { throw 'Repository no longer exists.' }
        $root = Get-RepositoryRoot $job.repo
        if (-not $root -or ($root.TrimEnd([char[]]@('/','\')) -ine ([string]$job.repo).TrimEnd([char[]]@('/','\')))) { throw 'Saved directory is no longer the repository root.' }
        $branch = Get-RepositoryBranch $root
        if ($branch -cne $job.branch) { throw "Branch changed from '$($job.branch)' to '$branch'. Refusing to run." }
        $logFolder = Split-Path -Parent ([string]$job.log)
        [void](New-Item -ItemType Directory -Path $logFolder -Force)
        Start-Transcript -LiteralPath $job.log -Force | Out-Null
        $transcribing = $true
        Set-Location -LiteralPath $root
        Write-Host "Codex scheduled continuation | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "Session: $($job.sessionId) | Repository: $root | Branch: $branch"
        Write-Host "Model: $($job.model) | Reasoning: $($job.effort) | Access: $($job.access) | Message: $($job.message)"
        $model = [string]$job.model
        Assert-ModelEffortSupported (Read-CodexModelCatalog) $model ([string]$job.effort)
        $auto = $job.autoResume -eq $true
        if ($auto -and [int]$job.retryAttempt -gt 0) {
            $state = Read-UsageState $model
            if ($job.accountId -and $state.accountId -and $job.accountId -ne $state.accountId) { throw 'Codex account changed since initial scheduling.' }
            if (-not $state.canAttempt) {
                if ($state.recommendationKind -eq 'exhausted-window' -and $state.recommendedResetAt -and [int]$job.retryAttempt -lt 4) {
                    Schedule-LimitRetry $job ([long]$state.recommendedResetAt) ([long]$state.recommendedResetAt + 120) ([string]$state.bucketId)
                } else { Write-Host "Usage still unavailable; no reliable future retry: $($state.blockedReason)" -ForegroundColor Yellow }
                return
            }
        }
        $argsList = @('exec','--json','-m',$model,'-c',"model_reasoning_effort=$($job.effort)",'-C',$root)
        if (-not $model) { $argsList = @('exec','--json','-c',"model_reasoning_effort=$($job.effort)",'-C',$root) }
        switch ($job.access) {
            'yolo'            { $argsList += '--dangerously-bypass-approvals-and-sandbox' }
            'workspace-write' { $argsList += @('--sandbox','workspace-write') }
            'read-only'       { $argsList += @('--sandbox','read-only') }
        }
        $argsList += @('resume', [string]$job.sessionId, [string]$job.message)
        $codex = (Get-Command codex.cmd -ErrorAction Stop).Source
        $events = Join-Path $appDir (([IO.Path]::GetFileNameWithoutExtension($JobFile)) + '.jsonl')
        & $codex @argsList 2>&1 | Tee-Object -FilePath $events
        $result = $LASTEXITCODE
        Write-Host "Codex exit code: $result" -ForegroundColor $(if ($result -eq 0) { 'Green' } else { 'Yellow' })
        if ($auto) {
            $retryHelper = Join-Path $PSScriptRoot 'CodexRetry.js'
            $cli = Get-CodexCliJs
            $assessment = & node $retryHelper --events $events --cli-js $cli --model $model | Select-Object -Last 1 | ConvertFrom-Json
            if ($assessment.kind -eq 'retry') {
                if ($job.accountId) {
                    $account = Read-UsageState $model
                    if ($account.accountId -and $account.accountId -ne $job.accountId) { throw 'Codex account changed; refusing retry.' }
                }
                Schedule-LimitRetry $job ([long]$assessment.resetAt) ([long]$assessment.runAt) ([string]$assessment.bucketId)
            } elseif ($assessment.kind -eq 'unknown') {
                Write-Host "Not auto-resuming: $($assessment.reason)" -ForegroundColor Yellow
            }
        }
    } catch {
        $failure = "Scheduled run failed: $($_.Exception.Message)"
        Write-Host $failure -ForegroundColor Red
        if (-not $transcribing) {
            $target = if ($job -and $job.log) { [string]$job.log } else { Join-Path $appDir 'scheduler-errors.log' }
            try {
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
                Add-Content -LiteralPath $target -Value "$(Get-Date -Format o) $failure" -ErrorAction Stop
            } catch { }
        }
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
        Write-Host 'Run finished. Check the logs folder for the transcript.' -ForegroundColor Cyan
    }
    return
}

if (-not $IsWindows) { throw 'This application requires Windows and PowerShell 7.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
# WScript launches PowerShell with its console hidden. The first window show
# request inherits that startup setting, so explicitly show the Forms window.
Add-Type -Namespace CodexScheduler -Name NativeWindow -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr handle, int command);
'@




# Repository candidates must be compared across the selected conversation.
# A valid startup repository is not necessarily the checkout with unfinished work.
# Ambiguous evidence must require an explicit Browse choice, never a guess.



$form = New-Object System.Windows.Forms.Form
$form.Text = 'Codex Resume Scheduler v1.11.0'
$form.ClientSize = [System.Drawing.Size]::new(920,865)
$form.MinimumSize = [System.Drawing.Size]::new(940,875)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::White
$form.Font = [System.Drawing.Font]::new('Segoe UI',10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

function Add-Label {
    param([string]$Text,[int]$X,[int]$Y,[int]$W = 130)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text; $label.Location = [System.Drawing.Point]::new($X,$Y)
    $label.Size = [System.Drawing.Size]::new($W,25)
    $form.Controls.Add($label)
    return $label
}
function Add-Button {
    param([string]$Text,[int]$X,[int]$Y,[int]$W = 110)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text; $button.Location = [System.Drawing.Point]::new($X,$Y)
    $button.Size = [System.Drawing.Size]::new($W,31)
    $button.UseVisualStyleBackColor = $true
    $form.Controls.Add($button)
    return $button
}

$heading = Add-Label 'Schedule a continuation' 18 14 500
$heading.Font = [System.Drawing.Font]::new('Segoe UI',15,[System.Drawing.FontStyle]::Bold)
$heading.Height = 34
$subtitle = Add-Label 'One-time run · Opens a visible terminal' 544 22 355
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.TextAlign = 'MiddleRight'

[void](Add-Label 'Conversation' 18 65)
$sessionBox = New-Object System.Windows.Forms.ComboBox
$sessionBox.Location = [System.Drawing.Point]::new(155,61)
$sessionBox.Size = [System.Drawing.Size]::new(605,30)
$sessionBox.DropDownStyle = 'DropDownList'
$sessionBox.DisplayMember = 'Display'
$form.Controls.Add($sessionBox)
$refreshSessions = Add-Button 'Refresh' 773 60 125

[void](Add-Label 'Repository root' 18 111)
$repoBox = New-Object System.Windows.Forms.TextBox
$repoBox.Location = [System.Drawing.Point]::new(155,108)
$repoBox.Size = [System.Drawing.Size]::new(605,30)
$form.Controls.Add($repoBox)
$browse = Add-Button 'Browse' 773 106 125

[void](Add-Label 'Run at (local)' 18 157)
$whenBox = New-Object System.Windows.Forms.DateTimePicker
$whenBox.Location = [System.Drawing.Point]::new(155,154)
$whenBox.Size = [System.Drawing.Size]::new(325,30)
$whenBox.Format = 'Custom'
$whenBox.CustomFormat = 'ddd MMM dd, yyyy  hh:mm tt'
$suggested = (Get-Date).AddMinutes(11)
$whenBox.Value = [datetime]::new($suggested.Year,$suggested.Month,$suggested.Day,$suggested.Hour,$suggested.Minute,0)
if ($script:savedDraft) {
    $restoredTime = Get-RestoredRunTime ([string]$script:savedDraft.runAt) (Get-Date)
    if ($restoredTime) { $whenBox.Value = $restoredTime }
}
$form.Controls.Add($whenBox)

[void](Add-Label 'Access' 500 157 95)
$effortBox = New-Object System.Windows.Forms.ComboBox
$effortBox.Location = [System.Drawing.Point]::new(597,199)
$effortBox.Size = [System.Drawing.Size]::new(301,30)
$effortBox.DropDownStyle = 'DropDownList'
$form.Controls.Add($effortBox)

[void](Add-Label 'Model' 18 202)
$accessBox = New-Object System.Windows.Forms.ComboBox
$accessBox.Location = [System.Drawing.Point]::new(597,154)
$accessBox.Size = [System.Drawing.Size]::new(301,30)
$accessBox.DropDownStyle = 'DropDownList'
[void]$accessBox.Items.AddRange([object[]]@('Workspace write','Full access (YOLO)','Read-only test'))
$script:lastAccessPreference = Get-SavedAccessPreference
$accessBox.SelectedIndex = switch ($script:lastAccessPreference) { 'yolo' { 1 } 'read-only' { 2 } default { 0 } }
$form.Controls.Add($accessBox)
[void](Add-Label 'Reasoning' 500 203 95)
$modelBox = New-Object System.Windows.Forms.ComboBox
$modelBox.Location = [System.Drawing.Point]::new(155,199)
$modelBox.Size = [System.Drawing.Size]::new(325,30)
$modelBox.DropDownStyle = 'DropDownList'
$modelBox.DisplayMember = 'Display'
$form.Controls.Add($modelBox)
$script:models = @()
$script:modelCatalogLoaded = $false

[void](Add-Label 'Instruction' 18 247)
$messageBox = New-Object System.Windows.Forms.TextBox
$messageBox.Location = [System.Drawing.Point]::new(155,243)
$messageBox.Size = [System.Drawing.Size]::new(743,30)
$messageBox.Text = if ($script:savedDraft -and $null -ne $script:savedDraft.message) { [string]$script:savedDraft.message } else { 'Resume.' }
$form.Controls.Add($messageBox)
$schedule = Add-Button 'Schedule once' 720 274 178
$schedule.Height = 31
$schedule.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$schedule.Enabled = $false
$autoResumeCheck = New-Object System.Windows.Forms.CheckBox
$autoResumeCheck.Text = 'Retry if Codex hits a usage limit (max 4)'
$autoResumeCheck.Location = [System.Drawing.Point]::new(155,276)
$autoResumeCheck.Size = [System.Drawing.Size]::new(520,21)
$autoResumeCheck.Checked = if ($script:savedDraft -and $script:savedDraft.autoResume -is [bool]) { [bool]$script:savedDraft.autoResume } else { $true }
$form.Controls.Add($autoResumeCheck)

function Get-SelectedModel {
    if ($modelBox.SelectedItem -and $modelBox.SelectedItem.Id) { return [string]$modelBox.SelectedItem.Id }
    return ''
}
function Select-AvailableEfforts {
    $model = Get-SelectedModel
    $entry = @($script:models | Where-Object { $_.id -ceq $model }) | Select-Object -First 1
    $prior = [string]$effortBox.SelectedItem
    $effortBox.Items.Clear()
    if ($entry) {
        foreach ($effort in @($entry.efforts | Where-Object { $_ -ne 'ultra' })) { [void]$effortBox.Items.Add([string]$effort) }
        if ($model -eq $script:preferredModelId -and $effortBox.Items.Contains($script:preferredEffort)) { $effortBox.SelectedItem = $script:preferredEffort }
        elseif ($effortBox.Items.Contains($prior)) { $effortBox.SelectedItem = $prior }
        elseif ($effortBox.Items.Contains([string]$entry.defaultEffort)) { $effortBox.SelectedItem = [string]$entry.defaultEffort }
        elseif ($effortBox.Items.Count -gt 0) { $effortBox.SelectedIndex = 0 }
    }
    $schedule.Enabled = ($null -ne $entry -and $effortBox.SelectedIndex -ge 0)
}


# Launch the existing CodexUsage.js reader without blocking the Windows Forms
# message loop. The UI polls only for process completion; no persistent service.
function Start-UsageRead {
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    $cliJs = Get-CodexCliJs
    $helper = Join-Path $PSScriptRoot 'CodexUsage.js'
    if (-not (Test-Path -LiteralPath $cliJs -PathType Leaf)) { throw 'Codex npm entrypoint not found. Update/install Codex via npm.' }
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'CodexUsage.js is missing. Extract the complete release.' }
    $start = [System.Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $node
    [void]$start.ArgumentList.Add($helper)
    [void]$start.ArgumentList.Add('--cli-js')
    [void]$start.ArgumentList.Add($cliJs)
    $chosen = Get-DashboardUsageModel
    if ($chosen) { [void]$start.ArgumentList.Add('--model'); [void]$start.ArgumentList.Add($chosen) }
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Could not start Codex usage reader.' }
        $script:usageRequestedModel = $chosen
        return $process
    } catch {
        $process.Dispose()
        throw
    }
}

function Format-ResetTime {
    param($Seconds)
    if ($null -eq $Seconds) { return 'Reset time unavailable' }
    return 'Resets ' + [DateTimeOffset]::FromUnixTimeSeconds([long]$Seconds).LocalDateTime.ToString('ddd MMM d, h:mm tt')
}

$separator = New-Object System.Windows.Forms.Label
$separator.BorderStyle = 'Fixed3D'
$separator.Location = [System.Drawing.Point]::new(18,309)
$separator.Size = [System.Drawing.Size]::new(880,2)
$form.Controls.Add($separator)

$usageHeading = Add-Label 'Usage remaining' 18 322 280
$usageHeading.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$usageHeading.Height = 30
$refreshUsage = Add-Button 'Refresh now' 605 320 139
$useReset = Add-Button 'Use reset +2 min' 755 320 143
$useReset.Enabled = $false

. (Join-Path $PSScriptRoot 'CodexFlowingBar.ps1')
. (Join-Path $PSScriptRoot 'CodexDashboard.ps1')

function New-UsageCard {
    param([int]$X, [string]$InitialTitle)
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = [System.Drawing.Point]::new($X,358)
    $card.Size = [System.Drawing.Size]::new(428,108)
    $card.BackColor = [System.Drawing.Color]::FromArgb(247,249,252)
    $card.BorderStyle = 'FixedSingle'
    $form.Controls.Add($card)
    $name = New-Object System.Windows.Forms.Label
    $name.Location = [System.Drawing.Point]::new(12,10)
    $name.Size = [System.Drawing.Size]::new(225,27)
    $name.Text = $InitialTitle
    $name.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $card.Controls.Add($name)
    $remaining = New-Object System.Windows.Forms.Label
    $remaining.Location = [System.Drawing.Point]::new(237,7)
    $remaining.Size = [System.Drawing.Size]::new(176,32)
    $remaining.TextAlign = 'MiddleRight'
    $remaining.Text = '—'
    $remaining.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $card.Controls.Add($remaining)
    $bar = New-FlowingProgressBar $card 12 44 400 17 'quota'
    $reset = New-Object System.Windows.Forms.Label
    $reset.Location = [System.Drawing.Point]::new(12,72)
    $reset.Size = [System.Drawing.Size]::new(400,24)
    $reset.Text = 'Waiting for Codex usage...'
    $reset.ForeColor = [System.Drawing.Color]::DimGray
    $card.Controls.Add($reset)
    return [pscustomobject]@{ Panel = $card; Title = $name; Remaining = $remaining; Bar = $bar; Reset = $reset }
}
$usageCards = @((New-UsageCard 18 'Primary window'), (New-UsageCard 470 'Secondary window'))
$usageNotice = Add-Label 'Loading account usage...' 18 477 880
$usageNotice.ForeColor = [System.Drawing.Color]::DimGray

$separator2 = New-Object System.Windows.Forms.Label
$separator2.BorderStyle = 'Fixed3D'
$separator2.Location = [System.Drawing.Point]::new(18,512)
$separator2.Size = [System.Drawing.Size]::new(880,2)
$form.Controls.Add($separator2)

$pending = Add-Label 'Upcoming runs' 18 527 400
$pending.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$pending.Height = 30

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = [System.Drawing.Point]::new(18,566)
$grid.Size = [System.Drawing.Size]::new(880,195)
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.MultiSelect = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.RowHeadersVisible = $false
$grid.AutoSizeColumnsMode = 'Fill'
$grid.BackgroundColor = [System.Drawing.Color]::White
[void]$grid.Columns.Add('When','Scheduled (local)')
[void]$grid.Columns.Add('Countdown','Time to run')
[void]$grid.Columns.Add('Project','Project')
[void]$grid.Columns.Add('Details','Model / access / instruction')
[void]$grid.Columns.Add('Session','Session')
$grid.Columns[0].FillWeight = 149
$grid.Columns[1].FillWeight = 150
$grid.Columns[2].FillWeight = 145
$grid.Columns[3].FillWeight = 325
$grid.Columns[4].FillWeight = 85
$grid.RowTemplate.Height = 54
$grid.ShowCellToolTips = $true
$form.Controls.Add($grid)
$emptyRuns = New-Object System.Windows.Forms.Label
$emptyRuns.Text = 'No upcoming runs'
$emptyRuns.ForeColor = [System.Drawing.Color]::DimGray
$emptyRuns.TextAlign = 'MiddleCenter'
$emptyRuns.Dock = 'Fill'
$grid.Controls.Add($emptyRuns)
$grid.Add_SelectionChanged({ $cancelRun.Enabled = ($grid.SelectedRows.Count -eq 1) })

$refreshRuns = Add-Button 'Refresh runs' 18 774 154
$cancelRun = Add-Button 'Cancel selected' 185 774 154
$cancelRun.Enabled = $false
$openFolder = Add-Button 'Open logs folder' 352 774 154
$status = Add-Label 'Ready. Keep Windows awake and signed in for scheduled runs.' 18 823 880
$status.ForeColor = [System.Drawing.Color]::DimGray
$status.AutoEllipsis = $true

function Update-Status {
    param([string]$Text)
    $status.Text = $Text
}

# Keep filesystem, Git, and Task Scheduler reads off the Windows Forms thread.
# Each operation has at most one active job and one coalesced follow-up request.
$script:dataJobs = @{}
$script:dataQueued = @{}
$script:pendingSnapshot = @()
$script:selectionGeneration = 0
$script:selectionJobGeneration = 0
$script:selectionOriginalModel = $null
$script:loadingSessions = $false
$repoHints = [System.Windows.Forms.ToolTip]::new()
$usageHints = [System.Windows.Forms.ToolTip]::new()
$actionHints = [System.Windows.Forms.ToolTip]::new()
$actionHints.SetToolTip($schedule, 'Creates one Windows Task Scheduler run. Your settings are rechecked when the task starts.')
$actionHints.SetToolTip($autoResumeCheck, 'Only retries after a confirmed Codex usage-limit failure; does not monitor other Codex terminals.')
$actionHints.SetToolTip($useReset, 'Uses the applicable exhausted quota reset time plus two minutes, when Codex reports one.')
$script:models = @()

function Start-DataRead {
    param([ValidateSet('sessions','pending','selection')][string]$Kind, $Session = $null)
    if ($script:dataJobs[$Kind]) { $script:dataQueued[$Kind] = $true; return }
    try {
        $sourceFolder = $PSScriptRoot
        $localAppDir = $appDir
        $job = Start-ThreadJob -ArgumentList @($sourceFolder,$localAppDir,$Kind,$Session) -ScriptBlock {
            param($Folder,$LocalAppDir,$Operation,$SelectedSession)
            $ErrorActionPreference = 'Stop'
            $appDir = $LocalAppDir
            $sessionIdPattern = '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            . (Join-Path $Folder 'CodexData.ps1')
            switch ($Operation) {
                'sessions'  { Get-RecentCliSessions }
                'pending'   { Get-UpcomingCodexTasks }
                'selection' {
                    $reportedCwd = Get-ReportedThreadDirectory ([string]$SelectedSession.Id) $Folder
                    [pscustomobject]@{ Id = [string]$SelectedSession.Id;
                        Model = Read-SessionModel $SelectedSession;
                        Found = Find-SessionRepository $SelectedSession $reportedCwd }
                }
            }
        }
        $script:dataJobs[$Kind] = $job
        if ($Kind -eq 'selection') { $script:selectionJobGeneration = $script:selectionGeneration }
    } catch { Update-Status "$Kind refresh failed to start: $($_.Exception.Message)" }
}

function Refresh-SessionList { Start-DataRead 'sessions' }
function Refresh-PendingList { Start-DataRead 'pending' }

function Request-SelectionLookup {
    if ($script:loadingSessions) { return }
    $script:selectionGeneration++
    $selected = $sessionBox.SelectedItem
    $selectedId = if ($selected) { [string]$selected.Id } else { '' }
    if ($selectedId -ne $script:repoSelectionSessionId) {
        $script:repoSelectionSessionId = $selectedId
        $repoBox.Clear()
        $repoHints.SetToolTip($repoBox, '')
    }
    if (-not $selected) { return }
    $script:selectionOriginalModel = Get-SelectedModel
    Update-Status 'Locating conversation repository in background...'
    Start-DataRead 'selection' $selected
}

function Apply-SessionList {
    param([object[]]$Sessions)
    $selectedId = if ($sessionBox.SelectedItem) { [string]$sessionBox.SelectedItem.Id } elseif ($script:preferredSessionId) { $script:preferredSessionId } else { $null }
    $script:loadingSessions = $true
    try {
        $sessionBox.BeginUpdate()
        $sessionBox.Items.Clear()
        foreach ($item in $Sessions) { [void]$sessionBox.Items.Add($item) }
        $sessionBox.EndUpdate()
        $chosen = $null
        if ($selectedId) { $chosen = @($sessionBox.Items | Where-Object { $_.Id -eq $selectedId }) | Select-Object -First 1 }
        if ($chosen) { $sessionBox.SelectedItem = $chosen }
        elseif ($sessionBox.Items.Count -gt 0) { $sessionBox.SelectedIndex = 0 }
    } finally { $script:loadingSessions = $false }
    if ($sessionBox.SelectedItem -and [string]$sessionBox.SelectedItem.Id -eq $script:preferredSessionId -and
        $script:savedDraft -and [string]::IsNullOrWhiteSpace($repoBox.Text) -and
        -not [string]::IsNullOrWhiteSpace([string]$script:savedDraft.repo)) {
        $script:repoSelectionSessionId = [string]$sessionBox.SelectedItem.Id
        $repoBox.Text = [string]$script:savedDraft.repo
    }
    if ($selectedId -and $chosen -and -not [string]::IsNullOrWhiteSpace($repoBox.Text)) {
        # Refreshing the conversation list must not discard a manually selected root.
        Update-Status "Conversations updated; repository selection retained."
    } else {
        Request-SelectionLookup
    }
}

function Apply-PendingList {
    param([object[]]$Items)
    $script:pendingSnapshot = @($Items)
    $grid.Rows.Clear()
    foreach ($item in $Items) {
        $path = ([string]$item.Repo).TrimEnd([char[]]@('/','\'))
        $project = if ($path -and $path -ne '-') { [System.IO.Path]::GetFileName($path) } else { 'Unknown project' }
        $session = if ([string]$item.Session -match '^[0-9a-fA-F]{8}-') { ([string]$item.Session).Substring(0,8) } else { '-' }
        $index = $grid.Rows.Add($item.When.ToString('MMM dd, h:mm tt'),'', $project,$item.Description,$session)
        $row = $grid.Rows[$index]
        $row.Tag = $item.Name
        $row.Cells[2].ToolTipText = [string]$item.Repo
        $row.Cells[3].ToolTipText = [string]$item.Description
        $row.Cells[4].ToolTipText = "Session: $($item.Session)`nTask: $($item.Name)"
    }
    $grid.ClearSelection()
    $cancelRun.Enabled = $false
    $pending.Text = "Upcoming runs ($($Items.Count))"
    $emptyRuns.Visible = $false
    Update-DashboardLayout
    Update-DashboardCountdowns
    if ($script:compactToggle.Checked -and (Get-DashboardUsageModel) -ne [string]$script:usageRequestedModel) { Request-UsageRefresh }
}

$dataPoll = New-Object System.Windows.Forms.Timer
$dataPoll.Interval = 250
$dataPoll.Add_Tick({
    foreach ($kind in @('sessions','pending','selection')) {
        $job = $script:dataJobs[$kind]
        if (-not $job -or $job.State -notin @('Completed','Failed','Stopped')) { continue }
        $script:dataJobs.Remove($kind)
        try {
            $result = @(Receive-Job -Job $job -ErrorAction Stop)
            switch ($kind) {
                'sessions' { Apply-SessionList $result }
                'pending' { Apply-PendingList $result }
                'selection' {
                    if ($script:selectionJobGeneration -ne $script:selectionGeneration) { break }
                    $info = $result | Select-Object -First 1
                    if (-not $info -or -not $sessionBox.SelectedItem -or $info.Id -ne $sessionBox.SelectedItem.Id) { break }
                    if ($info.Model -and (Get-SelectedModel) -eq $script:selectionOriginalModel -and
                        -not ($script:startupSavedModelId -and $script:startupSavedSessionId -eq [string]$sessionBox.SelectedItem.Id)) {
                        $script:preferredSessionModel = [string]$info.Model
                        $chosen = @($modelBox.Items | Where-Object { $_.Id -eq $info.Model }) | Select-Object -First 1
                        if ($chosen) { $modelBox.SelectedItem = $chosen; Select-AvailableEfforts }
                    }
                    if ($info.Found -and $info.Found.Root) {
                        # A user-entered root takes precedence over a late asynchronous lookup.
                        if (-not [string]::IsNullOrWhiteSpace($repoBox.Text)) { break }
                        $repoBox.Text = [string]$info.Found.Root
                        $otherRoots = @($info.Found.AlternativeRoots | Where-Object { $_ })
                        if ($otherRoots.Count -gt 0) {
                            $detail = "Codex reported: $($info.Found.Root)`nOther checkout(s): $($otherRoots -join '; ')`nChoose Browse to override."
                            $repoHints.SetToolTip($repoBox, $detail)
                            $repoHints.SetToolTip($status, $detail)
                            Update-Status "Codex: $($info.Found.Root) | Other: $($otherRoots -join '; ') (hover for details)"
                        } else {
                            $repoHints.SetToolTip($repoBox, "From $($info.Found.Source): $($info.Found.Root)")
                            Update-Status "Repository: $($info.Found.Root) ($($info.Found.Source))"
                        }
                    } elseif ($info.Found -and @($info.Found.Candidates).Count -gt 1) {
                        $detail = "Conflicting fallback checkouts: $(@($info.Found.Candidates) -join '; ')`nChoose Browse to select the active checkout."
                        $repoHints.SetToolTip($repoBox, $detail)
                        $repoHints.SetToolTip($status, $detail)
                        Update-Status "Conflicting roots: $(@($info.Found.Candidates) -join '; ') (hover for details)"
                    } else { Update-Status 'Repository could not be identified. Use Browse.' }
                }
            }
        } catch { Update-Status "$kind refresh failed: $($_.Exception.Message)" }
        finally { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
        if ($script:dataQueued[$kind]) {
            $script:dataQueued[$kind] = $false
            if ($kind -eq 'selection') {
                if ($sessionBox.SelectedItem) { Start-DataRead 'selection' $sessionBox.SelectedItem }
            } else { Start-DataRead $kind }
        }
    }
})

$script:usageSnapshot = $null
$script:usageRequestedModel = ''
$script:usageSnapshotRequestedModel = ''
$script:usageReadFailed = $false
$script:usageProcess = $null
$script:usageStarted = [datetime]::MinValue
$script:usageRefreshQueued = $false
$script:usageChecked = [datetime]::MinValue
$usagePoll = New-Object System.Windows.Forms.Timer
$usagePoll.Interval = 300

function Render-UsageCard {
    param($Card, $Window, [string]$FallbackTitle)
    if (-not $Window) {
        $Card.Title.Text = $FallbackTitle
        $Card.Remaining.Text = 'Not reported'
        Set-FlowingProgress $Card.Bar $null
        $Card.Reset.Text = 'No window supplied by Codex'
        return
    }
    $Card.Title.Text = [string]$Window.label
    if ($null -eq $Window.remainingPercent) {
        $Card.Remaining.Text = 'Unavailable'
        Set-FlowingProgress $Card.Bar $null
    } else {
        $remaining = [double]$Window.remainingPercent
        $Card.Remaining.Text = ('{0:0.#}% remaining' -f $remaining)
        Set-FlowingProgress $Card.Bar $remaining
    }
    $Card.Reset.Text = Format-ResetTime $Window.resetsAt
}

function Apply-UsageSnapshot {
    param($Snapshot)
    $script:usageSnapshot = $Snapshot
    $script:usageSnapshotRequestedModel = $script:usageRequestedModel
    $script:usageReadFailed = $false
    $script:usageChecked = Get-Date
    $script:models = @($Snapshot.models | Where-Object { $_ })
    $previous = if ($script:preferredModelId) { [string]$script:preferredModelId } elseif ($script:preferredSessionModel) { [string]$script:preferredSessionModel } else { Get-SelectedModel }
    $script:preferredSessionModel = $null # Do not override a subsequent manual model choice.
    $script:updatingModels = $true
    if ($script:models.Count -gt 0) {
        $modelBox.BeginUpdate()
        $modelBox.Items.Clear()
        foreach ($m in $script:models) {
            [void]$modelBox.Items.Add([pscustomobject]@{ Id = $m.id; Display = $m.name; Efforts = $m.efforts; DefaultEffort = $m.defaultEffort })
        }
        $modelBox.EndUpdate()
        $selected = @($script:models | Where-Object { $_.id -eq $previous }) | Select-Object -First 1
        if (-not $selected -and -not $previous) { $selected = @($script:models | Where-Object { $_.isDefault }) | Select-Object -First 1 }
        if (-not $selected -and -not $previous) { $selected = @($script:models) | Select-Object -First 1 }
        if ($selected) {
            $found = $false
            foreach ($item in $modelBox.Items) { if ($item.Id -eq $selected.id) { $modelBox.SelectedItem = $item; $found = $true; break } }
            if (-not $found) { $modelBox.SelectedIndex = -1 }
        }
        Select-AvailableEfforts
        if ($selected) {
            $script:preferredModelId = '' # Later catalog refresh preserves the live selection.
            $script:preferredEffort = ''
        }
    }
    $script:updatingModels = $false
    $windows = @($Snapshot.windows | Where-Object { $null -ne $_ })
    Render-UsageCard $usageCards[0] $(if ($windows.Count -ge 1) { $windows[0] } else { $null }) 'Primary window'
    Render-UsageCard $usageCards[1] $(if ($windows.Count -ge 2) { $windows[1] } else { $null }) 'Secondary window'
    $availability = switch ([string]$Snapshot.ordinaryUsageAllowed) {
        'True' { 'Usage allowed' }
        'False' { 'Usage restricted' }
        default { 'Availability not reported' }
    }
    $permission = "Model $($Snapshot.model) | Quota $($Snapshot.bucketId) | $availability"
    if ($Snapshot.limitReachedType) { $permission += "; limit: $($Snapshot.limitReachedType)" }
    $stateLabel = switch ([string]$Snapshot.ordinaryUsageAllowed) {
        'True' { 'Usage available' }
        'False' { 'Usage restricted' }
        default { 'Availability not reported' }
    }
    $usageNotice.Text = "$stateLabel  ·  Updated $($script:usageChecked.ToString('h:mm tt'))  ·  Refreshes every 60 seconds"
    if ($Snapshot.recommendationKind -eq 'next-window') {
        $usageNotice.Text += '  ·  Next reset is informational'
    }
    $usageHints.SetToolTip($usageNotice, $permission)
    $useReset.Enabled = $false
    if ($Snapshot.recommendationKind -eq 'exhausted-window' -and $Snapshot.recommendedResetAt) {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$Snapshot.recommendedResetAt).LocalDateTime
        $useReset.Enabled = ($reset.AddMinutes(2) -gt (Get-Date))
    }
    Update-DashboardLayout
}

function Request-UsageRefresh {
    if ($script:usageProcess) {
        $script:usageRefreshQueued = $true
        return
    }
    try {
        $script:usageProcess = Start-UsageRead
        $script:usageStarted = Get-Date
        $usageNotice.Text = 'Refreshing Codex usage...'
        $refreshUsage.Enabled = $false
        $usagePoll.Start()
    } catch {
        $usageNotice.Text = 'Usage refresh failed; try again.'
        $usageHints.SetToolTip($usageNotice, $_.Exception.Message)
        $script:usageReadFailed = $true
        $refreshUsage.Enabled = $true
        $useReset.Enabled = $false
        Update-DashboardLayout
    }
}

$usagePoll.Add_Tick({
    if (-not $script:usageProcess) { $usagePoll.Stop(); return }
    $process = $script:usageProcess
    if (-not $process.HasExited -and ((Get-Date) - $script:usageStarted).TotalSeconds -lt 22) { return }
    $usagePoll.Stop()
    $script:usageProcess = $null
    $refreshUsage.Enabled = $true
    try {
        if (-not $process.HasExited) {
            $process.Kill($true)
            throw 'Codex usage query timed out.'
        }
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $lines = @($output -split '[\r\n]+' | Where-Object { $_ })
        if ($lines.Count -eq 0) { throw "No Codex usage response. $errorOutput" }
        $snapshot = $lines[-1] | ConvertFrom-Json -ErrorAction Stop
        if (-not $snapshot.ok) { throw [string]$snapshot.error }
        Apply-UsageSnapshot $snapshot
    } catch {
        $usageNotice.Text = 'Usage refresh failed; last displayed values may be stale.'
        $usageHints.SetToolTip($usageNotice, $_.Exception.Message)
        $script:usageReadFailed = $true
        Update-DashboardLayout
        $useReset.Enabled = $false
        $schedule.Enabled = $false # Cannot verify current model/effort without the catalog.
    } finally {
        $process.Dispose()
        if ($script:usageRefreshQueued) {
            $script:usageRefreshQueued = $false
            Request-UsageRefresh
        }
    }
})
$refreshUsage.Add_Click({ Request-UsageRefresh })

$useReset.Add_Click({
    if (-not $script:usageSnapshot -or -not $script:usageSnapshot.recommendedResetAt) { return }
    $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$script:usageSnapshot.recommendedResetAt).LocalDateTime
    $after = $reset.AddMinutes(2)
    $rounded = [datetime]::new($after.Year,$after.Month,$after.Day,$after.Hour,$after.Minute,0)
    if ($after -gt $rounded) { $rounded = $rounded.AddMinutes(1) }
    if ($rounded -le (Get-Date)) {
        [System.Windows.Forms.MessageBox]::Show('That reset time has passed. Refresh usage.','Reset expired') | Out-Null
        return
    }
    $whenBox.Value = $rounded
    Update-Status "Selected reset +2 minutes: $($rounded.ToString('MMM dd, h:mm tt')). Review access before scheduling."
})

# Persist edited fields independently of scheduling. Debounce typing to avoid disk writes per keystroke.
$script:settingsTimer = New-Object System.Windows.Forms.Timer
$script:settingsTimer.Interval = 650
function Save-CurrentFormState {
    if (-not $script:settingsReady) { return }
    $sessionId = if ($sessionBox.SelectedItem) { [string]$sessionBox.SelectedItem.Id } else { $script:preferredSessionId }
    $model = Get-SelectedModel
    if (-not $model) { $model = $script:preferredModelId }
    $effort = if ($effortBox.SelectedItem) { [string]$effortBox.SelectedItem } else { $script:preferredEffort }
    $access = switch ($accessBox.SelectedIndex) { 1 { 'yolo' } 2 { 'read-only' } default { 'workspace-write' } }
    $savedRoot = [string]$repoBox.Text
    if (-not $sessionBox.SelectedItem -and -not $savedRoot -and $script:savedDraft) { $savedRoot = [string]$script:savedDraft.repo }
    $draft = [pscustomobject]@{
        sessionId = $sessionId
        repo = $savedRoot
        model = $model
        effort = $effort
        access = $access
        message = [string]$messageBox.Text
        autoResume = [bool]$autoResumeCheck.Checked
        runAt = $whenBox.Value.ToString('yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
    }
    Write-CodexUiSettings $appDir ([pscustomobject]@{ version = 1; lastAccess = $access; compactMode = [bool]$script:compactToggle.Checked; draft = $draft })
    $script:savedDraft = $draft
    $script:preferredSessionId = $sessionId
}
function Queue-FormStateSave {
    if (-not $script:settingsReady -or $script:loadingSessions -or $script:updatingModels) { return }
    $script:settingsTimer.Stop()
    $script:settingsTimer.Start()
}
$script:settingsTimer.Add_Tick({
    $script:settingsTimer.Stop()
    try { Save-CurrentFormState } catch { Update-Status "Settings were not saved: $($_.Exception.Message)" }
})
$repoBox.Add_TextChanged({ Queue-FormStateSave })
$whenBox.Add_ValueChanged({ Queue-FormStateSave })
$accessBox.Add_SelectedIndexChanged({ Queue-FormStateSave })
$effortBox.Add_SelectedIndexChanged({
    if (-not $script:updatingModels) {
        $script:preferredEffort = [string]$effortBox.SelectedItem
        Queue-FormStateSave
    }
})
$messageBox.Add_TextChanged({ Queue-FormStateSave })
$autoResumeCheck.Add_CheckedChanged({ Queue-FormStateSave })

$modelBox.Add_SelectedIndexChanged({
    if (-not $script:updatingModels) { $script:preferredModelId = Get-SelectedModel }
    Select-AvailableEfforts
    if (-not $script:updatingModels) {
        $useReset.Enabled = $false
        Request-UsageRefresh
        Queue-FormStateSave
    }
})
$sessionBox.Add_SelectedIndexChanged({
    if (-not $script:loadingSessions) { $script:preferredSessionId = if ($sessionBox.SelectedItem) { [string]$sessionBox.SelectedItem.Id } else { '' } }
    Request-SelectionLookup
    Queue-FormStateSave
})
$refreshSessions.Add_Click({ try { Refresh-SessionList } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Sessions error') | Out-Null } })
$browse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the Git repository root'
    if (Test-Path -LiteralPath $repoBox.Text -PathType Container) { $dialog.SelectedPath = $repoBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $root = Get-RepositoryRoot $dialog.SelectedPath
        if ($root) { $script:selectionGeneration++; $script:dataQueued['selection'] = $false; $repoBox.Text = $root }
        else { [System.Windows.Forms.MessageBox]::Show('Select a folder inside a Git repository.','Invalid folder') | Out-Null }
    }
    $dialog.Dispose()
})
$refreshRuns.Add_Click({ try { Refresh-PendingList } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Task Scheduler error') | Out-Null } })
$cancelRun.Add_Click({
    if ($grid.SelectedRows.Count -ne 1) { [System.Windows.Forms.MessageBox]::Show('Select an upcoming task first.','No selection') | Out-Null; return }
    $name = [string]$grid.SelectedRows[0].Tag
    if ([System.Windows.Forms.MessageBox]::Show("Disable the one-time task '$name'?",'Cancel scheduled run','YesNo','Question') -ne 'Yes') { return }
    try {
        Disable-ScheduledTask -TaskName $name -ErrorAction Stop | Out-Null
        Refresh-PendingList
        Request-UsageRefresh
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Cancellation failed') | Out-Null }
})
$openFolder.Add_Click({
    [void](New-Item -Path $appDir -ItemType Directory -Force)
    Start-Process explorer.exe -ArgumentList ('"' + $appDir + '"')
})

$schedule.Add_Click({
    try {
        if (-not $sessionBox.SelectedItem) { throw 'Select a saved CLI conversation.' }
        $sessionId = [string]$sessionBox.SelectedItem.Id
        if ($sessionId -notmatch $sessionIdPattern) { throw 'Selected session ID is invalid.' }
        $root = Get-RepositoryRoot $repoBox.Text.Trim().Trim('"')
        if (-not $root) { throw 'Select an existing Git repository.' }
        $branch = Get-RepositoryBranch $root
        # The control displays minutes, but can retain invisible seconds/ticks.
        # Task Scheduler serializes StartBoundary at second precision. Compare displayed minutes.
        $picked = $whenBox.Value
        $when = [datetime]::new($picked.Year,$picked.Month,$picked.Day,$picked.Hour,$picked.Minute,0)
        if ($when -lt (Get-Date).AddSeconds(30)) { throw 'Choose a future time (at least 30 seconds ahead).' }
        $message = $messageBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($message)) { throw 'Enter the instruction to send to Codex.' }
        $access = switch ($accessBox.SelectedIndex) { 0 { 'workspace-write' } 1 { 'yolo' } 2 { 'read-only' } default { throw 'Choose an access mode.' } }
        if ($access -eq 'yolo') {
            $confirmation = [System.Windows.Forms.MessageBox]::Show('Full access (YOLO) allows unattended commands with NO sandbox or approval prompts, including changes outside this repository. Schedule anyway?','Unrestricted access','YesNo','Warning')
            if ($confirmation -ne 'Yes') { return }
        }
        $model = Get-SelectedModel
        if ($model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$') { throw 'Select a valid Codex model.' }
        $effort = [string]$effortBox.SelectedItem
        if ($effort -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$') { throw 'Select a valid reasoning effort.' }
        Assert-ModelEffortSupported $script:models $model $effort
        # A GUI catalog snapshot can age before the scheduled task starts;
        # the runner independently revalidates the model and effort.
        $overlaps = @($script:pendingSnapshot | Where-Object { $_.Repo -ne '-' -and $_.Repo.TrimEnd([char[]]@('/','\')) -ieq $root.TrimEnd([char[]]@('/','\')) })
        if ($overlaps.Count -gt 0) {
            $answer = [System.Windows.Forms.MessageBox]::Show("There are already $($overlaps.Count) upcoming task(s) targeting this repository. Creating another may cause concurrent work if times overlap. Continue?",'Existing scheduled work','YesNo','Warning')
            if ($answer -ne 'Yes') { return }
        }
        [void](New-Item -Path $appDir -ItemType Directory -Force)
        $installedScript = Join-Path $appDir 'CodexResumeScheduler.ps1'
        if ($script:appSourcePath -ine $installedScript) { Copy-Item -LiteralPath $script:appSourcePath -Destination $installedScript -Force }
        foreach ($helperFile in @('CodexUsage.js','CodexRetry.js','CodexData.ps1','CodexDashboard.ps1','CodexFlowingBar.ps1','CodexRunJob.vbs')) {
            $source = Join-Path $PSScriptRoot $helperFile
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "$helperFile missing from installation." }
            $destination = Join-Path $appDir $helperFile
            if ($source -ine $destination) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        }
        $name = 'CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
        $jobFilePath = Join-Path $appDir ($name + '.json')
        $log = Join-Path $appDir ($name + '.log')
        [pscustomobject]@{ sessionId = $sessionId; repo = $root; branch = $branch; model = $model; effort = $effort; access = $access; message = $message; autoResume = $autoResumeCheck.Checked; retryAttempt = 0; createdAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); accountId = $script:usageSnapshot.accountId; log = $log } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jobFilePath -Encoding utf8
        $installedRunner = Join-Path $appDir 'CodexRunJob.vbs'
        $runnerArgs = '//B //Nologo "' + $installedRunner + '" "' + $jobFilePath + '"'
        $action = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\wscript.exe') -Argument $runnerArgs -WorkingDirectory $root
        $trigger = New-ScheduledTaskTrigger -Once -At $when
        $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $name -Description "Codex session $sessionId ($branch)" -Action $action -Trigger $trigger -Principal $principal -Settings (New-ScheduledTaskSettingsSet -StartWhenAvailable) -ErrorAction Stop | Out-Null
        $saved = Get-ScheduledTask -TaskName $name -ErrorAction Stop
        # Compare the minute shown in the UI, rather than raw DateTime ticks or Kind.
        $actualTime = if ($saved.Triggers.Count -eq 1 -and $saved.Triggers[0].StartBoundary) { ([datetime]$saved.Triggers[0].StartBoundary).ToString('yyyy-MM-dd HH:mm') } else { '(missing)' }
        $expectedTime = $when.ToString('yyyy-MM-dd HH:mm')
        $issues = @()
        if ($saved.State -notin @('Ready','Running')) { $issues += "Task state: $($saved.State)" }
        if ($actualTime -ne $expectedTime) { $issues += "Scheduled time: $actualTime (expected $expectedTime)" }
        if ($saved.Actions.Count -ne 1 -or [string]$saved.Actions[0].Execute -ine (Join-Path $env:WINDIR 'System32\wscript.exe')) { $issues += 'Windows Script Host runner is not registered' }
        if ($saved.Actions.Count -ne 1 -or [string]$saved.Actions[0].Arguments -notmatch '(?i)^//B\s+//Nologo\s+"[^"]+CodexRunJob\.vbs"\s+"[^"]+\.json"$') { $issues += 'Runner job argument missing' }
        if ($saved.Principal.LogonType -ne 'Interactive') { $issues += "Logon type: $($saved.Principal.LogonType)" }
        if ($issues.Count -gt 0) { throw ("Task '$name' WAS registered, but these checks need attention: " + ($issues -join '; ')) }
        $script:settingsTimer.Stop()
        Save-CurrentFormState
        Refresh-PendingList
        Request-UsageRefresh
        Update-Status "Scheduled once for $($when.ToString('MMM dd, h:mm tt')): $name"
        [System.Windows.Forms.MessageBox]::Show("Scheduled $($when.ToString('MMM dd, yyyy h:mm tt')).`nSession: $sessionId`nBranch: $branch`nInstruction: $message",'Codex task scheduled') | Out-Null
    } catch {
        # A task may have been registered before a later check failed. Surface it,
        # rather than leaving an empty list that encourages duplicate schedules.
        $failureMessage = $_.Exception.Message
        try { Refresh-PendingList } catch { $failureMessage += "`nPending-list refresh: $($_.Exception.Message)" }
        [System.Windows.Forms.MessageBox]::Show($failureMessage,'Scheduling check failed') | Out-Null
    }
})

Initialize-Dashboard

$autoRefresh = New-Object System.Windows.Forms.Timer
$autoRefresh.Interval = 60000
$autoRefresh.Add_Tick({
    try { Refresh-PendingList } catch { Update-Status "Pending refresh failed: $($_.Exception.Message)" }
    Request-UsageRefresh
})
$form.Add_Shown({
    [void][CodexScheduler.NativeWindow]::ShowWindow($form.Handle, 5) # SW_SHOW
    $form.Activate()
    $script:settingsReady = $true
    Update-DashboardLayout
    $script:countdownTimer.Start()
    try { Refresh-SessionList; Refresh-PendingList } catch { Update-Status "Startup warning: $($_.Exception.Message)" }
    Request-UsageRefresh
    $autoRefresh.Start()
    $dataPoll.Start()
})
$form.Add_FormClosing({
    $script:settingsTimer.Stop()
    try { Save-CurrentFormState } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not save preferences: $($_.Exception.Message)", 'Settings save error') | Out-Null
    }
})
$form.Add_FormClosed({
    $script:countdownTimer.Stop()
    $autoRefresh.Stop()
    $usagePoll.Stop()
    $dataPoll.Stop()
    foreach ($job in @($script:dataJobs.Values)) {
        try { Stop-Job -Job $job -ErrorAction SilentlyContinue; Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { }
    }
    if ($script:usageProcess) {
        try { if (-not $script:usageProcess.HasExited) { $script:usageProcess.Kill($true) } } catch { }
        $script:usageProcess.Dispose()
        $script:usageProcess = $null
    }
})
[void]$form.ShowDialog()
$autoRefresh.Dispose()
$script:countdownTimer.Dispose()
$script:settingsTimer.Dispose()
$usagePoll.Dispose()
$dataPoll.Dispose()
$repoHints.Dispose()
$usageHints.Dispose()
$actionHints.Dispose()
$form.Dispose()
