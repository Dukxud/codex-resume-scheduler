# Nonmutating capability probe; explicit -Open may start the native Codex TUI.
[CmdletBinding(DefaultParameterSetName='Probe')]
param(
 [Parameter(Mandatory,ParameterSetName='Open')][switch]$Open,
 [Parameter(Mandatory,ParameterSetName='OpenSaved')][switch]$OpenSaved,
 [Parameter(Mandatory,ParameterSetName='Open')][string]$SessionId,
 [Parameter(Mandatory,ParameterSetName='Open')][string]$Repository
)
$ErrorActionPreference='Stop'
function Quote-ContinuumArgument {
 param([Parameter(Mandatory)][string]$Value)
 if($Value.IndexOfAny([char[]]@([char]0,[char]10,[char]13,[char]34)) -ge 0){
    throw 'Unsupported character in terminal argument.'
 }
 return '"' + ($Value -replace '(\\+)$', '$1$1') + '"'
}
function Get-ContinuumTerminalArguments {
 param([string]$Codex,[string]$SessionId,[string]$Repository)
 if($SessionId -cnotmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){
    throw 'Invalid Codex session ID.'
 }
 if(-not [IO.Path]::IsPathFullyQualified($Repository)){
    throw 'The repository path must be absolute.'
 }
 return @('-w',('Continuum-'+$SessionId.Substring(0,8)), 'new-tab',
   '--title',(Quote-ContinuumArgument ('Codex '+$SessionId.Substring(0,8))),
   '-d',(Quote-ContinuumArgument $Repository),
   (Quote-ContinuumArgument $Codex),'-C',(Quote-ContinuumArgument $Repository),
   'resume',$SessionId)
}
function Assert-NoScheduledConversationOwner {
 param([string]$SessionId,[string]$Directory)
 foreach($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
    $_.TaskName -cmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[a-fA-F0-9]{8}$' })){
    if($task.State -notin @('Ready','Running','Queued')){continue}
    $jobFile=Join-Path $Directory ($task.TaskName+'.json')
    if(-not (Test-Path -LiteralPath $jobFile -PathType Leaf)){continue}
    try {
      $job=Get-Content -LiteralPath $jobFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch { throw "Scheduler job metadata unreadable: $($task.TaskName)" }
    if([string]$job.sessionId -cne $SessionId){continue}
    $result=Join-Path $Directory ($task.TaskName+'.result.json')
    if($task.State -eq 'Running' -or -not (Test-Path -LiteralPath $result -PathType Leaf)){
      throw "Conversation reserved by Scheduler job $($task.TaskName). Do not open a second writer."
    }
 }
}
$codexCommand=Get-Command codex.cmd -ErrorAction SilentlyContinue
$terminalCommand=Get-Command wt.exe -ErrorAction SilentlyContinue
$version=$null
if($codexCommand){
 $version=(& $codexCommand.Source --version 2>$null | Select-Object -First 1)
 if($LASTEXITCODE -ne 0){$version=$null}
}
$check=[ordered]@{
 CodexCli=if($codexCommand){$codexCommand.Source}else{$null}
 CodexVersion=$version
 WindowsTerminal=if($terminalCommand){$terminalCommand.Source}else{$null}
 SupportedForPreview=($null -ne $codexCommand -and $null -ne $terminalCommand -and [bool]$version)
 RunningOwnerCanBeAttached=$false
}
if(-not $Open -and -not $OpenSaved){[pscustomobject]$check;return}
if($OpenSaved){
 $settingsPath=Join-Path (Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler') 'settings.json'
 if(-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)){
   throw 'Continuum has no saved conversation selection.'
 }
 $saved=Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
 $SessionId=[string]$saved.draft.sessionId
 $Repository=[string]$saved.draft.repo
 if(-not $SessionId -or -not $Repository){throw 'Select a conversation and repository in Continuum first.'}
}
if(-not $check.SupportedForPreview){throw 'Codex CLI and Windows Terminal are required.'}
$root=(& git -C $Repository rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if($LASTEXITCODE -ne 0 -or -not $root){throw 'Selected directory is not a Git repository.'}
$full=[IO.Path]::GetFullPath($Repository).TrimEnd([char[]]@('/','\'))
$actual=[IO.Path]::GetFullPath([string]$root).TrimEnd([char[]]@('/','\'))
if($full -ine $actual){throw 'Provide the verified repository root, not a subfolder.'}
Assert-NoScheduledConversationOwner -SessionId $SessionId -Directory (Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler')
$argsList=Get-ContinuumTerminalArguments -Codex $codexCommand.Source -SessionId $SessionId -Repository $actual
[void](Start-Process -FilePath $terminalCommand.Source -ArgumentList ($argsList -join ' ') -PassThru -ErrorAction Stop)
Write-Host 'Native Codex TUI launch requested for the original conversation. No prompt submitted.' -ForegroundColor Green
