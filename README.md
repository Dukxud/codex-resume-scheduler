# Codex Resume Scheduler

A small Windows desktop GUI for scheduling one-time continuations of saved **Codex CLI** sessions. Uses **Windows Task Scheduler**—no always-on service.

![Windows](https://img.shields.io/badge/Windows-PowerShell%207-blue)

## What it does

- Selects from recent saved Codex CLI sessions, **auto-locates their Git root when evidence is sufficient**, and validates the selected repository/branch. A manual Browse override remains available.
- Schedules a message (default `Resume.`) at a specific local date and time.
- Configures reasoning effort and access mode (read-only, workspace-write, or unrestricted/YOLO).
- Shows pending scheduled runs, supports cancellation, and saves a transcript in `%LOCALAPPDATA%\CodexResumeScheduler`.
- Starts a visible PowerShell 7 window that **stays open** after Codex finishes.
- Displays **percentage remaining**, progress bars, and local reset times from Codex's official `account/rateLimits/read` App Server method. **Use reset +2 min** sets the scheduling control to two minutes after the selected reset, rounded up to the next whole minute. It never schedules automatically.
- Refreshes **usage and pending runs automatically on startup, every 60 seconds, and after scheduling or cancellation**. Usage reads run in a separate short-lived process so the interface remains responsive.

## Requirements

- Windows 10/11, signed-in desktop session, **PowerShell 7**.
- Codex CLI installed through **npm** and logged in with a ChatGPT account.
- **Node.js** available on `PATH` (installed already for npm-based Codex).
- Git available on `PATH`.

## Run

1. Download a release ZIP or clone this repository.
2. Keep `CodexResumeScheduler.ps1`, `CodexUsage.js`, and `Start-Codex-Scheduler.cmd` in the **same folder**.
3. Double-click `Start-Codex-Scheduler.cmd` as a normal (non-administrator) Windows user.
4. Usage and pending jobs load automatically; optionally click **Refresh now**. If a reset time is available, click **Use reset +2 min**, or enter a time manually.
5. Select the conversation, repository, effort, access mode, and instruction, then click **Schedule once**.

Pending jobs are persisted by Windows Task Scheduler. Keep the computer **awake, online, and signed into Windows** at the scheduled time. A task missed while the computer was unavailable may execute at the next opportunity.

## How the usage read works

`CodexUsage.js` starts a short-lived `codex app-server --listen stdio://` via the npm package's Node entrypoint, performs the supported `initialize`/`initialized` handshake, calls `account/rateLimits/read`, and exits. It does **not** read `auth.json`, use a custom web endpoint, scrape logs, send a prompt, or consume a Codex model turn.

The response may include both five-hour and weekly limits, or other-duration windows. The UI displays the snapshot's actual duration and reset time, not assumed 5h/weekly slots. If several windows are exhausted, it suggests the **latest** of their reset times. Otherwise, it displays the next window reset as informational, **not** a promise that usage will be restored. If the backend says usage is restricted without an identifiable exhausted window, the reset button remains disabled; scheduling remains available manually. Information can be stale, and actual model permission remains authoritative.

The usage helper currently supports the **npm Codex installation** on Windows. When the CLI isn't accessible, the usage area displays a readable error and manual scheduling continues to work. The UI refreshes automatically every minute, only while open; it does **not** create a recurring Windows task or poll in the background after closing.

## Repository auto-detection

On selecting a conversation, the app compares these session-specific sources:

1. The selected CLI session's starting working directory, if inside a Git repository.
2. Repositories previously scheduled for **the same session ID**.
3. Recent structured `cwd` values in the saved conversation.
4. Recent structured tool `workdir` values in the same conversation.

If multiple distinct Git roots are present, **the repository field is cleared** instead of silently preferring the conversation's original checkout. Use **Browse** to select the checkout containing unfinished work; its branch is validated when scheduling and running. The app does not scan the drive or guess from arbitrary command text. If session evidence is incomplete, manual verification remains necessary.

## License

MIT License. See [LICENSE](LICENSE).

## Security and limitations

- **YOLO** (`--dangerously-bypass-approvals-and-sandbox`) disables approvals and sandboxing, including **outside the repository**. Use only for trusted sessions. The default is **workspace-write**.
- The launcher and scheduled task runner use **`pwsh -ExecutionPolicy Bypass` for their own PowerShell process only**, because the local `.ps1` is not digitally signed. This does not change `CurrentUser` or `LocalMachine` policy; organization Group Policy can still block execution. Use only with source you trust. Existing scheduled jobs created before v1.3.1 retain their original command until repaired or recreated.
- The GUI validates repository root and branch at scheduling time, and the runner checks them again before execution. It does not revalidate the current task's full instruction/history. Concurrent sessions may conflict.
- Tasks run once, not every day; Windows Task Scheduler can launch them after a missed time if `StartWhenAvailable` is enabled.
- Scheduled tasks and job settings are kept locally. No code, repository content, or saved Codex conversations are uploaded by this app.
- Usage parsing has automated tests and the new GUI wiring was statically reviewed; **v1.3.2 must still be tested on Windows**. A successful Task Scheduler registration is not proof that Codex itself will complete a turn.

## Development

Run the usage parser/protocol tests with Node.js:

```sh
node --test tests/usage.test.js
```

On Windows, check PowerShell syntax:

```powershell
$tokens=$null; $errors=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\CodexResumeScheduler.ps1),[ref]$tokens,[ref]$errors); $errors
```

No build step or installed dependencies beyond Windows PowerShell 7, Node, Git and npm Codex.

## Protocol references

- [Codex App Server: initialization and account rate limits](https://learn.chatgpt.com/docs/app-server)
- [Codex CLI commands](https://learn.chatgpt.com/docs/developer-commands)

This is an independent community utility, not an official OpenAI product.

## Publishing a new public repository (maintainer)

The optional `Publish-To-GitHub.cmd` launches the publication helper, which uses an authenticated [GitHub CLI](https://cli.github.com/) to create `Dukxud/codex-resume-scheduler` as a public repository. It checks the GitHub login, uses GitHub's no-reply commit email, refuses to overwrite an existing repository, and verifies that the public `main` branch received the intended commit. This script is not part of normal app operation.
