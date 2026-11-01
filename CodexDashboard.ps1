# Dashboard views. Approved Aero v3 bars use WebView2, with WPF fallback.

function Get-RunCountdownText {
    param([datetime]$When, [datetime]$Now)
    $seconds = [long][math]::Ceiling(($When - $Now).TotalSeconds)
    if ($seconds -le 0) { return 'Due now' }
    $days = [long][math]::Floor($seconds / 86400)
    $hours = [long][math]::Floor(($seconds % 86400) / 3600)
    $minutes = [long][math]::Floor(($seconds % 3600) / 60)
    $remainder = $seconds % 60
    if ($days) { return ('{0}d {1}h {2}m' -f $days,$hours,$minutes) }
    if ($hours) { return ('{0}h {1}m' -f $hours,$minutes) }
    if ($minutes) { return ('{0}m {1}s' -f $minutes,$remainder) }
    return ('{0}s' -f $remainder)
}

function Get-RunCountdownPercent {
    param([datetime]$When, $CreatedAt, [datetime]$Now)
    if ($null -eq $CreatedAt -or [string]$CreatedAt -notmatch '^\d{9,12}$') { return $null }
    try {
        $start = [DateTimeOffset]::FromUnixTimeSeconds([long]$CreatedAt).LocalDateTime
        $duration = ($When - $start).TotalSeconds
        if ($duration -le 0) { return $null }
        $elapsed = ($Now - $start).TotalSeconds
        return [int][math]::Round([math]::Clamp(100 * $elapsed / $duration, 0, 100))
    } catch { return $null }
}

function Get-DashboardUsageModel {
    if ($script:compactToggle -and $script:compactToggle.Checked -and $script:pendingSnapshot.Count -gt 0) {
        $nextModel = [string]$script:pendingSnapshot[0].Model
        if ($nextModel -match '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$') { return $nextModel }
    }
    return Get-SelectedModel
}

function New-DashboardLabel {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$Width, [int]$Height)
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X,$Y)
    $label.Size = [System.Drawing.Size]::new($Width,$Height)
    $label.AutoEllipsis = $true
    $Parent.Controls.Add($label)
    return $label
}

