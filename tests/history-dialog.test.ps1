# Exercise actual result-history dialog through the WinForms message loop.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexJobStore.ps1')
. (Join-Path $root 'CodexUiHistory.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('history-dialog-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -Path $temp -ItemType Directory -Force)
$owner=[System.Windows.Forms.Form]::new()
$timer=[System.Windows.Forms.Timer]::new()
$timer.Interval=120
$script:historySeen=$false
$script:historyError=''
$script:historyStart=Get-Date
try {
    [void](Write-JobOutcome -Path (Join-Path $temp 'CodexResume-20260101-1000-abcdef01.result.json') -Status 'completed' -ExitCode 0 -Message 'Complete.')
    [void](Write-JobOutcome -Path (Join-Path $temp 'CodexResume-20260101-1100-abcdef02.result.json') -Status 'deferred' -ExitCode 17 -Attempt 1 -NextJob 'CodexResume-20260101-1200-abcdef03' -Message 'Rescheduled.')
    '{corrupt' | Set-Content -LiteralPath (Join-Path $temp 'CodexResume-20260101-0900-abcdef04.result.json')
    $owner.Show()
    $timer.Add_Tick({
        $dialog=$null
        try {
            $dialog=@([System.Windows.Forms.Application]::OpenForms | Where-Object { $_.Text -like 'Recent Codex run results*' }) | Select-Object -First 1
            if(-not $dialog) {
                if((Get-Date)-gt $script:historyStart.AddSeconds(12)){$script:historyError='History dialog did not open.'}
                return
            }
            $grid=@($dialog.Controls | Where-Object { $_ -is [System.Windows.Forms.DataGridView] }) | Select-Object -First 1
            if(-not $grid -or $grid.Rows.Count -ne 3){throw 'History must render completed, deferred and unreadable rows.'}
            $statuses=@($grid.Rows | ForEach-Object { [string]$_.Cells['Status'].Value })
            foreach($status in @('completed','deferred','unreadable')){
                if($statuses -notcontains $status){throw "History omitted status $status"}
            }
            $next=@($grid.Rows | Where-Object { [string]$_.Cells['Status'].Value -eq 'deferred' })[0].Cells['NextJob'].Value
            if($next -ne 'CodexResume-20260101-1200-abcdef03'){throw 'History did not display the follow-up task.'}
            $script:historySeen=$true
        } catch {
            $script:historyError=$_.Exception.Message
        } finally {
            if($dialog){$dialog.Close()}
        }
    })
    $timer.Start()
    Show-CodexRunHistoryDialog -Owner $owner -Directory $temp
    if($script:historyError){throw $script:historyError}
    if(-not $script:historySeen){throw 'The history dialog did not render its persisted outcomes.'}
    Write-Host 'WinForms history dialog renders completed, deferred, unreadable and follow-up task PASS.'
} finally {
    $timer.Stop()
    $timer.Dispose()
    $owner.Dispose()
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
