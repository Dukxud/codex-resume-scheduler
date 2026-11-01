# Export AeroProgress independently of the scheduler.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,
      [switch]$Preview,
      [string]$CertificateThumbprint,
      [string]$TimestampServer)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if(-not $Preview -and (-not $CertificateThumbprint -or -not $TimestampServer)){throw 'Public component distribution requires an authenticated code-signing certificate.'}
$name="AeroProgress-Component-v$version" + $(if($Preview){'-Preview'}else{''})
$tempRoot=if($env:RUNNER_TEMP){$env:RUNNER_TEMP}else{[IO.Path]::GetTempPath()}
$folder=Join-Path $tempRoot $name
if(Test-Path $folder){Remove-Item -LiteralPath $folder -Recurse -Force}
[void](New-Item -ItemType Directory -Force -Path $folder)
foreach($file in @('AeroProgress.psm1','AeroProgress.psd1','README.md')){
    Copy-Item -LiteralPath (Join-Path $root "components/AeroProgress/$file") -Destination $folder
}
Copy-Item -LiteralPath (Join-Path $root 'assets/AeroBar.html') -Destination $folder
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $folder
Copy-Item -LiteralPath (Join-Path $root 'AeroWebView2') -Destination $folder -Recurse
if(-not $Preview){
    & (Join-Path $PSScriptRoot 'Sign-Release.ps1') -BundleDirectory $folder -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer
}else{
    [IO.File]::WriteAllText((Join-Path $folder 'UNSIGNED-REVIEW-ONLY.txt'),'Preview component is not publisher-signed. Use only for engineering review.',[Text.UTF8Encoding]::new($false))
}
& (Join-Path $PSScriptRoot 'Write-ReleaseHashes.ps1') -BundleDirectory $folder
[void](New-Item -ItemType Directory -Force -Path $OutputDirectory)
$archive=Join-Path $OutputDirectory "$name.zip"
Compress-Archive -Path $folder -DestinationPath $archive -Force
Write-Output $archive
