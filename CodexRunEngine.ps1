# Codex-specific worker and CLI adapter. No GUI dependencies.
Import-Module (Join-Path $PSScriptRoot 'components/RuntimeBundle/RuntimeBundle.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'components/OneTimeTasks/OneTimeTasks.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'components/GitRepository/GitRepository.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'components/JobOutcomes/JobOutcomes.psm1') -Force -ErrorAction Stop
. (Join-Path $PSScriptRoot 'CodexQuotaContinuation.ps1')
. (Join-Path $PSScriptRoot 'CodexTerminalRun.ps1')

function Get-RepositoryBranch {
    param([string]$Path)
    return Get-GitCurrentBranch -Path $Path
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

# Read-only App Server check. A cleanup diagnostic can follow an actual
# quota failure, but only a still-readable conversation may be rescheduled.
function Assert-CodexConversationAvailable {
    param([Parameter(Mandatory)][string]$SessionId)
    $helper=Join-Path $PSScriptRoot 'CodexUsage.js'
    $cli=Get-CodexCliJs
    $lines=@(& node.exe $helper --cli-js $cli --thread-id $SessionId)
    if($LASTEXITCODE -ne 0 -or $lines.Count -eq 0){
        throw 'Codex conversation could not be read; automatic continuation refused.'
    }
    $thread=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($thread.ok -ne $true -or [string]$thread.threadId -cne $SessionId){
        throw 'Codex returned no matching resumable conversation.'
    }
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
        'CodexResumeScheduler.ps1','CodexRunEngine.ps1',
        'CodexUsage.js','CodexRunJob.vbs','CodexQuotaContinuation.ps1',
        'CodexTerminalRun.ps1',
        'components/SharedCodex/SharedProtocol.js',
        'components/SharedCodex/SharedController.js',
        'components/SharedCodex/SharedClient.js',
        'components/RuntimeBundle/RuntimeBundle.psm1',
        'components/OneTimeTasks/OneTimeTasks.psm1',
        'components/GitRepository/GitRepository.psm1',
        'components/JobOutcomes/JobOutcomes.psm1',
        'components/SettingsStore/SettingsStore.psm1'
    )
}
function Get-CodexTaskArguments {
    param([string]$Runner,[string]$JobFile,
          [ValidateSet('background','terminal','shared')][string]$ExecutionMode='background')
    if ($Runner.Contains('"') -or $JobFile.Contains('"')) { throw 'Unsafe quote in task path.' }
    # A terminal run deliberately gets a console; existing tasks keep their
    # original one-argument, hidden launch contract.
    $arguments='//B //Nologo "' + $Runner + '" "' + $JobFile + '"'
    if($ExecutionMode -eq 'terminal'){$arguments+=' terminal'}
    return $arguments
}
# One Codex thread can have only one writer. Keep the mutex for the entire
# scheduled continuation, including the time spent inside the Codex process.
function Enter-CodexSessionRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SessionId)
    if ($SessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        throw 'Invalid session ID for execution lock.'
    }
    $name = 'Local\CodexResumeScheduler-Session-' + $SessionId.ToLowerInvariant()
    $mutex = [System.Threading.Mutex]::new($false,$name)
    try {
        $acquired = $false
        try { $acquired = $mutex.WaitOne(0) }
        catch [System.Threading.AbandonedMutexException] {
            # The prior PowerShell owner died. Its Codex child might still live.
            $mutex.ReleaseMutex()
            throw 'Prior scheduled owner died; check that no Codex writer survived before rescheduling.'
        }
        if (-not $acquired) { $mutex.Dispose(); return $null }
        return $mutex
    } catch {
        $mutex.Dispose()
        throw
    }
}

# Only the canonical hash from the backend-selected workspace is a valid binding.
function Test-CanonicalWorkspaceIdentity {
    param([string]$Identity)
    return ($Identity -cmatch '^workspace-sha256:[0-9a-f]{64}$')
}

