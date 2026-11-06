# Nonmutating capability probe; explicit -Open may start the native Codex TUI.
[CmdletBinding(DefaultParameterSetName='Probe')]
param(
 [Parameter(Mandatory,ParameterSetName='Open')][switch]$Open,
 [Parameter(Mandatory,ParameterSetName='OpenSaved')][switch]$OpenSaved,
 [Parameter(Mandatory,ParameterSetName='StatusSaved')][switch]$StatusSaved,
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
function Quote-ContinuumPowerShellLiteral {
 param([Parameter(Mandatory)][string]$Value)
 if($Value.IndexOfAny([char[]]@([char]0,[char]10,[char]13)) -ge 0){
   throw 'Unsupported control character in terminal argument.'
 }
 return "'" + $Value.Replace("'","''") + "'"
}
function Get-ContinuumDefaultTerminalScript {
 param([string]$Codex,[string]$SessionId,[string]$Repository)
 # Reuse the exact-session and absolute-directory validation of the
 # Windows Terminal command before constructing the PowerShell fallback.
 [void](Get-ContinuumTerminalArguments -Codex $Codex -SessionId $SessionId -Repository $Repository)
 $directory=Quote-ContinuumPowerShellLiteral $Repository
 $program=Quote-ContinuumPowerShellLiteral $Codex
 $identity=Quote-ContinuumPowerShellLiteral $SessionId
 return "Set-Location -LiteralPath $directory; & $program -C $directory resume $identity"
}
# The preflight is informational; native Codex ownership remains authoritative.
# A ready job with no result still reserves the original conversation.
function Get-ContinuumConversationReservations {
 param([Parameter(Mandatory)][string]$SessionId,
       [Parameter(Mandatory)][string]$Directory)
 $reservations=[Collections.Generic.List[object]]::new()
 foreach($task in @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
    $_.TaskName -cmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[a-fA-F0-9]{8}$' })){
    if($task.State -notin @('Ready','Running','Queued')){continue}
    $jobFile=Join-Path $Directory ($task.TaskName+'.json')
    if(-not (Test-Path -LiteralPath $jobFile -PathType Leaf)){continue}
    try{
      $job=Get-Content -LiteralPath $jobFile -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    }catch{
      throw "Scheduler job metadata unreadable: $($task.TaskName)"
    }
    if([string]$job.sessionId -cne $SessionId){continue}
    $outcome=Join-Path $Directory ($task.TaskName+'.result.json')
    if($task.State -in @('Running','Queued') -or
       -not (Test-Path -LiteralPath $outcome -PathType Leaf)){
      $reservations.Add([pscustomobject]@{
        Job=$task.TaskName
        State=[string]$task.State
        Reason=if($task.State -eq 'Running'){'Running job'}else{'Pending or unreconciled job'}
      })
    }
 }
 return @($reservations.ToArray())
}
function Assert-NoScheduledConversationOwner {
 param([Parameter(Mandatory)][string]$SessionId,
       [Parameter(Mandatory)][string]$Directory)
 $reservations=@(Get-ContinuumConversationReservations -SessionId $SessionId -Directory $Directory)
 if($reservations.Count){
   $first=$reservations[0]
   throw "BLOCKED: $($first.Job) ($($first.State)) owns or reserves this conversation. A hidden worker cannot be reattached by starting another Codex TUI. Do not retry until the job has ended."
 }
}

$codexCommand=Get-Command codex.cmd -ErrorAction SilentlyContinue
$terminalCommand=Get-Command wt.exe -ErrorAction SilentlyContinue
$powerShellExecutable=Join-Path $PSHOME 'pwsh.exe'
# Version is diagnostic metadata, not evidence that a terminal may start.
# Codex builds can emit it on either stream, and a missing version string
# must never override an otherwise valid executable/terminal discovery.
$version=$null
$versionCheck='not checked'
if($codexCommand){
 try {
   $versionLines=@(& $codexCommand.Source --version 2>&1)
   $versionExitCode=$LASTEXITCODE
   $version=($versionLines | ForEach-Object { [string]$_ } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -First 1)
   $versionCheck=if($versionExitCode -eq 0){'exit 0'}else{"exit $versionExitCode"}
 }catch{
   $versionCheck='unavailable: '+$_.Exception.Message
 }
}
$check=[ordered]@{
 CodexCli=if($codexCommand){$codexCommand.Source}else{$null}
 CodexVersion=$version
 VersionProbe=$versionCheck
 WindowsTerminal=if($terminalCommand){$terminalCommand.Source}else{$null}
 DefaultTerminalHost=$powerShellExecutable
 LaunchMethod=if($terminalCommand){'Windows Terminal'}else{'Windows default console application'}
 SupportedForPreview=(Test-ContinuumPreviewReadiness -CliPresent ($null -ne $codexCommand) -WindowsTerminalPresent ($null -ne $terminalCommand) -PowerShellPresent (Test-Path -LiteralPath $powerShellExecutable -PathType Leaf))
 RunningOwnerCanBeAttached=$false
}
if(-not $Open -and -not $OpenSaved -and -not $StatusSaved){[pscustomobject]$check;return}
if($OpenSaved -or $StatusSaved){
 $settingsPath=Join-Path (Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler') 'settings.json'
 if(-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)){
   throw 'Continuum has no saved conversation selection.'
 }
 $saved=Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
 $SessionId=[string]$saved.draft.sessionId
 $Repository=[string]$saved.draft.repo
 if(-not $SessionId -or -not $Repository){throw 'Select a conversation and repository in Continuum first.'}
}
if($StatusSaved){
  $reservations=@(Get-ContinuumConversationReservations -SessionId $SessionId -Directory (Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'))
  [pscustomobject]@{
    Status=if($reservations.Count){'BLOCKED'}elseif($check.SupportedForPreview){'ELIGIBLE_FOR_PREVIEW'}else{'UNAVAILABLE'}
    Reservation=$reservations
    RunningOwnerCanBeAttached=$false
    Detail=if($reservations.Count){'Do not launch a second writer. Preserve the scheduled work.'}elseif($check.SupportedForPreview){'Native launcher can be tried when no other Codex writer owns the thread.'}else{'Required Codex or terminal executable missing.'}
  }
  return
}
if(-not $codexCommand){throw 'Codex CLI not found: codex.cmd is not available on this PowerShell PATH.'}
if(-not $check.SupportedForPreview){throw 'No supported terminal host: neither wt.exe nor PowerShell 7 is available.'}
$root=(& git -C $Repository rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if($LASTEXITCODE -ne 0 -or -not $root){throw 'Selected directory is not a Git repository.'}
$full=[IO.Path]::GetFullPath($Repository).TrimEnd([char[]]@('/','\'))
$actual=[IO.Path]::GetFullPath([string]$root).TrimEnd([char[]]@('/','\'))
if($full -ine $actual){throw 'Provide the verified repository root, not a subfolder.'}
Assert-NoScheduledConversationOwner -SessionId $SessionId -Directory (Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler')
if($terminalCommand){
  $argsList=Get-ContinuumTerminalArguments -Codex $codexCommand.Source -SessionId $SessionId -Repository $actual
  [void](Start-Process -FilePath $terminalCommand.Source -ArgumentList ($argsList -join ' ') -PassThru -ErrorAction Stop)
  Write-Host 'Codex TUI requested in Windows Terminal.' -ForegroundColor Green
}else{
  # Windows Terminal is optional. Opening a new console process uses the
  # terminal application configured by Windows; it retains the normal
  # PowerShell profile and Codex TUI, not a raw-log viewer.
  $script=Get-ContinuumDefaultTerminalScript -Codex $codexCommand.Source -SessionId $SessionId -Repository $actual
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  [void](Start-Process -FilePath $powerShellExecutable -WorkingDirectory $actual -ArgumentList @(
    '-NoLogo','-NoExit','-EncodedCommand',$encoded) -PassThru -ErrorAction Stop)
  Write-Host 'Codex TUI requested in the Windows default console application (wt.exe alias not found).' -ForegroundColor Green
}
Write-Host 'Original conversation requested; no prompt submitted and no fork.' -ForegroundColor Green
