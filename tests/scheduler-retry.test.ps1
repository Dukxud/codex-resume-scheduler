# Exercise retry scheduling with Task Scheduler cmdlets stubbed; no real tasks created.
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexResumeScheduler.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($source, [ref]$tokens, [ref]$errors)
if ($errors) { throw ($errors | ForEach-Object { $_.ToString() } | Out-String) }
$found = @($ast.FindAll({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Schedule-LimitRetry'}, $true))
if ($found.Count -ne 1) { throw 'Missing unique retry scheduler.' }
Invoke-Expression $found[0].Extent.Text
$script:registered = @()
function New-ScheduledTaskAction { param($Execute,$Argument,$WorkingDirectory) [pscustomobject]@{Execute=$Execute;Argument=$Argument;WorkingDirectory=$WorkingDirectory} }
function New-ScheduledTaskTrigger { param([switch]$Once,$At) $At }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) [pscustomobject]@{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel} }
function New-ScheduledTaskSettingsSet { param([switch]$StartWhenAvailable) 'settings' }
function Register-ScheduledTask { [CmdletBinding()]param($TaskName,$Action,$Trigger,$Principal,$Settings) $script:registered += [pscustomobject]@{TaskName=$TaskName;Action=$Action;Trigger=$Trigger;Principal=$Principal} }
$appDir = Join-Path ([IO.Path]::GetTempPath()) ('codex-retry-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $appDir -Force)
$script:appSourcePath = $source
try {
    $job = [pscustomobject]@{sessionId='00000000-0000-0000-0000-000000000001'; repo='C:\repo'; branch='feature'; model='some-future-model'; effort='deep'; access='workspace-write'; message='Resume.'; autoResume=$true; retryAttempt=0; accountId='account'}
    $reset = [long]([math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 60) * 60) + 3600
    $run = $reset + 120
    Schedule-LimitRetry $job $reset $run 'meter-1'
    if ($script:registered.Count -ne 1) { throw 'Expected one new task.' }
    $scheduled = $script:registered[0]
    $local = [DateTimeOffset]::FromUnixTimeSeconds($run).LocalDateTime
    $rounded = [datetime]::new($local.Year,$local.Month,$local.Day,$local.Hour,$local.Minute,0)
    if($local -gt $rounded){$rounded=$rounded.AddMinutes(1)}
    if ($scheduled.Trigger -ne $rounded) { throw 'Retry was not scheduled at reset +2min rounded up.' }
    $jobFile = @(Get-ChildItem -LiteralPath $appDir -Filter '*.json')
    if ($jobFile.Count -ne 1) { throw 'Expected one saved retry job.' }
    $saved = Get-Content -LiteralPath $jobFile[0].FullName -Raw | ConvertFrom-Json
    foreach($key in @('sessionId','repo','branch','model','effort','access','message','accountId')){ if($saved.$key -cne $job.$key){throw "Did not retain $key"} }
    if ($saved.retryAttempt -ne 1) { throw 'Retry count was not incremented.' }
    if ($scheduled.Action.Argument -notmatch '-ExecutionPolicy Bypass') { throw 'Process-scoped execution policy omitted.' }
    $job.retryAttempt = 4
    Schedule-LimitRetry $job $reset $run 'meter-1'
    if($script:registered.Count -ne 1){throw 'Retry cap was not honored.'}
    Write-Host 'Retry scheduling checks passed.'
} finally { Remove-Item -LiteralPath $appDir -Recurse -Force }

