# Codex theme adapter for the independently reusable animated WPF progress module.
Import-Module (Join-Path $PSScriptRoot 'components/FlowingProgress/FlowingProgress.psm1') -Force -ErrorAction Stop

function Get-CodexFlowingPalette {
    param([ValidateSet('quota','time')][string]$Kind,[string]$Color='')
    $defaults = if ($Kind -eq 'quota') {
        @{BaseTop='#5DE0B5';BaseBottom='#14805D';Track='#E5F1EC';Outline='#B3CFC2'}
    } else {
        @{BaseTop='#76B5F9';BaseBottom='#2566BC';Track='#E2ECFA';Outline='#B4C8E5'}
    }
    if (-not $Color -or ($Kind -eq 'quota' -and $Color -eq 'green') -or
        ($Kind -eq 'time' -and $Color -eq 'blue')) { return $defaults }
    $preset = @{
        green='#14DE8E';blue='#168DFF';cyan='#04D5F7'
        violet='#9D64FF';amber='#FFB328';red='#FF3B62'
    }
    $hex=if ($preset.ContainsKey($Color)) {$preset[$Color]} else {$Color}
    if ($hex -notmatch '^#[0-9a-fA-F]{6}$') { throw 'Invalid flowing-progress color.' }
    $base=[System.Drawing.ColorTranslator]::FromHtml($hex)
    function Mix-FlowColor($color,[int]$target,[double]$fraction) {
        $red=[int][math]::Round($color.R * (1-$fraction) + $target * $fraction)
        $green=[int][math]::Round($color.G * (1-$fraction) + $target * $fraction)
        $blue=[int][math]::Round($color.B * (1-$fraction) + $target * $fraction)
        return ('#{0:X2}{1:X2}{2:X2}' -f $red,$green,$blue)
    }
    return @{
        BaseTop=Mix-FlowColor $base 255 .30
        BaseBottom=Mix-FlowColor $base 0 .42
        Track=Mix-FlowColor $base 255 .90
        Outline=Mix-FlowColor $base 255 .60
    }
}
function New-FlowingProgressBar {
    param([System.Windows.Forms.Control]$Parent,
          [int]$X,[int]$Y,[int]$Width,[int]$Height,
          [ValidateSet('quota','time')][string]$Kind,
          [string]$Color='')
    $palette=Get-CodexFlowingPalette -Kind $Kind -Color $Color
    $accessible=if($Kind -eq 'quota'){'Usage remaining'}else{'Time until scheduled run'}
    return New-FlowingProgressView -Parent $Parent -X $X -Y $Y -Width $Width -Height $Height -Colors $palette -AccessibleName $accessible
}
function Set-FlowingProgress {
    param([System.Windows.Forms.Integration.ElementHost]$Bar,$Percent)
    Set-FlowingProgressViewState -Bar $Bar -Percent $Percent
}

function Set-FlowingProgressColors {
    param(
        [System.Windows.Forms.Integration.ElementHost]$Bar,
        [ValidateSet('quota','time')][string]$Kind,
        [string]$Color
    )
    Set-FlowingProgressViewColors -Bar $Bar -Colors (Get-CodexFlowingPalette -Kind $Kind -Color $Color)
}
