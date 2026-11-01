# Assemble exactly the same file set for preview and official releases.
# Microsoft's WebView2 signed libraries must have been staged by Prepare-AeroWebView2.ps1.
param(
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$Preview
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid VERSION file.' }
$name = "CodexResumeScheduler-v$version" + $(if ($Preview) { '-Preview' } else { '' })
$folder = Join-Path $env:RUNNER_TEMP $name
if (Test-Path $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
[void](New-Item -ItemType Directory -Path $folder -Force)
$files = @(
    'CodexResumeScheduler.ps1','CodexDashboard.ps1','CodexFlowingBar.ps1',
    'CodexAeroBar.ps1','CodexData.ps1','CodexUsage.js','CodexRetry.js',
    'Start-Codex-Scheduler.vbs','Start-Codex-Scheduler.cmd',
    'CodexRunJob.vbs','README.md','LICENSE','VERSION'
)
foreach($file in $files) {
    $source = Join-Path $root $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Release file missing: $file" }
    Copy-Item -LiteralPath $source -Destination $folder
}
foreach($dir in @('assets','AeroWebView2')) {
    $source = Join-Path $root $dir
    if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw "Release folder missing: $dir" }
    Copy-Item -LiteralPath $source -Destination $folder -Recurse
}
[void](New-Item -ItemType Directory -Force -Path $OutputDirectory)
$archive = Join-Path $OutputDirectory "$name.zip"
Compress-Archive -Path $folder -DestinationPath $archive -Force
Write-Output $archive