# Exercise the exact standalone .vbs shipped in the Aero hybrid ZIP.
# A hidden PowerShell process is insufficient: the Forms gallery must appear.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'Start-Native-Bar-Color-Lab.vbs'
$before = @(Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
$newPids = [System.Collections.Generic.HashSet[int]]::new()
$hostExe = Join-Path $env:WINDIR 'System32\wscript.exe'
try {
    $p = Start-Process -FilePath $hostExe -ArgumentList ('//B //Nologo "' + $launcher + '"') -PassThru
    if (-not $p.WaitForExit(6000)) { throw 'Windows Script Host did not return.' }
    if ($p.ExitCode -ne 0) { throw "Windows Script Host error: $($p.ExitCode)" }
    $opened = $false
    for($attempt=0;$attempt -lt 80;$attempt++) {
        $processes = @(Get-Process pwsh -ErrorAction SilentlyContinue |
            Where-Object { $_.Id -notin $before })
        foreach($candidate in $processes) {
            [void]$newPids.Add($candidate.Id)
            $candidate.Refresh()
            if($candidate.MainWindowTitle -eq 'v1.8 Windows bar + Aero Liquid (live comparison)') {
                $opened = $true
                break
            }
        }
        if($opened) { break }
        Start-Sleep -Milliseconds 150
    }
    if(-not $opened) { throw 'Aero hybrid double-click launcher did not display a window.' }
    Write-Host 'Actual Aero + native Windows color lab opened visibly from double-click launcher.'
} finally {
    foreach($processId in $newPids) {
        Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
}
