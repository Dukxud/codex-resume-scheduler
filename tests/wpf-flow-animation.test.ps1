# Verify actual WPF composition animation while the progress percentage is unchanged.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexFlowingBar.ps1')
function Require($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$form = [System.Windows.Forms.Form]::new()
$form.ClientSize = [System.Drawing.Size]::new(480,115)
try {
    $quota = New-FlowingProgressBar $form 18 18 400 18 'quota'
    $run = New-FlowingProgressBar $form 18 54 400 18 'time'
    Set-FlowingProgress $quota 57
    Set-FlowingProgress $run 38
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()

    Require ($quota -is [System.Windows.Forms.Integration.ElementHost]) 'Quota must use the supported WPF host.'
    Require ($run -is [System.Windows.Forms.Integration.ElementHost]) 'Countdown must use the supported WPF host.'
    Require ($quota.Child -is [System.Windows.Controls.ProgressBar]) 'Quota must be a real Microsoft WPF ProgressBar.'
    Require ($run.Child -is [System.Windows.Controls.ProgressBar]) 'Countdown must be a real Microsoft WPF ProgressBar.'
    Require ($quota.Child.Value -eq 57 -and $run.Child.Value -eq 38) 'WPF bars must show real, independent percentages.'
    $flow = $quota.Child.Template.FindName('FlowGlint',$quota.Child)
    Require ($null -ne $flow) 'The glint must exist in the WPF control template.'
    $start = [double]$flow.RenderTransform.X
    for ($i=0; $i -lt 18; $i++) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 35
    }
    $end = [double]$flow.RenderTransform.X
    Require ([math]::Abs($end-$start) -gt 7) "The shine must actually move while the quota stays constant: $start to $end"
    Require ($quota.Child.Value -eq 57) 'Shine animation must not modify true quota percentage.'
    Require ($run.Child.Value -eq 38) 'Shine animation must not alter countdown fraction.'
    Set-FlowingProgress $quota $null
    Require ($quota.Child.Value -eq 0) 'Unknown quota must remain unfilled.'
    Set-FlowingProgress $run 100
    Require ($run.Child.Value -eq 100) 'Completed run countdown must fill completely.'
    $customPalette=Get-CodexFlowingPalette -Kind quota -Color '#F08030'
    Require ($customPalette.BaseTop -ne '#5DE0B5' -and $customPalette.BaseBottom -ne '#14805D') 'Custom fallback palette must honor user-selected color.'
    $custom=New-FlowingProgressBar $form 18 88 400 18 'quota' -Color '#F08030'
    Set-FlowingProgress $custom 42
    Require ($custom.Child.Value -eq 42) 'Custom-color fallback must retain its true percentage.'
    Require ($null -ne $custom.Child.Template.FindName('FlowGlint',$custom.Child)) 'Custom-color fallback must retain moving glossy animation.'
    Write-Host "WPF animated flow confirmed: glint moved from $start to $end at fixed 57%."
} finally { $form.Close(); $form.Dispose() }
