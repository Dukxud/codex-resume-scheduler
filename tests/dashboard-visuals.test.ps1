# Render the actual WPF controls: green and blue filled segments, pale tracks,
# and compositor-driven animation while percentages do not change.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexFlowingBar.ps1')
function Require($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }

function Get-RenderedPixels($progress) {
    $bmp = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(
        400,18,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($progress.Child)
    $bytes = [byte[]]::new(400*18*4)
    $bmp.CopyPixels($bytes,400*4,0)
    return ,$bytes
}
function Get-Pixel($pixels,[int]$x,[int]$y) {
    $offset = ($y * 400 + $x) * 4
    return [pscustomobject]@{ B=[int]$pixels[$offset];G=[int]$pixels[$offset+1];R=[int]$pixels[$offset+2] }
}
$form = [System.Windows.Forms.Form]::new()
$form.ClientSize = [System.Drawing.Size]::new(460,110)
try {
    $quota = New-FlowingProgressBar $form 10 10 400 18 'quota'
    $time = New-FlowingProgressBar $form 10 50 400 18 'time'
    Set-FlowingProgress $quota 60
    Set-FlowingProgress $time 60
    $form.Show()
    for ($i=0;$i -lt 12;$i++){[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 30}
    $q0 = Get-RenderedPixels $quota
    $t0 = Get-RenderedPixels $time
    $qFill = Get-Pixel $q0 48 10
    $tFill = Get-Pixel $t0 48 10
    $qTrack = Get-Pixel $q0 350 10
    $tTrack = Get-Pixel $t0 350 10
    Require ($qFill.G -gt $qFill.R) 'Usage bar must actually render green.'
    Require ($tFill.B -gt $tFill.R) 'Time bar must actually render blue.'
    Require ($qFill.R -lt $qTrack.R -or $qFill.G -gt $qTrack.G) 'Usage fill must look different from the unfilled track.'
    Require ($tFill.B -gt $tTrack.B) 'Time fill must look different from the unfilled track.'
    for ($i=0;$i -lt 16;$i++){[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 35}
    $q1 = Get-RenderedPixels $quota
    $t1 = Get-RenderedPixels $time
    # Pixel differences across the filled portion prove the shine moves on-screen,
    # rather than merely changing a hidden animation parameter.
    $qChanged = 0; $tChanged = 0
    for ($y=3; $y -lt 15; $y+=3) {
        for ($x=10; $x -lt 200; $x+=5) {
            $index = ($y*400+$x)*4
            if ([math]::Abs([int]$q1[$index+1]-[int]$q0[$index+1]) -gt 6) {$qChanged++}
            if ([math]::Abs([int]$t1[$index]-[int]$t0[$index]) -gt 6) {$tChanged++}
        }
    }
    Require ($qChanged -gt 3) "Usage shine not visibly moving ($qChanged changed pixels)."
    Require ($tChanged -gt 3) "Countdown shine not visibly moving ($tChanged changed pixels)."
    Require ($quota.Child.Value -eq 60 -and $time.Child.Value -eq 60) 'Animation must not alter real progress.'
    Write-Host "WPF compositor renders colored bars and moving shine: usage=$qChanged, time=$tChanged"
} finally { $form.Close();$form.Dispose() }
