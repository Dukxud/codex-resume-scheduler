# Exercise real GDI+ rendering on the Windows CI worker; not just source-string assertions.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexDashboard.ps1')
function Require($Condition, $Message) { if (-not $Condition) { throw $Message } }

$bitmap = [System.Drawing.Bitmap]::new(220,30)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
    $rect = [System.Drawing.RectangleF]::new(4,4,200,12)
    $graphics.Clear([System.Drawing.Color]::White)
    Draw-SchedulerProgress $graphics $rect 50 'quota'
    $quotaFill = $bitmap.GetPixel(25,10)
    $quotaTrack = $bitmap.GetPixel(185,10)
    Require ($quotaFill.G -gt $quotaFill.R) 'Quota bar must be green.'
    Require ($quotaFill.ToArgb() -ne $quotaTrack.ToArgb()) 'Quota fill and track must be visibly distinct.'

    $graphics.Clear([System.Drawing.Color]::White)
    Draw-SchedulerProgress $graphics $rect 50 'time'
    $timeFill = $bitmap.GetPixel(25,10)
    $timeTrack = $bitmap.GetPixel(185,10)
    Require ($timeFill.B -gt $timeFill.R) 'Countdown bar must be blue.'
    Require ($timeFill.ToArgb() -ne $timeTrack.ToArgb()) 'Time fill and track must be visibly distinct.'
    Require ($quotaFill.ToArgb() -ne $timeFill.ToArgb()) 'Quota and countdown bars must not share colors.'

    $graphics.Clear([System.Drawing.Color]::White)
    Draw-SchedulerProgress $graphics $rect $null 'time'
    Require ($bitmap.GetPixel(25,10).ToArgb() -ne $timeFill.ToArgb()) 'Legacy run must have no invented progress fill.'

    $graphics.Clear([System.Drawing.Color]::White)
    Draw-SchedulerProgress $graphics $rect 100 'quota'
    Require ($bitmap.GetPixel(185,10).G -gt $bitmap.GetPixel(185,10).R) 'A full bar must fill the entire width.'

    $parent = [System.Windows.Forms.Panel]::new()
    try {
        $parent.Size = [System.Drawing.Size]::new(240,50)
        $bar = New-SchedulerProgressBar $parent 4 4 200 12 'time'
        Set-SchedulerProgress $bar 45
        Require ($bar.Tag.Percent -eq 45) 'Live progress value must be retained for repaint.'
        Set-SchedulerProgress $bar $null
        Require ($null -eq $bar.Tag.Percent) 'Unknown progress must stay unfilled.'
    } finally { $parent.Dispose() }
    Write-Host 'Rounded GDI+ bars, color distinction, unknown-progress handling, and painting controls passed.'
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}