function Initialize-Dashboard {
    # Capture the old full-view controls before adding the compact-only controls.
    $shared = @($heading,$usageHeading,$usageNotice,$usageCards[0].Panel,$usageCards[1].Panel)
    $script:dashboardStandardOnly = @($form.Controls | Where-Object { $shared -notcontains $_ })
    $script:fullTitleFont = $heading.Font
    $script:compactTitleFont = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $script:countdownBlue = [System.Drawing.Color]::FromArgb(49,95,167)

    # A high-contrast, button-style toggle in a reserved header location.
    # The former small checkbox overlapped the subtitle and compact title.
    $script:compactToggle = [System.Windows.Forms.CheckBox]::new()
    $script:compactToggle.Appearance = [System.Windows.Forms.Appearance]::Button
    $script:compactToggle.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $script:compactToggle.FlatAppearance.BorderSize = 1
    $script:compactToggle.Font = [System.Drawing.Font]::new('Segoe UI',10,[System.Drawing.FontStyle]::Bold)
    $script:compactToggle.TextAlign = 'MiddleCenter'
    $script:compactToggle.Location = [System.Drawing.Point]::new(728,13)
    $script:compactToggle.Size = [System.Drawing.Size]::new(170,38)
    $script:compactToggle.AccessibleName = 'Toggle compact mode'
    $script:compactToggle.Checked = ($script:uiSettings -and $script:uiSettings.compactMode -eq $true)
    $form.Controls.Add($script:compactToggle)
    $script:compactToggle.BringToFront()

    # Appearance controls remain accessible in both standard and compact layouts.
    $script:appearanceButton = [System.Windows.Forms.Button]::new()
    $script:appearanceButton.Text = 'Appearance...'
    $script:appearanceButton.AccessibleName = 'Customize progress bar appearance'
    $script:appearanceButton.Size = [System.Drawing.Size]::new(140,32)
    $form.Controls.Add($script:appearanceButton)
    $script:appearanceButton.Add_Click({ Show-AeroAppearanceDialog $form })

    $script:compactRunHeading = New-DashboardLabel $form 'Next run' 18 61 425 26
    $script:compactRunHeading.Font = [System.Drawing.Font]::new('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
    $script:compactRunPanel = [System.Windows.Forms.Panel]::new()
    $script:compactRunPanel.Location = [System.Drawing.Point]::new(18,91)
    $script:compactRunPanel.Size = [System.Drawing.Size]::new(428,129)
    $script:compactRunPanel.BackColor = [System.Drawing.Color]::FromArgb(246,249,253)
    $script:compactRunPanel.BorderStyle = 'FixedSingle'
    $form.Controls.Add($script:compactRunPanel)

    $script:compactRunName = New-DashboardLabel $script:compactRunPanel '' 14 12 240 27
    $script:compactRunName.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $script:compactRunEta = New-DashboardLabel $script:compactRunPanel '' 251 12 160 27
    $script:compactRunEta.TextAlign = 'MiddleRight'
    $script:compactRunEta.Font = [System.Drawing.Font]::new('Segoe UI',12,[System.Drawing.FontStyle]::Bold)
    $script:compactRunEta.ForeColor = $script:countdownBlue
    $script:compactRunDetails = New-DashboardLabel $script:compactRunPanel '' 14 42 395 24
    $script:compactRunDetails.ForeColor = [System.Drawing.Color]::DimGray
    $script:compactRunDate = New-DashboardLabel $script:compactRunPanel '' 14 70 395 23
    $script:compactRunDate.ForeColor = [System.Drawing.Color]::DimGray

    $script:compactRunTrack = New-AeroProgressBar $script:compactRunPanel 14 101 396 17 'time'

    $script:compactUsageModel = New-DashboardLabel $form '' 232 240 210 26
    $script:compactUsageModel.ForeColor = [System.Drawing.Color]::DimGray
    $script:compactUsageModel.TextAlign = 'MiddleRight'
    $script:compactUsageStatus = New-DashboardLabel $form 'Reading usage limits...' 18 85 426 32
    $script:compactUsageStatus.ForeColor = [System.Drawing.Color]::DimGray

    # A separate, non-networked timer updates only displayed countdowns.
    $script:countdownTimer = [System.Windows.Forms.Timer]::new()
    $script:countdownTimer.Interval = 1000
    $script:countdownTimer.Add_Tick({ Update-DashboardCountdowns })

    # Standard view displays the time label in the native grid, with a real
    # WPF progress control below it. The WPF compositor animates without timers.
    $script:runBarHosts = [System.Collections.Generic.List[System.Windows.Forms.Control]]::new()
    $grid.Add_CellPainting({
        param($sender,$e)
        if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne 1) { return }
        $e.PaintBackground($e.CellBounds,$true)
        $cell = $sender.Rows[$e.RowIndex].Cells[1]
        $bounds = [System.Drawing.Rectangle]::new(
            $e.CellBounds.X+8,$e.CellBounds.Y+2,$e.CellBounds.Width-16,23)
        $color = if (($e.State -band [System.Windows.Forms.DataGridViewElementStates]::Selected) -ne 0) {
            $e.CellStyle.SelectionForeColor
        } else { $e.CellStyle.ForeColor }
        [System.Windows.Forms.TextRenderer]::DrawText(
            $e.Graphics,[string]$cell.Value,$sender.Font,$bounds,$color,
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter)
        $e.Paint($e.CellBounds,[System.Windows.Forms.DataGridViewPaintParts]::Border)
        $e.Handled = $true
    })
    $grid.Add_Scroll({ Sync-DashboardRunBars })
    $grid.Add_ColumnWidthChanged({ Sync-DashboardRunBars })
    $grid.Add_SizeChanged({ Sync-DashboardRunBars })
    $grid.Add_VisibleChanged({ Sync-DashboardRunBars })

    $script:compactToggle.Add_CheckedChanged({
        Update-DashboardLayout
        Queue-FormStateSave
        if ((Get-DashboardUsageModel) -ne [string]$script:usageRequestedModel) { Request-UsageRefresh }
    })
}

