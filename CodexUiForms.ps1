if (-not $IsWindows) { throw 'This application requires Windows and PowerShell 7.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module (Join-Path $PSScriptRoot 'components/WindowShell/WindowShell.psm1') -Force -ErrorAction Stop
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



# Legacy settings.json files contain only lastAccess. A draft is optional.
$script:ui.Preferences.uiSettings = Read-CodexUiSettings $appDir
$script:ui.Preferences.savedDraft = if ($script:ui.Preferences.uiSettings -and $script:ui.Preferences.uiSettings.draft) { $script:ui.Preferences.uiSettings.draft } else { $null }
$script:ui.Selection.preferredSessionId = if ($script:ui.Preferences.savedDraft) { [string]$script:ui.Preferences.savedDraft.sessionId } else { '' }
$script:ui.Selection.preferredModelId = if ($script:ui.Preferences.savedDraft) { [string]$script:ui.Preferences.savedDraft.model } else { '' }
$script:ui.Selection.preferredEffort = if ($script:ui.Preferences.savedDraft) { [string]$script:ui.Preferences.savedDraft.effort } else { '' }
$script:ui.Selection.startupSavedSessionId = $script:ui.Selection.preferredSessionId
$script:ui.Selection.startupSavedModelId = $script:ui.Selection.preferredModelId
$script:ui.Selection.repoSelectionSessionId = ''
$script:ui.Preferences.settingsReady = $false

function Get-SavedAccessPreference {
    if ($script:ui.Preferences.savedDraft -and $script:ui.Preferences.savedDraft.access -in @('workspace-write','yolo','read-only')) { return [string]$script:ui.Preferences.savedDraft.access }
    if ($script:ui.Preferences.uiSettings -and $script:ui.Preferences.uiSettings.lastAccess -in @('workspace-write','yolo','read-only')) { return [string]$script:ui.Preferences.uiSettings.lastAccess }
    return 'workspace-write'
}

$form = New-DesktopWindow -Title 'Codex Resume Scheduler v1.14.0' -Width 920 -Height 865 -MinimumWidth 940 -MinimumHeight 875
function Add-Label {
    param([string]$Text,[int]$X,[int]$Y,[int]$W=130)
    return Add-DesktopLabel -Parent $form -Text $Text -X $X -Y $Y -Width $W
}
function Add-Button {
    param([string]$Text,[int]$X,[int]$Y,[int]$W=110)
    return Add-DesktopButton -Parent $form -Text $Text -X $X -Y $Y -Width $W
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
if ($script:ui.Preferences.savedDraft) {
    $restoredTime = Get-RestoredRunTime ([string]$script:ui.Preferences.savedDraft.runAt) (Get-Date)
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
$script:ui.Preferences.lastAccessPreference = Get-SavedAccessPreference
$accessBox.SelectedIndex = switch ($script:ui.Preferences.lastAccessPreference) { 'yolo' { 1 } 'read-only' { 2 } default { 0 } }
$form.Controls.Add($accessBox)
[void](Add-Label 'Reasoning' 500 203 95)
$modelBox = New-Object System.Windows.Forms.ComboBox
$modelBox.Location = [System.Drawing.Point]::new(155,199)
$modelBox.Size = [System.Drawing.Size]::new(325,30)
$modelBox.DropDownStyle = 'DropDownList'
$modelBox.DisplayMember = 'Display'
$form.Controls.Add($modelBox)
$script:ui.Selection.models = @()
$script:ui.Selection.modelCatalogLoaded = $false

[void](Add-Label 'Instruction' 18 247)
$messageBox = New-Object System.Windows.Forms.TextBox
$messageBox.Location = [System.Drawing.Point]::new(155,243)
$messageBox.Size = [System.Drawing.Size]::new(743,30)
$messageBox.Text = if ($script:ui.Preferences.savedDraft -and $null -ne $script:ui.Preferences.savedDraft.message) { [string]$script:ui.Preferences.savedDraft.message } else { 'Resume.' }
$form.Controls.Add($messageBox)
$schedule = Add-Button 'Schedule once' 720 274 178
$schedule.Height = 31
$schedule.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
$schedule.Enabled = $false
$autoResumeCheck = New-Object System.Windows.Forms.CheckBox
$autoResumeCheck.Text = 'Retry if Codex hits a usage limit (max 4)'
$autoResumeCheck.Location = [System.Drawing.Point]::new(155,276)
$autoResumeCheck.Size = [System.Drawing.Size]::new(520,21)
$autoResumeCheck.Checked = if ($script:ui.Preferences.savedDraft -and $script:ui.Preferences.savedDraft.autoResume -is [bool]) { [bool]$script:ui.Preferences.savedDraft.autoResume } else { $true }
$form.Controls.Add($autoResumeCheck)

function Get-SelectedModel {
    if ($modelBox.SelectedItem -and $modelBox.SelectedItem.Id) { return [string]$modelBox.SelectedItem.Id }
    return ''
}
function Select-AvailableEfforts {
    $model = Get-SelectedModel
    $entry = @($script:ui.Selection.models | Where-Object { $_.id -ceq $model }) | Select-Object -First 1
    $prior = [string]$effortBox.SelectedItem
    $effortBox.Items.Clear()
    if ($entry) {
        foreach ($effort in @($entry.efforts | Where-Object { $_ -ne 'ultra' })) { [void]$effortBox.Items.Add([string]$effort) }
        if ($model -eq $script:ui.Selection.preferredModelId -and $effortBox.Items.Contains($script:ui.Selection.preferredEffort)) { $effortBox.SelectedItem = $script:ui.Selection.preferredEffort }
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
        $script:ui.Usage.usageRequestedModel = $chosen
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
. (Join-Path $PSScriptRoot 'CodexAeroBar.ps1')
. (Join-Path $PSScriptRoot 'CodexBarAppearance.ps1')
Initialize-AeroAppearance $script:ui.Preferences.uiSettings
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
    $bar = New-AeroProgressBar $card 12 44 400 17 'quota'
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
$script:ui.Selection.dataJobs = @{}
$script:ui.Selection.dataQueued = @{}
$script:ui.Dashboard.pendingSnapshot = @()
$script:ui.Selection.selectionGeneration = 0
$script:ui.Selection.selectionJobGeneration = 0
$script:ui.Selection.selectionOriginalModel = $null
$script:ui.Selection.loadingSessions = $false
$repoHints = [System.Windows.Forms.ToolTip]::new()
$usageHints = [System.Windows.Forms.ToolTip]::new()
$actionHints = [System.Windows.Forms.ToolTip]::new()
$actionHints.SetToolTip($schedule, 'Creates one Windows Task Scheduler run. Your settings are rechecked when the task starts.')
$actionHints.SetToolTip($autoResumeCheck, 'Only retries after a confirmed Codex usage-limit failure; does not monitor other Codex terminals.')
$actionHints.SetToolTip($useReset, 'Uses the applicable exhausted quota reset time plus two minutes, when Codex reports one.')
$script:ui.Selection.models = @()

