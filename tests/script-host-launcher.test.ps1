# Real Windows smoke test: WScript launches PowerShell with no visible console,
# preserves the scheduled job exit code, and supports the GUI's async entrypoint.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$folder = Join-Path ([IO.Path]::GetTempPath()) ('codex-wscript-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -Path $folder -ItemType Directory -Force)
try {
    foreach ($name in @('Start-Codex-Scheduler.vbs','CodexRunJob.vbs')) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $folder $name)
    }
    $job = Join-Path $folder 'job.json'
    '{}' | Set-Content -LiteralPath $job -Encoding utf8
    $out = Join-Path $folder 'observed.json'
    $stub = @'
param([switch]$RunJob,[string]$JobFile)
$decl = @"
using System;
using System.Runtime.InteropServices;
public static class WindowProbe {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@
Add-Type -TypeDefinition $decl
$handle = [WindowProbe]::GetConsoleWindow()
$visible = ($handle -ne [IntPtr]::Zero) -and [WindowProbe]::IsWindowVisible($handle)
[pscustomobject]@{ Job = [bool]$RunJob; VisibleConsole = [bool]$visible } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'observed.json') -Encoding utf8
if ($RunJob) { exit 17 }
'@
    Set-Content -LiteralPath (Join-Path $folder 'CodexResumeScheduler.ps1') -Value $stub -Encoding utf8
    $hostExe = Join-Path $env:WINDIR 'System32\wscript.exe'
    $script = Join-Path $folder 'CodexRunJob.vbs'
    $arguments = '//B //Nologo "' + $script + '" "' + $job + '"'
    $proc = Start-Process -FilePath $hostExe -ArgumentList $arguments -Wait -PassThru
    if ($proc.ExitCode -ne 17) { throw "Scheduled wrapper lost the worker exit code ($($proc.ExitCode))." }
    $result = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
    if (-not $result.Job -or $result.VisibleConsole) { throw 'Scheduled run failed to execute invisibly.' }
    Remove-Item -LiteralPath $out -Force
    $startup = Join-Path $folder 'Start-Codex-Scheduler.vbs'
    $startProc = Start-Process -FilePath $hostExe -ArgumentList ('//B //Nologo "' + $startup + '"') -Wait -PassThru
    if ($startProc.ExitCode -ne 0) { throw 'GUI script-host entrypoint failed.' }
    for ($attempt = 0; $attempt -lt 50 -and -not (Test-Path $out); $attempt++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path $out)) { throw 'GUI host did not start a background PowerShell process.' }
    $result = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
    if ($result.Job -or $result.VisibleConsole) { throw 'GUI launcher must start without a visible console.' }
    Write-Host 'Script-host GUI and scheduled job are invisible; job exit status is preserved.'
} finally {
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}
