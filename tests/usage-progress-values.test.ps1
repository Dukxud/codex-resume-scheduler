# Verify that the production usage cards use WPF compositor-driven progress.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$env:CODEX_BAR_RENDERER = 'wpf'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexFlowingBar.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexAeroBar.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($spec in @(
    @('New-UsageCard','CodexUiForms.ps1'),
    @('Render-UsageCard','CodexUiRefresh.ps1')
)) {
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root $spec[1]),[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
    $matches = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $spec[0]
    },$true))
    if ($matches.Count -ne 1) { throw "Expected one function: $($spec[0])" }
    Invoke-Expression $matches[0].Extent.Text
}
function Format-ResetTime { param($Seconds) return 'Reset display' }
function Require($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }

$form = [System.Windows.Forms.Form]::new()
try {
    $first = New-UsageCard 18 'Primary window'
    $second = New-UsageCard 470 'Secondary window'
    foreach ($card in @($first,$second)) {
        Require ($card.Bar -is [System.Windows.Forms.Integration.ElementHost]) 'Usage must be WPF hosted in WinForms.'
        Require ($card.Bar.Child -is [System.Windows.Controls.ProgressBar]) 'Usage must be a real WPF percentage bar.'
        Require ($card.Bar.Width -eq 400 -and $card.Bar.Height -eq 17) 'Usage bars must preserve layout.'
        Require ($card.Bar.Parent -eq $card.Panel) 'Usage bar must stay inside its card.'
    }
    $window = [pscustomobject]@{ label='5-hour usage'; remainingPercent=62.6; resetsAt=$null }
    Render-UsageCard $first $window 'Primary window'
    Require ([math]::Abs($first.Bar.Child.Value - 62.6) -lt 0.01) 'Real percentage should not be rounded for WPF.'
    $window.remainingPercent = 120
    Render-UsageCard $first $window 'Primary window'
    Require ($first.Bar.Child.Value -eq 100) 'Remaining fraction must clamp to 100.'
    $window.remainingPercent = -10
    Render-UsageCard $first $window 'Primary window'
    Require ($first.Bar.Child.Value -eq 0) 'Remaining fraction must clamp to zero.'
    $window.remainingPercent = $null
    Render-UsageCard $first $window 'Primary window'
    Require ($first.Bar.Child.Value -eq 0 -and $first.Remaining.Text -eq 'Unavailable') 'Missing quota must not invent a percentage.'
    Render-UsageCard $second $null 'Secondary window'
    Require ($second.Bar.Child.Value -eq 0) 'Missing window must not show a filled bar.'
    Write-Host 'Production usage cards retain real percentages with WPF flowing controls.'
} finally { $form.Dispose() }
