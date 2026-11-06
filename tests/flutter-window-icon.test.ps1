# Read-only native Windows PE icon check. Does not launch the executable.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Executable)
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows is required for native PE icon verification.' }
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "Windows executable missing: $Executable"
}
Add-Type -AssemblyName System.Drawing
$icon = [Drawing.Icon]::ExtractAssociatedIcon($Executable)
if ($null -eq $icon) { throw 'No application icon embedded in Windows executable.' }
try {
    $bitmap = $icon.ToBitmap()
    try {
        $w = $bitmap.Width
        $h = $bitmap.Height
        if ($w -lt 16 -or $h -lt 16) { throw 'Embedded icon resolution is too small.' }
        $outer = $bitmap.GetPixel([int][math]::Floor($w * 0.22), [int][math]::Floor($h * 0.22))
        $inner = $bitmap.GetPixel([int][math]::Floor($w * 0.35), [int][math]::Floor($h * 0.50))
        # Exterior: Continuum coral/iris gradient. Interior: deep ink play disk.
        # An old Flutter icon or Windows warning triangle is not this palette.
        if ($outer.R -lt 160 -or $outer.G -lt 80 -or $outer.B -lt 90 -or
            $outer.R -le $outer.G + 30 -or
            $inner.R -gt 70 -or $inner.G -gt 70 -or $inner.B -gt 70) {
            throw "EXE icon does not show Continuum branding (outer=$outer inner=$inner)."
        }
        Write-Host "CONTINUUM PE ICON PASS - native $w x $h branding confirmed." -ForegroundColor Green
    } finally { $bitmap.Dispose() }
} finally { $icon.Dispose() }
