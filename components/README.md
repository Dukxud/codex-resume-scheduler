# Reusable components

These PowerShell modules can be imported independently. None needs Codex, the scheduler GUI, a session ID or application-specific settings. Choose only the components your next application needs.

| Module | Purpose | Platform | Public functions |
|---|---|---|---|
| AeroProgress | Live WebGL2 optical progress bars in Windows Forms | Windows + WebView2 | Test-AeroProgressColor, Test-AeroProgressSupport, New-AeroProgressView, Set-AeroProgressViewState |
| Countdown | Pure elapsed percentage and time-to-run text | PowerShell 7 | Get-CountdownText, Get-CountdownElapsedPercent |
| SettingsStore | Atomic local JSON settings, schema defined by the host | PowerShell 7 | Read-JsonSettings, Write-JsonSettings |
| RuntimeBundle | Fingerprinted, content-addressed runtime snapshots | PowerShell 7 | Get-RuntimeFingerprint, Assert-RuntimeFingerprint, Publish-ImmutableRuntime |
| OneTimeTasks | One-time Windows Task Scheduler registration, validation and cancellation | Windows | Register-OneTimeTask, Disable-OneTimeTask, Remove-OneTimeTask |

## Additional independently reusable modules

| Module | Purpose | Platform |
|---|---|---|
| GitRepository | Read-only Git root and current-branch inspection | PowerShell 7 + Git |
| JobOutcomes | Atomic and validated completed/failed/deferred/blocked/cancelled outcome records | PowerShell 7 |
| WindowShell | Native Windows Forms windows and standard controls | Windows |
| ProgressHost | Renderer-neutral fallback ownership and lifecycle without requiring `Control.Tag` metadata | Windows |
| FlowingProgress | Native WPF compositor-animated glossy progress surface with caller-defined colors | Windows |

The reusable kit has **ten** modules. Each may be copied alone, except JobOutcomes requires the small SettingsStore dependency (copy both folders together). AeroProgress requires its local HTML shader and WebView2 SDK files. FlowingProgress requires WPF and WindowsFormsIntegration, but no Codex settings, quota code, or browser.

The independent consumer test under tests/second-application-reuse.test.ps1 copies only components/ into an unrelated application and exercises the APIs without importing Codex.

## Using any component

Copy the desired folder from this repository's components directory into another application, or extract the versioned ReusableComponents preview ZIP. Import only the module you need:

~~~powershell
Import-Module .\components\Countdown\Countdown.psd1
Get-CountdownText -DueAt (Get-Date).AddMinutes(8) -Now (Get-Date)
~~~

Another application can use the JSON settings store without the scheduler:

~~~powershell
Import-Module .\components\SettingsStore\SettingsStore.psd1
Write-JsonSettings -Path "$env:LOCALAPPDATA\MyApp\settings.json" -Value @{ theme='blue' }
Read-JsonSettings -Path "$env:LOCALAPPDATA\MyApp\settings.json"
~~~

A program that registers independent background work can copy its necessary script files into a content-addressed snapshot and store the returned fingerprint alongside its task metadata:

~~~powershell
Import-Module .\components\RuntimeBundle\RuntimeBundle.psd1
$runtime=Publish-ImmutableRuntime -SourceDirectory . -DestinationDirectory "$env:LOCALAPPDATA\MyApp\runtimes" -RelativeFiles @('worker.ps1')
Assert-RuntimeFingerprint -Directory $runtime.Directory -RelativeFiles @('worker.ps1') -ExpectedFingerprint $runtime.Fingerprint
~~~

OneTimeTasks accepts **your** executable path, arguments, working directory, task name and time; it does not assume PowerShell or Codex. The application must decide how to launch its worker and handle errors. A successfully registered task is **not** proof that the worker completed.

See [AeroProgress](AeroProgress/README.md) for a complete standalone animated Windows Forms example. The standalone reusable-kit ZIP places the advanced shader's AeroBar.html and Microsoft WebView2 SDK DLLs **inside** the AeroProgress folder so that folder can be copied and imported by itself.

## Boundaries and constraints

- UI-specific bindings (CodexUi*) and CodexRunEngine.ps1 are adapters, not reusable core.
- RuntimeBundle protects against accidental replacement and checks file content before execution. It is **not** a security boundary against the same Windows user, who can modify both the runtime and locally stored task metadata. Signed first-party code is needed for publisher authentication.
- OneTimeTasks uses Windows Task Scheduler's interactive-user principal and does not run while signed out.
- SettingsStore returns null on absent or unreadable JSON; the host owns schema validation and any upgrades.
- Countdown has no UI dependencies; unknown creation time produces null, never a fabricated progress percentage.
- Each module is independently importable; the Windows-specific modules are not directly portable to non-Windows UI frameworks.
- The scheduler's Codex-specific recovery and account verification are intentionally **not** in the general-purpose components.

Unit and Windows GUI integration checks live under tests. The app package and standalone components package share exactly the same module sources.

## Host and threading prerequisites

The reusable Windows Forms and Windows Presentation Foundation components (`WindowShell`, `AeroProgress`, `FlowingProgress`, `ProgressHost`) must run on **Windows with a single-threaded apartment (STA) UI thread** and a functioning message loop. Independent tests launch them with `pwsh -STA`. The Aero view also needs the Microsoft Edge WebView2 runtime plus the locally packaged WebView2 SDK and HTML shader. These components are not language-independent or headless services; they can be transplanted into other Windows desktop applications that supply a compatible host.

`OneTimeTasks` requires Windows Task Scheduler and registers tasks for the signed-in interactive desktop user. `Countdown`, `SettingsStore`, `RuntimeBundle`, `GitRepository`, and `JobOutcomes` require PowerShell 7 and their stated external dependencies (for GitRepository, Git), but not a UI thread.

## Renderer host ownership

`Repair-ProgressHost -Primary <control> -Failed $true -FallbackFactory <scriptblock>` creates a generic fallback when the host's renderer has failed. The host—not the library—determines failure. `Get-ProgressHostSurface` returns the active view, `Set-ProgressHostLayout` updates it, `Reset-ProgressHostFallback` frees the fallback while retaining the primary, and `Remove-ProgressHost` disposes both. The host is free to use `Control.Tag` for unrelated information.

`AeroProgress` loads its WebView2 native loader from an explicit SDK path; it never mutates global `PATH`. A previously missing asset can be installed and retested without restarting. Switching native SDKs inside a process where one has already loaded may require restarting, because loaded native DLLs cannot always be unloaded safely.

The standalone consumer tests run generic one-time scheduling against an isolated fake OS task provider and exercise the **real** WebView2 shader from a packaged standalone module in a separate Windows application. They do not execute the user's actual scheduled tasks.

**Clock correctness:** Countdown converts timestamps to UTC before computing elapsed time, preventing wrong durations across daylight-saving time changes. OneTimeTasks rejects ambiguous or nonexistent local trigger times rather than guessing which clock occurrence to schedule; the caller should request another unambiguous time.

OneTimeTasks accepts local `DateTime` instances and explicit UTC `DateTime` values, converting UTC instants to local Task Scheduler boundaries. Unspecified `DateTime` values are interpreted as local wall-clock times. Ambiguous or invalid daylight-saving clock times are rejected rather than guessed.
