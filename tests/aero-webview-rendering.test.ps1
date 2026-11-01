# Test the actual owner-approved Aero v3 renderer hosted inside WinForms on Windows.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexFlowingBar.ps1')
. (Join-Path $root 'CodexAeroBar.ps1')

function Require($ok,[string]$what) { if (-not $ok) { throw $what } }
function PumpUntil([scriptblock]$condition,[int]$seconds=25) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while (-not (& $condition)) {
        if ((Get-Date) -gt $deadline) { throw "Timed out awaiting WebView2 rendering: $script:aeroError; quotaReady=$($quota.Tag.Ready); runReady=$($run.Tag.Ready); quotaCore=$($null -ne $quota.CoreWebView2); runCore=$($null -ne $run.CoreWebView2)" }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
}
function Evaluate($bar,[string]$js) {
    $task = $bar.CoreWebView2.ExecuteScriptAsync($js)
    PumpUntil { $task.IsCompleted }
    if ($task.IsFaulted) { throw $task.Exception.ToString() }
    return ($task.Result | ConvertFrom-Json)
}
function Snapshot($bar,[string]$path) {
    $stream = [System.IO.MemoryStream]::new()
    try {
        $task = $bar.CoreWebView2.CapturePreviewAsync(
            [Microsoft.Web.WebView2.Core.CoreWebView2CapturePreviewImageFormat]::Png,$stream)
        PumpUntil { $task.IsCompleted }
        if ($task.IsFaulted) { throw $task.Exception.ToString() }
        $stream.Position = 0
        $picture = [System.Drawing.Bitmap]::new($stream)
        try {
            Require ($picture.Width -ge 350 -and $picture.Height -ge 13) 'WebView screenshot has incorrect dimensions.'
            $picture.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
            return $picture.GetPixel(40,[int]($picture.Height/2))
        } finally { $picture.Dispose() }
    } finally { $stream.Dispose() }
}

Require (Test-AeroRenderer) "Aero renderer unavailable: $script:aeroError"
$form = [System.Windows.Forms.Form]::new()
$form.ClientSize = [System.Drawing.Size]::new(480,145)
$form.StartPosition = 'Manual'
try {
    $quota = New-AeroProgressBar $form 15 20 400 17 'quota'
    $run = New-AeroProgressBar $form 15 64 400 17 'time'
    Require ($quota.GetType().FullName -eq 'Microsoft.Web.WebView2.WinForms.WebView2') 'Quota was not WebView2.'
    Require ($run.GetType().FullName -eq 'Microsoft.Web.WebView2.WinForms.WebView2') 'Time was not WebView2.'
    Set-AeroProgress $quota 63.5
    Set-AeroProgress $run 24
    $form.Show()
    PumpUntil { $quota.Tag.Ready -and $run.Tag.Ready }
    PumpUntil {
        $q = Evaluate $quota 'window.aeroBarProof?.getTarget()'
        $r = Evaluate $run 'window.aeroBarProof?.getTarget()'
        [math]::Abs([double]$q-.635) -lt .001 -and [math]::Abs([double]$r-.24) -lt .001
    }
    Require ((Evaluate $quota 'window.aeroBarProof.getColor()') -eq 'green') 'Quota color must be original green.'
    Require ((Evaluate $run 'window.aeroBarProof.getColor()') -eq 'blue') 'Countdown color must be blue.'
    Require ((Evaluate $quota 'window.aeroBarProof.getEngine()') -eq 'webgl2') 'Approved optical shader failed to initialize.'
    Require ((Evaluate $run 'window.aeroBarProof.getEngine()') -eq 'webgl2') 'Second shader failed.'

    Set-AeroProgress $quota 0
    PumpUntil { [math]::Abs([double](Evaluate $quota 'window.aeroBarProof.getVisual()')) -lt .005 }
    $captures = Join-Path $root 'AeroScreenshots'
    [void](New-Item -ItemType Directory -Path $captures -Force)
    $emptyColor = Snapshot $quota (Join-Path $captures 'aero-empty.png')

    foreach ($value in @(1,2,5,25,68,100)) {
        Set-AeroProgress $quota $value
        PumpUntil { [math]::Abs([double](Evaluate $quota 'window.aeroBarProof.getVisual()') - $value/100) -lt .015 }
        Require ([math]::Abs([double](Evaluate $quota 'window.aeroBarProof.getTarget()') - $value/100) -lt .001) 'Reported percent changed.'
        if ($value -eq 68) { $fillColor = Snapshot $quota (Join-Path $captures 'aero-green-68.png') }
    }
    Require ($emptyColor.ToArgb() -ne $fillColor.ToArgb()) 'Aero fill did not alter the actual rendered bitmap.'
    Set-AeroProgress $run 75
    PumpUntil { [math]::Abs([double](Evaluate $run 'window.aeroBarProof.getVisual()') - .75) -lt .015 }
    [void](Snapshot $run (Join-Path $captures 'aero-blue-75.png'))
    Set-AeroProgress $run $null
    PumpUntil { [math]::Abs([double](Evaluate $run 'window.aeroBarProof.getTarget()')) -lt .001 }
    Require ($run.Tag.Percent -eq $null) 'Unknown run value must remain unknown in application state.'

    # A rapid update must retain the last authoritative percentage despite
    # the shader's intentional physical spring lag.
    foreach($value in @(20,85,49,93)) { Set-AeroProgress $quota $value }
    PumpUntil { [math]::Abs([double](Evaluate $quota 'window.aeroBarProof.getTarget()') - .93) -lt .001 }
    PumpUntil { [math]::Abs([double](Evaluate $quota 'window.aeroBarProof.getVisual()') - .93) -lt .015 }

    Write-Host 'WebView2: real optical v3, independent quota/time, rounded tip, screenshot, null, rapid updates PASS'
} finally {
    $form.Close()
    $form.Dispose()
}