# Architecture — Codex Resume Scheduler v1.16.0

## Design boundaries

There are two layers:

**Reusable infrastructure** (each folder imports independently, no Codex imports):
- components/AeroProgress: offline WebView2 renderer with a small explicit state contract; host owns fallback and persistence.
- components/Countdown: pure time formatting and elapsed fraction.
- components/SettingsStore: atomic JSON read/write; does not define settings schema.
- components/RuntimeBundle: immutable content-addressed worker file copies and fingerprint verification.
- components/OneTimeTasks: platform task registration, validation, rollback and cancellation; executable and arguments are caller-owned.
- components/WindowShell: general-purpose WinForms window, labels and buttons.
- components/ProgressHost: renderer-neutral fallback, positioning and paired-control disposal.
- components/FlowingProgress: independently reusable WPF glossy progress bar with caller-provided colors and state; CodexFlowingBar is only a theme adapter.
- components/GitRepository: independent read-only Git root and branch checks.
- components/JobOutcomes: durable state distinction between completed, deferred, blocked, failed and cancelled, built on SettingsStore.

**Application-specific adapters**:
- CodexResumeScheduler.ps1 — thin entrypoint: worker mode or GUI mode.
- CodexRunEngine.ps1 — Codex model/catalog validation, CLI session continuation, usage-based retry, pinned runtime contract.
- CodexData.ps1 — local session, Git, pending task and UI-settings facade.
- CodexUsage.js / CodexRetry.js — official App Server protocol reads and pure quota/retry decisions.
- CodexUiForms.ps1 — WinForms layout through reusable WindowShell primitives.
- CodexUiSelection.ps1 — conversation selection and repository evidence decisions.
- CodexUiPending.ps1 — scheduled-run queue presentation and indexing.
- CodexUiUsage.ps1 — short-lived quota-process and snapshot presentation.
- CodexUiHistory.ps1 — user-visible persisted run outcomes.
- CodexJobStore.ps1 — read-only payload/history discovery that excludes result records from repository searches.
- CodexUiState.ps1 — explicit, separately owned selection, usage, preferences, dashboard and asynchronous-dispatch contexts; reusable modules do not import this.
- CodexUiRefresh.ps1 — coalesced background-operation dispatcher, delegating to the selection, pending and usage controllers.
- CodexUiActions.ps1 — user actions, autosave and task creation.
- CodexUiLifecycle.ps1 — window startup/shutdown and resource cleanup.
- CodexDashboard.ps1 — standard/compact presentation and countdown display.
- CodexAeroBar.ps1 — scheduler-specific colors, WebView2/WPF fallback and disposal.
- CodexBarAppearance.ps1 — transactional appearance editor.
- CodexFlowingBar.ps1 — Codex-specific color/theme adapter to the independent native WPF FlowingProgress module.

## Contract and data flow

1. **UI launch**: Start-Codex-Scheduler.vbs starts CodexResumeScheduler.ps1 with no terminal. The entrypoint loads app-specific adapters and then the GUI. No scheduled worker code requires a WinForms window.
2. **Discovery**: CodexUiRefresh asynchronously reads sessions, the selected thread's current directory and Windows tasks. CodexUsage.js communicates through the documented App Server handshake. UI state is updated on the WinForms thread.
3. **Scheduling**: CodexUiActions validates model, reasoning effort, Git root, branch, access and requested time. When auto-resume is selected, a trustworthy account identity is also required. It calls RuntimeBundle to snapshot its exact worker dependencies, writes task metadata containing that fingerprint, and uses OneTimeTasks to register and re-read the task definition.
4. **Worker launch**: Task Scheduler invokes the exact saved CodexRunJob.vbs inside the fingerprinted runtime, which launches the thin entrypoint in job mode. The worker checks the saved fingerprint **before** executing Codex and then verifies the repository, branch, model and effort.
5. **Codex execution**: The worker launches one saved Codex session and writes a transcript plus JSONL events. It returns 0 only for a successful CLI execution or a verified deferral that registered a new retry; a CLI failure or a refused retry is nonzero.
6. **Retry**: Only a failed CLI execution with a genuine usage-limit error can be reconsidered. Fresh App Server data must identify the applicable quota, future reset, ordinary usage permission and matching active account. Retry preserves the original parameters and runtime fingerprint. Four reschedules maximum.
7. **Rendering**: AeroProgress owns the WebView2 view; CodexAeroBar is the host adapter that translates quota/countdown colors and recovers a failed view with WPF. The dashboard positions the *visible surface* on every scroll, resize, refresh and countdown tick, then destroys the view and fallback together.

## Reuse contract

