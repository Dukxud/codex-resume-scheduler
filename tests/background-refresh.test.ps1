# Verify costly data reads are dispatched to background jobs, never from refresh handlers.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gui = Get-Content -LiteralPath (Join-Path $root 'CodexResumeScheduler.ps1') -Raw
$data = Get-Content -LiteralPath (Join-Path $root 'CodexData.ps1') -Raw
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($gui, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw ($parseErrors | Out-String) }
if ($gui -match 'Get-CodexSessionCollision|Get-CimInstance\s+Win32_Process') { throw 'Unreliable Codex process detection must be removed from UI and runner.' }
if ($data -match 'Get-CimInstance\s+Win32_Process') { throw 'Process inspection remains in background code.' }
if ($gui -notmatch 'Start-ThreadJob' -or $gui -notmatch '\$dataPoll\.Add_Tick') { throw 'Background refresh and result polling missing.' }
if ($data -notmatch "Get-ScheduledTask -TaskName 'CodexResume-\*'") { throw 'Pending refresh must use task name filtering.' }
if ($gui -notmatch "'CodexUsage.js','CodexRetry.js','CodexData.ps1'") { throw 'Scheduled runner needs all helper files installed.' }
$definitions = @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in @('Refresh-SessionList','Refresh-PendingList','Request-SelectionLookup','Start-DataRead')}, $true))
if ($definitions.Count -ne 4) { throw 'Expected four async data-refresh entrypoints.' }
foreach ($definition in $definitions | Where-Object Name -in @('Refresh-SessionList','Refresh-PendingList','Request-SelectionLookup')) {
    if ($definition.Extent.Text -match 'Get-ScheduledTask|Get-Content|Get-RecentCliSessions|Find-SessionRepository|Read-SessionModel') { throw "UI entrypoint $($definition.Name) performs blocking work." }
}
# Start-DataRead must coalesce an in-flight request, not start parallel duplicates.
Invoke-Expression (@($definitions | Where-Object Name -eq 'Start-DataRead')[0].Extent.Text)
$script:dataJobs = @{}; $script:dataQueued = @{}; $script:startedJobs = 0
function Start-ThreadJob { param($ArgumentList,$ScriptBlock) $script:startedJobs++; [pscustomobject]@{ State = 'Running' } }
function Update-Status { param($Text) throw "Unexpected start failure: $Text" }
$appDir = 'C:\fake'
Start-DataRead -Kind 'pending'
Start-DataRead -Kind 'pending'
if ($script:startedJobs -ne 1 -or -not $script:dataQueued['pending']) { throw 'Duplicate pending refresh was not coalesced.' }
Write-Host 'Background refresh wiring and coalescing checks passed.'
