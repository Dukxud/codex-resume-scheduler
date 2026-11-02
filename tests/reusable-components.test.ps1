# Exercise generic modules without loading the Codex application or GUI.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'components/RuntimeBundle/RuntimeBundle.psm1') -Force
Import-Module (Join-Path $root 'components/SettingsStore/SettingsStore.psm1') -Force
Import-Module (Join-Path $root 'components/Countdown/Countdown.psm1') -Force
function Require($ok,[string]$message){if(-not $ok){throw $message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-components-' + [guid]::NewGuid().ToString('N'))
try{
    $source=Join-Path $temp 'source'
    [void](New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force)
    $file=Join-Path $source 'nested/runner.ps1'
    Set-Content -LiteralPath $file -Value "Write-Host 'first'"
    $snapshot=Publish-ImmutableRuntime -SourceDirectory $source -DestinationDirectory (Join-Path $temp 'runtimes') -RelativeFiles @('nested/runner.ps1')
    Require ($snapshot.Fingerprint -match '^[a-f0-9]{64}$') 'Runtime must be addressed by full SHA-256.'
    Assert-RuntimeFingerprint -Directory $snapshot.Directory -RelativeFiles @('nested/runner.ps1') -ExpectedFingerprint $snapshot.Fingerprint
    $same=Publish-ImmutableRuntime -SourceDirectory $source -DestinationDirectory (Join-Path $temp 'runtimes') -RelativeFiles @('nested/runner.ps1')
    Require ($same.Directory -eq $snapshot.Directory) 'Unchanged source must reuse a snapshot.'
    Set-Content -LiteralPath $file -Value "Write-Host 'second'"
    $new=Publish-ImmutableRuntime -SourceDirectory $source -DestinationDirectory (Join-Path $temp 'runtimes') -RelativeFiles @('nested/runner.ps1')
    Require ($new.Directory -ne $snapshot.Directory) 'Updated source must not overwrite the original runtime.'
    Assert-RuntimeFingerprint -Directory $snapshot.Directory -RelativeFiles @('nested/runner.ps1') -ExpectedFingerprint $snapshot.Fingerprint
    Set-Content -LiteralPath (Join-Path $snapshot.Directory 'nested/runner.ps1') -Value 'tampered'
    $rejected=$false
    try{Assert-RuntimeFingerprint -Directory $snapshot.Directory -RelativeFiles @('nested/runner.ps1') -ExpectedFingerprint $snapshot.Fingerprint}catch{$rejected=$true}
    Require $rejected 'Mutated runtime must be refused.'
    $rejected=$false
    try{[void](Get-RuntimeFingerprint -Directory $source -RelativeFiles @('../outside.ps1'))}catch{$rejected=$true}
    Require $rejected 'Runtime paths must not escape their source directory.'

    $settings=Join-Path $temp 'prefs/settings.json'
    Write-JsonSettings -Path $settings -Value ([pscustomobject]@{Count=3;Enabled=$false})
    $read=Read-JsonSettings -Path $settings
    Require ($read.Count -eq 3 -and $read.Enabled -eq $false) 'Settings did not round-trip.'
    Set-Content -LiteralPath $settings -Value '{invalid'
    Require ($null -eq (Read-JsonSettings -Path $settings)) 'Malformed JSON must be treated as unavailable.'

    $now=[datetime]'2027-01-01T10:00:00'
    Require ((Get-CountdownText -DueAt $now.AddMinutes(5) -Now $now) -eq '5m 0s') 'Countdown label incorrect.'
    Require ((Get-CountdownElapsedPercent -DueAt $now -CreatedAt $null -Now $now) -eq $null) 'Missing start must remain unknown.'
    # UTC and local instants must produce identical countdowns even when the
    # host is in a non-UTC timezone. Avoid subtracting local wall-clock ticks.
    $utc=[datetime]::SpecifyKind([datetime]'2026-11-01T05:30:00',[DateTimeKind]::Utc)
    $local=$utc.ToLocalTime()
    Require ((Get-CountdownText -DueAt $utc.AddHours(2) -Now $local) -eq '2h 0m') 'Mixed UTC/local instants were compared as wall-clock values.'
    $epoch=[DateTimeOffset]::new($utc).ToUnixTimeSeconds()
    $elapsed=Get-CountdownElapsedPercent -DueAt $utc.AddHours(2) -CreatedAt $epoch -Now $utc.AddHours(1).ToLocalTime()
    Require ($elapsed -eq 50) 'Elapsed progress must be computed in UTC, not local wall-clock hours.'
    Write-Host 'Independent runtime, settings and timezone-safe countdown components PASS.'
}finally{
    if(Test-Path $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
