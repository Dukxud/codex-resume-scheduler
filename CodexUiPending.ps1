# Codex-specific upcoming-task projection into WinForms.
function Apply-PendingList {
    param([object[]]$Items)
    $script:ui.Dashboard.pendingSnapshot = @($Items)
    $index=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in @($Items)){if($item.Name){$index[[string]$item.Name]=$item}}
    $script:ui.Dashboard.pendingIndex=$index
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
    if ($script:ui.Dashboard.compactToggle.Checked -and (Get-DashboardUsageModel) -ne [string]$script:ui.Usage.usageRequestedModel) { Request-UsageRefresh }
}
