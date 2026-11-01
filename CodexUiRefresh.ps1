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
        Set-AeroProgress $Card.Bar $null
        $Card.Reset.Text = 'No window supplied by Codex'
        return
    }
    $Card.Title.Text = [string]$Window.label
    if ($null -eq $Window.remainingPercent) {
        $Card.Remaining.Text = 'Unavailable'
        Set-AeroProgress $Card.Bar $null
    } else {
        $remaining = [double]$Window.remainingPercent
        $Card.Remaining.Text = ('{0:0.#}% remaining' -f $remaining)
        Set-AeroProgress $Card.Bar $remaining
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

