# Standalone reusable-kit ZIP: independent PowerShell modules, no scheduler runtime.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$OutputDirectory,
      [switch]$Preview,
      [string]$CertificateThumbprint,
      [string]$TimestampServer)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid VERSION file.'}
if(-not $Preview -and (-not $CertificateThumbprint -or -not $TimestampServer)){
    throw 'Standalone production components require verified code signing.'
}
$name="ReusableComponents-v$version" + $(if($Preview){'-Preview'}else{''})
$tempRoot=if($env:RUNNER_TEMP){$env:RUNNER_TEMP}else{[IO.Path]::GetTempPath()}
$folder=Join-Path $tempRoot $name
if(Test-Path $folder){Remove-Item -LiteralPath $folder -Recurse -Force}
[void](New-Item -ItemType Directory -Path $folder -Force)
Copy-Item -LiteralPath (Join-Path $root 'components') -Destination $folder -Recurse
# Make each module folder independently portable: AeroProgress carries its
# renderer and the required Microsoft SDK DLLs beside its own module.
$aeroFolder=Join-Path $folder 'components/AeroProgress'
Copy-Item -LiteralPath (Join-Path $root 'AeroWebView2') -Destination $aeroFolder -Recurse
Copy-Item -LiteralPath (Join-Path $root 'assets/AeroBar.html') -Destination (Join-Path $aeroFolder 'AeroBar.html')
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $folder
Copy-Item -LiteralPath (Join-Path $root 'VERSION') -Destination $folder
if(-not $Preview){
    & (Join-Path $PSScriptRoot 'Sign-Release.ps1') -BundleDirectory $folder -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer
}else{
    [IO.File]::WriteAllText((Join-Path $folder 'UNSIGNED-REVIEW-ONLY.txt'),'Standalone components engineering preview: scripts are not publisher-signed.',[Text.UTF8Encoding]::new($false))
}
& (Join-Path $PSScriptRoot 'Write-ReleaseHashes.ps1') -BundleDirectory $folder
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$archive=Join-Path $OutputDirectory "$name.zip"
Compress-Archive -Path $folder -DestinationPath $archive -Force
Write-Output $archive
