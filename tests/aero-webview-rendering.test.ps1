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
        if ((Get-Date) -gt $deadline) { throw "Timed out awaiting WebView2 rendering: $script:aeroError; quotaReady=$((Get-AeroProgressViewStatus -View $quota).Ready); runReady=$((Get-AeroProgressViewStatus -View $run).Ready); quotaCore=$($null -ne $quota.CoreWebView2); runCore=$($null -ne $run.CoreWebView2); quotaFailure=$((Get-AeroProgressViewStatus -View $quota).Failure); runFailure=$((Get-AeroProgressViewStatus -View $run).Failure)" }
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

function Count-VisualChanges([string]$pathA,[string]$pathB) {
    $a = [System.Drawing.Bitmap]::new($pathA)
    $b = [System.Drawing.Bitmap]::new($pathB)
    try {
        $changes = 0
        for ($y = 3; $y -lt [math]::Min(15,$a.Height); $y+=2) {
            for ($x = 12; $x -lt [math]::Min(260,$a.Width); $x+=2) {
                $p = $a.GetPixel($x,$y)
                $q = $b.GetPixel($x,$y)
                if ([math]::Abs([int]$p.R-[int]$q.R) -gt 14 -or
                    [math]::Abs([int]$p.G-[int]$q.G) -gt 14 -or
                    [math]::Abs([int]$p.B-[int]$q.B) -gt 14) { $changes++ }
            }
        }
        return $changes
    } finally { $a.Dispose();$b.Dispose() }
}
Require (Test-AeroRenderer) "Aero renderer unavailable: $script:aeroError"
# A rendering acceptance test must not share the installed application's
# persistent browser profile with an existing scheduler or another test.
# Both bars deliberately share one unique profile to exercise multi-view reuse.
$testUserData = Join-Path ([IO.Path]::GetTempPath()) ('codex-aero-render-' + [guid]::NewGuid().ToString('N'))
Write-Host "WebView2 diagnostic: isolated profile $testUserData"
$form = [System.Windows.Forms.Form]::new()
$form.ClientSize = [System.Drawing.Size]::new(480,145)
$form.StartPosition = 'Manual'
try {
    $quota = New-AeroProgressBar $form 15 20 400 17 'quota' -UserDataDirectory $testUserData
    $run = New-AeroProgressBar $form 15 64 400 17 'time' -UserDataDirectory $testUserData
    Require ($quota.GetType().FullName -eq 'Microsoft.Web.WebView2.WinForms.WebView2') 'Quota was not WebView2.'
    Require ($run.GetType().FullName -eq 'Microsoft.Web.WebView2.WinForms.WebView2') 'Time was not WebView2.'
    Set-AeroProgress $quota 63.5
    Set-AeroProgress $run 24
    $form.Show()
    PumpUntil { (Get-AeroProgressViewStatus -View $quota).Ready -and (Get-AeroProgressViewStatus -View $run).Ready }
    PumpUntil {
        $q = Evaluate $quota 'window.aeroBarProof?.getTarget()'
        $r = Evaluate $run 'window.aeroBarProof?.getTarget()'
        [math]::Abs([double]$q-.635) -lt .001 -and [math]::Abs([double]$r-.24) -lt .001
    }
    Require ((Evaluate $quota 'window.aeroBarProof.getColor()') -eq 'green') 'Quota color must be original green.'
    Require ((Evaluate $run 'window.aeroBarProof.getColor()') -eq 'blue') 'Countdown color must be blue.'
    Require ((Evaluate $quota 'window.aeroBarProof.getEngine()') -eq 'webgl2') 'Approved optical shader failed to initialize.'
    Require ((Evaluate $run 'window.aeroBarProof.getEngine()') -eq 'webgl2') 'Second shader failed.'

    # The original CI only tested that percentages changed. It did not
    # prove animation continued at a CONSTANT percentage.
    Set-AeroProgress $quota 68
    PumpUntil { [math]::Abs([double](Evaluate $quota 'window.aeroBarProof.getVisual()') - .68) -lt .001 }
    $captures = Join-Path $root 'AeroScreenshots'
    [void](New-Item -ItemType Directory -Path $captures -Force)
    $initialFrame = [int](Evaluate $quota 'window.aeroBarProof.getFrames()')
    $first = Join-Path $captures 'shimmer-frame-a.png'
    $second = Join-Path $captures 'shimmer-frame-b.png'
    [void](Snapshot $quota $first)
    $strongMotion = 0
    foreach($i in 1..7) {
        Start-Sleep -Milliseconds 370
        [System.Windows.Forms.Application]::DoEvents()
        [void](Snapshot $quota $second)
        $strongMotion = [math]::Max($strongMotion,(Count-VisualChanges $first $second))
        if ($strongMotion -gt 10) { break }
    }
    $laterFrame = [int](Evaluate $quota 'window.aeroBarProof.getFrames()')
    Require ($laterFrame -gt $initialFrame + 5) 'WebGL frame loop stopped at fixed progress.'
    Require ($strongMotion -gt 10) "Shimmer invisible: only $strongMotion strongly changed pixels at fixed progress."
    Write-Host "Visible shimmer at 68%: $strongMotion changed sampled pixels; $($laterFrame-$initialFrame) frames."

    # Per-bar preferences must update already-running WebView2 controls.
    Update-AeroAppearance ([ordered]@{
        quota='violet'; time='amber'; finish=2; lighting=2
        shimmer=165; speed=190; aero=$true
    })
    PumpUntil {
        (Evaluate $quota 'window.aeroBarProof.getColor()') -eq 'violet' -and
        (Evaluate $run 'window.aeroBarProof.getColor()') -eq 'amber' -and
        [double](Evaluate $quota 'window.aeroBarProof.getSettings().shimmer') -gt 1.6
    }
    Require ((Evaluate $quota 'window.aeroBarProof.getSettings().finish') -eq 2) 'Material setting not applied.'
    Require ((Evaluate $run 'window.aeroBarProof.getSettings().lighting') -eq 2) 'Lighting not applied.'
    # A true arbitrary RGB color must produce a non-empty native source
    # and reach the live WebView2 control without restarting it.
    Update-AeroAppearance ([ordered]@{
        quota='#F08A3C'; time='#2AC1DD'; finish=0; lighting=0
        shimmer=100; speed=100; aero=$true
    })
    PumpUntil {
        (Evaluate $quota 'window.aeroBarProof.getColor()') -eq '#F08A3C' -and
        (Evaluate $run 'window.aeroBarProof.getColor()') -eq '#2AC1DD' -and
        (Evaluate $quota 'window.aeroBarProof.isNativeSourceReady()') -eq $true
    }
    $orange = Snapshot $quota (Join-Path $captures 'aero-custom-orange.png')
    Update-AeroAppearance ([ordered]@{
        quota='green'; time='blue'; finish=0; lighting=0
        shimmer=100; speed=100; aero=$true
    })
    PumpUntil { (Evaluate $quota 'window.aeroBarProof.getColor()') -eq 'green' }
    $green = Snapshot $quota (Join-Path $captures 'aero-green-default.png')
    Require ($orange.ToArgb() -ne $green.ToArgb()) 'Custom RGB selection did not change rendered native color.'
    PumpUntil { (Evaluate $quota 'window.aeroBarProof.getColor()') -eq 'green' }

    Set-AeroProgress $quota 0
    PumpUntil { [math]::Abs([double](Evaluate $quota 'window.aeroBarProof.getVisual()')) -lt .005 }
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
    # WebView2 process shutdown can lag disposal; failure to remove an isolated
    # test profile must not conceal the renderer's actual acceptance outcome.
    if (Test-Path -LiteralPath $testUserData) {
        Remove-Item -LiteralPath $testUserData -Recurse -Force -ErrorAction SilentlyContinue
    }
}