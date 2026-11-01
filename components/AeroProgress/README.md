# AeroProgress component — Windows Forms / WebView2

**Standalone module.** It knows nothing about Codex, scheduled tasks, project paths, WPF, settings storage, or host-app fallbacks. It is not a compiled launcher or browser extension.

The host supplies:
- `-Parent` (Windows Forms control), position/size in pixels, and accessible name.
- `-SdkDirectory` (three unmodified Microsoft WebView2 SDK assemblies/native loader).
- `-AssetPath` (offline `AeroBar.html` renderer) and writable per-user `-UserDataDirectory`.
- View state: normalized `value` (0–1), six named colors or `#RRGGBB`, `finish`/ `lighting` (0–2), `shimmer` (0–2), `speed` (0.25–3), and `aero` (Boolean).

The host chooses how to persist preferences and what to show when WebView2 is unavailable or fails. No network resources are loaded. The module blocks external navigation/popups and denies browser permissions.

## Minimal consumer example (PowerShell 7, Windows desktop)

```powershell
Add-Type -AssemblyName System.Windows.Forms
Import-Module .\AeroProgress.psd1 -Force

$form = [Windows.Forms.Form]::new()
$form.ClientSize = [Drawing.Size]::new(430,75)
$component = $PSScriptRoot

$support = Test-AeroProgressSupport -SdkDirectory "$component\AeroWebView2" -AssetPath "$component\AeroBar.html"
if (-not $support.Available) { throw "WebView2 unavailable: $($support.Reason)" }

$view = New-AeroProgressView -Parent $form -SdkDirectory "$component\AeroWebView2" -AssetPath "$component\AeroBar.html" `
  -UserDataDirectory (Join-Path $env:LOCALAPPDATA 'MyApp\AeroWebView2') -X 15 -Y 20 -Width 400 -Height 17 -Color blue

Set-AeroProgressViewState -View $view -State @{
    type='set'; value=.68; color='blue'; finish=0; lighting=0
    shimmer=1.0; speed=1.0; aero=$true
}
[Windows.Forms.Application]::Run($form)
```

The module queues the state until WebView2 is initialized, so callers do not need to sleep, poll, or manage WebView2 message events. Inspect `$view.Tag.Failure` if a view fails.

**Distribution:** the release workflow publishes a separate `AeroProgress-Component.zip` containing the module, renderer and Microsoft SDK libraries. That SDK is not the WebView2 Evergreen Runtime. A supported Windows installation must have the runtime installed.

**License:** the module and renderer are distributed under the repository MIT license; Microsoft WebView2 binaries retain their own publisher/licensing terms.

**Trust:** the component ZIP is not signed merely because its Microsoft dependencies are. Do not claim publisher authentication until a trusted release certificate is configured.
