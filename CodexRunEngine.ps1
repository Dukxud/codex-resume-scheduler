# Codex-specific worker and CLI adapter. No GUI dependencies.
Import-Module (Join-Path $PSScriptRoot 'components/RuntimeBundle/RuntimeBundle.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'components/OneTimeTasks/OneTimeTasks.psm1') -Force -ErrorAction Stop

function Get-RepositoryBranch {
    param([string]$Path)
    $branch = & git -C $Path branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branch) { throw 'Unable to identify a Git branch (detached HEAD is not supported).' }
    return ([string]($branch | Select-Object -First 1)).Trim()
}

function Get-CodexCliJs {
    $shim = (Get-Command codex.cmd -ErrorAction Stop).Source
    $entry = Join-Path (Split-Path -Parent $shim) 'node_modules\@openai\codex\bin\codex.js'
    if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw 'Cannot locate npm Codex App Server entrypoint.' }
    return $entry
}

function Read-UsageState {
    param([string]$Model)
    $helper = Join-Path $PSScriptRoot 'CodexUsage.js'
    if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'CodexUsage.js missing.' }
    $cli = Get-CodexCliJs
    $params = @($helper,'--cli-js',$cli,'--rates-only')
    if ($Model) { $params += @('--model',$Model) }
    $response = & node @params
    if ($LASTEXITCODE -ne 0) { throw 'Could not read Codex usage.' }
    $state = ($response | Select-Object -Last 1) | ConvertFrom-Json
    if (-not $state.ok) { throw 'Codex rate-limit response unavailable.' }
    return $state
}

# Legacy settings.json files contain only lastAccess. A draft is optional.
$script:uiSettings = Read-CodexUiSettings $appDir
$script:savedDraft = if ($script:uiSettings -and $script:uiSettings.draft) { $script:uiSettings.draft } else { $null }
$script:preferredSessionId = if ($script:savedDraft) { [string]$script:savedDraft.sessionId } else { '' }
$script:preferredModelId = if ($script:savedDraft) { [string]$script:savedDraft.model } else { '' }
$script:preferredEffort = if ($script:savedDraft) { [string]$script:savedDraft.effort } else { '' }
$script:startupSavedSessionId = $script:preferredSessionId
$script:startupSavedModelId = $script:preferredModelId
$script:repoSelectionSessionId = ''
$script:settingsReady = $false

function Get-SavedAccessPreference {
    if ($script:savedDraft -and $script:savedDraft.access -in @('workspace-write','yolo','read-only')) { return [string]$script:savedDraft.access }
    if ($script:uiSettings -and $script:uiSettings.lastAccess -in @('workspace-write','yolo','read-only')) { return [string]$script:uiSettings.lastAccess }
    return 'workspace-write'
}

function Assert-ModelEffortSupported {
    param([object[]]$Models, [string]$Model, [string]$Effort)
    $entry = @($Models | Where-Object { $_.id -ceq $Model }) | Select-Object -First 1
    if (-not $entry) { throw "Model '$Model' is not in the currently available Codex catalog. Refresh models." }
    $allowed = @($entry.efforts | Where-Object { $_ -is [string] -and $_ -ne 'ultra' })
    if ($allowed.Count -eq 0 -or $allowed -cnotcontains $Effort) {
        throw "Model '$Model' does not advertise reasoning effort '$Effort'. Supported: $($allowed -join ', ')."
    }
}

function Read-CodexModelCatalog {
    $helper = Join-Path $PSScriptRoot 'CodexUsage.js'
    $cli = Get-CodexCliJs
    $lines = & node $helper --cli-js $cli --models-only
    if ($LASTEXITCODE -ne 0 -or -not $lines) { throw 'Could not verify current Codex model capabilities.' }
    $state = ($lines | Select-Object -Last 1) | ConvertFrom-Json
    if (-not $state.ok -or -not $state.models -or $state.models.Count -eq 0) { throw 'Codex model catalog unavailable.' }
    return @($state.models)
}