# Task Scheduler reports handler success; the persisted outcome distinguishes
# completed, failed, or blocked one-time work.
function Set-CodexRunOutcome {
    param([string]$JobFile,[string]$Status,$ExitCode=$null,[string]$Message='',
          [int]$Attempt=0,[string]$NextJob='')
    if (-not $JobFile -or -not [IO.Path]::IsPathRooted($JobFile)) { return }
    $outcomePath=[IO.Path]::ChangeExtension($JobFile,'.result.json')
    [void](Write-JobOutcome -Path $outcomePath -Status $Status -Attempt $Attempt -ExitCode $ExitCode -Message $Message -NextJob $NextJob)
}
# The decision is single-shot. A reliable model-specific reset is required,
# and a failure to register is reported without an invented future job.
function Try-DeferCodexQuotaJob {
    param($Job,[string]$JobFile,[string]$AppDirectory,
          [string]$RuntimeDirectory,$Quota,[int]$ExitCode)
    if(-not (Test-CodexContinuationPolicy $Job) -or [int]$Job.retryAttempt -ge 3){return $false}
    $at=Get-VerifiedQuotaContinuationTime -Quota $Quota -AccountId ([string]$Job.accountId) -Model ([string]$Job.model)
    if(-not $at){Write-Warning 'Quota exhausted, but no verified future reset for this model/workspace; no automatic continuation.';return $false}
    try {
        Assert-CodexConversationAvailable -SessionId ([string]$Job.sessionId)
        $child=Register-CodexQuotaContinuation -Job $Job -JobFile $JobFile -AppDirectory $AppDirectory -RuntimeDirectory $RuntimeDirectory -When $at
        Set-CodexRunOutcome -JobFile $JobFile -Status 'deferred' -Attempt ([int]$Job.retryAttempt) -ExitCode $ExitCode -NextJob $child.Name -Message "Waiting for verified quota reset at $($child.When.ToString('o'))"
        Write-Host "Quota exhausted. One bounded continuation registered: $($child.Name) at $($child.When.ToString('o'))" -ForegroundColor Cyan
        return $true
    }catch{
        Write-Warning "Quota continuation not registered: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-CodexScheduledJob {
    [CmdletBinding()]
    param([string]$JobFile, [string]$AppDirectory, [string]$RuntimeDirectory)
    $appDir = $AppDirectory
    $job = $null
    $transcribing = $false
    $sessionGuard = $null
    try {
        if (-not $JobFile -or -not (Test-Path -LiteralPath $JobFile -PathType Leaf)) { throw 'Scheduled job file is missing.' }
        $job = Get-Content -LiteralPath $JobFile -Raw | ConvertFrom-Json
        if (-not $job.runtimeFingerprint) { throw 'Legacy task has no pinned runtime. Cancel and reschedule.' }
        Assert-RuntimeFingerprint -Directory $RuntimeDirectory -RelativeFiles (Get-CodexRuntimeFiles) -ExpectedFingerprint ([string]$job.runtimeFingerprint)
        if ([string]$job.sessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { throw 'Invalid saved session ID.' }
        if ($job.effort -notmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$') { throw 'Invalid reasoning effort.' }
        if ($job.model -and $job.model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$') { throw 'Invalid model identifier.' }
        if ($job.access -notin @('read-only','workspace-write','yolo')) { throw 'Invalid saved access setting.' }
        $executionMode=if($job.executionMode){[string]$job.executionMode}else{'background'}
        if($executionMode -cnotin @('background','terminal','shared')){throw 'Invalid saved execution mode.'}
        if($executionMode -in @('terminal','shared') -and (Test-CodexContinuationPolicy $job)){
            throw 'Interactive terminal runs cannot use automatic quota continuation.'
        }
        if (-not (Test-Path -LiteralPath $job.repo -PathType Container)) { throw 'Repository no longer exists.' }
        $root = Get-GitRepositoryRoot -Path $job.repo
        if (-not $root -or ($root.TrimEnd([char[]]@('/','\')) -ine ([string]$job.repo).TrimEnd([char[]]@('/','\')))) { throw 'Saved directory is no longer the repository root.' }
        $branch = Get-RepositoryBranch $root
        if ($branch -cne $job.branch) { throw "Branch changed from '$($job.branch)' to '$branch'. Refusing to run." }
        $sessionGuard = Enter-CodexSessionRun -SessionId ([string]$job.sessionId)
        if (-not $sessionGuard) {
            $message = 'Another scheduled continuation is active for this Codex conversation; duplicate execution refused.'
            Set-CodexRunOutcome -JobFile $JobFile -Status 'blocked' -ExitCode 1 -Attempt ([int]$job.retryAttempt) -Message $message
            Write-Host $message -ForegroundColor Yellow
            return 1
        }
        # Every quota child must still be the child authorized by its saved
        # parent and the registered Windows action at the moment it starts.
        if($job.parentJob -or [int]$job.retryAttempt -gt 0){
            $parentName=[string]$job.parentJob
            if($parentName -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[a-fA-F0-9]{8}\z'){
                throw 'Quota child has no valid parent job.'
            }
            $parentFile=Join-Path $appDir ($parentName+'.json')
            $parentJob=Get-Content -LiteralPath $parentFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $registered=Get-RegisteredCodexQuotaContinuation -Job $parentJob -JobFile $parentFile -Directory $appDir -RuntimeDirectory $RuntimeDirectory
            if(-not $registered -or $registered.Name -cne [IO.Path]::GetFileNameWithoutExtension($JobFile)){
                throw 'Quota child does not match its registered parent.'
            }
        }
        # A process may stop after creating its child but before the parent
        # outcome is written. Reconcile the persisted intent instead of
        # executing the same Codex turn or registering another child.
        $intentPath=Join-Path $appDir ([IO.Path]::GetFileNameWithoutExtension($JobFile)+'.continuation.json')
        if(Test-Path -LiteralPath $intentPath -PathType Leaf){
            try {
                $linked=Get-RegisteredCodexQuotaContinuation -Job $job -JobFile $JobFile -Directory $appDir -RuntimeDirectory $RuntimeDirectory
                Set-CodexRunOutcome -JobFile $JobFile -Status 'deferred' -Attempt ([int]$job.retryAttempt) -NextJob $linked.Name -Message "Existing quota continuation: $($linked.Name)"
                Write-Host "Existing continuation preserved: $($linked.Name)" -ForegroundColor Cyan
                return 0
            }catch{
                Write-Warning "Continuation registration requires review; refusing to run this parent twice: $($_.Exception.Message)"
                return 1
            }
        }
        $logFolder = Split-Path -Parent ([string]$job.log)
        [void](New-Item -ItemType Directory -Path $logFolder -Force)
        Start-Transcript -LiteralPath $job.log -Force | Out-Null
        $transcribing = $true
        Set-Location -LiteralPath $root
        Write-Host "Codex scheduled continuation | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "Session: $($job.sessionId) | Repository: $root | Branch: $branch"
        Write-Host "Model: $($job.model) | Reasoning: $($job.effort) | Access: $($job.access) | Message: $($job.message)"
        $model = [string]$job.model
        # A child must still reference a readable original thread at launch.
        if((Test-CodexContinuationPolicy $job) -and [int]$job.retryAttempt -gt 0){
            Assert-CodexConversationAvailable -SessionId ([string]$job.sessionId)
        }
        Assert-ModelEffortSupported (Read-CodexModelCatalog) $model ([string]$job.effort)
        # Every invocation rechecks the pinned workspace and quota before
        # execution. Only explicitly opted-in, verified quota exhaustion may
        # register one bounded future continuation; unrelated failures stop.
        if (-not (Test-CanonicalWorkspaceIdentity ([string]$job.accountId))) {
            throw 'Scheduled job lacks verified workspace identity. Refresh usage and reschedule.'
        }
        $state = Read-UsageState $model
        if (-not (Test-CanonicalWorkspaceIdentity ([string]$state.accountId)) -or
            [string]$job.accountId -cne [string]$state.accountId) {
            throw 'Selected workspace identity is unavailable or changed; scheduled execution refused.'
        }
        if ($state.canAttempt -ne $true) {
            if(Try-DeferCodexQuotaJob -Job $job -JobFile $JobFile -AppDirectory $appDir -RuntimeDirectory $RuntimeDirectory -Quota $state -ExitCode 1){return 0}
            $message = if ($state.blockedReason) { [string]$state.blockedReason } else { 'Codex reports usage unavailable for the selected model.' }
            Set-CodexRunOutcome -JobFile $JobFile -Status 'blocked' -ExitCode 1 -Attempt ([int]$job.retryAttempt) -Message $message
            Write-Host $message -ForegroundColor Yellow
            return 1
        }
        # Both execution modes inherit the same verified identity, branch,
        # quota and session mutex. Only the Codex UI/transport differs.
        $codex = (Get-Command codex.cmd -ErrorAction Stop).Source
        [void](New-Item -Path $AppDirectory -ItemType Directory -Force -ErrorAction Stop)
        $PSNativeCommandUseErrorActionPreference = $false
        if($executionMode -eq 'shared'){
            # The PowerShell worker retains the per-thread mutex and Task
            # Scheduler's full lifetime while one App Server owns the turn.
            # The GUI's control client connects over an authenticated local
            # pipe; it must never start a second Codex instance.
            $controller=Join-Path $RuntimeDirectory 'components/SharedCodex/SharedController.js'
            $cli=Get-CodexCliJs
            & (Get-Command node.exe -ErrorAction Stop).Source $controller $JobFile $cli
            $result=$LASTEXITCODE
            if([int]$result -eq 0){
                Set-CodexRunOutcome -JobFile $JobFile -Status 'completed' -ExitCode 0 -Attempt ([int]$job.retryAttempt) -Message 'Shared App Server confirmed turn/completed with completed status.'
                return 0
            }
            Set-CodexRunOutcome -JobFile $JobFile -Status 'failed' -ExitCode ([int]$result) -Attempt ([int]$job.retryAttempt) -Message 'Shared App Server turn did not complete; inspect the shared controller state.'
            return 1
        }
        if($executionMode -eq 'terminal'){
            # The interactive TUI MUST inherit real stdin/stdout/stderr:
            # piping through Tee-Object would prevent prompts and approvals.
            $argsList=@('resume','-m',$model,'-c',"model_reasoning_effort=$($job.effort)",'-C',$root)
            switch ($job.access) {
                'yolo'            { $argsList += '--dangerously-bypass-approvals-and-sandbox' }
                'workspace-write' { $argsList += @('--sandbox','workspace-write') }
                'read-only'       { $argsList += @('--sandbox','read-only') }
            }
            $argsList+=@([string]$job.sessionId,[string]$job.message)
            Write-Host 'Starting interactive Codex in this terminal. Questions and approvals appear here.' -ForegroundColor Cyan
            $result=Invoke-CodexTerminal -CliEntry (Get-CodexCliJs) -Arguments $argsList
            Write-Host "Codex terminal exit code: $result" -ForegroundColor $(if($result -eq 0){'Green'}else{'Yellow'})
            if([int]$result -eq 0){
                # A TUI can exit voluntarily before the user-requested work
                # completes. Only the user can verify task completion.
                Set-CodexRunOutcome -JobFile $JobFile -Status 'finished' -ExitCode 0 -Attempt ([int]$job.retryAttempt) -Message 'Interactive Codex terminal exited; verify the conversation for completion.'
                return 0
            }
            Set-CodexRunOutcome -JobFile $JobFile -Status 'failed' -ExitCode ([int]$result) -Attempt ([int]$job.retryAttempt) -Message 'Interactive Codex exited unsuccessfully; check the terminal and conversation.'
            return [int]$result
        }
        # Legacy unattended execution remains byte-for-byte compatible with
        # existing background jobs and retains structured JSONL evidence.
        $argsList = @('exec','--json','-m',$model,'-c',"model_reasoning_effort=$($job.effort)",'-C',$root)
        if (-not $model) { $argsList = @('exec','--json','-c',"model_reasoning_effort=$($job.effort)",'-C',$root) }
        switch ($job.access) {
            'yolo'            { $argsList += '--dangerously-bypass-approvals-and-sandbox' }
            'workspace-write' { $argsList += @('--sandbox','workspace-write') }
            'read-only'       { $argsList += @('--sandbox','read-only') }
        }
        $argsList += @('resume', [string]$job.sessionId, [string]$job.message)
        $events = Join-Path $appDir (([IO.Path]::GetFileNameWithoutExtension($JobFile)) + '.jsonl')
        & $codex @argsList 2>&1 | Tee-Object -FilePath $events | Out-Host
        $result = $LASTEXITCODE
        Write-Host "Codex exit code: $result" -ForegroundColor $(if ($result -eq 0) { 'Green' } else { 'Yellow' })
        # An interactive Codex process does not hold our Scheduler mutex.
        # Report native thread-writer conflicts rather than a generic failure.
        if ($result -ne 0 -and (Select-String -LiteralPath $events -Pattern 'thread-store conflict|already has an active writer' -Quiet)) {
            $message = 'Codex reports an existing active writer for this conversation. Scheduled run blocked.'
            Set-CodexRunOutcome -JobFile $JobFile -Status 'blocked' -ExitCode ([int]$result) -Attempt ([int]$job.retryAttempt) -Message $message
            return [int]$result
        }
        if ([int]$result -eq 0) {
            Set-CodexRunOutcome -JobFile $JobFile -Status 'completed' -ExitCode 0 -Attempt ([int]$job.retryAttempt)
            return 0
        }
        if((Test-CodexContinuationPolicy $job) -and
           (Test-CodexTerminalQuotaFailure -EventsPath $events)){
            try {
                $postQuota=Read-UsageState $model
                if(Try-DeferCodexQuotaJob -Job $job -JobFile $JobFile -AppDirectory $appDir -RuntimeDirectory $RuntimeDirectory -Quota $postQuota -ExitCode ([int]$result)){return 0}
            }catch{Write-Warning "Quota verification failed after Codex exit: $($_.Exception.Message)"}
        }
        Set-CodexRunOutcome -JobFile $JobFile -Status 'failed' -ExitCode ([int]$result) -Message 'Codex exited unsuccessfully; no verified automatic continuation was registered.' -Attempt ([int]$job.retryAttempt)
        return [int]$result
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
        try { Set-CodexRunOutcome -JobFile $JobFile -Status 'failed' -ExitCode 1 -Attempt ([int]$job.retryAttempt) -Message $failure } catch { }
        return 1
    } finally {
        # Releasing the writer lock must not depend on transcript shutdown.
        # A failing Stop-Transcript is never allowed to strand ownership.
        if ($sessionGuard) {
            try { $sessionGuard.ReleaseMutex() }
            catch { Write-Warning "Worker session lock could not be released: $($_.Exception.Message)" }
            try { $sessionGuard.Dispose() }
            catch { Write-Warning "Worker session lock could not be disposed: $($_.Exception.Message)" }
        }
        if ($transcribing) {
            try { Stop-Transcript -ErrorAction Stop | Out-Null }
            catch { Write-Warning "Worker transcript could not be closed: $($_.Exception.Message)" }
        }
        Write-Host 'Run finished. Check the logs folder for the transcript.' -ForegroundColor Cyan
    }
}

