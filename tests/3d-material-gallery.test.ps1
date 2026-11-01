# Runs the actual in-app comparison window and captures real WPF pixels.
# Do not use AI images or static pictures for this test.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexFlowingBar.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexBarGallery.ps1')
function Require($ok,[string]$message) { if (-not $ok) { throw $message } }

$lab = New-SchedulerBarGallery
$output = Join-Path (Split-Path -Parent $PSScriptRoot) 'preview-captures'
[void](New-Item -ItemType Directory -Path $output -Force)
try {
    $lab.Form.Show()
    for ($i = 0; $i -lt 12; $i++) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 35
    }
    Require ($lab.Form.Visible) 'The real interactive preview window must be visible.'
    Require ($lab.Bars.Count -eq 4) 'All four actual bar instances must be present.'
    $expected = @('crystal','gel','machined','prism')
    for ($i=0;$i -lt 4;$i++) {
        $bar = $lab.Bars[$i]
        Require ($bar -is [System.Windows.Forms.Integration.ElementHost]) 'Each bar must be a Windows Presentation Foundation ElementHost.'
        Require ($bar.Child -is [System.Windows.Controls.ProgressBar]) 'Each bar must be an actual percentage-driven WPF ProgressBar.'
        Require ($bar.Tag -eq $expected[$i]) 'Styles must be distinct and correctly labeled.'
        Require ($bar.Width -eq 500 -and $bar.Height -eq 40) 'Real app must provide enough height for material depth.'
        Require ($bar.Child.Value -eq 68) 'Initial sample 68% must be real progress rather than a static drawing.'
    }
    $glint = $lab.Bars[0].Child.Template.FindName('FlowGlint',$lab.Bars[0].Child)
    Require ($null -ne $glint) 'First control must have a real WPF animated highlight.'
    $from = [double]$glint.RenderTransform.X
    for ($i=0;$i -lt 17;$i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 35 }
    $to = [double]$glint.RenderTransform.X
    Require ([math]::Abs($to-$from) -gt 10) "Animated highlight must move in the actual app ($from to $to)."

    $lab.Slider.Value = 42
    [System.Windows.Forms.Application]::DoEvents()
    foreach ($bar in $lab.Bars) {
        Require ($bar.Child.Value -eq 42) 'Moving the actual slider must update every underlying native WPF percentage.'
        Require ($bar.Parent.Controls["GalleryValue_$($bar.Tag)"].Text -match '^42%') 'Visible percentage must follow the slider.'
    }
    $lab.Slider.Value = 68
    [System.Windows.Forms.Application]::DoEvents()
    $snapshots = @()
    foreach ($bar in $lab.Bars) {
        $target = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(500,40,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
        $target.Render($bar.Child)
        $png = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
        [void]$png.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($target))
        $path = Join-Path $output ("{0}-actual-wpf.png" -f $bar.Tag)
        $stream = [System.IO.File]::Open($path,[System.IO.FileMode]::Create)
        try { $png.Save($stream) } finally { $stream.Dispose() }
        $snapshots += $path
    }

    # Assemble the evidence sheet from captured WPF controls only.
    # Titles are GDI text; every progress graphic is a live native WPF render.
    $sheet = [System.Drawing.Bitmap]::new(850,600)
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    $font = [System.Drawing.Font]::new('Segoe UI',15,[System.Drawing.FontStyle]::Bold)
    $small = [System.Drawing.Font]::new('Segoe UI',10)
    $textBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(238,245,253))
    $subBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(182,199,218))
    try {
        $g.Clear([System.Drawing.Color]::FromArgb(21,27,38))
        $g.DrawString('CODEX SCHEDULER — CAPTURED LIVE WPF CONTROLS',$font,$textBrush,24,20)
        $g.DrawString('Actual 500 × 40 px controls, 68% value, not concept art',$small,$subBrush,26,60)
        $labels = @('A — Optical Crystal','B — Liquid Gel','C — Machined Alloy','D — Prism Energy')
        for($i=0;$i -lt 4;$i++){
            $y = 110 + $i*115
            $g.DrawString($labels[$i],$small,$textBrush,28,$y)
            $g.DrawString('68%',$small,$subBrush,730,$y)
            $image = [System.Drawing.Image]::FromFile($snapshots[$i])
            try { $g.DrawImage($image,[System.Drawing.Rectangle]::new(190,$y-12,500,40)) }
            finally { $image.Dispose() }
        }
        $sheet.Save((Join-Path $output 'comparison-actual-wpf.png'),[System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $subBrush.Dispose();$textBrush.Dispose();$small.Dispose();$font.Dispose();$g.Dispose();$sheet.Dispose()
    }
    $hashes = @($snapshots | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
    Require (($hashes | Select-Object -Unique).Count -eq 4) 'Each real WPF material style must render differently.'
    Write-Host "REAL WPF BAR PREVIEW PASSED: four distinct styles, slider updates, visible gallery, animated glint $from to $to"
    Write-Host "Captured comparison: $output"
} finally {
    $lab.Form.Close()
    $lab.Form.Dispose()
}