function Get-CodexRuntimeFiles {
    return @(
        'CodexResumeScheduler.ps1','CodexRunEngine.ps1','CodexData.ps1',
        'CodexUsage.js','CodexRetry.js','CodexRunJob.vbs',
        'components/RuntimeBundle/RuntimeBundle.psm1',
        'components/OneTimeTasks/OneTimeTasks.psm1',
        'components/SettingsStore/SettingsStore.psm1'
    )
}
function Get-CodexTaskArguments {
    param([string]$Runner,[string]$JobFile)
    if ($Runner.Contains('"') -or $JobFile.Contains('"')) { throw 'Unsafe quote in task path.' }
    return '//B //Nologo "' + $Runner + '" "' + $JobFile + '"'
}
function Schedule-LimitRetry {
    param($Job, [long]$ResetAt, [long]$RunAt, [string]$BucketId,
          [string]$AppDirectory, [string]$RuntimeDirectory)
    $attempt = [int]$Job.retryAttempt + 1
    if ($attempt -gt 4) { Write-Host 'Automatic resume stopped: maximum four attempts reached.' -ForegroundColor Yellow; return $false }
    if (-not $Job.accountId) { throw 'No saved account identity; automatic retry refused.' }
    Assert-RuntimeFingerprint -Directory $RuntimeDirectory -RelativeFiles (Get-CodexRuntimeFiles) -ExpectedFingerprint ([string]$Job.runtimeFingerprint)
    $when = [DateTimeOffset]::FromUnixTimeSeconds($RunAt).LocalDateTime
    $rounded = [datetime]::new($when.Year,$when.Month,$when.Day,$when.Hour,$when.Minute,0)
    if ($when -gt $rounded) { $rounded = $rounded.AddMinutes(1) }
    $when = $rounded
    if ($when -le (Get-Date).AddSeconds(60)) { Write-Host 'Reset time is not safely in the future; no retry scheduled.' -ForegroundColor Yellow; return $false }
    $name = 'CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
    $jobFile = Join-Path $AppDirectory ($name + '.json')
    $next = [pscustomobject]@{
        sessionId=$Job.sessionId; repo=$Job.repo; branch=$Job.branch
        model=$Job.model; effort=$Job.effort; access=$Job.access; message=$Job.message
        autoResume=$true; createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        accountId=$Job.accountId; retryAttempt=$attempt; previousResetAt=$ResetAt
        runtimeFingerprint=$Job.runtimeFingerprint; log=(Join-Path $AppDirectory ($name + '.log'))
    }
    $next | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jobFile -Encoding utf8
    $runner = Join-Path $RuntimeDirectory 'CodexRunJob.vbs'
    $exe = Join-Path $env:WINDIR 'System32\wscript.exe'
    try {
        [void](Register-OneTimeTask -Name $name -At $when -Executable $exe -Arguments (Get-CodexTaskArguments $runner $jobFile) -WorkingDirectory $Job.repo -Description "Codex retry $attempt/4")
    } catch {
        Remove-Item -LiteralPath $jobFile -Force -ErrorAction SilentlyContinue
        throw
    }
    Write-Host "Quota '$BucketId' blocked; retry $attempt/4 scheduled for $($when.ToString('yyyy-MM-dd HH:mm')) (local)."
    return $true
}

