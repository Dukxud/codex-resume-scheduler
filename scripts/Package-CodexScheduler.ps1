# Deterministic, allowlisted Windows ZIP packaging. Production requires a
# trusted signing identity; preview builds are explicitly marked unsigned.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$Preview,
    [string]$CertificateThumbprint,
    [string]$TimestampServer
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid VERSION file.'}
if(-not $Preview -and (-not $CertificateThumbprint -or -not $TimestampServer)){
    throw 'Production releases require trusted -CertificateThumbprint and -TimestampServer. Refusing unsigned publication.'
}
$name="CodexResumeScheduler-v$version" + $(if($Preview){'-Preview'}else{''})
$folder=Join-Path $env:RUNNER_TEMP $name
if(Test-Path $folder){Remove-Item -LiteralPath $folder -Recurse -Force}
[void](New-Item -ItemType Directory -Path $folder -Force)
$files=@(
 'CodexResumeScheduler.ps1','CodexDashboard.ps1','CodexFlowingBar.ps1',
 'CodexAeroBar.ps1','CodexBarAppearance.ps1','CodexData.ps1',
 'CodexUsage.js','CodexRetry.js','Start-Codex-Scheduler.vbs',
 'Start-Codex-Scheduler.cmd','CodexRunJob.vbs','README.md','LICENSE','VERSION'
)
foreach($file in $files){
    $src=Join-Path $root $file
    if(-not (Test-Path -LiteralPath $src -PathType Leaf)){throw "Release file missing: $file"}
    Copy-Item -LiteralPath $src -Destination $folder
}
foreach($dir in @('assets','AeroWebView2','components')){
    $src=Join-Path $root $dir
    if(-not (Test-Path -LiteralPath $src -PathType Container)){throw "Release folder missing: $dir"}
    Copy-Item -LiteralPath $src -Destination $folder -Recurse
}
# A signed release MUST NOT ask PowerShell to bypass signature checks.
if(-not $Preview){
    foreach($launcher in @('Start-Codex-Scheduler.vbs','CodexRunJob.vbs')){
        $target=Join-Path $folder $launcher
        $contents=[IO.File]::ReadAllText($target)
        if(-not $contents.Contains(' -ExecutionPolicy Bypass')){throw "Release launcher contract changed: $launcher"}
        [IO.File]::WriteAllText($target,$contents.Replace(' -ExecutionPolicy Bypass',''),[Text.UTF8Encoding]::new($false))
    }
    & (Join-Path $PSScriptRoot 'Sign-Release.ps1') -BundleDirectory $folder -CertificateThumbprint $CertificateThumbprint -TimestampServer $TimestampServer
}else{
    [IO.File]::WriteAllText((Join-Path $folder 'UNSIGNED-REVIEW-ONLY.txt'),@'
PREVIEW — NOT AUTHENTICODE SIGNED
This is an engineering/test build. The existing Windows Script Host launcher
still invokes PowerShell with an execution-policy override; this is one source
of antivirus suspicion. Do not disable Bitdefender or add broad exclusions.
For production distribution, use a publisher-signed build.
'@,[Text.UTF8Encoding]::new($false))
}
# Hash after signing; hashes are not themselves a publisher signature.
& (Join-Path $PSScriptRoot 'Write-ReleaseHashes.ps1') -BundleDirectory $folder
[void](New-Item -ItemType Directory -Force -Path $OutputDirectory)
$archive=Join-Path $OutputDirectory "$name.zip"
Compress-Archive -Path $folder -DestinationPath $archive -Force
Write-Output $archive
