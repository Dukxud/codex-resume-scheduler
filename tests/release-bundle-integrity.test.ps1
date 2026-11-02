# Tests both versioned ZIP distributions, path allowlists and post-build SHA256.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$tempRoot=if($env:RUNNER_TEMP){$env:RUNNER_TEMP}else{[IO.Path]::GetTempPath()}
$work=Join-Path $tempRoot ('aero-integrity-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $work -Force)
try {
  $one=& (Join-Path $root 'scripts/Package-CodexScheduler.ps1') -OutputDirectory $work -Preview |
    Where-Object {$_ -is [string] -and $_ -like '*.zip'} | Select-Object -Last 1
  $two=& (Join-Path $root 'scripts/Package-AeroComponent.ps1') -OutputDirectory $work -Preview |
    Where-Object {$_ -is [string] -and $_ -like '*.zip'} | Select-Object -Last 1
  $three=& (Join-Path $root 'scripts/Package-ReusableComponents.ps1') -OutputDirectory $work -Preview |
    Where-Object {$_ -is [string] -and $_ -like '*.zip'} | Select-Object -Last 1
  if(-not (Test-Path -LiteralPath $one) -or -not (Test-Path -LiteralPath $two) -or -not (Test-Path -LiteralPath $three)){throw 'Missing ZIP build outputs.'}
  $paths=@($one,$two,$three)
  foreach($zip in $paths){
    $target=Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($zip))
    Expand-Archive -LiteralPath $zip -DestinationPath $target -Force
    $manifest=@(Get-ChildItem -LiteralPath $target -Recurse -File -Filter 'SHA256SUMS.txt')
    if($manifest.Count -ne 1){throw 'Checksum manifest missing or duplicated.'}
    $base=Split-Path -Parent $manifest[0].FullName
    $checked=0
    foreach($line in [IO.File]::ReadAllLines($manifest[0].FullName)){
      if($line -notmatch '^([0-9a-f]{64})  (.+)$'){throw "Malformed checksum entry: $line"}
      $relative=$Matches[2]
      if($relative -match '(^/|^[A-Za-z]:|\.\.)'){throw 'Unsafe relative path in checksum manifest.'}
      $file=[IO.Path]::GetFullPath((Join-Path $base $relative))
      if(-not $file.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Checksum escaped the release root.'}
      if(-not [IO.File]::Exists($file)){throw "Missing manifest file: $relative"}
      if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Matches[1]){throw "Corrupt file: $relative"}
      $checked++
    }
    if($checked -lt 5){throw 'Suspiciously empty manifest.'}
    $actualFiles=@(Get-ChildItem -LiteralPath $base -Recurse -File | Where-Object {$_.Name -ne 'SHA256SUMS.txt'})
    if($actualFiles.Count -ne $checked){throw 'Extra files not inventoried in checksum manifest.'}
    if(-not (Test-Path (Join-Path $base 'UNSIGNED-REVIEW-ONLY.txt'))){throw 'Unsigned preview not labeled.'}
    if($zip -eq $one){
      foreach($file in @('CodexResumeScheduler.ps1','CodexRunJob.vbs','CodexUiState.ps1','CodexUiHistory.ps1','CodexJobStore.ps1',
        'CodexUiSelection.ps1','CodexUiPending.ps1','CodexUiUsage.ps1','components/AeroProgress/AeroProgress.psm1','tools/Get-SchedulerSecurityDiagnostics.ps1','docs/SECURITY-REVIEW.md','docs/ARCHITECTURE.md')){
        if(-not (Test-Path -LiteralPath (Join-Path $base $file))){throw "Missing scheduler release component: $file"}
      }
    }elseif($zip -eq $two){
      foreach($file in @('AeroProgress.psm1','AeroProgress.psd1','AeroBar.html','AeroWebView2/WebView2Loader.dll')){
        if(-not (Test-Path -LiteralPath (Join-Path $base $file))){throw "Missing reusable component: $file"}
      }
      if(Test-Path (Join-Path $base 'CodexResumeScheduler.ps1')){throw 'Reusable component includes scheduler core.'}
    }else{
      foreach($file in @(
        'components/README.md','components/AeroProgress/AeroProgress.psm1',
        'components/RuntimeBundle/RuntimeBundle.psm1','components/SettingsStore/SettingsStore.psm1',
        'components/ProgressHost/ProgressHost.psm1','components/WindowShell/WindowShell.psm1',
        'components/FlowingProgress/FlowingProgress.psm1',
        'components/GitRepository/GitRepository.psm1','components/JobOutcomes/JobOutcomes.psm1',
        'components/Countdown/Countdown.psm1','components/OneTimeTasks/OneTimeTasks.psm1',
        'components/AeroProgress/AeroWebView2/WebView2Loader.dll','components/AeroProgress/AeroBar.html')){
        if(-not (Test-Path -LiteralPath (Join-Path $base $file))){throw "Missing reusable module artifact: $file"}
      }
      if(Test-Path (Join-Path $base 'CodexResumeScheduler.ps1')){throw 'Reusable kit must not contain Codex or UI runtime.'}
    }
    Write-Host "$([IO.Path]::GetFileName($zip)): $checked files independently verified."
  }
}finally{
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
