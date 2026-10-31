$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexDashboard.ps1')
function Require($Condition, $Message) { if (-not $Condition) { throw $Message } }

$now = [datetime]'2027-01-01T10:00:00'
Require ((Get-RunCountdownText $now $now) -eq 'Due now') 'A due run must not appear pending.'
Require ((Get-RunCountdownText $now.AddSeconds(-1) $now) -eq 'Due now') 'An overdue run must not show a positive countdown.'
Require ((Get-RunCountdownText $now.AddSeconds(35) $now) -eq '35s') 'Seconds countdown is wrong.'
Require ((Get-RunCountdownText $now.AddHours(2).AddMinutes(5) $now) -eq '2h 5m') 'Hour countdown is wrong.'
Require ((Get-RunCountdownText $now.AddDays(1).AddHours(3) $now) -eq '1d 3h 0m') 'Day countdown is wrong.'

$epoch = 1700000000L
$created = [DateTimeOffset]::FromUnixTimeSeconds($epoch).LocalDateTime
$runAt = $created.AddMinutes(20)
Require ((Get-RunCountdownPercent $runAt $epoch $created) -eq 0) 'A new countdown starts at zero.'
Require ((Get-RunCountdownPercent $runAt $epoch $created.AddMinutes(10)) -eq 50) 'The bar should fill halfway at the midpoint.'
Require ((Get-RunCountdownPercent $runAt $epoch $created.AddMinutes(30)) -eq 100) 'Elapsed progress must be clamped to 100.'
Require ((Get-RunCountdownPercent $runAt $epoch $created.AddMinutes(-10)) -eq 0) 'Early progress must be clamped to zero.'
Require ($null -eq (Get-RunCountdownPercent $runAt $null $created)) 'Legacy jobs must not invent a creation time.'
Require ($null -eq (Get-RunCountdownPercent $runAt 'not-a-time' $created)) 'Invalid timestamps must be treated as unknown.'
Require ($null -eq (Get-RunCountdownPercent $created $epoch $created)) 'Nonpositive durations must be unknown.'

function Get-SelectedModel { 'form-model' }
$script:pendingSnapshot = @([pscustomobject]@{ Model = 'queued-model' })
$script:compactToggle = [pscustomobject]@{ Checked = $true }
Require ((Get-DashboardUsageModel) -eq 'queued-model') 'Compact mode must use the next run model for quota reads.'
$script:pendingSnapshot = @()
Require ((Get-DashboardUsageModel) -eq 'form-model') 'Empty queue must fall back to the selected form model.'
$script:compactToggle.Checked = $false
$script:pendingSnapshot = @([pscustomobject]@{ Model = 'queued-model' })
Require ((Get-DashboardUsageModel) -eq 'form-model') 'Full mode must use the selected form model.'
Write-Host 'Countdown format, clamping, legacy fallback, and model targeting passed.'
