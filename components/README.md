# Reusable components

These PowerShell modules can be imported independently. None needs Codex, the scheduler GUI, a session ID or application-specific settings. Choose only the components your next application needs.

| Module | Purpose | Platform | Public functions |
|---|---|---|---|
| AeroProgress | Live WebGL2 optical progress bars in Windows Forms | Windows + WebView2 | Test-AeroProgressColor, Test-AeroProgressSupport, New-AeroProgressView, Set-AeroProgressViewState |
| Countdown | Pure elapsed percentage and time-to-run text | PowerShell 7 | Get-CountdownText, Get-CountdownElapsedPercent |
| SettingsStore | Atomic local JSON settings, schema defined by the host | PowerShell 7 | Read-JsonSettings, Write-JsonSettings |
| RuntimeBundle | Fingerprinted, content-addressed runtime snapshots | PowerShell 7 | Get-RuntimeFingerprint, Assert-RuntimeFingerprint, Publish-ImmutableRuntime |
| OneTimeTasks | One-time Windows Task Scheduler registration and validation | Windows | Register-OneTimeTask, Disable-OneTimeTask |

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
