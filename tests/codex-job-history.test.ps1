# Adversarial history and saved-payload separation without Windows Forms.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexJobStore.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-history-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp -Force)
try {
    if(@(Get-CodexRunHistory -Directory $temp).Count -ne 0){throw 'Fresh installation must show empty history.'}
    $payload=Join-Path $temp 'CodexResume-20261101-1200-abc12345.json'
    '{"sessionId":"legacy"}' | Set-Content -LiteralPath $payload
    $result=Join-Path $temp 'CodexResume-20261101-1300-def12345.result.json'
    [void](Write-JobOutcome -Path $result -Status 'deferred' -Attempt 2 -ExitCode 17 -NextJob 'CodexResume-20261101-1400-abc43210' -Message 'Quota exhausted')
    $invalid=Join-Path $temp 'CodexResume-20261101-1201-bad33333.result.json'
    '{invalid-json' | Set-Content -LiteralPath $invalid
    $jobs=@(Get-CodexJobPayloadFiles -Directory $temp)
    if($jobs.Count -ne 1 -or $jobs[0].FullName -ne $payload){throw 'Result records polluted scheduled-job discovery.'}
    $history=@(Get-CodexRunHistory -Directory $temp -Limit 10)
    $deferred=@($history | Where-Object Status -eq 'deferred')
    $corrupt=@($history | Where-Object Status -eq 'unreadable')
    if($deferred.Count -ne 1 -or $deferred[0].NextJob -ne 'CodexResume-20261101-1400-abc43210' -or $deferred[0].ExitCode -ne 17){throw 'Deferred retry linkage was lost.'}
    if($corrupt.Count -ne 1){throw 'Unreadable results must not be silently hidden.'}
    if(@(Get-CodexRunHistory -Directory $temp -Limit 1).Count -ne 1){throw 'History limit ignored.'}
    Write-Host 'Result records, job discovery isolation, linked retries and corrupt-history visibility PASS.'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
