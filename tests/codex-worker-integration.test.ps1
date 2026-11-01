# End-to-end worker process tests with a local fake Codex CLI and App Server.
# Never contacts the user's account, creates Windows tasks, or runs real Codex.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexData.ps1')
. (Join-Path $root 'CodexRunEngine.ps1')
function Require($ok,[string]$message){if(-not $ok){throw $message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-worker-mock-' + [guid]::NewGuid().ToString('N'))
try {
    $bin=Join-Path $temp 'bin'
    $cliFolder=Join-Path $bin 'node_modules/@openai/codex/bin'
    [void](New-Item -ItemType Directory -Path $cliFolder -Force)
    $cli=Join-Path $cliFolder 'codex.js'
    @'
'use strict';
const fs=require('node:fs');
if(process.argv.includes('app-server')){
 const rl=require('node:readline').createInterface({input:process.stdin});
 rl.on('line',line=>{
  const m=JSON.parse(line);
  if(m.method==='initialize')process.stdout.write(JSON.stringify({id:m.id,result:{userAgent:'test'}})+'\n');
  if(m.method==='account/read')process.stdout.write(JSON.stringify({id:m.id,result:{account:{type:'chatgpt',email:'worker@example.test'}}})+'\n');
  if(m.method==='model/list')process.stdout.write(JSON.stringify({id:m.id,result:{data:[{model:'test-model',displayName:'Mock',defaultReasoningEffort:'high',supportedReasoningEfforts:[{reasoningEffort:'high'}],isDefault:true}],nextCursor:null}})+'\n');
  if(m.method==='account/rateLimits/read')process.stdout.write(JSON.stringify({id:m.id,result:{accountId:process.env.CODEX_STUB_ACCOUNT||'acct-1',ordinaryUsageAllowed:true,rateLimits:{limitId:'test-model',normalModelSlug:'test-model',primary:{usedPercent:0,resetsAt:Math.floor(Date.now()/1000)+3600,windowDurationMins:300}}}})+'\n');
 });
}else if(process.argv.includes('exec')){
 if(process.env.CODEX_STUB_MARKER)fs.writeFileSync(process.env.CODEX_STUB_MARKER,'executed');
 if(process.env.CODEX_STUB_EMIT_LIMIT==='1')console.log(JSON.stringify({type:'turn.failed',error:{message:'Usage limit exceeded'}}));
 else console.log(JSON.stringify({type:'turn.completed'}));
 process.exitCode=Number(process.env.CODEX_STUB_EXIT||0);
}else{process.exitCode=2;}
'@ | Set-Content -LiteralPath $cli -Encoding utf8
    $shim=Join-Path $bin 'codex.cmd'
    @'
@echo off
node "%~dp0node_modules\@openai\codex\bin\codex.js" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath $shim -Encoding ascii
    $repo=Join-Path $temp 'workspace'
    [void](New-Item -ItemType Directory -Path $repo -Force)
    & git -C $repo init --quiet -b feature
    if($LASTEXITCODE -ne 0){throw 'Failed to initialize isolated test repository.'}
    $repoRoot=([string](& git -C $repo rev-parse --show-toplevel)).Trim()
    $runtime=Publish-ImmutableRuntime -SourceDirectory $root -DestinationDirectory (Join-Path $temp 'runtimes') -RelativeFiles (Get-CodexRuntimeFiles)
    $fingerprint=$runtime.Fingerprint
    $jobPath=Join-Path $temp 'job.json'
    $marker=Join-Path $temp 'executed.marker'
    $settingsDir=Join-Path $temp 'isolated-appdata'
    [void](New-Item -ItemType Directory -Path $settingsDir -Force)

    function Run-CodexStub([int]$expectedExit,[bool]$auto,[string]$activeAccount,[bool]$emitLimit) {
        if(Test-Path $marker){Remove-Item -LiteralPath $marker -Force}
        [pscustomobject]@{
            sessionId='00000000-0000-0000-0000-000000000001'
            repo=$repoRoot;branch='feature';model='test-model';effort='high'
            access='read-only';message='Resume.';autoResume=$auto
            retryAttempt=0;accountId='acct-1';runtimeFingerprint=$fingerprint
            log=(Join-Path $temp 'worker.log')
        } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jobPath
        $psi=[Diagnostics.ProcessStartInfo]::new()
        $psi.FileName=(Get-Command pwsh.exe -ErrorAction Stop).Source
        foreach($argument in @('-NoLogo','-NoProfile','-File',(Join-Path $runtime.Directory 'CodexResumeScheduler.ps1'),'-RunJob','-JobFile',$jobPath)){
            [void]$psi.ArgumentList.Add($argument)
        }
        $psi.UseShellExecute=$false
        $psi.RedirectStandardOutput=$true
        $psi.RedirectStandardError=$true
        $psi.CreateNoWindow=$true
        $psi.Environment['PATH']="$bin;$env:PATH"
        $psi.Environment['LOCALAPPDATA']=$settingsDir
        $psi.Environment['CODEX_STUB_EXIT']=[string]$expectedExit
        $psi.Environment['CODEX_STUB_ACCOUNT']=$activeAccount
        $psi.Environment['CODEX_STUB_EMIT_LIMIT']=if($emitLimit){'1'}else{'0'}
        $psi.Environment['CODEX_STUB_MARKER']=$marker
        $proc=[Diagnostics.Process]::Start($psi)
        try{
            if(-not $proc.WaitForExit(20000)){
                try{$proc.Kill($true)}catch{}
                throw 'Isolated worker exceeded twenty seconds.'
            }
            $output=$proc.StandardOutput.ReadToEnd()
            $errors=$proc.StandardError.ReadToEnd()
            return [pscustomobject]@{ Exit=[int]$proc.ExitCode;Executed=(Test-Path $marker);Output=$output;Errors=$errors }
        }finally{$proc.Dispose()}
    }

    $ok=Run-CodexStub 0 $false 'acct-1' $false
    Require ($ok.Exit -eq 0 -and $ok.Executed) "Successful Codex execution must return zero: $($ok.Output) $($ok.Errors)"
    $failed=Run-CodexStub 17 $false 'acct-1' $false
    Require ($failed.Exit -eq 17 -and $failed.Executed) "CLI exit 17 must be preserved, not reported as success: $($failed.Output) $($failed.Errors)"
    $stale=Run-CodexStub 0 $true 'acct-1' $true
    Require ($stale.Exit -eq 0 -and $stale.Executed) "Success must override stale limit-like events: $($stale.Output) $($stale.Errors)"
    $changed=Run-CodexStub 0 $true 'different-account' $false
    Require ($changed.Exit -ne 0 -and -not $changed.Executed) "Wrong account must stop before invoking Codex: $($changed.Output) $($changed.Errors)"
    # A pinned runtime must fail closed after an existing dependency changes.
    Set-Content -LiteralPath (Join-Path $runtime.Directory 'CodexRetry.js') -Value 'tampered'
    $tampered=Run-CodexStub 0 $false 'acct-1' $false
    Require ($tampered.Exit -ne 0 -and -not $tampered.Executed) "Modified scheduled runtime must fail before Codex: $($tampered.Output) $($tampered.Errors)"
    Write-Host 'Isolated pinned worker: success, exit 17, stale error, identity and tampering PASS.'
}finally{
    if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
