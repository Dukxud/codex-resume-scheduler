Initialize-Dashboard

$autoRefresh = New-Object System.Windows.Forms.Timer
$autoRefresh.Interval = 60000
$autoRefresh.Add_Tick({
    try { Refresh-PendingList } catch { Update-Status "Pending refresh failed: $($_.Exception.Message)" }
    Request-UsageRefresh
})
$form.Add_Shown({
    [void][CodexScheduler.NativeWindow]::ShowWindow($form.Handle, 5) # SW_SHOW
    $form.Activate()
    $script:settingsReady = $true
    Update-DashboardLayout
    $script:countdownTimer.Start()
    try { Refresh-SessionList; Refresh-PendingList } catch { Update-Status "Startup warning: $($_.Exception.Message)" }
    Request-UsageRefresh
    $autoRefresh.Start()
    $dataPoll.Start()
})
$form.Add_FormClosing({
    $script:settingsTimer.Stop()
    try { Save-CurrentFormState } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not save preferences: $($_.Exception.Message)", 'Settings save error') | Out-Null
    }
})
$form.Add_FormClosed({
    $script:countdownTimer.Stop()
    $autoRefresh.Stop()
    $usagePoll.Stop()
    $dataPoll.Stop()
    foreach ($job in @($script:dataJobs.Values)) {
        try { Stop-Job -Job $job -ErrorAction SilentlyContinue; Remove-Job -Job $job -Force -ErrorAction SilentlyContinue } catch { }
    }
    if ($script:aeroHealthTimer) { $script:aeroHealthTimer.Stop(); $script:aeroHealthTimer.Dispose() }
    if ($script:usageProcess) {
        try { if (-not $script:usageProcess.HasExited) { $script:usageProcess.Kill($true) } } catch { }
        $script:usageProcess.Dispose()
        $script:usageProcess = $null
    }
})
[void]$form.ShowDialog()
$autoRefresh.Dispose()
$script:countdownTimer.Dispose()
$script:settingsTimer.Dispose()
$usagePoll.Dispose()
$dataPoll.Dispose()
$repoHints.Dispose()
$usageHints.Dispose()
$actionHints.Dispose()
$form.Dispose()
