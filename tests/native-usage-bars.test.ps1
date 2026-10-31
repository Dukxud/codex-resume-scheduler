# Inspect real production functions and require native Windows-themed ProgressBar controls.
# The v1.8/1.9 visual sweep is provided by Windows itself, not hand-painted GDI+.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexResumeScheduler.ps1'
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('New-UsageCard','Render-UsageCard')) {
    $definition = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    },$true))
    if ($definition.Count -ne 1) { throw "Expected one function: $name" }
    Invoke-Expression $definition[0].Extent.Text
}
function Require($condition,[string]$message) { if (-not $condition) { throw $message } }
function Format-ResetTime { param($Seconds) return 'Reset display' }

$form = [System.Windows.Forms.Form]::new()
try {
    $first = New-UsageCard 18 'Primary window'
    $second = New-UsageCard 470 'Secondary window'
    foreach ($card in @($first,$second)) {
        Require ($card.Bar -is [System.Windows.Forms.ProgressBar]) 'Usage card must contain the native WinForms ProgressBar, not a custom panel.'
        Require ($card.Bar.Style -eq [System.Windows.Forms.ProgressBarStyle]::Blocks) 'Native Windows Blocks theme (with OS-rendered animation) must be preserved.'
        Require ($card.Bar.Minimum -eq 0 -and $card.Bar.Maximum -eq 100) 'Native percentage bounds must be 0–100.'
        Require ($card.Bar.Width -eq 400 -and $card.Bar.Height -eq 13) 'Restore original v1.9 Windows bar dimensions.'
        Require ($card.Bar.Parent -eq $card.Panel) 'Bar must remain attached to its original card for both layouts.'
    }
    $data = [pscustomobject]@{ label='5-hour usage'; remainingPercent=62.6; resetsAt=$null }
    Render-UsageCard $first $data 'Primary window'
    Require ($first.Bar.Value -eq 63) 'Percentage must be applied to the native bar.'
    $data.remainingPercent = 120
    Render-UsageCard $first $data 'Primary window'
    Require ($first.Bar.Value -eq 100) 'Progress must be clamped to native maximum.'
    $data.remainingPercent = -10
    Render-UsageCard $first $data 'Primary window'
    Require ($first.Bar.Value -eq 0) 'Progress must be clamped to native minimum.'
    $data.remainingPercent = $null
    Render-UsageCard $first $data 'Primary window'
    Require ($first.Bar.Value -eq 0) 'Unavailable quota must show no invented fill.'
    Require ($first.Remaining.Text -eq 'Unavailable') 'Unavailable quota label must be preserved.'
    Render-UsageCard $second $null 'Secondary window'
    Require ($second.Bar.Value -eq 0) 'Missing window must reset its native bar.'
    Write-Host 'Both usage windows use original native Windows progress bars with correct value handling.'
} finally {
    $form.Dispose()
}
