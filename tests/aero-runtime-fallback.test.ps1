# Regression: browser renderer termination must leave a functional WPF bar.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexFlowingBar.ps1')
. (Join-Path $root 'CodexAeroBar.ps1')
. (Join-Path $root 'CodexDashboard.ps1')
. (Join-Path $root 'CodexUiState.ps1')
$script:ui = New-CodexUiState
function Require($condition,[string]$message){if(-not $condition){throw $message}}
Require (Test-AeroRenderer) "Aero prerequisite absent: $script:aeroError"
$form=[Windows.Forms.Form]::new()
$form.ClientSize=[Drawing.Size]::new(450,310)
try{
    $bar=New-AeroProgressBar $form 16 22 400 17 'quota'
    Require ($bar.GetType().Name -eq 'WebView2') 'Initial Aero bar not WebView2.'
    Set-AeroProgress $bar 62
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $bar.Tag.Failure='Simulated WebView2 renderer process exit'
    $bar.Tag.Ready=$false
    Ensure-AeroFallback $bar
    $fallbackHost=$bar.Tag.Fallback
    Require ($fallbackHost -is [Windows.Forms.Integration.ElementHost]) 'WPF recovery bar was not created.'
    Require (-not $bar.Visible -and $fallbackHost.Visible) 'Failed WebView must be hidden and WPF visible.'
    Require ([math]::Abs([double]$fallbackHost.Tag-62) -lt .001) 'Recovery lost last authoritative percentage.'
    Set-AeroProgress $bar 91
    Require ([math]::Abs([double]$fallbackHost.Tag-91) -lt .001) 'Further percentage updates failed after recovery.'
    Set-AeroProgress $bar $null
    Require ($null -eq $fallbackHost.Tag) 'Unknown percentage must remain unknown after recovery.'
    Ensure-AeroFallback $bar
    Require ([object]::ReferenceEquals($fallbackHost,$bar.Tag.Fallback)) 'Recovery created duplicate controls.'
    # Recovered bars must follow the real DataGridView layout and be destroyed
    # with their row; otherwise they remain stuck on screen after scrolling.
    $grid=[Windows.Forms.DataGridView]::new()
    $grid.Location=[Drawing.Point]::new(15,120)
    $grid.Size=[Drawing.Size]::new(400,160)
    $grid.AllowUserToAddRows=$false
    $grid.RowTemplate.Height=54
    [void]$grid.Columns.Add('When','When')
    [void]$grid.Columns.Add('Countdown','Time')
    $form.Controls.Add($grid)
    [void]$grid.Rows.Add('Next','10m')
    $script:ui.Dashboard.runBarHosts=[Collections.Generic.List[Windows.Forms.Control]]::new()
    $runBar=New-AeroProgressBar $grid 0 0 100 15 'time'
    $script:ui.Dashboard.runBarHosts.Add($runBar)
    $grid.Rows[0].Cells[1].Tag=45
    $runBar.Tag.Failure='Simulated failure in a grid cell'
    Ensure-AeroFallback $runBar
    Sync-DashboardRunBars
    $active=Get-AeroProgressSurface $runBar
    $cell=$grid.GetCellDisplayRectangle(1,0,$true)
    Require ($active.Left -eq ($cell.X+8) -and $active.Width -eq ($cell.Width-16)) 'Recovered bar did not follow the grid cell.'
    $grid.Columns[1].Width+=27
    Sync-DashboardRunBars
    $cell=$grid.GetCellDisplayRectangle(1,0,$true)
    Require ($active.Width -eq ($cell.Width-16)) 'Recovered bar did not resize with the cell.'
    $grid.Rows.Clear()
    Sync-DashboardRunBars
    Require ($runBar.IsDisposed -and $active.IsDisposed) 'Deleting the row must dispose both renderer and WPF fallback.'
    Write-Host 'WebView2 failure recovery, responsive cell positioning and lifecycle PASS.'
} finally {
    $form.Close();$form.Dispose()
    if($script:aeroHealthTimer){$script:aeroHealthTimer.Stop();$script:aeroHealthTimer.Dispose()}
}
