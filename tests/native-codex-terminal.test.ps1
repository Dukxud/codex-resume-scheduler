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
# Blank/failed CLI version reporting is diagnostic only: a detected
# executable plus a terminal host is enough to attempt native TUI launch.
if(-not (Test-ContinuumPreviewReadiness -CliPresent $true -WindowsTerminalPresent $true -PowerShellPresent $false)){
 throw 'A detected Codex executable with Windows Terminal must permit a preview attempt.'
}
if(-not (Test-ContinuumPreviewReadiness -CliPresent $true -WindowsTerminalPresent $false -PowerShellPresent $true)){
 throw 'Default-terminal fallback must permit a preview attempt without wt.exe.'
}
if((Test-ContinuumPreviewReadiness -CliPresent $false -WindowsTerminalPresent $true -PowerShellPresent $true)){
 throw 'A missing Codex executable was incorrectly accepted.'
}
if((Test-ContinuumPreviewReadiness -CliPresent $true -WindowsTerminalPresent $false -PowerShellPresent $false)){
 throw 'Missing terminal hosts were incorrectly accepted.'
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
$fallback=Get-ContinuumDefaultTerminalScript -Codex 'C:\Program Files\Codex\codex.cmd' -SessionId $id -Repository 'C:\QA\Project Alpha'
if($fallback -notmatch [regex]::Escape("'C:\Program Files\Codex\codex.cmd'") -or
   $fallback -notmatch [regex]::Escape("Set-Location -LiteralPath 'C:\QA\Project Alpha'") -or
   $fallback -notmatch [regex]::Escape("resume '$id'") -or
   $fallback -match '\bfork\b|\bexec\b'){
   throw 'Default-console fallback did not preserve the native TUI, identity or quoting.'
}
$apostrophe=Get-ContinuumDefaultTerminalScript -Codex 'C:\QA\It''s Tool\codex.cmd' -SessionId $id -Repository 'C:\QA\It''s Repo'
if($apostrophe -notmatch [regex]::Escape("'C:\QA\It''s Repo'") -or
   $apostrophe -notmatch [regex]::Escape("'C:\QA\It''s Tool\codex.cmd'")){
   throw 'Default-console fallback lost literal apostrophe escaping.'
}
Write-Host 'Native Codex TUI preview: parser, exact-session resume, safe Windows Terminal and default-console argument encoding PASS.' -ForegroundColor Green
