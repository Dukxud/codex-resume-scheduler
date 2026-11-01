# Fetch Microsoft's pinned, signed WebView2 SDK for test/release packaging.
# Do not run at application startup. Installed users receive these files in ZIP.
$ErrorActionPreference = 'Stop'
$version = '1.0.4314.35'
$root = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $root 'AeroWebView2'
[void](New-Item -ItemType Directory -Force -Path $folder)
$package = Join-Path $env:RUNNER_TEMP "Microsoft.Web.WebView2.$version.zip"
$expanded = Join-Path $env:RUNNER_TEMP "Microsoft.Web.WebView2.$version"
$url = "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$version/microsoft.web.webview2.$version.nupkg"
# The pinned digest will be verified against a separate, HTTPS-fetched
# Microsoft NuGet package. Print once during the audit, then lock it in source.
Invoke-WebRequest -Uri $url -OutFile $package
$sha256=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "AUDIT_WEBVIEW2_PACKAGE_SHA256=$sha256"
if (Test-Path $expanded) { Remove-Item $expanded -Recurse -Force }
Expand-Archive -Path $package -DestinationPath $expanded -Force

function Copy-RequiredFile([string]$relative,[string]$filename) {
    $source = Join-Path $expanded $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "SDK $version missing $relative" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $folder $filename) -Force
}
# Package target frameworks evolve independently of our Windows host. Select
# a shared compatible framework directory, never mix versions of the two DLLs.
$frameworks = @('net8.0-windows','net8.0','net6.0-windows','net6.0','netcoreapp3.0','net462','net45')
$managed = $null
foreach($tfm in $frameworks){
    $dir = Join-Path $expanded "lib/$tfm"
    if ((Test-Path (Join-Path $dir 'Microsoft.Web.WebView2.Core.dll')) -and
        (Test-Path (Join-Path $dir 'Microsoft.Web.WebView2.WinForms.dll'))) {
        $managed = "lib/$tfm"
        break
    }
}
if (-not $managed) {
    $candidates = @(Get-ChildItem -Path $expanded -Recurse -Filter 'Microsoft.Web.WebView2.Core.dll' | Select-Object -ExpandProperty FullName)
    throw "No compatible WebView2 framework in SDK. Core DLL candidates: $($candidates -join ', ')"
}
Write-Host "WebView2 assemblies: $managed"
Copy-RequiredFile "$managed/Microsoft.Web.WebView2.Core.dll" 'Microsoft.Web.WebView2.Core.dll'
Copy-RequiredFile "$managed/Microsoft.Web.WebView2.WinForms.dll" 'Microsoft.Web.WebView2.WinForms.dll'
Copy-RequiredFile 'runtimes/win-x64/native/WebView2Loader.dll' 'WebView2Loader.dll'
Write-Host "Microsoft WebView2 SDK $version staged for x64 Windows. No executable installed."