# Flutter Windows adapter. JSON-in/JSON-out; no UI globals or shared server.
# The existing verified worker owns all execution and account safety checks.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('load','labels','pending','usage','select','schedule','cancel','evidence','hide','save','browse','interactiveStatus','interactiveRespond','interactiveSteer')][string]$Action,
    [string]$Payload = ''
)
$ErrorActionPreference='Stop'
try {
    $source=Split-Path -Parent $PSScriptRoot
    $appDir=Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
    # ConvertFrom-Json otherwise turns ISO strings into DateTime and loses the
    # exact wire format. PowerShell 7.5+ can explicitly preserve JSON strings.
    # Older PowerShell 7 versions retain the already-parsed local DateTime below.
    $request=if($Payload){
        $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload))
        if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){
            ConvertFrom-Json -InputObject $json -DateKind String -ErrorAction Stop
        }else{
            ConvertFrom-Json -InputObject $json -ErrorAction Stop
        }
    }else{[pscustomobject]@{}}
    . (Join-Path $source 'CodexRunEngine.ps1')
    . (Join-Path $source 'CodexData.ps1')
    . (Join-Path $source 'CodexRunActivity.ps1')
    # Presentation-only labels: preserve the WinForms session reader and its
    # full stable IDs, while making the Flutter chooser distinguish projects.
    function Get-FlutterSessionChoices {
        param([switch]$IncludeActivity)
        $choices=@(Get-RecentCliSessions)
        $threads=@{}
        if($IncludeActivity -and $choices.Count){
            # Use one metadata-only Codex App Server for all session titles.
            # This is optional presentation work, never a scheduling authority.
            try {
                $shim=(Get-Command codex.cmd -ErrorAction Stop).Source
                $cli=Join-Path (Split-Path -Parent $shim) 'node_modules\@openai\codex\bin\codex.js'
                $helper=Join-Path $source 'CodexUsage.js'
                if((Test-Path -LiteralPath $cli -PathType Leaf) -and
                   (Test-Path -LiteralPath $helper -PathType Leaf)){
                    $ids=@($choices | ForEach-Object { [string]$_.Id })
                    $lines=@(& node.exe $helper --cli-js $cli --thread-ids ($ids -join ','))
                    if($LASTEXITCODE -eq 0 -and $lines.Count){
                        $reply=($lines | Select-Object -Last 1) |
                            ConvertFrom-Json -AsHashtable -ErrorAction Stop
                        if($reply.ok -eq $true -and $reply.threads -is [System.Collections.IDictionary]){
                            $threads=$reply.threads
                        }
                    }
                }
            }catch{
                # Use local user activity or stable folder/time identity below.
            }
        }
        $rootCache=@{}
        foreach($session in $choices){
            try {
                $cwd=[string]$session.Cwd
                $root=$null
                if(-not [string]::IsNullOrWhiteSpace($cwd)){
                    if(-not $rootCache.ContainsKey($cwd)){
                        $rootCache[$cwd]=Get-RepositoryRoot $cwd
                    }
                    $root=$rootCache[$cwd]
                }
                $folder=if($cwd){Split-Path -Leaf ($cwd.TrimEnd([char[]]@('/','\')))}else{'unknown folder'}
                $title=if($root){
                    'Git: '+(Split-Path -Leaf ($root.TrimEnd([char[]]@('/','\'))))
                }else{'Outside Git: '+$folder}
                $when=(Get-Item -LiteralPath $session.File -ErrorAction Stop).LastWriteTime
                $id=[string]$session.Id
                $date=$when.ToString('d MMM HH:mm',[Globalization.CultureInfo]::InvariantCulture)
                # Activity excerpts are optional. Never scan large live Codex
                # rollouts as part of the critical startup data load.
                $activity=$null
                if($IncludeActivity){
                    $detail=if($threads.Contains($id)){$threads[$id]}else{$null}
                    if($detail -and $detail.name){
                        $activity=Format-CodexSessionTitle -Title ([string]$detail.name) -AllowShort
                    }
                    if(-not $activity -and $detail -and $detail.preview){
                        $activity=Format-CodexSessionTitle -Title ([string]$detail.preview) -AllowShort
                    }
                    if(-not $activity){
                        $activity=Get-CodexSessionActivity -SessionFile ([string]$session.File)
                    }
                }
                $identity=('{0} | {1} | {2}' -f $title,$date,$id.Substring($id.Length-8))
                $session.Display=if($activity){$activity+' | '+$identity}else{$identity}
            }catch{
                # A disappearing/invalid session file must not hide the choice.
                # Its original reader label remains usable.
            }
            $session
        }
    }
    function Get-CodexPickerPreview {
        param([Parameter(Mandatory)][string]$SessionId)
        # Non-mutating metadata. This is optional and must never bypass Git
        # verification or a conflicting repository result.
        try {
            $shim=(Get-Command codex.cmd -ErrorAction Stop).Source
            $cli=Join-Path (Split-Path -Parent $shim) 'node_modules\@openai\codex\bin\codex.js'
            $helper=Join-Path $source 'CodexUsage.js'
            if(-not (Test-Path -LiteralPath $cli -PathType Leaf) -or
               -not (Test-Path -LiteralPath $helper -PathType Leaf)){return $null}
            $lines=@(& node.exe $helper --cli-js $cli --thread-ids $SessionId)
            if($LASTEXITCODE -ne 0 -or -not $lines.Count){return $null}
            $data=($lines | Select-Object -Last 1) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if($data.ok -ne $true -or -not $data.threads.Contains($SessionId)){return $null}
            return [string]$data.threads[$SessionId].preview
        }catch{return $null}
    }
    function Get-FlutterHistory {
        param([object[]]$Tasks=@())
        $recentTasks=@($Tasks)
        $records=@(Get-CodexRunHistory -Directory $appDir -Limit 100)
        $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach($entry in $records){[void]$known.Add([string]$entry.Name)}
        $hidden=Get-HiddenCodexRunNames -Directory $appDir
        foreach($task in $recentTasks){
            $name=[string]$task.Name
            if($task.Status -in @('Scheduled','Running') -or $known.Contains($name) -or $hidden.Contains($name)){continue}
            $records+= [pscustomobject]@{
                Name=$name;When=$task.When;Status=$task.Status;ExitCode=$null
                Attempt=$null;NextJob='';Message='Windows Task Scheduler record; no saved worker outcome available.'
            }
            [void]$known.Add($name)
        }
        return @($records | Sort-Object When -Descending)
    }
    # Only running Scheduler jobs expose their own event summaries. There
    # are no extra processes or raw command/output disclosures in the poll.
    function Get-FlutterRunActivities {
        param([object[]]$Tasks=@())
        $activities=@{}
        foreach($task in @($Tasks | Where-Object { $_.Status -eq 'Running' } |
                Select-Object -First 8)){
            $name=[string]$task.Name
            if($name -cmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){
                $activities[$name]=Get-CodexRunActivity -Directory $appDir -Name $name
            }
        }
        return $activities
    }
    function Invoke-InteractiveOwnerClient {
        param([string]$Name,[string]$Operation,$InputData=$null)
        if($Name -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){
            throw 'Invalid interactive job identity.'
        }
        $descriptor=Join-Path $appDir ($Name+'.interactive.json')
        if(-not (Test-Path -LiteralPath $descriptor -PathType Leaf)){
            if($Operation -eq 'snapshot'){return @{available=$false;reason='No interactive owner is active.'}}
            throw 'Interactive owner is unavailable; no answer was sent.'
        }
        $task=Get-ScheduledTask -TaskName $Name -ErrorAction Stop
        if($task.State -ne 'Running'){
            throw 'Scheduler is not running this interactive owner; request refused.'
        }
        $helper=Join-Path $source 'interactive/owner-client.js'
        if(-not (Test-Path -LiteralPath $helper -PathType Leaf)){throw 'Interactive bridge is unavailable.'}
        $node=(Get-Command node.exe -ErrorAction Stop).Source
        $argsList=@($helper,'--descriptor',$descriptor,'--action',$Operation)
        $PSNativeCommandUseErrorActionPreference=$false
        $lines=if($null -eq $InputData){
            @(& $node @argsList)
        }else{
            $body=$InputData | ConvertTo-Json -Depth 20 -Compress
            @($body | & $node @argsList)
        }
        if($LASTEXITCODE -ne 0 -or -not $lines){
            $last=if($lines){($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction SilentlyContinue}else{$null}
            throw $(if($last -and $last.error){[string]$last.error}else{'Interactive owner request failed.'})
        }
        $reply=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
        if($reply.ok -ne $true){throw 'Interactive owner did not confirm the operation.'}
        return $reply.result
    }
    $result=$null
    switch($Action){
        'load' {
            $tasks=@(Get-UpcomingCodexTasks -AppDirectory $appDir)
            $result=@{
                sessions=@(Get-FlutterSessionChoices)
                pending=$tasks
                activities=(Get-FlutterRunActivities -Tasks $tasks)
                history=@(Get-FlutterHistory -Tasks $tasks)
                settings=Read-CodexUiSettings $appDir
                logDirectory=$appDir
            }
        }
        'labels' {
            $result=@{sessions=@(Get-FlutterSessionChoices -IncludeActivity)}
        }
        'pending' {
            $tasks=@(Get-UpcomingCodexTasks -AppDirectory $appDir)
            $result=@{
                pending=$tasks
                activities=(Get-FlutterRunActivities -Tasks $tasks)
                history=@(Get-FlutterHistory -Tasks $tasks)
            }
        }
        'usage' {
            $model=[string]$request.model
            if($model -and $model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$'){throw 'Invalid model identifier.'}
            $helper=Join-Path $source 'CodexUsage.js'
            $cli=Get-CodexCliJs
            $arguments=@($helper,'--cli-js',$cli)
            if($model){$arguments+=@('--model',$model)}
            $lines=@(& node.exe @arguments)
            if($LASTEXITCODE -ne 0 -or -not $lines){throw 'Codex account and model query failed.'}
            $snapshot=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
            if(-not $snapshot.ok){throw "Codex usage unavailable: $($snapshot.error)"}
            $result=$snapshot
        }
        'select' {
            $id=[string]$request.sessionId
            $session=@(Get-RecentCliSessions | Where-Object { $_.Id -ceq $id }) | Select-Object -First 1
            if(-not $session){throw 'Selected CLI conversation could not be verified.'}
            $cwd=Get-ReportedThreadDirectory -SessionId $id -SourceFolder $source
            $found=Find-SessionRepository -Session $session -ReportedCwd $cwd -AppDirectory $appDir
            if(-not $found){
                # The title query already knows which CLI session is selected;
                # the picker preview may retain its explicit project heading
                # when the rollout format lacks event_msg/user_message records.
                $preview=Get-CodexPickerPreview -SessionId $id
                if($preview){
                    $found=Find-SessionRepository -Session $session -ReportedCwd $cwd -AppDirectory $appDir -CodexPreview $preview
                }
            }
            $result=@{sessionId=$id;model=Read-SessionModel $session;found=$found}
        }
        'schedule' {
            if($null -ne $request.autoResumeOnLimit -and $request.autoResumeOnLimit -isnot [bool]){throw 'Invalid automatic-continuation option.'}
            $sessionId=[string]$request.sessionId
            if($sessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){throw 'Invalid session ID.'}
            # Validate the actual Flutter wall-clock value before any lookup or
            # mutation. Reject UTC/offset inputs, which are not local times.
            $when=[datetime]::MinValue
            $runAt=$request.runAt
            if($runAt -is [datetime]){
                if($runAt.Kind -ne [DateTimeKind]::Unspecified){throw 'Invalid local run time.'}
                $when=$runAt
            }elseif($runAt -isnot [string] -or -not [datetime]::TryParseExact(
                    $runAt,'yyyy-MM-ddTHH:mm:ss',
                    [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None,[ref]$when)){
                throw 'Invalid local run time.'
            }
            if($when -lt (Get-Date).AddSeconds(30)){throw 'Choose a time at least 30 seconds ahead.'}
            if([TimeZoneInfo]::Local.IsAmbiguousTime($when) -or [TimeZoneInfo]::Local.IsInvalidTime($when)){
                throw 'Run time is ambiguous or nonexistent due to daylight saving time.'
            }
            if(-not @(Get-RecentCliSessions | Where-Object { $_.Id -ceq $sessionId }).Count){throw 'Selected CLI session not verified.'}
            $root=Get-RepositoryRoot ([string]$request.repo).Trim().Trim('"')
            if(-not $root){throw 'Choose an existing Git repository.'}
            $branchName=Get-RepositoryBranch $root
            $model=[string]$request.model
            $effort=[string]$request.effort
            if($model -cnotmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$'){throw 'Invalid model.'}
            if($effort -cnotmatch '^[a-zA-Z][a-zA-Z0-9_-]{0,40}$'){throw 'Invalid reasoning effort.'}
            $access=[string]$request.access
            if($access -cnotin @('workspace-write','read-only','yolo')){throw 'Invalid access mode.'}
            if($access -eq 'yolo' -and $request.confirmUnrestricted -ne $true){throw 'Explicit unrestricted-access confirmation required.'}
            $executionMode=if($request.executionMode){[string]$request.executionMode}else{'unattended'}
            if($executionMode -cnotin @('unattended','interactive')){throw 'Invalid execution mode.'}
            if($executionMode -eq 'interactive'){
                if($access -eq 'yolo'){throw 'Interactive mode requires approval-capable permissions.'}
                if($request.autoResumeOnLimit -eq $true){throw 'Automatic quota continuation is not supported in interactive mode.'}
            }
            $policy=if($request.autoResumeOnLimit -eq $true){
                @{schema=1;mode='quota-only';maxContinuations=3}
            }else{$null}
            $message=([string]$request.message).Trim()
            if(-not $message){throw 'Enter an instruction.'}
            # Register only with a fresh model-specific catalog and verified workspace.
            $helper=Join-Path $source 'CodexUsage.js'
            $cli=Get-CodexCliJs
            $lines=@(& node.exe $helper --cli-js $cli --model $model)
            if($LASTEXITCODE -ne 0 -or -not $lines){throw 'Live Codex account verification failed.'}
            $usage=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
            if(-not $usage.ok -or $usage.catalogError){throw 'Live model catalog or quota unavailable; scheduling is disabled.'}
            Assert-ModelEffortSupported -Models @($usage.models) -Model $model -Effort $effort
            if($usage.model -cne $model){throw 'Quota response does not match the chosen model.'}
            if(-not (Test-CanonicalWorkspaceIdentity ([string]$usage.accountId))){throw 'Workspace identity could not be verified.'}
            # Matching WinForms v1.16: a future task may be registered while
            # current quota is exhausted. The pinned worker independently
            # fails closed if quota is still unavailable at execution time.
            $upcoming=@(Get-UpcomingCodexTasks -AppDirectory $appDir | Where-Object { $_.Status -in @('Running','Scheduled') })
            if(@($upcoming | Where-Object {$_.Status -eq 'Running' -and $_.Session -ceq $sessionId}).Count){
                throw 'This conversation is already running in a Scheduler worker.'
            }
            $overlap=@($upcoming | Where-Object { $_.Repo -ne '-' -and $_.Repo.TrimEnd([char[]]@('/','\')) -ieq $root.TrimEnd([char[]]@('/','\')) })
            if($overlap.Count -gt 0 -and $request.confirmOverlap -ne $true){
                throw "Repository has $($overlap.Count) upcoming job(s). Confirm possible overlap first."
            }
            [void](New-Item -Path $appDir -ItemType Directory -Force)
            $runtime=Publish-ImmutableRuntime -SourceDirectory $source -DestinationDirectory (Join-Path $appDir 'runtimes') -RelativeFiles (Get-CodexRuntimeFiles)
            $name='CodexResume-' + $when.ToString('yyyyMMdd-HHmm') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,8))
            $jobFilePath=Join-Path $appDir ($name+'.json')
            $log=Join-Path $appDir ($name+'.log')
            [pscustomobject]@{
                sessionId=$sessionId;repo=$root;branch=$branchName;model=$model
                effort=$effort;access=$access;message=$message;executionMode=$executionMode
                continuationPolicy=$policy;retryAttempt=0
                createdAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                accountId=[string]$usage.accountId;runtimeFingerprint=$runtime.Fingerprint;log=$log
            } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jobFilePath -Encoding utf8
            $runner=Join-Path $runtime.Directory 'CodexRunJob.vbs'
            $arguments=Get-CodexTaskArguments -Runner $runner -JobFile $jobFilePath
            try {
                [void](Register-OneTimeTask -Name $name -At $when -Executable (Join-Path $env:WINDIR 'System32\wscript.exe') -Arguments $arguments -WorkingDirectory $root -Description "Codex session $sessionId ($branchName)")
            }catch{
                if(-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)){
                    Remove-Item -LiteralPath $jobFilePath -Force -ErrorAction SilentlyContinue
                }
                throw
            }
            $result=@{name=$name;status='Scheduled'}
        }
        'interactiveStatus' {
            $result=Invoke-InteractiveOwnerClient -Name ([string]$request.name) -Operation 'snapshot'
        }
        'interactiveRespond' {
            if([string]$request.id -cnotmatch '^[0-9]{1,15}$'){throw 'Invalid prompt ID.'}
            if($request.response -isnot [pscustomobject]){throw 'Missing interactive answer.'}
            $result=Invoke-InteractiveOwnerClient -Name ([string]$request.name) -Operation 'respond' -InputData @{
                kind='respond';id=[string]$request.id;response=$request.response
            }
        }
        'interactiveSteer' {
            $text=[string]$request.text
            if(-not $text.Trim() -or $text.Length -gt 16000){throw 'Invalid interactive message.'}
            $result=Invoke-InteractiveOwnerClient -Name ([string]$request.name) -Operation 'steer' -InputData @{
                kind='steer';text=$text
            }
        }
        'cancel' {
            $name=[string]$request.name
            if($name -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){throw 'Invalid Scheduler task name.'}
            Remove-OneTimeTask -Name $name -OnlyBeforeStart
            $warning=''
            $payloadPath=Join-Path $appDir ($name+'.json')
            if(Test-Path -LiteralPath $payloadPath -PathType Leaf){
                try {
                    [void](Write-JobOutcome -Path ([IO.Path]::ChangeExtension($payloadPath,'.result.json')) -Status 'cancelled' -Message 'Cancelled by operator before execution.')
                    Remove-Item -LiteralPath $payloadPath -Force -ErrorAction Stop
                }catch{$warning=$_.Exception.Message}
            }
            $result=@{name=$name;status='Cancelled';warning=$warning}
        }
        'evidence' {
            $name=[string]$request.name
            if($name -cnotmatch '^(?:CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}|BP[0-9]+-Codex-(?:Resume|Test))$'){
                throw 'Invalid history identifier.'
            }
            $result=Get-CodexRunEvidence -Directory $appDir -Name $name
        }
        'hide' {
            $name=[string]$request.name
            Hide-CodexRunRecord -Directory $appDir -Name $name
            $result=@{hidden=$name}
        }
        'save' {
            $draft=$request.draft
            if(-not $draft){throw 'No draft supplied.'}
            $access=[string]$draft.access
            if($access -cnotin @('workspace-write','read-only','yolo')){throw 'Invalid access mode.'}
            if($null -ne $draft.autoResumeOnLimit -and $draft.autoResumeOnLimit -isnot [bool]){throw 'Invalid saved quota continuation option.'}
            $mode=if($draft.executionMode){[string]$draft.executionMode}else{'unattended'}
            if($mode -cnotin @('unattended','interactive')){throw 'Invalid saved execution mode.'}
            foreach($flag in @('microMode','alwaysOnTop')){
                if($null -ne $request.$flag -and $request.$flag -isnot [bool]){throw "Invalid window preference: $flag"}
            }
            $previous=Read-CodexUiSettings $appDir
            $safeDraft=[pscustomobject]@{
                sessionId=[string]$draft.sessionId;repo=[string]$draft.repo
                model=[string]$draft.model;effort=[string]$draft.effort
                access=$access;message=[string]$draft.message;runAt=[string]$draft.runAt
                autoResumeOnLimit=($draft.autoResumeOnLimit -eq $true);executionMode=$mode
            }
            $appearance=if($request.barAppearance){$request.barAppearance}elseif($previous){$previous.barAppearance}else{$null}
            if($appearance){
                $validColors=@('green','blue','cyan','violet','amber','red')
                foreach($kind in @('quota','weekly','time','working')){
                    $color=[string]$appearance.$kind
                    if($color -cnotin $validColors -and $color -cnotmatch '^#[0-9a-fA-F]{6}$'){
                        throw "Invalid appearance color for $kind."
                    }
                }
                foreach($kind in @('finish','lighting')){
                    if($appearance.$kind -notin @(0,1,2)){throw "Invalid appearance $kind."}
                }
                if($appearance.shimmer -isnot [int] -and $appearance.shimmer -isnot [long]){throw 'Reflection strength must be integral.'}
                if([int]$appearance.shimmer -lt 0 -or [int]$appearance.shimmer -gt 200){throw 'Invalid reflection strength.'}
                if($appearance.speed -isnot [int] -and $appearance.speed -isnot [long]){throw 'Reflection speed must be integral.'}
                if([int]$appearance.speed -lt 25 -or [int]$appearance.speed -gt 300){throw 'Invalid reflection speed.'}
                if($appearance.aero -isnot [bool]){throw 'Invalid Aero Liquid setting.'}
            }
            $settings=[pscustomobject]@{
                version=1;lastAccess=$access
                compactMode=($request.compactMode -eq $true -or $request.microMode -eq $true)
                microMode=($request.microMode -eq $true)
                alwaysOnTop=($request.alwaysOnTop -eq $true)
                barAppearance=$appearance
                draft=$safeDraft
            }
            Write-CodexUiSettings -Directory $appDir -State $settings
            $result=@{saved=$true}
        }
        'browse' {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog=[Windows.Forms.FolderBrowserDialog]::new()
            $dialog.Description='Select the Git repository for this conversation'
            try {
                $result=if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
                    $root=Get-RepositoryRoot ([string]$dialog.SelectedPath)
                    if(-not $root){throw 'Select a folder inside an existing Git repository.'}
                    @{path=[string]$root}
                }else{@{path=''}}
            }finally{$dialog.Dispose()}
        }
    }
    [Console]::Out.WriteLine((@{ok=$true;result=$result} | ConvertTo-Json -Depth 20 -Compress))
} catch {
    [Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Depth 6 -Compress))
    exit 1
}
