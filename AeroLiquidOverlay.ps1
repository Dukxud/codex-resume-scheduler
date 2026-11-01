# Aero Liquid optical overlay for the original themed Windows progress bar.
# Rendering source remains the real WinForms ProgressBar. This module only
# adds moving internal light/refraction under its existing color and silhouette.
# Zero strength means an untouched native-bar frame.
function Draw-AeroLiquidOverlay {
    param(
        [System.Drawing.Graphics]$Graphics,
        [int]$Width,
        [int]$Height,
        [double]$Percent,
        [double]$Phase,
        [double]$Strength,
        [string]$ColorName
    )
    if ($Percent -le 0 -or $Strength -le 0 -or $Width -le 3 -or $Height -le 5) { return }
    $filled = [single]($Width * [math]::Min(100,[math]::Max(0,$Percent)) / 100.0)
    $innerRight = [single]([math]::Min($Width - 1,$filled - 1))
    if ($innerRight -le 2) { return }
    $amount = [math]::Min(1.0,[math]::Max(0.0,$Strength/100.0))
    $saved = $Graphics.Save()
    $graphicsSmoothing = $Graphics.SmoothingMode
    $colors = @{
        Blue   = [System.Drawing.Color]::FromArgb(124,226,255)
        Cyan   = [System.Drawing.Color]::FromArgb(168,252,255)
        Violet = [System.Drawing.Color]::FromArgb(241,185,255)
        Amber  = [System.Drawing.Color]::FromArgb(255,232,145)
        Red    = [System.Drawing.Color]::FromArgb(255,168,173)
    }
    $accent = if ($colors.ContainsKey($ColorName)) { $colors[$ColorName] } else {
        [System.Drawing.Color]::FromArgb(169,255,210)
    }
    $clip = [System.Drawing.RectangleF]::new(1,1,$innerRight-1,[single]($Height-2))
    $Graphics.SetClip($clip)
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    function New-WavePoints {
        param([double]$Offset,[double]$Amplitude,[double]$Speed,[double]$Secondary)
        $pts = [System.Collections.Generic.List[System.Drawing.PointF]]::new()
        for ($i = 0; $i -le 160; $i++) {
            $x = [double]($innerRight * $i / 160.0)
            $wave = [math]::Sin($x/27.0 + $Phase*$Speed) * $Amplitude
            $wave += [math]::Sin($x/59.0 - $Phase*0.45 + $Secondary) * ($Amplitude * 0.51)
            $pts.Add([System.Drawing.PointF]::new([single]$x,[single]($Offset + $wave)))
        }
        return ,$pts.ToArray()
    }

    $pens = [System.Collections.Generic.List[System.Drawing.Pen]]::new()
    $brushes = [System.Collections.Generic.List[System.Drawing.Brush]]::new()
    try {
        # Curved, interacting optical layers. Each highlight follows the
        # fluid surface rather than sweeping a white rectangle across it.
        $shade = [System.Drawing.SolidBrush]::new(
            [System.Drawing.Color]::FromArgb([int](37*$amount),10,21,38))
        $brushes.Add($shade)
        $Graphics.FillRectangle($shade,[single]1,[single]($Height*.42),$innerRight,
            [single]($Height*.32))

        $topShadow = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb([int](48*$amount),5,30,45),[single]1.6)
        $pens.Add($topShadow)
        $surfaceShadow = New-WavePoints ($Height*.36) (0.62*$amount) 0.80 0.4
        $Graphics.DrawLines($topShadow,$surfaceShadow)

        $top = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb([int](132*$amount),$accent.R,$accent.G,$accent.B),
            [single]1.35)
        $pens.Add($top)
        $surface = New-WavePoints ($Height*.25) (0.80*$amount) 0.85 0.1
        $Graphics.DrawLines($top,$surface)

        $white = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb([int](104*$amount),255,255,255),[single]0.85)
        $pens.Add($white)
        $surfaceWhite = New-WavePoints ($Height*.15) (0.56*$amount) 0.85 0.8
        $Graphics.DrawLines($white,$surfaceWhite)

        $deep = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb([int](66*$amount),7,14,31),[single]1.4)
        $pens.Add($deep)
        $depth = New-WavePoints ($Height*.67) (0.83*$amount) 0.53 2.2
        $Graphics.DrawLines($deep,$depth)

        $caustic = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb([int](137*$amount),$accent.R,$accent.G,$accent.B),
            [single]1.0)
        $pens.Add($caustic)
        $bottomWave = New-WavePoints ($Height*.82) (0.54*$amount) 0.67 1.3
        $Graphics.DrawLines($caustic,$bottomWave)

        # Refractive pockets: dim reflected studio lights floating inside the
        # fill, not a screen-space gradient stripe.
        $bubbles = @(
            @{ X=0.21; Y=.52; Size=2.2; Speed=.19 },
            @{ X=0.48; Y=.42; Size=1.6; Speed=.13 },
            @{ X=0.75; Y=.58; Size=1.8; Speed=.15 }
        )
        foreach($bubble in $bubbles) {
            $x = [single]($innerRight*$bubble.X + 2.6*[math]::Sin($Phase*$bubble.Speed + $bubble.X*9.0))
            $y = [single]($Height*$bubble.Y + 1.1*[math]::Sin($Phase*.31+$bubble.X*6.0))
            $size = [single]($bubble.Size * [math]::Min(1.2,$Height/13.0))
            $p = [System.Drawing.Pen]::new(
                [System.Drawing.Color]::FromArgb([int](66*$amount),251,253,255),[single]0.7)
            $pens.Add($p)
            $Graphics.DrawEllipse($p,[single]($x-$size/2),[single]($y-$size/2),$size,$size)
        }

        # Rounded contact meniscus where liquid meets the empty native track.
        # At 100%, the tube end takes over and we omit the interior cap.
        if ($Percent -lt 99.5 -and $filled -gt 11) {
            $capShade = [System.Drawing.Pen]::new(
                [System.Drawing.Color]::FromArgb([int](94*$amount),2,14,30),[single]1.25)
            $pens.Add($capShade)
            $Graphics.DrawArc($capShade,[single]($filled-8),[single]0,
                [single]9,[single]($Height-1),-90,180)
            $capHighlight = [System.Drawing.Pen]::new(
                [System.Drawing.Color]::FromArgb([int](166*$amount),236,253,255),[single]1.0)
            $pens.Add($capHighlight)
            $Graphics.DrawArc($capHighlight,[single]($filled-5),[single]1,
                [single]5,[single]($Height-3),-87,174)
        }
    } finally {
        foreach($p in $pens) { $p.Dispose() }
        foreach($b in $brushes) { $b.Dispose() }
        $Graphics.Restore($saved)
        $Graphics.SmoothingMode = $graphicsSmoothing
    }
}
