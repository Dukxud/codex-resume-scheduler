# Start the complete production entrypoint rather than an isolated dashboard mock.
# A responsive native Forms window must exist, not merely a live PowerShell process.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'CodexResumeScheduler.ps1'
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = (Get-Command pwsh.exe -ErrorAction Stop).Source
$start.WorkingDirectory = $root
foreach ($arg in @('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$app)) { [void]$start.ArgumentList.Add($arg) }
$start.UseShellExecute = $false
$start.RedirectStandardError = $true
$start.RedirectStandardOutput = $true
$start.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::new()
$p.StartInfo = $start
try {
    if (-not $p.Start()) { throw 'PowerShell GUI host did not start.' }
    $title = ''
    for ($i=0; $i -lt 90; $i++) {
        $p.Refresh()
        if ($p.HasExited) { break }
        $title = [string]$p.MainWindowTitle
        if ($title -match 'Codex Resume Scheduler v') { break }
        Start-Sleep -Milliseconds 150
    }
    $p.Refresh()
    if ($title -notmatch 'Codex Resume Scheduler v') {
        $info = if ($p.HasExited) { "exit=$($p.ExitCode)" } else { 'process alive but no GUI window' }
        if (-not $p.HasExited) { try { $p.Kill($true); $p.WaitForExit(4000) | Out-Null } catch {} }
        $errors = $p.StandardError.ReadToEnd()
        $output = $p.StandardOutput.ReadToEnd()
        throw "Full UI failed to open ($info); stderr: $errors; stdout: $output"
    }
    Write-Host "Full production GUI opened: $title"
} finally {
    if (-not $p.HasExited) { try { $p.Kill($true); $p.WaitForExit(4000) | Out-Null } catch {} }
    $p.Dispose()
}