function Sync-DashboardRunBars {
    # The DataGridView remains responsible for text, scrolling, selection and
    # task identity. One WPF ElementHost is positioned in each visible time cell.
    if ($null -eq $script:runBarHosts -or $grid.Columns.Count -lt 2) { return }
    $count = $grid.Rows.Count
    while ($script:runBarHosts.Count -gt $count) {
        $last = $script:runBarHosts.Count - 1
        $obsolete = $script:runBarHosts[$last]
        $grid.Controls.Remove($obsolete)
        $obsolete.Dispose()
        $script:runBarHosts.RemoveAt($last)
    }
    while ($script:runBarHosts.Count -lt $count) {
        $new = New-AeroProgressBar $grid 0 0 100 15 'time'
        $script:runBarHosts.Add($new)
    }
    for ($i=0; $i -lt $count; $i++) {
        $bar = $script:runBarHosts[$i]
        $cell = $grid.GetCellDisplayRectangle(1,$i,$true)
        $inside = $grid.Visible -and $grid.Rows[$i].Visible -and
            $cell.Width -gt 32 -and $cell.Height -ge 22
        if (-not $inside) {
            $bar.Visible = $false
            continue
        }
        $bar.Location = [System.Drawing.Point]::new($cell.X + 8,$cell.Bottom - 19)
        $bar.Size = [System.Drawing.Size]::new($cell.Width - 16,15)
        $bar.Visible = $true
        Set-AeroProgress $bar $grid.Rows[$i].Cells[1].Tag
    }
}

