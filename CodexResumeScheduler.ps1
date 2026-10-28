# Codex Resume Scheduler — Windows PowerShell 7 / Windows Forms
# Single-file UI and scheduled-task runner. No external modules or services.
# v1.4.0: discover models/efforts, model-specific limits, bounded automatic resumption.
[CmdletBinding()]
param(
    [switch]$RunJob,
    [string]$JobFile
)

$ErrorActionPreference = 'Stop'
$appDir = Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
$sessionIdPattern = '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$script:appSourcePath = $PSCommandPath

function Get-RepositoryRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    try {
        $result = & git -C $Path rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $result) { return $null }
        return ([string]($result | Select-Object -First 1)).Trim()
    } catch { return $null }
}

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

function Schedule-LimitRetry {
    param($Job, [long]$ResetAt, [long]$RunAt, [string]$BucketId)
    $attempt = [int]$Job.retryAttempt + 1
    if ($attempt -gt 4) { Write-Host 'Automatic resume stopped: maximum four attempts reached.' -ForegroundColor Yellow; return }
    $when = [DateTimeOffset]::FromUnixTimeSeconds($RunAt).LocalDateTime
    $when = [datetime]::new($when.Year,$when.Month,$when.Day,$when.Hour,$when.Minute,0).AddMinutes(1)
    if ($when -le (Get-Date).AddSeconds(60)) { Write-Host 'Reset time is not safely in the future; no retry scheduled.' -ForegroundColor Yellow; return }
    $name = 'CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
    $jobFile = Join-Path $appDir ($name + '.json')
    $next = [pscustomobject]@{ sessionId=$Job.sessionId; repo=$Job.repo; branch=$Job.branch; model=$Job.model;
        effort=$Job.effort; access=$Job.access; message=$Job.message; autoResume=$true;
        accountId=$Job.accountId; retryAttempt=$attempt; previousResetAt=$ResetAt;
        log=(Join-Path $appDir ($name + '.log')) }
    $next | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jobFile -Encoding utf8
    # Use the same application copy that is executing the current job.
    $arguments = '-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "' + $script:appSourcePath + '" -RunJob -JobFile "' + $jobFile + '"'
    $action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'pwsh.exe') -Argument $arguments -WorkingDirectory $Job.repo
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
        Write-Host "Scheduled run failed: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
        Write-Host 'Run finished. This terminal stays open until you close it.' -ForegroundColor Cyan
    }
    return
}

if (-not $IsWindows) { throw 'This application requires Windows and PowerShell 7.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-RecentCliSessions {
    $sessionRoot = Join-Path $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }) 'sessions'
    $sessions = @()
    if (Test-Path -LiteralPath $sessionRoot -PathType Container) {
        $rollouts = @(Get-ChildItem -LiteralPath $sessionRoot -File -Recurse -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        foreach ($item in $rollouts) {
            try {
                $line = Get-Content -LiteralPath $item.FullName -TotalCount 1 -ErrorAction Stop
                $meta = ($line | ConvertFrom-Json).payload
                if ($meta.source -ne 'cli' -or $meta.id -notmatch $sessionIdPattern) { continue }
                if ($sessions | Where-Object Id -eq $meta.id) { continue }
                $name = if ($meta.cwd) { Split-Path -Leaf ([string]$meta.cwd) } else { 'CLI session' }
                $sessions += [pscustomobject]@{
                    Id = [string]$meta.id
                    Cwd = [string]$meta.cwd
                    File = [string]$item.FullName
                    Display = ('{0} | {1:MM/dd HH:mm} | {2}' -f $name,$item.LastWriteTime,$meta.id)
                }
                if ($sessions.Count -ge 30) { break }
            } catch { continue }
        }
    }
    return $sessions
}

