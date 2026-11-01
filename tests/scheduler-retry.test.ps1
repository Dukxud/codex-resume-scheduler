# Exercise real Codex retry scheduling through the generic OneTimeTasks adapter.
# ScheduledTask platform calls are replaced; no task is registered on CI.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path ([IO.Path]::GetTempPath()) ('codex-retry-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $appDir -Force)
. (Join-Path $root 'CodexData.ps1')
. (Join-Path $root 'CodexRunEngine.ps1')

$script:registered = @()
function global:New-ScheduledTaskAction {
    param($Execute,$Argument,$WorkingDirectory)
    [pscustomobject]@{ Execute=$Execute; Arguments=$Argument; WorkingDirectory=$WorkingDirectory }
}
function global:New-ScheduledTaskTrigger { param([switch]$Once,$At) [pscustomobject]@{ StartBoundary=$At } }
function global:New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) [pscustomobject]@{ LogonType=$LogonType } }
function global:New-ScheduledTaskSettingsSet { param([switch]$StartWhenAvailable) 'settings' }
function global:Register-ScheduledTask {
    [CmdletBinding()]
    param($TaskName,$Description,$Action,$Trigger,$Principal,$Settings)
    $script:registered += [pscustomobject]@{TaskName=$TaskName; Action=$Action; Trigger=$Trigger; Principal=$Principal}
}
function global:Get-ScheduledTask {
    param($TaskName)
    $item = @($script:registered | Where-Object { $_.TaskName -eq $TaskName }) | Select-Object -Last 1
    if (-not $item) { throw 'Mock task missing' }
    return [pscustomobject]@{ State='Ready'; Actions=@($item.Action); Triggers=@($item.Trigger); Principal=$item.Principal }
}
function global:Unregister-ScheduledTask { param($TaskName,[switch]$Confirm) $script:registered = @($script:registered | Where-Object { $_.TaskName -ne $TaskName }) }
function Assert($condition,[string]$message) { if (-not $condition) { throw $message } }

try {
    $job = [pscustomobject]@{
        sessionId='00000000-0000-0000-0000-000000000001'; repo=$appDir; branch='feature'
        model='some-future-model'; effort='deep'; access='workspace-write'; message='Resume.'
        autoResume=$true; retryAttempt=0; accountId='account'
        runtimeFingerprint=(Get-RuntimeFingerprint -Directory $root -RelativeFiles (Get-CodexRuntimeFiles))
    }
    $reset = [long]([math]::Floor([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 60) * 60) + 3600
    $run = $reset + 120
    $scheduled = Schedule-LimitRetry $job $reset $run 'meter-1' $appDir $root
    Assert $scheduled 'Expected successful verified retry registration.'
    Assert ($script:registered.Count -eq 1) 'Expected one new task.'
    $item = $script:registered[0]
    $expectedTime = [DateTimeOffset]::FromUnixTimeSeconds($run).LocalDateTime
    Assert ($item.Trigger.StartBoundary -eq $expectedTime) 'Retry was not scheduled at reset +2min.'
    Assert ($item.Action.Execute -match 'wscript\.exe$') 'Retry must use Windows Script Host.'
    Assert ($item.Action.Arguments -match 'CodexRunJob\.vbs') 'Retry must use pinned runtime runner.'
    $file = Get-ChildItem -LiteralPath $appDir -Filter '*.json' | Select-Object -First 1
    $saved = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    foreach ($key in @('sessionId','repo','branch','model','effort','access','message','accountId','runtimeFingerprint')) {
        Assert ($saved.$key -ceq $job.$key) "Retry changed $key."
    }
    Assert ($saved.retryAttempt -eq 1) 'Retry count must advance once.'
    $job.retryAttempt = 4
    Assert (-not (Schedule-LimitRetry $job $reset $run 'meter-1' $appDir $root)) 'Retry cap must refuse a fifth attempt.'
    Assert ($script:registered.Count -eq 1) 'Retry cap must not register tasks.'
    $job.retryAttempt = 0
    $job.accountId = ''
    $rejected = $false
    try { [void](Schedule-LimitRetry $job $reset $run 'meter-1' $appDir $root) } catch { $rejected = $true }
    Assert $rejected 'Missing identity must reject retry.'
    Assert ($script:registered.Count -eq 1) 'Identity failure must not register a task.'
    Write-Host 'Retries honor pinned runtime, account identity, timing and cap.'
} finally {
    Remove-Item -LiteralPath $appDir -Recurse -Force -ErrorAction SilentlyContinue
}