function Update-DashboardCountdowns {
    $now = Get-Date
    foreach ($row in @($grid.Rows)) {
        $item = @($script:pendingSnapshot | Where-Object { $_.Name -eq [string]$row.Tag } | Select-Object -First 1)
        if ($item.Count -eq 0) { continue }
        $cell = $row.Cells[1]
        $label = Get-RunCountdownText $item[0].When $now
        $percent = Get-RunCountdownPercent $item[0].When $item[0].CreatedAt $now
        if ($cell.Value -cne $label -or $cell.Tag -ne $percent) {
            $cell.Value = $label
            $cell.Tag = $percent
            $grid.InvalidateCell($cell)
        }
    }
    Sync-DashboardRunBars
    if (-not $script:compactToggle.Checked -or $script:pendingSnapshot.Count -eq 0) { return }
    $next = $script:pendingSnapshot[0]
    $root = ([string]$next.Repo).TrimEnd([char[]]@('/','\'))
    $script:compactRunName.Text = if ($root -and $root -ne '-') { [IO.Path]::GetFileName($root) } else { 'Scheduled Codex run' }
    $script:compactRunEta.Text = Get-RunCountdownText $next.When $now
    $script:compactRunDetails.Text = [string]$next.Description
    $script:compactRunDate.Text = 'Scheduled ' + $next.When.ToString('ddd MMM d, h:mm tt')
    $percent = Get-RunCountdownPercent $next.When $next.CreatedAt $now
    Set-AeroProgress $script:compactRunTrack $percent
    $script:compactRunTrack.AccessibleName = $script:compactRunEta.Text + $(if ($null -ne $percent) { ", $percent% elapsed since scheduled" } else { ', schedule creation time unavailable' })
}

function Update-DashboardLayout {
    $compact = $script:compactToggle.Checked
    foreach ($control in $script:dashboardStandardOnly) { $control.Visible = -not $compact }
    $script:compactRunHeading.Visible = $compact -and $script:pendingSnapshot.Count -gt 0
    $script:compactRunPanel.Visible = $script:compactRunHeading.Visible
    $script:compactUsageModel.Visible = $false
    $script:compactUsageStatus.Visible = $false
    if (-not $compact) {
        $heading.Text = 'Schedule a continuation'
        $heading.Font = $script:fullTitleFont
        $heading.Width = 500
        $script:appearanceButton.Location = [System.Drawing.Point]::new(574,15)
        $script:compactToggle.Location = [System.Drawing.Point]::new(728,13)
        $script:compactToggle.Size = [System.Drawing.Size]::new(170,38)
        $script:compactToggle.Text = 'Compact mode: OFF'
        $script:compactToggle.BackColor = [System.Drawing.Color]::FromArgb(236,242,250)
        $script:compactToggle.ForeColor = [System.Drawing.Color]::FromArgb(40,76,128)
        $script:compactToggle.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(163,189,219)
        $subtitle.Visible = $false
        $usageHeading.Text = 'Usage remaining'
        $usageHeading.Location = [System.Drawing.Point]::new(18,322)
        $usageNotice.Visible = $true
        $usageNotice.Location = [System.Drawing.Point]::new(18,477)
        foreach ($i in 0..1) {
            $usageCards[$i].Panel.Visible = $true
            $usageCards[$i].Panel.Location = [System.Drawing.Point]::new($(if ($i -eq 0) { 18 } else { 470 }),358)
        }
        $hasRuns = $script:pendingSnapshot.Count -gt 0
        foreach ($control in @($separator2,$pending,$grid,$refreshRuns,$cancelRun)) { $control.Visible = $hasRuns }
        $openFolder.Location = [System.Drawing.Point]::new($(if ($hasRuns) { 352 } else { 18 }),$(if ($hasRuns) { 774 } else { 523 }))
        $status.Location = [System.Drawing.Point]::new(18,$(if ($hasRuns) { 823 } else { 575 }))
        $form.MinimumSize = [System.Drawing.Size]::new(940,$(if ($hasRuns) { 875 } else { 625 }))
        $form.ClientSize = [System.Drawing.Size]::new(920,$(if ($hasRuns) { 865 } else { 615 }))
        Sync-DashboardRunBars
        return
    }

    $heading.Text = 'Codex Scheduler'
    $heading.Font = $script:compactTitleFont
    $heading.Width = 270
    $script:compactToggle.Location = [System.Drawing.Point]::new(298,13)
    $script:compactToggle.Size = [System.Drawing.Size]::new(148,38)
    $script:compactToggle.Text = 'Compact mode: ON'
    $script:compactToggle.BackColor = [System.Drawing.Color]::FromArgb(49,95,167)
    $script:compactToggle.ForeColor = [System.Drawing.Color]::White
    $script:compactToggle.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(36,73,130)
    $usageNotice.Visible = $false
    $top = if ($script:pendingSnapshot.Count -gt 0) { 246 } else { 65 }
    $visibleWindows = @()
    $targetModel = Get-DashboardUsageModel
    $currentSnapshot = $script:usageSnapshot -and (-not $targetModel -or $script:usageSnapshotRequestedModel -ceq $targetModel)
    if ($currentSnapshot -and -not $script:usageReadFailed) {
        $visibleWindows = @($script:usageSnapshot.windows | Where-Object { $null -ne $_ })
    }
    if ($visibleWindows.Count -eq 0) {
        $usageHeading.Visible = $false
        $script:compactUsageStatus.Text = if ($script:usageReadFailed -or $currentSnapshot) { 'Usage limits unavailable' } else { 'Reading usage limits...' }
        $script:compactUsageStatus.Location = [System.Drawing.Point]::new(18,$top)
        $script:compactUsageStatus.Visible = $true
        foreach ($card in $usageCards) { $card.Panel.Visible = $false }
        $height = $top + 52
    } else {
        $usageHeading.Text = 'Usage limits'
        $usageHeading.Location = [System.Drawing.Point]::new(18,$top)
        $usageHeading.Visible = $true
        $script:compactUsageModel.Location = [System.Drawing.Point]::new(225,$top)
        $script:compactUsageModel.Text = [string]$script:usageSnapshot.model
        $script:compactUsageModel.Visible = $true
        $cardTop = $top + 34
        foreach ($i in 0..1) {
            $visible = $i -lt $visibleWindows.Count
            $usageCards[$i].Panel.Visible = $visible
            if ($visible) {
                $usageCards[$i].Panel.Location = [System.Drawing.Point]::new(18,$cardTop)
                $cardTop += 117
            }
        }
        $height = $cardTop + 18
    }
    $form.MinimumSize = [System.Drawing.Size]::new(480,150)
    # Reserve space below the final card for appearance customization.
    $form.ClientSize = [System.Drawing.Size]::new(464,[math]::Max(166,$height+40))
    $script:appearanceButton.Location = [System.Drawing.Point]::new(306,$form.ClientSize.Height-37)
    $script:appearanceButton.Size = [System.Drawing.Size]::new(140,32)
    Update-DashboardCountdowns
    Sync-DashboardRunBars
}
