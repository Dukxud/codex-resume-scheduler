# Codex Resume Scheduler

A small Windows desktop GUI for scheduling continuations of saved **Codex CLI** sessions. Uses **Windows Task Scheduler**—no always-on service.

![Windows](https://img.shields.io/badge/Windows-PowerShell%207-blue)

## What it does

- Selects from recent saved Codex CLI sessions, **auto-locates their Git root when evidence is sufficient**, and validates the selected repository/branch. A manual Browse override remains available.
- Schedules a message (default `Resume.`) at a specific local date and time.
- Configures the Codex model and *only* that model’s advertised ordinary reasoning efforts (excluding the separate Ultra/multi-agent mode), plus access mode (read-only, workspace-write, or unrestricted/YOLO). The list comes from Codex `model/list`, not a built-in list of model names.
- Shows pending scheduled runs, supports cancellation, and saves a transcript in `%LOCALAPPDATA%\CodexResumeScheduler`.
- Remembers the last successfully scheduled access mode (including YOLO) locally for the next launch.
- Starts a visible PowerShell 7 window that **stays open** after Codex finishes.
- When a scheduled Codex run reports an actual usage-limit failure, **Auto-resume** (enabled by default) reads the current model’s applicable quota and schedules another one-time run after the reported reset **+2 minutes**. A retry is only started when backend permission is explicitly restored; attempts are capped at four.
- Displays **percentage remaining**, progress bars, and local reset times from Codex's official `account/rateLimits/read` App Server method. **Use reset +2 min** sets the scheduling control to two minutes after the selected reset, rounded up to the next whole minute. It never schedules automatically.
- Refreshes **usage and pending runs automatically on startup, every 60 seconds, and after scheduling or cancellation**. Usage reads run in a short-lived process; conversation, repository, and pending-task reads run in background jobs.

## Responsiveness and concurrent sessions

The GUI dispatches saved-conversation discovery, repository lookup, and pending scheduled-task reads to short-lived background PowerShell jobs. It coalesces overlapping refresh requests, and all UI updates occur on the interface thread. No persistent service runs after you close the GUI.

**Concurrent sessions:** the previous process-based open-session detector was removed because it could not reliably identify an independently opened interactive Codex conversation. Before scheduling a continuation, close any other Codex window that might be using that conversation.

## Requirements

- Windows 10/11, signed-in desktop session, **PowerShell 7**.
- Codex CLI installed through **npm** and logged in with a ChatGPT account.
- **Node.js** available on `PATH` (installed already for npm-based Codex).
- Git available on `PATH`.

## Run

1. Download a release ZIP or clone this repository.
2. Keep `CodexResumeScheduler.ps1`, `CodexData.ps1`, `CodexUsage.js`, `CodexRetry.js`, and `Start-Codex-Scheduler.cmd` in the **same folder**.
3. Double-click `Start-Codex-Scheduler.cmd` as a normal (non-administrator) Windows user.
4. Usage and pending jobs load automatically; optionally click **Refresh now**. If a reset time is available, click **Use reset +2 min**, or enter a time manually.
5. Select the conversation, **model**, repository, model-supported effort, access mode, and instruction, then click **Schedule once**. Leave Auto-resume checked to retry on a confirmed usage-limit failure.

Pending jobs are persisted by Windows Task Scheduler. Keep the computer **awake, online, and signed into Windows** at the scheduled time. A task missed while the computer was unavailable may execute at the next opportunity.

## How the usage read works

`CodexUsage.js` starts a short-lived `codex app-server --listen stdio://` via the npm package's Node entrypoint, performs the supported `initialize`/`initialized` handshake, calls `account/rateLimits/read`, and exits. It does **not** read `auth.json`, use a custom web endpoint, scrape logs, send a prompt, or consume a Codex model turn.

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

## License

MIT License. See [LICENSE](LICENSE).

## Security and limitations

- **YOLO** (`--dangerously-bypass-approvals-and-sandbox`) disables approvals and sandboxing, including **outside the repository**. Use only for trusted sessions. The first-run default is **workspace-write**; later launches restore the last successfully scheduled access mode from `%LOCALAPPDATA%\CodexResumeScheduler\settings.json`. YOLO remains explicitly confirmed for each newly scheduled run.
- The launcher and scheduled task runner use **`pwsh -ExecutionPolicy Bypass` for their own PowerShell process only**, because the local `.ps1` is not digitally signed. This does not change `CurrentUser` or `LocalMachine` policy; organization Group Policy can still block execution. Use only with source you trust. Existing scheduled jobs created before v1.3.1 retain their original command until repaired or recreated.
- The GUI validates repository root, branch, model, and effort at scheduling time, and the runner revalidates them before execution. It cannot detect another open copy of the same Codex conversation. Close other copies before scheduling to prevent concurrent activity.
- Tasks run once, not every day; Windows Task Scheduler can launch them after a missed time if `StartWhenAvailable` is enabled.
- Scheduled tasks and job settings are kept locally. No code, repository content, or saved Codex conversations are uploaded by this app.
- Usage parsing has automated tests and the new GUI wiring was statically reviewed; **v1.7 must still be tested end-to-end on BLACK-PUDDLE**. A successful Task Scheduler registration is not proof that Codex itself will complete a turn.

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
