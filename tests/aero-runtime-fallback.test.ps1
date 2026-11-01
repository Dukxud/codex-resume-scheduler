# Regression: browser renderer termination must leave a functional WPF bar.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexFlowingBar.ps1')
. (Join-Path $root 'CodexAeroBar.ps1')
function Require($condition,[string]$message){if(-not $condition){throw $message}}
Require (Test-AeroRenderer) "Aero prerequisite absent: $script:aeroError"
$form=[Windows.Forms.Form]::new()
$form.ClientSize=[Drawing.Size]::new(450,100)
try{
    $bar=New-AeroProgressBar $form 16 22 400 17 'quota'
    Require ($bar.GetType().Name -eq 'WebView2') 'Initial Aero bar not WebView2.'
    Set-AeroProgress $bar 62
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $bar.Tag.Failure='Simulated WebView2 renderer process exit'
    $bar.Tag.Ready=$false
    Ensure-AeroFallback $bar
    $host=$bar.Tag.Fallback
    Require ($host -is [Windows.Forms.Integration.ElementHost]) 'WPF recovery bar was not created.'
    Require (-not $bar.Visible -and $host.Visible) 'Failed WebView must be hidden and WPF visible.'
    Require ([math]::Abs([double]$host.Tag-62) -lt .001) 'Recovery lost last authoritative percentage.'
    Set-AeroProgress $bar 91
    Require ([math]::Abs([double]$host.Tag-91) -lt .001) 'Further percentage updates failed after recovery.'
    Set-AeroProgress $bar $null
    Require ($null -eq $host.Tag) 'Unknown percentage must remain unknown after recovery.'
    Ensure-AeroFallback $bar
    Require ([object]::ReferenceEquals($host,$bar.Tag.Fallback)) 'Recovery created duplicate controls.'
    Write-Host 'WebView2 failure -> WPF fallback, prior value, future values, null and idempotence PASS.'
} finally {
    $form.Close();$form.Dispose()
    if($script:aeroHealthTimer){$script:aeroHealthTimer.Stop();$script:aeroHealthTimer.Dispose()}
}
