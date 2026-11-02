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

function Apply-SelectionResult {
    param([object[]]$Result)

    if ($script:ui.Selection.selectionJobGeneration -ne $script:ui.Selection.selectionGeneration) { return }
    $info = $Result | Select-Object -First 1
    if (-not $info -or -not $sessionBox.SelectedItem -or $info.Id -ne $sessionBox.SelectedItem.Id) { return }
    if ($info.Model -and (Get-SelectedModel) -eq $script:ui.Selection.selectionOriginalModel -and
        -not ($script:ui.Selection.startupSavedModelId -and $script:ui.Selection.startupSavedSessionId -eq [string]$sessionBox.SelectedItem.Id)) {
        $script:ui.Selection.preferredSessionModel = [string]$info.Model
        $chosen = @($modelBox.Items | Where-Object { $_.Id -eq $info.Model }) | Select-Object -First 1
        if ($chosen) { $modelBox.SelectedItem = $chosen; Select-AvailableEfforts }
    }
    if ($info.Found -and $info.Found.Root) {
        # A user-entered root takes precedence over a late asynchronous lookup.
        if (-not [string]::IsNullOrWhiteSpace($repoBox.Text)) { return }
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

function Apply-CodexModelCatalog {
    param([Parameter(Mandatory)]$Snapshot)
    $script:ui.Selection.models = @($Snapshot.models | Where-Object { $_ })
    $previous = if ($script:ui.Selection.preferredModelId) { [string]$script:ui.Selection.preferredModelId } elseif ($script:ui.Selection.preferredSessionModel) { [string]$script:ui.Selection.preferredSessionModel } else { Get-SelectedModel }
    $script:ui.Selection.preferredSessionModel = $null # Do not override a subsequent manual model choice.
    $script:ui.Selection.updatingModels = $true
    if ($script:ui.Selection.models.Count -gt 0) {
        $modelBox.BeginUpdate()
        $modelBox.Items.Clear()
        foreach ($m in $script:ui.Selection.models) {
            [void]$modelBox.Items.Add([pscustomobject]@{ Id = $m.id; Display = $m.name; Efforts = $m.efforts; DefaultEffort = $m.defaultEffort })
        }
        $modelBox.EndUpdate()
        $selected = @($script:ui.Selection.models | Where-Object { $_.id -eq $previous }) | Select-Object -First 1
        if (-not $selected -and -not $previous) { $selected = @($script:ui.Selection.models | Where-Object { $_.isDefault }) | Select-Object -First 1 }
        if (-not $selected -and -not $previous) { $selected = @($script:ui.Selection.models) | Select-Object -First 1 }
        if ($selected) {
            $found = $false
            foreach ($item in $modelBox.Items) { if ($item.Id -eq $selected.id) { $modelBox.SelectedItem = $item; $found = $true; break } }
            if (-not $found) { $modelBox.SelectedIndex = -1 }
        }
        Select-AvailableEfforts
        if ($selected) {
            $script:ui.Selection.preferredModelId = '' # Later catalog refresh preserves the live selection.
            $script:ui.Selection.preferredEffort = ''
        }
    }
    $script:ui.Selection.updatingModels = $false
}
