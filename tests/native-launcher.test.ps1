# Runtime proof that the GUI-subsystem launcher creates no console for the Codex worker.
# This uses a temporary no-op PowerShell script instead of a real Codex run.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root 'CodexScheduler.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'GUI-subsystem executable was not compiled.' }
$folder = Join-Path ([IO.Path]::GetTempPath()) ('codex-launcher-smoke-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder -Force)
try {
    Copy-Item -LiteralPath $exe -Destination (Join-Path $folder 'CodexScheduler.exe')
    $job = Join-Path $folder 'job.json'
    $output = Join-Path $folder 'no-console.json'
    '{}' | Set-Content -LiteralPath $job -Encoding utf8
    $stub = @'
param([switch]$RunJob, [string]$JobFile)
Add-Type -Namespace Native -Name Console -MemberDefinition '[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();'
[pscustomobject]@{
    IsJob = [bool]$RunJob
    HasConsole = ([Native.Console]::GetConsoleWindow() -ne [IntPtr]::Zero)
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'no-console.json') -Encoding utf8
'@
    Set-Content -LiteralPath (Join-Path $folder 'CodexResumeScheduler.ps1') -Value $stub -Encoding utf8
    $process = Start-Process -FilePath (Join-Path $folder 'CodexScheduler.exe') -ArgumentList @('--run-job',('"' + $job + '"')) -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Native launcher failed: $($process.ExitCode)" }
    if (-not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'Native GUI launcher did not run the worker script.' }
    $result = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    if (-not $result.IsJob) { throw 'Native host did not preserve scheduled-run arguments.' }
    if ($result.HasConsole) { throw 'Native child PowerShell allocated a console window.' }
    $bytes = [IO.File]::ReadAllBytes($exe)
    $pe = [BitConverter]::ToInt32($bytes,0x3c)
    $subsystem = [BitConverter]::ToUInt16($bytes,$pe+24+68)
    if ($subsystem -ne 2) { throw 'Launcher is not a Windows GUI-subsystem executable.' }
    Write-Host 'Native launcher is a Windows GUI executable; its scheduled child runs with no console.'
} finally {
    Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
}