# Repository candidates must be compared across the selected conversation.
# A valid startup repository is not necessarily the checkout with unfinished work.
# Ambiguous evidence must require an explicit Browse choice, never a guess.
function Find-SessionRepository {
    param($Session)
    if (-not $Session) { return $null }
    $candidates = [System.Collections.Generic.List[string]]::new()
    $direct = Get-RepositoryRoot ([string]$Session.Cwd)
    if ($direct) { $candidates.Add($direct) }

    # A prior schedule is evidence, not proof that it targeted the right checkout.
    if (Test-Path -LiteralPath $appDir -PathType Container) {
        foreach ($saved in @(Get-ChildItem -LiteralPath $appDir -Filter 'CodexResume-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 5)) {
            try {
                $job = Get-Content -LiteralPath $saved.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                if ([string]$job.sessionId -ne [string]$Session.Id) { continue }
                $root = Get-RepositoryRoot ([string]$job.repo)
                if ($root -and $root.TrimEnd([char[]]@('/','\')) -ieq ([string]$job.repo).TrimEnd([char[]]@('/','\'))) {
                    $candidates.Add($root)
                }
            } catch { continue }
        }
    }

    # Use only structured cwd/workdir fields belonging to this session.
    # CLI sessions can move from their starting repository to an isolated worktree.
    if (Test-Path -LiteralPath $Session.File -PathType Leaf) {
        $contexts = [System.Collections.Generic.List[string]]::new()
        $toolDirs = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($line in @(Get-Content -LiteralPath $Session.File -Tail 800 -ErrorAction Stop)) {
                if ($line -notmatch '"(?:cwd|workdir|arguments)"') { continue }
                try {
                    $record = $line | ConvertFrom-Json -ErrorAction Stop
                    if ($record.type -eq 'turn_context' -and -not [string]::IsNullOrWhiteSpace([string]$record.payload.cwd)) {
                        $contexts.Add([string]$record.payload.cwd)
                    } elseif ($record.type -eq 'response_item' -and $record.payload.type -eq 'function_call' -and $record.payload.arguments) {
                        $arguments = $record.payload.arguments | ConvertFrom-Json -ErrorAction Stop
                        if ($arguments.workdir -is [string] -and $arguments.workdir) { $toolDirs.Add([string]$arguments.workdir) }
                    }
                } catch { continue }
            }
            foreach ($directory in @($contexts.ToArray() | Select-Object -Last 8) + @($toolDirs.ToArray() | Select-Object -Last 12)) {
                $root = Get-RepositoryRoot $directory
                if ($root) { $candidates.Add($root) }
            }
        } catch {
            # Preserve other evidence, but never infer a root from malformed rollout text.
        }
    }

    $roots = @($candidates.ToArray() | Sort-Object -Unique)
    if ($roots.Count -eq 1) { return [pscustomobject]@{ Root = $roots[0]; Source = 'consistent session repository evidence'; Candidates = $roots } }
    if ($roots.Count -gt 1) { return [pscustomobject]@{ Root = $null; Source = 'conflicting worktrees'; Candidates = $roots } }
    return $null
}
function Get-UpcomingCodexTasks {
    $items = @()
    foreach ($task in @(Get-ScheduledTask -ErrorAction Stop)) {
        if ($task.TaskName -notmatch '^(CodexResume-|BP\d+-Codex-(?:Resume|Test)$)') { continue }
        if ($task.State -eq 'Disabled' -or $task.State -eq 'Running') { continue }
        $trig = @($task.Triggers | Where-Object { $_.StartBoundary }) | Select-Object -First 1
        if (-not $trig) { continue }
        try { $when = [datetime]$trig.StartBoundary } catch { continue }
        if ($when -le (Get-Date)) { continue }
        $name = [string]$task.TaskName
        $json = Join-Path $appDir ($name + '.json')
        $description = 'Existing scheduled task'
        $session = '-'
        $repo = '-'
        if (Test-Path -LiteralPath $json) {
            try {
                $job = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
                $description = "$($job.model) / $($job.effort) | $($job.access) | $($job.message)"
                $session = [string]$job.sessionId
                $repo = [string]$job.repo
            } catch { $description = 'Scheduled task (job data unreadable)' }
        } elseif ($name -match '^BP\d+-Codex-') {
            # Surface existing BPxx tasks without modifying their definitions.
            $repo = [string]$task.Actions[0].WorkingDirectory
            $match = [regex]::Match([string]$task.Actions[0].Arguments, '-File\s+"([^"]+)"')
            if ($match.Success -and (Test-Path -LiteralPath $match.Groups[1].Value -PathType Leaf)) {
                try {
                    $legacy = Get-Content -LiteralPath $match.Groups[1].Value -Raw
                    $sidMatch = [regex]::Match($legacy, 'resume\s+"([0-9a-fA-F-]{36})"')
                    if ($sidMatch.Success) { $session = $sidMatch.Groups[1].Value }
                    $effortMatch = [regex]::Match($legacy, 'model_reasoning_effort=(medium|high|xhigh)')
                    $effortName = if ($effortMatch.Success) { $effortMatch.Groups[1].Value } else { 'unspecified' }
                    $accessName = if ($legacy.Contains('--dangerously-bypass-approvals-and-sandbox')) { 'YOLO' } elseif ($legacy.Contains('--sandbox read-only')) { 'read-only' } else { 'other' }
                    $description = "$effortName | $accessName | existing BP task"
                } catch { }
            }
        }
        $items += [pscustomobject]@{ Name = $name; When = $when; Repo = $repo; Session = $session; Description = $description }
    }
    return ($items | Sort-Object When)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Codex Resume Scheduler v1.4'
$form.ClientSize = [System.Drawing.Size]::new(920,865)
$form.MinimumSize = [System.Drawing.Size]::new(940,875)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [System.Drawing.Color]::White
$form.Font = [System.Drawing.Font]::new('Segoe UI',10)

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

$heading = Add-Label 'Schedule Codex continuation' 18 14 500
$heading.Font = [System.Drawing.Font]::new('Segoe UI',15,[System.Drawing.FontStyle]::Bold)
$heading.Height = 34

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
$form.Controls.Add($whenBox)

[void](Add-Label 'Reasoning' 500 157 95)
$effortBox = New-Object System.Windows.Forms.ComboBox
$effortBox.Location = [System.Drawing.Point]::new(597,154)
$effortBox.Size = [System.Drawing.Size]::new(163,30)
$effortBox.DropDownStyle = 'DropDownList'
$effortBox.DropDownStyle = 'DropDown'
$effortBox.Text = 'high'
$form.Controls.Add($effortBox)

[void](Add-Label 'Access' 18 202)
$accessBox = New-Object System.Windows.Forms.ComboBox
$accessBox.Location = [System.Drawing.Point]::new(155,199)
$accessBox.Size = [System.Drawing.Size]::new(325,30)
$accessBox.DropDownStyle = 'DropDownList'
[void]$accessBox.Items.AddRange([object[]]@('Workspace write','Full access (YOLO)','Read-only test'))
$accessBox.SelectedIndex = 0
$form.Controls.Add($accessBox)
[void](Add-Label 'Model' 500 203 95)
$modelBox = New-Object System.Windows.Forms.ComboBox
$modelBox.Location = [System.Drawing.Point]::new(597,199)
$modelBox.Size = [System.Drawing.Size]::new(301,30)
$modelBox.DropDownStyle = 'DropDown'
$modelBox.DisplayMember = 'Display'
$form.Controls.Add($modelBox)
$script:models = @()
$script:modelCatalogLoaded = $false

[void](Add-Label 'Instruction' 18 247)
$messageBox = New-Object System.Windows.Forms.TextBox
$messageBox.Location = [System.Drawing.Point]::new(155,243)
$messageBox.Size = [System.Drawing.Size]::new(605,30)
$messageBox.Text = 'Resume.'
$form.Controls.Add($messageBox)
$schedule = Add-Button 'Schedule once' 773 240 125
$autoResumeCheck = New-Object System.Windows.Forms.CheckBox
$autoResumeCheck.Text = 'Auto-resume after usage resets (up to 4 attempts)'
$autoResumeCheck.Location = [System.Drawing.Point]::new(155,276)
$autoResumeCheck.Size = [System.Drawing.Size]::new(500,21)
$autoResumeCheck.Checked = $true
$form.Controls.Add($autoResumeCheck)

function Get-SelectedModel {
    if ($modelBox.SelectedItem -and $modelBox.SelectedItem.Id) { return [string]$modelBox.SelectedItem.Id }
    return $modelBox.Text.Trim()
}
function Select-AvailableEfforts {
    $model = Get-SelectedModel
    $entry = @($script:models | Where-Object { $_.id -eq $model }) | Select-Object -First 1
    $prior = $effortBox.Text
    $effortBox.Items.Clear()
    if ($entry) {
        foreach ($effort in $entry.efforts) { [void]$effortBox.Items.Add([string]$effort) }
        if ($entry.efforts -contains $prior) { $effortBox.Text = $prior }
        elseif ($entry.defaultEffort) { $effortBox.Text = $entry.defaultEffort }
        elseif ($entry.efforts.Count -gt 0) { $effortBox.Text = $entry.efforts[0] }
    } else { $effortBox.Text = $prior }
}
function Read-SessionModel {
    param($Session)
    if (-not $Session -or -not (Test-Path -LiteralPath $Session.File -PathType Leaf)) { return $null }
    try {
        foreach ($line in @(Get-Content -LiteralPath $Session.File -Tail 600) | Select-Object -Last 600) {
            if ($line -notmatch '"model"') { continue }
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($record.type -eq 'turn_context' -and $record.payload.model -is [string]) { $found = [string]$record.payload.model }
        }
        return $found
    } catch { return $null }
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
    $chosen = Get-SelectedModel
    if ($chosen) { [void]$start.ArgumentList.Add('--model'); [void]$start.ArgumentList.Add($chosen) }
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Could not start Codex usage reader.' }
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

$usageHeading = Add-Label 'Codex usage' 18 322 280
$usageHeading.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
$usageHeading.Height = 30
$refreshUsage = Add-Button 'Refresh now' 605 320 139
$useReset = Add-Button 'Use reset +2 min' 755 320 143
$useReset.Enabled = $false

function New-UsageCard {
    param([int]$X, [string]$InitialTitle)
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = [System.Drawing.Point]::new($X,358)
    $card.Size = [System.Drawing.Size]::new(428,108)
    $card.BackColor = [System.Drawing.Color]::FromArgb(245,247,250)
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
    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = [System.Drawing.Point]::new(12,45)
    $bar.Size = [System.Drawing.Size]::new(400,13)
    $bar.Minimum = 0
    $bar.Maximum = 100
    $bar.Value = 0
    $card.Controls.Add($bar)
    $reset = New-Object System.Windows.Forms.Label
    $reset.Location = [System.Drawing.Point]::new(12,72)
    $reset.Size = [System.Drawing.Size]::new(400,24)
    $reset.Text = 'Waiting for Codex usage...'
    $reset.ForeColor = [System.Drawing.Color]::DimGray
    $card.Controls.Add($reset)
    return [pscustomobject]@{ Title = $name; Remaining = $remaining; Bar = $bar; Reset = $reset }
}
$usageCards = @((New-UsageCard 18 'Primary window'), (New-UsageCard 470 'Secondary window'))
$usageNotice = Add-Label 'Loading account usage...' 18 477 880
$usageNotice.ForeColor = [System.Drawing.Color]::DimGray

$separator2 = New-Object System.Windows.Forms.Label
$separator2.BorderStyle = 'Fixed3D'
$separator2.Location = [System.Drawing.Point]::new(18,512)
$separator2.Size = [System.Drawing.Size]::new(880,2)
$form.Controls.Add($separator2)

$pending = Add-Label 'Pending scheduled runs' 18 527 400
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
[void]$grid.Columns.Add('Task','Task')
[void]$grid.Columns.Add('Repository','Repository')
[void]$grid.Columns.Add('Settings','Settings / instruction')
$grid.Columns[0].FillWeight = 125
$grid.Columns[1].FillWeight = 145
$grid.Columns[2].FillWeight = 230
$grid.Columns[3].FillWeight = 260
$form.Controls.Add($grid)

$refreshRuns = Add-Button 'Refresh pending' 18 774 154
$cancelRun = Add-Button 'Cancel selected' 185 774 154
$openFolder = Add-Button 'Open logs folder' 352 774 154
$status = Add-Label 'Ready. Runs occur once and require Windows to remain signed in and awake.' 18 823 860
$status.ForeColor = [System.Drawing.Color]::DimGray

function Update-Status {
    param([string]$Text)
    $status.Text = $Text
}

function Refresh-SessionList {
    $sessionBox.Items.Clear()
    $sessions = @(Get-RecentCliSessions)
    foreach ($item in $sessions) { [void]$sessionBox.Items.Add($item) }
    if ($sessionBox.Items.Count -gt 0) { $sessionBox.SelectedIndex = 0 }
    Update-Status "Found $($sessionBox.Items.Count) saved CLI conversations."
}

function Refresh-PendingList {
    $grid.Rows.Clear()
    $items = @(Get-UpcomingCodexTasks)
    foreach ($item in $items) {
        $index = $grid.Rows.Add($item.When.ToString('MMM dd, h:mm tt'),$item.Name,$item.Repo,$item.Description)
        $grid.Rows[$index].Tag = $item.Name
    }
    $grid.ClearSelection()
    Update-Status "$($items.Count) upcoming Codex task(s). One-time schedules only."
}

$script:usageSnapshot = $null
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
        $Card.Bar.Value = 0
        $Card.Reset.Text = 'No window supplied by Codex'
        return
    }
    $Card.Title.Text = [string]$Window.label
    if ($null -eq $Window.remainingPercent) {
        $Card.Remaining.Text = 'Unavailable'
        $Card.Bar.Value = 0
    } else {
        $remaining = [double]$Window.remainingPercent
        $Card.Remaining.Text = ('{0:0.#}% left' -f $remaining)
        $Card.Bar.Value = [int][math]::Round($remaining)
    }
    $Card.Reset.Text = Format-ResetTime $Window.resetsAt
}

function Apply-UsageSnapshot {
    param($Snapshot)
    $script:usageSnapshot = $Snapshot
    $script:usageChecked = Get-Date
    $script:models = @($Snapshot.models | Where-Object { $_ })
    $previous = Get-SelectedModel
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
        if ($selected) {
            $found = $false
            foreach ($item in $modelBox.Items) { if ($item.Id -eq $selected.id) { $modelBox.SelectedItem = $item; $found = $true; break } }
            if (-not $found) { $modelBox.Text = $previous }
        } elseif ($previous) { $modelBox.Text = $previous }
        Select-AvailableEfforts
    }
    $script:updatingModels = $false
    $windows = @($Snapshot.windows | Where-Object { $null -ne $_ })
    Render-UsageCard $usageCards[0] $(if ($windows.Count -ge 1) { $windows[0] } else { $null }) 'Primary window'
    Render-UsageCard $usageCards[1] $(if ($windows.Count -ge 2) { $windows[1] } else { $null }) 'Secondary window'
    $permission = 'Model ' + [string]$Snapshot.model + ' | Quota ' + [string]$Snapshot.bucketId + ' | ' + (switch ([string]$Snapshot.ordinaryUsageAllowed) {
        'True' { 'Usage allowed' }
        'False' { 'Usage restricted' }
        default { 'Availability not reported' }
    })
    if ($Snapshot.limitReachedType) { $permission += "; limit: $($Snapshot.limitReachedType)" }
    $usageNotice.Text = "$permission | updated $($script:usageChecked.ToString('h:mm tt')) | refreshes every minute"
    if ($Snapshot.recommendationKind -eq 'next-window') {
        $usageNotice.Text += ' | Next reset does not guarantee access.'
    }
    $useReset.Enabled = $false
    if ($Snapshot.recommendationKind -eq 'exhausted-window' -and $Snapshot.recommendedResetAt) {
        $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$Snapshot.recommendedResetAt).LocalDateTime
        $useReset.Enabled = ($reset.AddMinutes(2) -gt (Get-Date))
    }
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
        $usageNotice.Text = "Usage refresh failed: $($_.Exception.Message)"
        $refreshUsage.Enabled = $true
        $useReset.Enabled = $false
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
        $usageNotice.Text = "Usage refresh failed: $($_.Exception.Message)"
        $useReset.Enabled = $false
        # Retain the last known values rather than replace them with invented zeros.
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

$modelBox.Add_SelectedIndexChanged({
    Select-AvailableEfforts
    if (-not $script:updatingModels) {
        $useReset.Enabled = $false
        Request-UsageRefresh
    }
})
$sessionBox.Add_SelectedIndexChanged({
    $preferred = Read-SessionModel $sessionBox.SelectedItem
    if ($preferred) { $modelBox.Text = $preferred; Select-AvailableEfforts }
    if (-not $sessionBox.SelectedItem) { $repoBox.Clear(); return }
    $found = Find-SessionRepository $sessionBox.SelectedItem
    if ($found -and $found.Root) {
        $repoBox.Text = [string]$found.Root
        Update-Status "Repository auto-located from $($found.Source). Verify the active checkout before scheduling."
    } else {
        $repoBox.Clear()
        if ($found -and $found.Candidates.Count -gt 1) {
            Update-Status "Multiple Git checkouts detected in this conversation. Use Browse to select the checkout containing unfinished work."
        } else {
            Update-Status 'Repository not reliably identified from this conversation. Choose Browse.'
        }
    }
})
$refreshSessions.Add_Click({ try { Refresh-SessionList } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Sessions error') | Out-Null } })
$browse.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select the Git repository root'
    if (Test-Path -LiteralPath $repoBox.Text -PathType Container) { $dialog.SelectedPath = $repoBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $root = Get-RepositoryRoot $dialog.SelectedPath
        if ($root) { $repoBox.Text = $root }
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
        $effort = $effortBox.Text.Trim()
        if ($effort -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$') { throw 'Select a valid reasoning effort.' }
        $catalogEntry = @($script:models | Where-Object { $_.id -eq $model }) | Select-Object -First 1
        if ($catalogEntry -and $catalogEntry.efforts.Count -gt 0 -and $catalogEntry.efforts -notcontains $effort) { throw "Model '$model' does not advertise reasoning effort '$effort'." }
        $overlaps = @(Get-UpcomingCodexTasks | Where-Object { $_.Repo -ne '-' -and $_.Repo.TrimEnd([char[]]@('/','\')) -ieq $root.TrimEnd([char[]]@('/','\')) })
        if ($overlaps.Count -gt 0) {
            $answer = [System.Windows.Forms.MessageBox]::Show("There are already $($overlaps.Count) upcoming task(s) targeting this repository. Creating another may cause concurrent work if times overlap. Continue?",'Existing scheduled work','YesNo','Warning')
            if ($answer -ne 'Yes') { return }
        }
        [void](New-Item -Path $appDir -ItemType Directory -Force)
        $installedScript = Join-Path $appDir 'CodexResumeScheduler.ps1'
        if ($script:appSourcePath -ine $installedScript) { Copy-Item -LiteralPath $script:appSourcePath -Destination $installedScript -Force }
        foreach ($helperFile in @('CodexUsage.js','CodexRetry.js')) {
            $source = Join-Path $PSScriptRoot $helperFile
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "$helperFile missing from installation." }
            $destination = Join-Path $appDir $helperFile
            if ($source -ine $destination) { Copy-Item -LiteralPath $source -Destination $destination -Force }
        }
        $name = 'CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
        $jobFilePath = Join-Path $appDir ($name + '.json')
        $log = Join-Path $appDir ($name + '.log')
        [pscustomobject]@{ sessionId = $sessionId; repo = $root; branch = $branch; model = $model; effort = $effort; access = $access; message = $message; autoResume = $autoResumeCheck.Checked; retryAttempt = 0; accountId = $script:usageSnapshot.accountId; log = $log } |
            ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jobFilePath -Encoding utf8
        $runnerArgs = '-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "' + $installedScript + '" -RunJob -JobFile "' + $jobFilePath + '"'
        $action = New-ScheduledTaskAction -Execute (Join-Path $PSHOME 'pwsh.exe') -Argument $runnerArgs -WorkingDirectory $root
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
        if ($saved.Actions.Count -ne 1 -or $saved.Actions[0].Arguments -notmatch '(?i)(?:^|\s)-NoExit(?:\s|$)') { $issues += 'PowerShell -NoExit missing' }
        if ($saved.Actions.Count -ne 1 -or $saved.Actions[0].Arguments -notmatch '(?i)(?:^|\s)-ExecutionPolicy\s+Bypass(?:\s|$)') { $issues += 'PowerShell process execution-policy override missing' }
        if ($saved.Principal.LogonType -ne 'Interactive') { $issues += "Logon type: $($saved.Principal.LogonType)" }
        if ($issues.Count -gt 0) { throw ("Task '$name' WAS registered, but these checks need attention: " + ($issues -join '; ')) }
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

$autoRefresh = New-Object System.Windows.Forms.Timer
$autoRefresh.Interval = 60000
$autoRefresh.Add_Tick({
    try { Refresh-PendingList } catch { Update-Status "Pending refresh failed: $($_.Exception.Message)" }
    Request-UsageRefresh
})
$form.Add_Shown({
    try { Refresh-SessionList; Refresh-PendingList } catch { Update-Status "Startup warning: $($_.Exception.Message)" }
    Request-UsageRefresh
    $autoRefresh.Start()
})
$form.Add_FormClosed({
    $autoRefresh.Stop()
    $usagePoll.Stop()
    if ($script:usageProcess) {
        try { if (-not $script:usageProcess.HasExited) { $script:usageProcess.Kill($true) } } catch { }
        $script:usageProcess.Dispose()
        $script:usageProcess = $null
    }
})
[void]$form.ShowDialog()
$autoRefresh.Dispose()
$usagePoll.Dispose()
$form.Dispose()