# OneTimeTasks exercised by an unrelated Windows app with isolated fake OS scheduler.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('independent-tasks-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -Path $temp -ItemType Directory -Force)
try {
    Copy-Item -LiteralPath (Join-Path $root 'components/OneTimeTasks') -Destination $temp -Recurse
    Import-Module (Join-Path $temp 'OneTimeTasks/OneTimeTasks.psd1') -Force
    $script:tasks=@{}
    $script:badRead=$false
    function global:New-ScheduledTaskAction {param($Execute,$Argument,$WorkingDirectory) [pscustomobject]@{Execute=$Execute;Arguments=$Argument;WorkingDirectory=$WorkingDirectory}}
    function global:New-ScheduledTaskTrigger {param([switch]$Once,$At) [pscustomobject]@{StartBoundary=$At}}
    function global:New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{LogonType=$LogonType}}
    function global:New-ScheduledTaskSettingsSet {param([switch]$StartWhenAvailable) 'settings'}
    function global:Register-ScheduledTask {
        [CmdletBinding()]
        param($TaskName,$Description,$Action,$Trigger,$Principal,$Settings)
        $script:tasks[$TaskName]=[pscustomobject]@{Actions=@($Action);Triggers=@($Trigger);Principal=$Principal;State='Ready'}
    }
    function global:Get-ScheduledTask {
        param($TaskName)
        if(-not $script:tasks.ContainsKey($TaskName)){throw 'Not found'}
        $task=$script:tasks[$TaskName]
        if($script:badRead){return [pscustomobject]@{Actions=@([pscustomobject]@{Execute='unexpected.exe';Arguments='';WorkingDirectory=$temp});Triggers=$task.Triggers;Principal=$task.Principal;State='Ready'}}
        return $task
    }
    function global:Unregister-ScheduledTask {param($TaskName,[switch]$Confirm) [void]$script:tasks.Remove($TaskName)}
    function global:Disable-ScheduledTask {param($TaskName) $script:tasks[$TaskName].State='Disabled'}
    $name=Register-OneTimeTask -Name 'Unrelated-Background-Job' -At (Get-Date).AddHours(2) -Executable (Get-Command pwsh.exe).Source -Arguments '-NoProfile -File worker.ps1' -WorkingDirectory $temp
    if($name -ne 'Unrelated-Background-Job' -or -not $script:tasks.ContainsKey($name)){throw 'Standalone registration failed.'}
    Disable-OneTimeTask -Name $name
    if($script:tasks[$name].State -ne 'Disabled'){throw 'Standalone disable failed.'}
    Remove-OneTimeTask -Name $name
    if($script:tasks.Count -ne 0){throw 'Standalone removal failed.'}
    $utcFuture=[DateTimeOffset]::UtcNow.AddHours(3).UtcDateTime
    $utcJob=Register-OneTimeTask -Name 'Utc-Example' -At $utcFuture -Executable (Get-Command pwsh.exe).Source -Arguments 'abc' -WorkingDirectory $temp
    $triggerTime=([datetime]$script:tasks[$utcJob].Triggers[0].StartBoundary).ToString('yyyy-MM-dd HH:mm')
    if($triggerTime -ne $utcFuture.ToLocalTime().ToString('yyyy-MM-dd HH:mm')){throw 'UTC instant was not normalized to the local task boundary.'}
    Remove-OneTimeTask -Name $utcJob
    $script:badRead=$true
    $failed=$false
    try{[void](Register-OneTimeTask -Name 'Rollback-Example' -At (Get-Date).AddHours(2) -Executable (Get-Command pwsh.exe).Source -Arguments 'abc' -WorkingDirectory $temp)}catch{$failed=$true}
    if(-not $failed -or $script:tasks.Count -ne 0){throw 'Validation mismatch must roll back OS registration.'}
    # If the Windows host uses daylight saving time, reject a repeated
    # local wall-clock time rather than scheduling the wrong occurrence.
    $zone=[TimeZoneInfo]::Local
    $checked=0
    if($zone.SupportsDaylightSavingTime){
        $candidate=[datetime]'2027-11-07T01:30:00'
        if($zone.IsAmbiguousTime($candidate)){
            $checked++
            $rejected=$false
            try{[void](Register-OneTimeTask -Name 'Ambiguous-Example' -At $candidate -Executable (Get-Command pwsh.exe).Source -Arguments 'abc' -WorkingDirectory $temp)}catch{$rejected=$true}
            if(-not $rejected){throw 'Repeated daylight-saving-time hour must be rejected.'}
        }
    }
    Write-Host "Standalone task registration, disable, removal, rollback and DST safety PASS ($checked transition checks)."
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue}}
