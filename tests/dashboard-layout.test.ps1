# Runtime Windows Forms smoke test: catch overlapped / hidden compact controls.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexUiState.ps1')
$script:ui = New-CodexUiState
$env:CODEX_BAR_RENDERER = 'wpf'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexFlowingBar.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexAeroBar.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexDashboard.ps1')
function Require($Condition, $Message) { if (-not $Condition) { throw $Message } }
function New-TestControl {
    param([string]$Kind,[int]$X,[int]$Y,[int]$Width,[int]$Height)
    $control = switch ($Kind) {
        'label' { [System.Windows.Forms.Label]::new() }
        'grid'  { [System.Windows.Forms.DataGridView]::new() }
        default { [System.Windows.Forms.Panel]::new() }
    }
    $control.Location = [System.Drawing.Point]::new($X,$Y)
    $control.Size = [System.Drawing.Size]::new($Width,$Height)
    $form.Controls.Add($control)
    return $control
}
function Get-SelectedModel { 'test-model' }
function Queue-FormStateSave { }
function Request-UsageRefresh { }

$form = [System.Windows.Forms.Form]::new()
try {
    $form.ClientSize = [System.Drawing.Size]::new(920,865)
    $heading = New-TestControl label 18 14 500 34
    $heading.Font = [System.Drawing.Font]::new('Segoe UI',15,[System.Drawing.FontStyle]::Bold)
    $subtitle = New-TestControl label 544 22 355 25
    $usageHeading = New-TestControl label 18 322 280 30
    $usageNotice = New-TestControl label 18 477 880 25
    $first = New-TestControl panel 18 358 428 108
    $second = New-TestControl panel 470 358 428 108
    $usageCards = @([pscustomobject]@{Panel=$first},[pscustomobject]@{Panel=$second})
    $separator2 = New-TestControl panel 18 512 880 2
    $pending = New-TestControl label 18 527 400 30
    $grid = New-TestControl grid 18 566 880 195
    $grid.AllowUserToAddRows = $false
    $grid.RowTemplate.Height = 54
    [void]$grid.Columns.Add('When','When')
    [void]$grid.Columns.Add('Countdown','Time to run')
    [void]$grid.Columns.Add('Project','Project')
    $refreshRuns = New-TestControl panel 18 774 154 31
    $cancelRun = New-TestControl panel 185 774 154 31
    $openFolder = New-TestControl panel 352 774 154 31
    $recentResults = New-TestControl panel 520 774 158 31
    $status = New-TestControl label 18 823 880 25
    $script:ui.Preferences.uiSettings = $null
    $script:ui.Dashboard.pendingSnapshot = @()
    $script:ui.Usage.usageSnapshot = $null
    $script:ui.Usage.usageReadFailed = $false
    $script:ui.Usage.usageRequestedModel = ''
    $script:ui.Usage.usageSnapshotRequestedModel = ''
    # Child Visible is false until its parent Form is shown; show it for this smoke test.
    $form.Show()
    Initialize-Dashboard
    Update-DashboardLayout

    Require ($script:ui.Dashboard.compactToggle.Visible) 'The compact toggle must be visible in full view.'
    Require ($script:ui.Dashboard.compactToggle.Left -gt $heading.Right) 'The full-mode toggle must not overlap the heading.'
    Require (-not $subtitle.Visible) 'The retired subtitle must not overlap the switch.'
    Require ($script:ui.Dashboard.compactToggle.Right -le $form.ClientSize.Width) 'The full-mode toggle must be inside the window.'
    Require ($script:ui.Dashboard.compactToggle.Text -eq 'Compact mode: OFF') 'Full mode should clearly offer the compact switch.'

    $script:ui.Dashboard.compactToggle.Checked = $true
    Require ($script:ui.Dashboard.compactToggle.Visible) 'The compact switch must remain visible in compact mode.'
    Require ($script:ui.Dashboard.compactToggle.Text -eq 'Compact mode: ON') 'Compact mode should clearly show its state.'
    Require ($script:ui.Dashboard.compactToggle.Left -gt $heading.Right) 'The compact-mode switch must not overlap the heading.'
    Require ($script:ui.Dashboard.compactToggle.Right -le $form.ClientSize.Width) 'Compact-mode switch must not be clipped.'
    Require (-not $script:ui.Dashboard.compactRunPanel.Visible) 'An empty queue must not render a run placeholder.'

    $script:ui.Dashboard.pendingSnapshot = @([pscustomobject]@{
        Model='test-model'; Name='pending-1'; Repo='C:\work\demo'; Description='test instruction'
        When=(Get-Date).AddHours(2); CreatedAt=$null
    })
    Update-DashboardLayout
    Require ($script:ui.Dashboard.compactRunPanel.Visible) 'The upcoming-run card must appear when there is a run.'
    Require ($script:ui.Dashboard.compactRunTrack.Visible) 'The blue countdown bar must remain visible.'
    $script:ui.Dashboard.compactToggle.Checked = $false
    Require ($script:ui.Dashboard.compactToggle.Visible) 'The switch must remain visible when returning to full mode.'
    Require ($grid.Visible) 'The full run list should be restored.'
    Require ($recentResults.Visible) 'Run-history control must be available in normal mode.'
    [void]$grid.Rows.Add('Time','5m','Demo 1')
    [void]$grid.Rows.Add('Time','7m','Demo 2')
    [void]$grid.Rows.Add('Time','9m','Demo 3')
    $grid.Rows[0].Cells[1].Tag = 25
    $grid.Rows[1].Cells[1].Tag = 75
    $grid.Rows[2].Cells[1].Tag = $null
    Sync-DashboardRunBars
    Require ($script:ui.Dashboard.runBarHosts.Count -eq 3) 'Every queued run must have an independent WPF progress bar.'
    Require ($script:ui.Dashboard.runBarHosts[0].Child.Value -eq 25) 'First run shows its own percentage.'
    Require ($script:ui.Dashboard.runBarHosts[1].Child.Value -eq 75) 'Second run shows its own percentage.'
    Require ($script:ui.Dashboard.runBarHosts[2].Child.Value -eq 0) 'Legacy run keeps an empty track.'
    Require ($script:ui.Dashboard.runBarHosts[0].Child -is [System.Windows.Controls.ProgressBar]) 'Runs must use real WPF controls.'
    # A queue of hundreds of tasks must NOT spawn hundreds of WebView2 browsers.
    foreach($index in 4..120){[void]$grid.Rows.Add('Time','2m',"Other $index")}
    Sync-DashboardRunBars
    Require ($script:ui.Dashboard.runBarHosts.Count -lt 10) 'Rendering hidden jobs created unbounded browser controls.'
    $grid.Rows.Clear()
    Sync-DashboardRunBars
    Require ($script:ui.Dashboard.runBarHosts.Count -eq 0) 'Empty queue must release all run bars and their WPF hosts.'
    Write-Host 'Visible switch, empty state, and per-run WPF bar lifecycle passed.'
} finally {
    if ($script:ui.Dashboard.countdownTimer) { $script:ui.Dashboard.countdownTimer.Dispose() }
    $form.Dispose()
}
