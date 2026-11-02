# The independently importable module must never need a scheduler app context.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$manifest=Join-Path $root 'components/AeroProgress/AeroProgress.psd1'
$module=Import-Module $manifest -PassThru -Force -ErrorAction Stop
if($module.Name -ne 'AeroProgress'){throw 'Unexpected module identity.'}
$expected=@('Test-AeroProgressColor','Test-AeroProgressSupport','New-AeroProgressView','Set-AeroProgressViewState','Get-AeroProgressViewStatus')
foreach($cmd in $expected){
  if(-not (Get-Command $cmd -Module AeroProgress -ErrorAction SilentlyContinue)){throw "Reusable API missing: $cmd"}
}
foreach($valid in @('green','blue','red','#00ff90','#BADA55')){
  if(-not (Test-AeroProgressColor $valid)){throw "Rejected valid color: $valid"}
}
foreach($invalid in @('','url(data:)','#FFFF','../../evil','#12345678','rgb(0,0,0)','green;stop')){
  if($invalid -and (Test-AeroProgressColor $invalid)){throw "Accepted invalid color: $invalid"}
}
$unsupported=Test-AeroProgressSupport -SdkDirectory (Join-Path $env:TEMP 'no-such-sdk') -AssetPath (Join-Path $env:TEMP 'missing.html')
if($unsupported.Available -or -not $unsupported.Reason){throw 'Missing dependencies must fail closed.'}
$support=Test-AeroProgressSupport -SdkDirectory (Join-Path $root 'AeroWebView2') -AssetPath (Join-Path $root 'assets/AeroBar.html')
if(-not $support.Available){throw "Expected Microsoft WebView2 SDK and renderer: $($support.Reason)"}
# Production release must not silently package unsigned scripts.
$didFail=$false
try{
  & (Join-Path $root 'scripts/Package-CodexScheduler.ps1') -OutputDirectory (Join-Path $env:TEMP 'not-produced')
}catch{
  $didFail=$_.Exception.Message -match 'Production releases require'
}
if(-not $didFail){throw 'Production packaging did not enforce certificate requirement.'}
Write-Host 'Independent AeroProgress module, allowed colors, absent dependency and signing gate PASS.'
