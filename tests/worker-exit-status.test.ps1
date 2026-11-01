# Failures in the actual shipped entrypoint must propagate as nonzero process status.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$work=Join-Path ([IO.Path]::GetTempPath()) ('codex-worker-status-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work -Force)
try {
    $jobFile=Join-Path $work 'invalid-job.json'
    '{}' | Set-Content -LiteralPath $jobFile
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=(Get-Command pwsh.exe -ErrorAction Stop).Source
    foreach($arg in @('-NoLogo','-NoProfile','-File',(Join-Path $root 'CodexResumeScheduler.ps1'),'-RunJob','-JobFile',$jobFile)){[void]$psi.ArgumentList.Add($arg)}
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $proc=[Diagnostics.Process]::Start($psi)
    if(-not $proc.WaitForExit(20000)){try{$proc.Kill($true)}catch{};throw 'Worker test timed out.'}
    $stderr=$proc.StandardError.ReadToEnd()
    $stdout=$proc.StandardOutput.ReadToEnd()
    if($proc.ExitCode -ne 1){throw "Invalid worker job must exit 1, got $($proc.ExitCode). stdout=$stdout stderr=$stderr"}
    Write-Host 'Worker entrypoint propagates failure status to Windows Script Host.'
}finally{
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
