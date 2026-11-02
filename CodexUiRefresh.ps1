# Asynchronous Codex data-job dispatcher. Domain rendering lives in individual controllers.
function Start-DataRead {
    param([ValidateSet('sessions','pending','selection')][string]$Kind, $Session = $null)
    if ($script:ui.Selection.dataJobs[$Kind]) { $script:ui.Selection.dataQueued[$Kind] = $true; return }
    try {
        $sourceFolder = $PSScriptRoot
        $localAppDir = $appDir
        $job = Start-ThreadJob -ArgumentList @($sourceFolder,$localAppDir,$Kind,$Session) -ScriptBlock {
            param($Folder,$LocalAppDir,$Operation,$SelectedSession)
            $ErrorActionPreference = 'Stop'
            $appDir = $LocalAppDir
            $sessionIdPattern = '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            . (Join-Path $Folder 'CodexData.ps1')
            switch ($Operation) {
                'sessions'  { Get-RecentCliSessions }
                'pending'   { Get-UpcomingCodexTasks }
                'selection' {
                    $reportedCwd = Get-ReportedThreadDirectory ([string]$SelectedSession.Id) $Folder
                    [pscustomobject]@{ Id = [string]$SelectedSession.Id;
                        Model = Read-SessionModel $SelectedSession;
                        Found = Find-SessionRepository $SelectedSession $reportedCwd }
                }
            }
        }
        $script:ui.Selection.dataJobs[$Kind] = $job
        if ($Kind -eq 'selection') { $script:ui.Selection.selectionJobGeneration = $script:ui.Selection.selectionGeneration }
    } catch { Update-Status "$Kind refresh failed to start: $($_.Exception.Message)" }
}

function Refresh-SessionList { Start-DataRead 'sessions' }
function Refresh-PendingList { Start-DataRead 'pending' }

$dataPoll = New-Object System.Windows.Forms.Timer
$dataPoll.Interval = 250
$dataPoll.Add_Tick({
    foreach ($kind in @('sessions','pending','selection')) {
        $job = $script:ui.Selection.dataJobs[$kind]
        if (-not $job -or $job.State -notin @('Completed','Failed','Stopped')) { continue }
        $script:ui.Selection.dataJobs.Remove($kind)
        try {
            $result = @(Receive-Job -Job $job -ErrorAction Stop)
            switch ($kind) {
                'sessions' { Apply-SessionList $result }
                'pending' { Apply-PendingList $result }
                'selection' { Apply-SelectionResult $result }
            }
        } catch { Update-Status "$kind refresh failed: $($_.Exception.Message)" }
        finally { Remove-Job -Job $job -Force -ErrorAction SilentlyContinue }
        if ($script:ui.Selection.dataQueued[$kind]) {
            $script:ui.Selection.dataQueued[$kind] = $false
            if ($kind -eq 'selection') {
                if ($sessionBox.SelectedItem) { Start-DataRead 'selection' $sessionBox.SelectedItem }
            } else { Start-DataRead $kind }
        }
    }
})
