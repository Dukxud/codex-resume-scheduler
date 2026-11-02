# Codex-specific conversation-selection controller: no usage or task queries.
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

function Request-SelectionLookup {
    if ($script:ui.Selection.loadingSessions) { return }
    $script:ui.Selection.selectionGeneration++
    $selected = $sessionBox.SelectedItem
    $selectedId = if ($selected) { [string]$selected.Id } else { '' }
    if ($selectedId -ne $script:ui.Selection.repoSelectionSessionId) {
        $script:ui.Selection.repoSelectionSessionId = $selectedId
        $repoBox.Clear()
        $repoHints.SetToolTip($repoBox, '')
    }
    if (-not $selected) { return }
    $script:ui.Selection.selectionOriginalModel = Get-SelectedModel
    Update-Status 'Locating conversation repository in background...'
    Start-DataRead 'selection' $selected
}

function Apply-SessionList {
    param([object[]]$Sessions)
    $selectedId = if ($sessionBox.SelectedItem) { [string]$sessionBox.SelectedItem.Id } elseif ($script:ui.Selection.preferredSessionId) { $script:ui.Selection.preferredSessionId } else { $null }
    $script:ui.Selection.loadingSessions = $true
    try {
        $sessionBox.BeginUpdate()
        $sessionBox.Items.Clear()
        foreach ($item in $Sessions) { [void]$sessionBox.Items.Add($item) }
        $sessionBox.EndUpdate()
        $chosen = $null
        if ($selectedId) { $chosen = @($sessionBox.Items | Where-Object { $_.Id -eq $selectedId }) | Select-Object -First 1 }
        if ($chosen) { $sessionBox.SelectedItem = $chosen }
        elseif ($sessionBox.Items.Count -gt 0) { $sessionBox.SelectedIndex = 0 }
    } finally { $script:ui.Selection.loadingSessions = $false }
    if ($sessionBox.SelectedItem -and [string]$sessionBox.SelectedItem.Id -eq $script:ui.Selection.preferredSessionId -and
        $script:ui.Preferences.savedDraft -and [string]::IsNullOrWhiteSpace($repoBox.Text) -and
        -not [string]::IsNullOrWhiteSpace([string]$script:ui.Preferences.savedDraft.repo)) {
        $script:ui.Selection.repoSelectionSessionId = [string]$sessionBox.SelectedItem.Id
        $repoBox.Text = [string]$script:ui.Preferences.savedDraft.repo
    }
    if ($selectedId -and $chosen -and -not [string]::IsNullOrWhiteSpace($repoBox.Text)) {
        # Refreshing the conversation list must not discard a manually selected root.
        Update-Status "Conversations updated; repository selection retained."
    } else {
        Request-SelectionLookup
    }
}
