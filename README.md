# Codex Resume Scheduler

A small Windows desktop GUI for scheduling continuations of saved **Codex CLI** sessions. Uses **Windows Task Scheduler**—no always-on service.

![Windows](https://img.shields.io/badge/Windows-PowerShell%207-blue)

**Latest published versioned release (main branch): [GitHub Releases](https://github.com/Dukxud/codex-resume-scheduler/releases/latest)**

Download the versioned ZIP from **Releases**, not GitHub's generic `main.zip`. The review package contains PowerShell/JavaScript, independently importable modules, the AeroProgress material and Microsoft WebView2 SDK libraries. First-party preview scripts are **unsigned**, and no executable is supplied.

## What it does

- Selects from recent saved Codex CLI sessions, **auto-locates their Git root when evidence is sufficient**, and validates the selected repository/branch. A manual Browse override remains available.
- Schedules a message (default `Resume.`) at a specific local date and time.
- Configures the Codex model and *only* that model’s advertised ordinary reasoning efforts (excluding the separate Ultra/multi-agent mode), plus access mode (read-only, workspace-write, or unrestricted/YOLO). The list comes from Codex `model/list`, not a built-in list of model names.
- Shows pending scheduled runs, supports cancellation, and saves a transcript in `%LOCALAPPDATA%\CodexResumeScheduler`.
- **Compact mode** remembers the preferred view, displays the next upcoming run and its model-specific usage windows, and hides the run section entirely when no run is scheduled. Standard mode shows every upcoming run.
- **The progress bars use the owner-approved Windows v1.8 + Aero Liquid v3 hybrid (v2.0.1)**. Quota bars are green and countdowns blue, with the corrected rounded liquid tip, Fresnel optics, reflections, and continuous animation. The actual approved shader and Windows-color source pixels are packaged locally. It runs through Microsoft Edge WebView2; if the runtime/SDK is unavailable, the prior WPF progress bars remain a functional fallback. Time bars fill from **schedule creation** to the scheduled launch time; older tasks without a creation timestamp display the remaining time and an unfilled track rather than a made-up percentage. Reaching 100% is not confirmation that Codex started.
- Countdown labels update locally every second without additional Codex requests. Task and quota snapshots still refresh every 60 seconds.
- Autosaves and restores the complete scheduling draft: conversation, repository, model, reasoning effort, access, instruction, auto-resume, and requested local run time. Saving does not require creating a scheduled run.
- Starts through Windows' built-in Script Host (`wscript.exe`), without a visible terminal. New scheduled jobs also run with a hidden window and report their exit status; transcripts and event logs remain available.
- When a scheduled Codex run reports an actual usage-limit failure, **Auto-resume** (enabled by default) reads the current model’s applicable quota and schedules another one-time run after the reported reset **+2 minutes**. A retry is only started when backend permission is explicitly restored; attempts are capped at four.
- Displays **percentage remaining**, progress bars, and local reset times from Codex's official `account/rateLimits/read` App Server method. **Use reset +2 min** sets the scheduling control to two minutes after the selected reset, rounded up to the next whole minute. It never schedules automatically.
- Refreshes **usage and pending runs automatically on startup, every 60 seconds, and after scheduling or cancellation**. Usage reads run in a short-lived process; conversation, repository, and pending-task reads run in background jobs.

## Responsiveness and concurrent sessions

The modular GUI dispatches saved-conversation discovery, repository lookup, and pending scheduled-task reads to short-lived background PowerShell jobs. It coalesces overlapping refresh requests, and all UI updates occur on the interface thread. No persistent service runs after you close the GUI. The interface groups model and reasoning settings, displays recognizable project names rather than opaque task IDs, and keeps full details in tooltips. When there are no scheduled runs, the upcoming-run section collapses. Background pending refresh no longer replaces actionable status messages.

**Concurrent sessions:** the previous process-based open-session detector was removed because it could not reliably identify an independently opened interactive Codex conversation. Before scheduling a continuation, close any other Codex window that might be using that conversation.

## Customize progress bars (v1.12.2)

Click **Appearance...** in the scheduler (standard or compact). The dialog now contains **two actual animated bars** (usage at 68%, countdown at 75%). Every change is previewed immediately in the dialog and the open application. **Cancel restores all previous settings** without writing them. **Save and close** makes the choices persistent.

The dialog controls:
- **Usage-bar color** and **countdown color** independently: Windows green, Aero sapphire, cyan, violet, amber, ruby red. Each dropdown has real color swatches. Click **Choose...** to open the native Windows color picker for any RGB color; your chosen hexadecimal colors survive restart.
- **Liquid material:** optical glass, mirror enamel, iridescent pearl.
- **Reflections:** product studio, Aero daylight, neon showroom.
- **Shimmer intensity:** 0–200%; **shimmer speed:** 25–300%.
- **Aero Liquid ON/OFF:** turn the shader off to keep the original v1.8-style Windows-color bar. The underlying percentages never change.

Use **Save and close** to apply to all visible bars and persist the choices locally with other scheduler preferences; **Cancel** discards edits, and **Defaults** restores the approved baseline. The moving light is now a wider, curved, view-dependent pool of reflection instead of the previous narrow zebra-stripe sweep. Its motion remains visible at the actual 400×17 usage-bar scale. This is an Aero/WebGL2 visual effect; machines without WebView2 continue using the prior WPF fallback instead.

## Security and reusable components (v1.13.0 review)

**Current preview builds remain unsigned.** The previous hidden Windows Script Host/PowerShell launcher may still be flagged by antivirus. This preview does **not** disable antivirus or ask for exclusions. A production build now fails unless it has a real publisher code-signing certificate and timestamp; signed launcher scripts no longer request `-ExecutionPolicy Bypass`. Signing does not guarantee immediate SmartScreen reputation.

The Aero progress-bar renderer has been separated into an independently importable **[AeroProgress PowerShell module](components/AeroProgress/README.md)**. Windows CI packages it separately as `AeroProgress-Component-v1.16.0-Preview.zip`; other WinForms apps can use its API without importing the scheduler or Task Scheduler. The existing scheduler adapter retains WPF fallback, including recovery if WebView2 reports a child-process failure.

See [security review, risks and signing workflow](docs/SECURITY-REVIEW.md). A read-only security diagnostics script is included at `tools/Get-SchedulerSecurityDiagnostics.ps1` in the packaged app (or in the repository `scripts` directory). It does not change Bitdefender settings.

## Modular architecture and reusable components (v1.16.0 adversarial review)

The GUI has a thin entrypoint and smaller Codex-specific controllers for forms, conversation selection, upcoming runs, model/usage polling, background dispatch, recent results, actions, and lifecycle. The Codex-specific worker lives in CodexRunEngine.ps1, **outside the GUI**. Generic infrastructure is independently importable:

- **AeroProgress:** reusable animated material and WebView2 host.
- **Countdown:** independent text and percentage calculations.
- **SettingsStore:** atomic JSON persistence without application-specific fields.
- **RuntimeBundle:** immutable content-addressed snapshots of worker files.
- **OneTimeTasks:** validated Windows one-time task registration and cancellation.
- **WindowShell:** standalone WinForms window and control constructors.
- **ProgressHost:** renderer-neutral fallback recovery and safe disposal.
- **FlowingProgress:** reusable glossy WPF progress bars with independent palettes and compositor animation.
- **GitRepository:** generic read-only Git root/branch checks.
- **JobOutcomes:** persistent completed, deferred, failed, blocked and cancelled outcomes.

See [reusable components and usage examples](components/README.md) and [architecture / boundaries](docs/ARCHITECTURE.md). The review workflow produces a standalone reusable-components ZIP, separate from the scheduler and AeroProgress-only ZIP. Windows-specific components require Windows; the others require PowerShell 7.

**Scheduled jobs are pinned to their original worker files.** A later app upgrade creates a new runtime snapshot rather than overwriting the runner for existing tasks. Before execution, the worker validates every pinned file against the saved SHA-256 fingerprint. This detects accidental runtime changes; it does not defend against the same Windows account intentionally rewriting both job metadata and files.

The scheduler records completed, deferred, failed, blocked and cancelled outcomes, including the name of any registered follow-up task. Use **Recent results** to inspect their history. Automatic retry requires a verified selected-workspace identity. The application computes the same canonical hash from `account/rateLimits/read.accountId` or from experimental `account/read.workspaceRouting.chatgptAccountId`; it rejects conflicting identifiers. **Email alone never permits unattended execution.** If the backend offers no reliable workspace ID, automatic retry is unavailable and manual scheduling remains possible. Previously created tasks retain their old launchers and must be cancelled and rescheduled to use pinned runtimes.

## Requirements

- Windows 10/11 x64, signed-in desktop session, **PowerShell 7 installed to the standard `C:\Program Files\PowerShell\7` location**. The launcher deliberately refuses unqualified executables from `PATH` or a repository folder. The Aero graphics need the Microsoft Edge WebView2 Runtime, normally installed on Windows 11. WPF fallback remains available without it.
- Codex CLI installed through **npm** and logged in with a ChatGPT account.
- **Node.js** available on `PATH` (installed already for npm-based Codex).
- Git available on `PATH`.

## Run

1. Download the latest **versioned CodexResumeScheduler ZIP** from [Releases](https://github.com/Dukxud/codex-resume-scheduler/releases/latest).
2. Extract the complete versioned folder, preserving its `assets` and `AeroWebView2` subfolders alongside the supplied scripts.
3. Double-click **`Start-Codex-Scheduler.vbs`** to open the interface without a visible terminal. The `.cmd` fallback may briefly flash its own shell before exiting.
4. Usage and pending jobs load automatically; optionally click **Refresh now**. If a reset time is available, click **Use reset +2 min**, or enter a time manually.
5. Select the conversation, **model**, repository, model-supported effort, access mode, and instruction, then click **Schedule once**. Leave Auto-resume checked to retry on a confirmed usage-limit failure.

Newly scheduled jobs use Windows Script Host (`wscript.exe`) to run in the background without a visible terminal. Output and failures are saved in `%LOCALAPPDATA%\CodexResumeScheduler`; use **Open logs folder** for transcripts and **Recent results** for the recorded run status. **Older pending jobs retain their originally registered command**; cancel and reschedule them if you want them to run without a console. Keep the computer **awake, online, and signed into Windows** at the scheduled time. A task missed while the computer was unavailable may execute at the next opportunity.

## How the usage read works

`CodexUsage.js` starts a short-lived `codex app-server --listen stdio://` via the npm package's Node entrypoint, performs the `initialize`/`initialized` handshake with experimental workspace-routing capability enabled, reads `account/read` and `account/rateLimits/read`, and exits. It does **not** read `auth.json`, use a custom web endpoint, scrape logs, send a prompt, or consume a Codex model turn.

The response may include both five-hour and weekly limits, or other-duration windows. The UI displays the snapshot's actual duration and reset time, not assumed 5h/weekly slots. If several **applicable** windows are exhausted, it suggests the **latest** of their reset times. Otherwise, it displays the next window reset as informational, **not** a promise that usage will be restored. If the backend says usage is restricted without an identifiable exhausted window, the reset button remains disabled; scheduling remains available manually. Quota selection uses `rateLimitsByLimitId` and the reported `normalModelSlug` when present. When multiple quotas exist and the selected model cannot be mapped unambiguously, **no automatic reset time is inferred**. Information can be stale, and actual model permission remains authoritative.

The usage helper currently supports the **npm Codex installation** on Windows. When the CLI model catalog is unavailable, the GUI disables new scheduling rather than guess model/effort compatibility; previously registered tasks are unchanged. The UI refreshes automatically every minute, only while open; it does **not** create a recurring Windows task or poll in the background after closing.

## Automatic continuation after a limit

Only operations launched **through a scheduled job in this application** are monitored; this utility cannot capture and pause arbitrary Codex CLI sessions started independently. A run uses `codex exec --json` with its saved session, model, reasoning effort, repository, access mode, and original instruction. If a structured Codex error reports an actual usage limit, it re-reads `account/rateLimits/read` and registers a one-time retry for the **relevant reported reset plus two minutes**. The retry starts by checking that Codex explicitly reports ordinary usage allowed and that the applicable window is no longer exhausted.

Unknown quota-to-model mappings, missing/expired reset times, changes in account, non-quota failures, exhausted credits, and unsupported responses **stop automatic retries** rather than guess or spin. A maximum of four reschedules prevents an unattended loop. A retried task retains the model, reasoning, worktree, branch, access, and message, and validates the worktree and branch at execution. Every attempt has a local PowerShell transcript and Codex JSONL event log; these may contain conversation text and should remain private.

Model choices are dynamically discovered with Codex's `model/list`. If discovery fails or a session references a model not currently listed, the scheduler does not offer arbitrary model/effort combinations. Refresh the Codex model catalog or select an advertised model. Scheduled jobs independently revalidate the model and effort against fresh catalog data at launch. Ultra is a multi-agent selection in the CLI, not an ordinary reasoning-effort tier, and is deliberately excluded. The application does not assume that all models share a quota or that the availability of one model permits another to run.

## Repository auto-detection

When a conversation is selected, the GUI first asks the **Codex App Server** for its saved working directory using read-only `thread/read`. This is the directory Codex reports for the conversation, and the scheduler resolves its Git root. The lookup runs in the existing background selection job and does **not** resume or alter the conversation.

If that path is missing, unavailable or not in an existing Git repository, the scheduler falls back to session-specific evidence: the original CLI working directory, prior scheduler jobs for the same session ID, and recent structured `cwd`/tool `workdir` entries. Conflicting **fallback-only** checkouts require **Browse**.

If Codex's reported root differs from a fallback checkout, **the reported root is selected**, but the other checkout path is displayed in the status line and in a hover tooltip on the repository field; **Browse** can override it. This selection is not proof that unfinished work is in the reported directory. Branch and Git-root validation still apply at scheduling and execution. No entire-drive scanning or process heuristics are used.

## Remembered scheduling draft

Edits are saved automatically after a short pause and again when the window closes. Refreshing models and conversations should not silently replace the saved model or manual repository selection. If a saved run time is already past, the date picker starts at a new safe future time rather than attempting to schedule in the past. Previously created Windows tasks are unaffected. The settings file is local to your Windows profile and contains the instruction text in plain text.

## License

MIT License. See [LICENSE](LICENSE).

## Security and limitations

- **YOLO** (`--dangerously-bypass-approvals-and-sandbox`) disables approvals and sandboxing, including **outside the repository**. Use only for trusted sessions. The first-run default is **workspace-write**; later launches restore the last edited access mode and other form fields from `%LOCALAPPDATA%\CodexResumeScheduler\settings.json`. This local JSON includes your entered instruction in plain text; do not paste secrets into the instruction. YOLO remains explicitly confirmed for each newly scheduled run.
- The bundled Windows Script Host wrapper starts **`pwsh -ExecutionPolicy Bypass` for its own PowerShell child process only**, because the local `.ps1` is not digitally signed. This does not change `CurrentUser` or `LocalMachine` policy; organization Group Policy can still block execution. Use only with source you trust. Existing scheduled jobs created before v1.3.1 retain their original command until repaired or recreated.
- The GUI validates repository root, branch, model, and effort at scheduling time, and the runner revalidates them before execution. It cannot detect another open copy of the same Codex conversation. Close other copies before scheduling to prevent concurrent activity.
- Tasks run once, not every day; Windows Task Scheduler can launch them after a missed time if `StartWhenAvailable` is enabled.
- Scheduled tasks and job settings are kept locally. No code, repository content, or saved Codex conversations are uploaded by this app.
- Usage parsing, hidden Windows Script Host process behavior, WinForms layout, real Aero WebView2 rendering (plus WPF fallback), fixed progress values, and runner wiring are covered by Windows CI; **real Codex end-to-end runs on BLACK-PUDDLE still require manual validation**. A successful Task Scheduler registration is not proof that Codex itself will complete a turn.

## Development

Run the quota, model discovery, and retry-decision tests with Node.js:

```sh
node --test tests/*.test.js
```

On Windows, check PowerShell syntax:

```powershell
$tokens=$null; $errors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\CodexResumeScheduler.ps1),[ref]$tokens,[ref]$errors); $errors
```

No build step or installed dependencies beyond Windows PowerShell 7, Node, Git and npm Codex. Background data refresh uses the `ThreadJob` module bundled with PowerShell 7.

## Protocol references

- [Codex App Server: initialization and account rate limits](https://learn.chatgpt.com/docs/app-server)
- [Codex CLI commands](https://learn.chatgpt.com/docs/developer-commands)

This is an independent community utility, not an official OpenAI product.

## Publishing a new public repository (maintainer)

The optional `Publish-To-GitHub.cmd` launches the publication helper, which uses an authenticated [GitHub CLI](https://cli.github.com/) to create `Dukxud/codex-resume-scheduler` as a public repository. It checks the GitHub login, uses GitHub's no-reply commit email, refuses to overwrite an existing repository, and verifies that the public `main` branch received the intended commit. This script is not part of normal app operation.

### Reuse acceptance

The standalone component kit is exercised by a **second unrelated Windows application**, using only copied component folders and no Codex runtime, source files or user profile. Dedicated acceptance tests exercise the generic one-time-task adapter and create a real WebGL2 progress bar using the extracted reusable ZIP. The scheduler UI uses an explicit selection/usage/preferences/dashboard state context; the Codex worker has no GUI state dependency. Queued tasks allocate browser-backed progress views only for visible rows. Windows acceptance tests exist, but the latest source-level changes were deliberately not run through CI or target-device Windows execution. Application-specific forms and renderer integrations remain Windows-only.

### Current development validation status

The v1.16 source-level pass corrected Browse queue ownership, native WPF appearance updates, generic progress state ownership, implicit data-reader paths, and post-registration status reporting. The PR remains a draft. No CI was run for those corrections. See docs/ADVERSARIAL-SOURCE-REVIEW.md for evidence and remaining target-device acceptance.

## Consolidated merge status

The production-release safety guard is already installed on main. The v1.16 PR is retargeted directly to main and its candidate workflow removes the publication job; tests are manual-dispatch only. Preview ZIP scripts remain available but unsigned.

AeroProgress now stores WebView2 state privately, without reading or overwriting Control.Tag. Consumers query Get-AeroProgressViewStatus instead. The Scheduler's quota/time Tag data belongs to its own adapter. SettingsStore is for replaceable preferences, not Weight Trajectory measurements.

**Do not merge until direct Windows acceptance on BLACK-PUDDLE is complete.** Follow docs/WINDOWS-ACCEPTANCE.md and docs/RELEASE-POLICY.md. PRs #14 and #15 are superseded by PR #16; they should not be merged independently. After acceptance, squash-merge #16 and close the older PRs. No CI tests were run for these changes.
