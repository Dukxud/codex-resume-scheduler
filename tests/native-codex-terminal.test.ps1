# A read-only feasibility gate: no session launch, no tasks and no account access.
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/Probe-NativeCodexTerminal.ps1'
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ('Native terminal probe PowerShell syntax invalid: ' + ($errors -join '; '))}
. $path
$scriptText=Get-Content -LiteralPath $path -Raw
if($scriptText -notmatch 'OpenSaved' -or $scriptText -notmatch 'Assert-NoScheduledConversationOwner'){
    throw 'Saved-conversation preview omitted the owner safety gate.'
}
$id='11111111-2222-3333-4444-555555555555'
$argsList=@(Get-ContinuumTerminalArguments -Codex 'C:\Program Files\Codex\codex.cmd' -SessionId $id -Repository 'C:\QA\Project Alpha')
if($argsList -ccontains 'fork' -or $argsList -ccontains 'exec' -or
    @($argsList | Where-Object { $_ -ceq 'resume' }).Count -ne 1 -or
    @($argsList | Where-Object { $_ -ceq $id }).Count -ne 1){
    throw 'Preview must resume the original thread, not fork, exec, or submit a prompt.'
}
if($argsList -cnotcontains '"C:\QA\Project Alpha"' -or
   $argsList -cnotcontains '"C:\Program Files\Codex\codex.cmd"'){
    throw 'Windows paths with spaces were not quoted.'
}
foreach($unsafe in @('../other','11111111-2222-3333-4444-555555555555 && whoami')){
    $rejected=$false
    try {[void](Get-ContinuumTerminalArguments -Codex 'codex.cmd' -SessionId $unsafe -Repository 'C:\QA\Project Alpha')}
    catch{$rejected=$true}
    if(-not $rejected){throw 'Unsafe or noncanonical Codex identity accepted.'}
}
$rejected=$false
try{[void](Quote-ContinuumArgument 'test"inject')}
catch{$rejected=$true}
if(-not $rejected){throw 'Untrusted quote accepted in terminal command.'}
Write-Host 'Native Codex TUI preview: parser, exact-session resume, safe Windows argument encoding PASS.' -ForegroundColor Green
