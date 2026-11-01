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
    Write-CodexUiSettings $appDir ([pscustomobject]@{ version = 1; lastAccess = $access; compactMode = [bool]$script:compactToggle.Checked; barAppearance = $script:aeroAppearance; draft = $draft })
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
        Disable-OneTimeTask -Name $name
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
        if ($autoResumeCheck.Checked -and (-not $script:usageSnapshot -or
            [string]::IsNullOrWhiteSpace([string]$script:usageSnapshot.accountId))) {
            throw 'Automatic resume requires verified account identity. Refresh usage, or turn off Auto-resume for manual scheduling.'
        }
        # A GUI catalog snapshot can age before the scheduled task starts;
        # the runner independently revalidates the model and effort.
        $overlaps = @($script:pendingSnapshot | Where-Object { $_.Repo -ne '-' -and $_.Repo.TrimEnd([char[]]@('/','\')) -ieq $root.TrimEnd([char[]]@('/','\')) })
        if ($overlaps.Count -gt 0) {
            $answer = [System.Windows.Forms.MessageBox]::Show("There are already $($overlaps.Count) upcoming task(s) targeting this repository. Creating another may cause concurrent work if times overlap. Continue?",'Existing scheduled work','YesNo','Warning')
            if ($answer -ne 'Yes') { return }
        }
        [void](New-Item -Path $appDir -ItemType Directory -Force)
        # Copy a self-contained, content-addressed runtime once. Future schedules
        # never overwrite the files used by an already registered task.
        $runtime = Publish-ImmutableRuntime -SourceDirectory $PSScriptRoot -DestinationDirectory (Join-Path $appDir 'runtimes') -RelativeFiles (Get-CodexRuntimeFiles)
        $name = 'CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
        $jobFilePath = Join-Path $appDir ($name + '.json')
        $log = Join-Path $appDir ($name + '.log')
        [pscustomobject]@{
            sessionId=$sessionId; repo=$root; branch=$branch
            model=$model; effort=$effort; access=$access; message=$message
            autoResume=[bool]$autoResumeCheck.Checked; retryAttempt=0
            createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            accountId=$script:usageSnapshot.accountId
            runtimeFingerprint=$runtime.Fingerprint; log=$log
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jobFilePath -Encoding utf8
        $installedRunner = Join-Path $runtime.Directory 'CodexRunJob.vbs'
        $runnerArguments = Get-CodexTaskArguments $installedRunner $jobFilePath
        [void](Register-OneTimeTask -Name $name -At $when -Executable (Join-Path $env:WINDIR 'System32\wscript.exe') -Arguments $runnerArguments -WorkingDirectory $root -Description "Codex session $sessionId ($branch)")
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

