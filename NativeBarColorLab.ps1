# Codex native progress-bar recolor experiment.
# Uses the EXACT v1.8 WinForms ProgressBar under Windows visual styles as
# the only rendering source. Pixel-channel color transforms preserve its
# native contours, luminance, specular whites and track geometry.
# This is a read-only standalone preview. No scheduler data is accessed.
param([string]$TestDir)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This lab requires Windows and PowerShell 7.' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'AeroLiquidOverlay.ps1')
Add-Type -Namespace NativeBarLab -Name Window -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr handle, int command);
'@

function New-ColorTransform([string]$color) {
    $m = [System.Drawing.Imaging.ColorMatrix]::new()
    # These are RGB channel remaps, not new painted gradients.
    # Whites, greys, glare and track highlights retain their luminance.
    switch ($color) {
        'Blue' {
            $m.Matrix11 = 0; $m.Matrix12 = 1
            $m.Matrix21 = 1; $m.Matrix22 = 0
        }
        'Cyan' {
            $m.Matrix22 = 0; $m.Matrix12 = 1
        }
        'Violet' {
            $m.Matrix00 = [single]0.30; $m.Matrix10 = [single]0.70
            $m.Matrix01 = [single]0.80; $m.Matrix11 = 0; $m.Matrix21 = [single]0.20
            $m.Matrix02 = [single]0.15; $m.Matrix12 = [single]0.85; $m.Matrix22 = 0
        }
        'Amber' {
            $m.Matrix00 = 0; $m.Matrix10 = 1
            $m.Matrix01 = [single]0.33; $m.Matrix11 = [single]0.67
        }
        'Red' {
            $m.Matrix00 = 0; $m.Matrix01 = 1
            $m.Matrix10 = 1; $m.Matrix11 = 0
        }
        default { throw "Unknown color: $color" }
    }
    $attr = [System.Drawing.Imaging.ImageAttributes]::new()
    $attr.SetColorMatrix($m,[System.Drawing.Imaging.ColorMatrixFlag]::Default,
        [System.Drawing.Imaging.ColorAdjustType]::Bitmap)
    return $attr
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'v1.8 Windows bar + Aero Liquid (live comparison)'
$form.ClientSize = [System.Drawing.Size]::new(620,580)
$form.MinimumSize = [System.Drawing.Size]::new(638,605)
$form.BackColor = [System.Drawing.Color]::White
$form.StartPosition = 'CenterScreen'
$form.Font = [System.Drawing.Font]::new('Segoe UI',10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.MaximizeBox = $false
$form.FormBorderStyle = 'FixedDialog'

$state = [pscustomobject]@{
    Native=$null
    Frame=$null
    AeroEnabled=$true
    AeroStrength=70.0
    Phase=0.0
    Timer=$null
    ValueLabel=$null
    Copies=@()
    Attributes=@{}
    Captures=0
    Errors=0
}
$form.Tag = $state

function Add-Text([string]$text,[int]$x,[int]$y,[int]$w=550,[int]$h=24) {
    $lab = [System.Windows.Forms.Label]::new()
    $lab.Text = $text
    $lab.Location = [System.Drawing.Point]::new($x,$y)
    $lab.Size = [System.Drawing.Size]::new($w,$h)
    $form.Controls.Add($lab)
    return $lab
}
$heading = Add-Text 'THE ORIGINAL v1.8 BAR + AERO LIQUID' 24 18 575 36
$heading.Font = [System.Drawing.Font]::new('Segoe UI',11,[System.Drawing.FontStyle]::Bold)
$note = Add-Text 'Unchanged Windows bar and colors. Toggle liquid inside the fill.' 24 53 570 26
$note.ForeColor = [System.Drawing.Color]::DimGray

$colors = @('Original green','Blue','Cyan','Violet','Amber','Red')
foreach($i in 0..($colors.Count-1)) {
    $y = 108 + $i*47
    $label = Add-Text $colors[$i] 27 $y 130 20
    if ($i -eq 0) {
        # Original native control from v1.8, with the original theme and dimensions.
        $bar = [System.Windows.Forms.ProgressBar]::new()
        $bar.Location = [System.Drawing.Point]::new(160,$y)
        $bar.Size = [System.Drawing.Size]::new(400,13)
        $bar.Minimum = 0
        $bar.Maximum = 100
        $bar.Value = 68
        $form.Controls.Add($bar)
        $state.Native = $bar
    } else {
        $image = [System.Windows.Forms.PictureBox]::new()
        $image.Location = [System.Drawing.Point]::new(160,$y)
        $image.Size = [System.Drawing.Size]::new(400,13)
        $image.BackColor = [System.Drawing.Color]::White
        $image.Tag = $colors[$i]
        $image.Add_Paint({
            param($sender,$e)
            $s = $sender.FindForm().Tag
            if ($null -eq $s.Frame) { return }
            $target = [System.Drawing.Rectangle]::new(0,0,$sender.Width,$sender.Height)
            $e.Graphics.DrawImage($s.Frame,$target,
                0,0,$s.Frame.Width,$s.Frame.Height,
                [System.Drawing.GraphicsUnit]::Pixel,$s.Attributes[[string]$sender.Tag])
            if ($s.AeroEnabled) {
                Draw-AeroLiquidOverlay -Graphics $e.Graphics -Width $sender.Width -Height $sender.Height -Percent ([double]$s.Native.Value) -Phase $s.Phase -Strength $s.AeroStrength -ColorName ([string]$sender.Tag)
            }
        })
        $form.Controls.Add($image)
        $state.Copies += $image
        $state.Attributes[$colors[$i]] = New-ColorTransform $colors[$i]
    }
}

$valueLabel = Add-Text '68%' 527 408 70 30
$state.ValueLabel = $valueLabel
$slider = [System.Windows.Forms.TrackBar]::new()
$slider.Minimum = 0; $slider.Maximum = 100; $slider.Value = 68
$slider.TickFrequency = 10
$slider.Location = [System.Drawing.Point]::new(25,396)
$slider.Size = [System.Drawing.Size]::new(485,45)
$form.Controls.Add($slider)
$slider.Add_ValueChanged({
    param($sender,$e)
    $s = $sender.FindForm().Tag
    $s.Native.Value = $sender.Value
    $s.ValueLabel.Text = "$($sender.Value)%"
    Update-NativeFrame
})


$aeroToggle = [System.Windows.Forms.CheckBox]::new()
$aeroToggle.Text = 'Aero Liquid ON (uncheck for exact approved v1.8 colors)'
$aeroToggle.AutoSize = $true
$aeroToggle.Checked = $true
$aeroToggle.Location = [System.Drawing.Point]::new(28,454)
$form.Controls.Add($aeroToggle)
$aeroToggle.Add_CheckedChanged({
    param($sender,$e)
    $s = $sender.FindForm().Tag
    $s.AeroEnabled = [bool]$sender.Checked
    foreach ($view in $s.Copies) { $view.Invalidate() }
})
$intensity = Add-Text 'Aero intensity' 28 501 105 26
$strength = [System.Windows.Forms.TrackBar]::new()
$strength.Minimum = 0
$strength.Maximum = 100
$strength.Value = 70
$strength.TickFrequency = 20
$strength.Location = [System.Drawing.Point]::new(142,490)
$strength.Size = [System.Drawing.Size]::new(366,43)
$form.Controls.Add($strength)
$strengthReadout = Add-Text '70%' 527 501 75 24
$strength.Add_ValueChanged({
    param($sender,$e)
    $s = $sender.FindForm().Tag
    $s.AeroStrength = [double]$sender.Value
    $strengthReadout.Text = "$($sender.Value)%"
    foreach ($view in $s.Copies) { $view.Invalidate() }
})
$footnote = Add-Text 'The original green bar stays untouched. The other bars reuse its theme.' 28 545 568 24
$footnote.ForeColor = [System.Drawing.Color]::DimGray

function Update-NativeFrame {
    $bmp = [System.Drawing.Bitmap]::new(400,13)
    try {
        $state.Native.DrawToBitmap($bmp,[System.Drawing.Rectangle]::new(0,0,400,13))
        if ($null -ne $state.Frame) { $state.Frame.Dispose() }
        $state.Frame = $bmp
        $state.Captures++
        foreach($view in $state.Copies) { $view.Invalidate() }
    } catch {
        $state.Errors++
        $bmp.Dispose()
        throw
    }
}
function Save-TintedFrame([string]$color,[string]$path,[bool]$withAero = $false) {
    $bmp = [System.Drawing.Bitmap]::new(400,13)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        if ($color -eq 'Original green') {
            $g.DrawImageUnscaled($state.Frame,0,0)
        } else {
            $g.DrawImage($state.Frame,
                [System.Drawing.Rectangle]::new(0,0,400,13),
                0,0,400,13,
                [System.Drawing.GraphicsUnit]::Pixel,$state.Attributes[$color])
        }
        if ($withAero -and $color -ne 'Original green') {
            Draw-AeroLiquidOverlay -Graphics $g -Width 400 -Height 13 -Percent ([double]$state.Native.Value) -Phase $state.Phase -Strength $state.AeroStrength -ColorName $color
        }
        $bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
    } finally { $g.Dispose(); $bmp.Dispose() }
}

$timer = [System.Windows.Forms.Timer]::new()
$timer.Interval = 33
$timer.Add_Tick({ $state.Phase += 0.11; Update-NativeFrame })
$state.Timer = $timer

$form.Add_Shown({
    [void][NativeBarLab.Window]::ShowWindow($form.Handle,5)
    $form.Activate()
    Update-NativeFrame
    $state.Timer.Start()
})
$form.Add_FormClosed({
    $state.Timer.Stop()
    $state.Timer.Dispose()
    if ($state.Frame) { $state.Frame.Dispose() }
    foreach ($attr in $state.Attributes.Values) { $attr.Dispose() }
})

if (-not $TestDir) {
    try { [void][System.Windows.Forms.Application]::Run($form) }
    finally { $form.Dispose() }
} else {
    [void](New-Item -ItemType Directory -Force -Path $TestDir)
    try {
        $form.Show()
        for($i=0;$i -lt 5;$i++) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        if (-not $form.Visible -or $state.Captures -lt 2) {
            throw 'Original v1.8 control or capture loop is not functioning.'
        }
        $baseline = [System.Drawing.Bitmap]::new($state.Frame)
        $slider.Value = 24
        [System.Windows.Forms.Application]::DoEvents()
        Update-NativeFrame
        if ($state.Native.Value -ne 24) { throw 'Slider not connected to native original.' }
        $slider.Value = 68
        [System.Windows.Forms.Application]::DoEvents()
        Update-NativeFrame
        foreach($c in $colors) {
            Save-TintedFrame $c (Join-Path $TestDir "$($c.Replace(' ','-')).png")
        }
        $frame = [System.Drawing.Bitmap]::new(620,475)
        $form.DrawToBitmap($frame,[System.Drawing.Rectangle]::new(0,0,620,475))
        $frame.Save((Join-Path $TestDir 'native-windows-color-comparison.png'),[System.Drawing.Imaging.ImageFormat]::Png)
        $frame.Dispose()
        $baseline.Dispose()
        if ($state.Errors -ne 0) { throw "Native snapshot errors: $($state.Errors)" }
        Write-Host "Approved v1.8 colors retained; the Aero layer is optional. Captures: $($state.Captures)."
    } finally { $form.Close(); $form.Dispose() }
}
