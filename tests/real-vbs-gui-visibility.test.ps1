# Exercise the shipped double-click VBS launcher and locate a visible GUI window.
# A running pwsh process is NOT sufficient; a hidden form caused the v1.10 regression.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'Start-Codex-Scheduler.vbs'
$before = @(Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$started = @()
try {
    $hostExe = Join-Path $env:WINDIR 'System32\wscript.exe'
    $hostProcess = Start-Process -FilePath $hostExe -ArgumentList ('//B //Nologo "' + $launcher + '"') -PassThru -Wait
    if ($hostProcess.ExitCode -ne 0) { throw "VBS entrypoint failed: $($hostProcess.ExitCode)" }
    $found = $null
    for ($i = 0; $i -lt 80; $i++) {
        $processes = @(Get-Process pwsh -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -notin $before })
        foreach ($p in $processes) {
            if ($started -notcontains $p.Id) { $started += $p.Id }
            $p.Refresh()
            if ($p.MainWindowTitle -like 'Codex Resume Scheduler v*') { $found = $p; break }
        }
        if ($found) { break }
        Start-Sleep -Milliseconds 150
    }
    if (-not $found) {
        $details = @($started | ForEach-Object {
            try { $p = Get-Process -Id $_ -ErrorAction Stop; "PID $_ title='$($p.MainWindowTitle)'" }
            catch { "PID $_ exited" }
        }) -join '; '
        throw "Double-click launcher did not display the scheduler window. Child processes: $details"
    }
    Write-Host "Visible application window from the real VBS launcher: $($found.MainWindowTitle)"
} finally {
    foreach ($processId in $started) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
}
