# Codex Resume Scheduler — Windows PowerShell 7 / Windows Forms
# WinForms UI, owner-approved Aero v3 progress bars with WPF fallback, and scheduled runner.
# v1.16.0: canonical workspace identity, clean host boundaries and run history.
[CmdletBinding()]
param(
    [switch]$RunJob,
    [string]$JobFile
)

$ErrorActionPreference = 'Stop'
# A hidden GUI host must still report startup errors visibly, rather than failing silently.
trap {
    if (-not $RunJob) {
        $problem = "Codex Resume Scheduler could not start: $($_.Exception.Message)"
        try {
            $errorDir = Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
            [void](New-Item -ItemType Directory -Path $errorDir -Force)
            Add-Content -LiteralPath (Join-Path $errorDir 'gui-startup.log') -Value "$(Get-Date -Format o) $problem"
        } catch { }
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show($problem,'Scheduler startup error') | Out-Null
        } catch { }
    }
    exit 1
}
$appDir = Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
$sessionIdPattern = '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$script:appSourcePath = $PSCommandPath




. (Join-Path $PSScriptRoot 'CodexRunEngine.ps1')
if ($RunJob) {
    exit (Invoke-CodexScheduledJob -JobFile $JobFile -AppDirectory $appDir -RuntimeDirectory $PSScriptRoot)
}
. (Join-Path $PSScriptRoot 'CodexData.ps1')
. (Join-Path $PSScriptRoot 'CodexUiState.ps1')
$script:ui = New-CodexUiState
. (Join-Path $PSScriptRoot 'CodexUiForms.ps1')
. (Join-Path $PSScriptRoot 'CodexUiRefresh.ps1')
. (Join-Path $PSScriptRoot 'CodexUiHistory.ps1')
. (Join-Path $PSScriptRoot 'CodexUiActions.ps1')
. (Join-Path $PSScriptRoot 'CodexUiLifecycle.ps1')
