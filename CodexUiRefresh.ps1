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
                'selection' {
                    if ($script:ui.Selection.selectionJobGeneration -ne $script:ui.Selection.selectionGeneration) { break }
                    $info = $result | Select-Object -First 1
                    if (-not $info -or -not $sessionBox.SelectedItem -or $info.Id -ne $sessionBox.SelectedItem.Id) { break }
                    if ($info.Model -and (Get-SelectedModel) -eq $script:ui.Selection.selectionOriginalModel -and
                        -not ($script:ui.Selection.startupSavedModelId -and $script:ui.Selection.startupSavedSessionId -eq [string]$sessionBox.SelectedItem.Id)) {
                        $script:ui.Selection.preferredSessionModel = [string]$info.Model
                        $chosen = @($modelBox.Items | Where-Object { $_.Id -eq $info.Model }) | Select-Object -First 1
                        if ($chosen) { $modelBox.SelectedItem = $chosen; Select-AvailableEfforts }
                    }
                    if ($info.Found -and $info.Found.Root) {
                        # A user-entered root takes precedence over a late asynchronous lookup.
                        if (-not [string]::IsNullOrWhiteSpace($repoBox.Text)) { break }
                        $repoBox.Text = [string]$info.Found.Root
                        $otherRoots = @($info.Found.AlternativeRoots | Where-Object { $_ })
                        if ($otherRoots.Count -gt 0) {
                            $detail = "Codex reported: $($info.Found.Root)`nOther checkout(s): $($otherRoots -join '; ')`nChoose Browse to override."
                            $repoHints.SetToolTip($repoBox, $detail)
                            $repoHints.SetToolTip($status, $detail)
                            Update-Status "Codex: $($info.Found.Root) | Other: $($otherRoots -join '; ') (hover for details)"
                        } else {
                            $repoHints.SetToolTip($repoBox, "From $($info.Found.Source): $($info.Found.Root)")
                            Update-Status "Repository: $($info.Found.Root) ($($info.Found.Source))"
                        }
                    } elseif ($info.Found -and @($info.Found.Candidates).Count -gt 1) {
                        $detail = "Conflicting fallback checkouts: $(@($info.Found.Candidates) -join '; ')`nChoose Browse to select the active checkout."
                        $repoHints.SetToolTip($repoBox, $detail)
                        $repoHints.SetToolTip($status, $detail)
                        Update-Status "Conflicting roots: $(@($info.Found.Candidates) -join '; ') (hover for details)"
                    } else { Update-Status 'Repository could not be identified. Use Browse.' }
                }
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

$script:ui.Usage.usageSnapshot = $null
$script:ui.Usage.usageRequestedModel = ''
$script:ui.Usage.usageSnapshotRequestedModel = ''
$script:ui.Usage.usageReadFailed = $false
$script:ui.Usage.usageProcess = $null
$script:ui.Usage.usageStarted = [datetime]::MinValue
$script:ui.Usage.usageRefreshQueued = $false
$script:ui.Usage.usageChecked = [datetime]::MinValue