function Invoke-CodexScheduledJob {
    [CmdletBinding()]
    param([string]$JobFile, [string]$AppDirectory, [string]$RuntimeDirectory)
    $appDir = $AppDirectory
    $job = $null
    $transcribing = $false
    try {
        if (-not $JobFile -or -not (Test-Path -LiteralPath $JobFile -PathType Leaf)) { throw 'Scheduled job file is missing.' }
        $job = Get-Content -LiteralPath $JobFile -Raw | ConvertFrom-Json
        if (-not $job.runtimeFingerprint) { throw 'Legacy task has no pinned runtime. Cancel and reschedule.' }
        Assert-RuntimeFingerprint -Directory $RuntimeDirectory -RelativeFiles (Get-CodexRuntimeFiles) -ExpectedFingerprint ([string]$job.runtimeFingerprint)
        if ($job.sessionId -notmatch $sessionIdPattern) { throw 'Invalid saved session ID.' }
        if ($job.effort -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$') { throw 'Invalid reasoning effort.' }
        if ($job.model -and $job.model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$') { throw 'Invalid model identifier.' }
        if ($job.access -notin @('read-only','workspace-write','yolo')) { throw 'Invalid saved access setting.' }
        if (-not (Test-Path -LiteralPath $job.repo -PathType Container)) { throw 'Repository no longer exists.' }
        $root = Get-RepositoryRoot $job.repo
        if (-not $root -or ($root.TrimEnd([char[]]@('/','\')) -ine ([string]$job.repo).TrimEnd([char[]]@('/','\')))) { throw 'Saved directory is no longer the repository root.' }
        $branch = Get-RepositoryBranch $root
        if ($branch -cne $job.branch) { throw "Branch changed from '$($job.branch)' to '$branch'. Refusing to run." }
        $logFolder = Split-Path -Parent ([string]$job.log)
        [void](New-Item -ItemType Directory -Path $logFolder -Force)
        Start-Transcript -LiteralPath $job.log -Force | Out-Null
        $transcribing = $true
        Set-Location -LiteralPath $root
        Write-Host "Codex scheduled continuation | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "Session: $($job.sessionId) | Repository: $root | Branch: $branch"
        Write-Host "Model: $($job.model) | Reasoning: $($job.effort) | Access: $($job.access) | Message: $($job.message)"
        $model = [string]$job.model
        Assert-ModelEffortSupported (Read-CodexModelCatalog) $model ([string]$job.effort)
        $auto = $job.autoResume -eq $true
        if ($auto -and -not $job.accountId) { throw 'Automatic retry requires a verified saved account identity. Reschedule after refreshing usage.' }
        if ($auto -and [int]$job.retryAttempt -gt 0) {
            $state = Read-UsageState $model
            if (-not $state.accountId -or $job.accountId -cne $state.accountId) { throw 'Codex account identity unavailable or changed; refusing automated continuation.' }
            if (-not $state.canAttempt) {
                if ($state.recommendationKind -eq 'exhausted-window' -and $state.recommendedResetAt -and [int]$job.retryAttempt -lt 4) {
                    if (Schedule-LimitRetry $job ([long]$state.recommendedResetAt) ([long]$state.recommendedResetAt + 120) ([string]$state.bucketId) $AppDirectory $RuntimeDirectory) { return 0 }
                } else { Write-Host "Usage still unavailable; no reliable future retry: $($state.blockedReason)" -ForegroundColor Yellow }
                return 1
            }
        }
        $argsList = @('exec','--json','-m',$model,'-c',"model_reasoning_effort=$($job.effort)",'-C',$root)
        if (-not $model) { $argsList = @('exec','--json','-c',"model_reasoning_effort=$($job.effort)",'-C',$root) }
        switch ($job.access) {
            'yolo'            { $argsList += '--dangerously-bypass-approvals-and-sandbox' }
            'workspace-write' { $argsList += @('--sandbox','workspace-write') }
            'read-only'       { $argsList += @('--sandbox','read-only') }
        }
        $argsList += @('resume', [string]$job.sessionId, [string]$job.message)
        $codex = (Get-Command codex.cmd -ErrorAction Stop).Source
        $events = Join-Path $appDir (([IO.Path]::GetFileNameWithoutExtension($JobFile)) + '.jsonl')
        & $codex @argsList 2>&1 | Tee-Object -FilePath $events | Out-Host
        $result = $LASTEXITCODE
        Write-Host "Codex exit code: $result" -ForegroundColor $(if ($result -eq 0) { 'Green' } else { 'Yellow' })
        if ($auto -and $result -ne 0) {
            $retryHelper = Join-Path $PSScriptRoot 'CodexRetry.js'
            $cli = Get-CodexCliJs
            $assessment = & node $retryHelper --events $events --cli-js $cli --model $model --exit-code $result | Select-Object -Last 1 | ConvertFrom-Json
            if ($assessment.kind -eq 'retry') {
                if (-not $assessment.accountId -or $assessment.accountId -cne $job.accountId) { throw 'Codex account changed or identity unavailable; refusing retry.' }
                [void](Schedule-LimitRetry $job ([long]$assessment.resetAt) ([long]$assessment.runAt) ([string]$assessment.bucketId) $AppDirectory $RuntimeDirectory)
            } elseif ($assessment.kind -eq 'unknown') {
                Write-Host "Not auto-resuming: $($assessment.reason)" -ForegroundColor Yellow
            }
        }
        return $(if ([int]$result -eq 0) { 0 } else { [int]$result })
    } catch {
        $failure = "Scheduled run failed: $($_.Exception.Message)"
        Write-Host $failure -ForegroundColor Red
        if (-not $transcribing) {
            $target = if ($job -and $job.log) { [string]$job.log } else { Join-Path $appDir 'scheduler-errors.log' }
            try {
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force)
                Add-Content -LiteralPath $target -Value "$(Get-Date -Format o) $failure" -ErrorAction Stop
            } catch { }
        }
        return 1
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
        Write-Host 'Run finished. Check the logs folder for the transcript.' -ForegroundColor Cyan
    }
}