Other projects import modules from components/ directly. They should not dot-source the Codex UI adapters or depend on their global variables. Calling applications supply paths, task names, timestamps, state, and any domain validation. A standalone ZIP contains all public components and excludes Codex code entirely. See components/README.md for examples.

The copied runtime is content-addressed to prevent accidental later updates. It is **not immutable to a malicious same-user process**: task metadata and runtime copies both live under the user profile. Module signatures, external packaging integrity and local OS protections remain separate security concerns.

## Verification boundaries

Static tests cover protocol normalization, ambiguous quotas, malformed settings, retry decisions, module contracts and manifest integrity. Windows integration tests launch the VBS entrypoint, WinForms/WPF and WebView2 controls, verify screenshots/animation and check the actual worker's exit code. They do not prove live Codex CLI execution, Task Scheduler reliability on BLACK-PUDDLE, account switching, or antivirus outcomes; those require end-to-end validation on the target device.

## Upgrade behavior

New tasks use a separate fingerprinted runtime folder. Older tasks retain their original Windows Task Scheduler action and code copy; there is no automatic rewrite. Cancel and reschedule tasks to opt into the pinned worker. Existing source-based previews may use a different unsigned launcher, and successful CI is not a publisher signature.

## Adversarial clean-code pass

The standalone worker no longer imports CodexData or references UI globals; its Git and account checks are explicit imports. The UI has a declared state owner grouped by responsibility rather than dozens of unowned script variables. ProgressHost owns the primary/fallback lifecycle, and the dashboard allocates one bar per **visible row**, never per queued task. `account/read.workspaceRouting.chatgptAccountId` provides experimental, workspace-specific identity if a rate-limit account ID is absent. Both paths use the same canonical hash, and contradictory IDs fail closed. Email-only identity is never accepted; two workspaces sharing an email must not be conflated.

A queued retry is persisted as `deferred`, not `completed`. Removing an upcoming task unregisters it and records `cancelled`, while logs are retained for audit. Existing work may still be interrupted by Windows sign-out or sleeping, and real hardware/antivirus behavior remains outside CI.

## v1.16 adversarial acceptance

Auto-resume hashes a backend-selected workspace ID (experimental workspaceRouting or rate-limit accountId). Email-only identity and contradictory IDs fail closed. No raw workspace identifiers or emails are written to job metadata.

Run-history files (`*.result.json`) are parsed independently of pending job payloads (`*.json`); the former never displace repository evidence. Deferred outcomes retain the next scheduled task name. The UI displays completion, failure, blocking, deferral and cancellation statuses, including malformed records. Countdown updates use a prebuilt index rather than scanning the entire pending queue for each row.

The WebView2 module loads its native SDK by explicit path, leaves process `PATH` untouched, and retries dependency checks after failures. ProgressHost owns fallback controls without claiming caller `Control.Tag`.

The second-app test exercises all ten component imports, while separate acceptance cases invoke generic scheduling operations and test real, packaged WebGL2 rendering with no Codex code. CI cannot establish real account operations, Bitdefender response or Windows Task Scheduler behavior on BLACK-PUDDLE.

## Application-state responsibility contracts

`CodexUiState.ps1` constructs the application-only context. The context is deliberately **not** a reusable module. It carries only state needed to coordinate application-specific controllers; consumers of the ten `components/` modules never import it.

- **Selection** owns selected conversations, repository alternatives, model catalog and effort control. `CodexUiSelection.ps1` is the sole model-catalog reconciler; usage only calls `Apply-CodexModelCatalog` instead of mutating selection fields directly. An empty catalog clears stale model and effort controls and blocks scheduling.
- **Usage** owns the short-lived query process, quota snapshots, and refresh state, through `CodexUiUsage.ps1`.
- **Async** owns coalesced background jobs and queued requests. `CodexUiRefresh.ps1` handles dispatch, not domain-specific result rendering.
- **Dashboard** owns visual controls, the pending run snapshot and its keyed index. `CodexUiPending.ps1` publishes the index and `CodexDashboard.ps1` renders only visible progress bars.
- **Preferences** owns saved drafts and appearance configuration; event actions and lifecycle compose these controllers, rather than becoming reusable infrastructure.

The boundaries are enforced by source-level dependency tests and isolated model-controller tests. Shared WinForms control objects in the application-specific presentation remain an intentional Windows desktop orchestration detail, **not** an exported component contract.

One-time task creation normalizes explicitly UTC timestamps to local Windows trigger times, rejects ambiguous/nonexistent daylight-saving local timestamps, and records real outcomes. Countdown arithmetic uses UTC instants even when timestamps are shown in local time.
