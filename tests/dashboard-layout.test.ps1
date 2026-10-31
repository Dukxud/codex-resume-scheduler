# Runtime Windows Forms smoke test: catch overlapped / hidden compact controls.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
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
    $refreshRuns = New-TestControl panel 18 774 154 31
    $cancelRun = New-TestControl panel 185 774 154 31
    $openFolder = New-TestControl panel 352 774 154 31
    $status = New-TestControl label 18 823 880 25
    $script:uiSettings = $null
    $script:pendingSnapshot = @()
    $script:usageSnapshot = $null
    $script:usageReadFailed = $false
    $script:usageRequestedModel = ''
    $script:usageSnapshotRequestedModel = ''
    # Child Visible is false until its parent Form is shown; show it for this smoke test.
    $form.Show()
    Initialize-Dashboard
    Update-DashboardLayout

    Require ($script:compactToggle.Visible) 'The compact toggle must be visible in full view.'
    Require ($script:compactToggle.Left -gt $heading.Right) 'The full-mode toggle must not overlap the heading.'
    Require (-not $subtitle.Visible) 'The retired subtitle must not overlap the switch.'
    Require ($script:compactToggle.Right -le $form.ClientSize.Width) 'The full-mode toggle must be inside the window.'
    Require ($script:compactToggle.Text -eq 'Compact mode: OFF') 'Full mode should clearly offer the compact switch.'

    $script:compactToggle.Checked = $true
    Require ($script:compactToggle.Visible) 'The compact switch must remain visible in compact mode.'
    Require ($script:compactToggle.Text -eq 'Compact mode: ON') 'Compact mode should clearly show its state.'
    Require ($script:compactToggle.Left -gt $heading.Right) 'The compact-mode switch must not overlap the heading.'
    Require ($script:compactToggle.Right -le $form.ClientSize.Width) 'Compact-mode switch must not be clipped.'
    Require (-not $script:compactRunPanel.Visible) 'An empty queue must not render a run placeholder.'

    $script:pendingSnapshot = @([pscustomobject]@{
        Model='test-model'; Name='pending-1'; Repo='C:\work\demo'; Description='test instruction'
        When=(Get-Date).AddHours(2); CreatedAt=$null
    })
    Update-DashboardLayout
    Require ($script:compactRunPanel.Visible) 'The upcoming-run card must appear when there is a run.'
    Require ($script:compactRunTrack.Visible) 'The blue countdown bar must remain visible.'
    $script:compactToggle.Checked = $false
    Require ($script:compactToggle.Visible) 'The switch must remain visible when returning to full mode.'
    Require ($grid.Visible) 'The full run list should be restored.'
    Write-Host 'Visible mode toggle, header clearance, empty queue, and switching passed.'
} finally {
    if ($script:countdownTimer) { $script:countdownTimer.Dispose() }
    $form.Dispose()
}
