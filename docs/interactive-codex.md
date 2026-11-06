# Continuum interactive Codex: single-owner design

## Purpose

Scheduled jobs must support the real Codex TUI so the user can see questions, approve tools and respond interactively. A user clicking Open terminal must focus the **existing** Codex process, not fork or create a second writer.

## Confirmed in this repository

- CodexRunJob.vbs currently hides PowerShell using WScript.Shell.Run(command, 0, True).
- CodexRunEngine.ps1 executes codex exec --json resume, keeps a named single-session mutex and writes JSONL.
- OneTimeTasks.psm1 registers Windows interactive-logon tasks under the current user, RunLevel Limited.
- No console/PTY exists to reopen for a current hidden run. The current dashboard feed is necessarily read-only.

## External references

- Native Codex TUI can resume a session by ID: https://learn.chatgpt.com/docs/cli/reference
- Windows Terminal can create uniquely named windows: https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments
- Experimental App Server daemon, Windows limitations and remote TUI clients: https://github.com/openai/codex/blob/main/codex-rs/app-server-daemon/README.md

## Delivery and boundaries

Stage 1 (this branch): isolated, explicitly invoked feasibility probe. With no arguments, scripts/Probe-NativeCodexTerminal.ps1 reports installed Codex and Windows Terminal without executing a turn, scheduling a task or changing configuration. With explicit -Open, -SessionId and -Repository, it requests a native Codex TUI in a uniquely named Windows Terminal window. It submits no prompt, never forks and refuses known scheduled/running ownership of that conversation.

Stage 2: introduce persisted execution mode (Unattended default, Interactive terminal explicit). At schedule and launch, verify Windows Terminal, interactive logon, exact saved thread, model, workspace account, quota, repository branch and existing single-writer ownership. No fallback to an unattended run on terminal failure; fail closed.

Stage 3: a child terminal runner must remain owned by the tracked Windows task through its entire lifetime. The wt.exe command exits quickly; it is not a valid completion signal. Require bounded startup handshake, reliable process identity/liveness, terminal exit evidence, and lost-console failure outcomes. The scheduler parent must own its mutex until that child exits.

Stage 4: Open terminal focuses/restores the SAME verified named window and tab. Never spawn codex resume in the Open action. If it has closed, report the ended state and provide recorded evidence. Do not silently create a replacement conversation writer.

Stage 5 (optional): verify a canonical App Server backend plus a Codex --remote TUI client on BLACK-PUDDLE before allowing attachment to an already-started unattended turn. This is currently an unverified experimental capability, not an assumption.

## Acceptance criteria

1. Original session ID preserved; no fork, no concurrent writers.
2. Codex prompt/question or approval can be read and answered using the genuine native TUI.
3. Repeated Open terminal actions focus the same running process.
4. Dashboard stays usable; its close does not terminate Codex.
5. Scheduled task status reflects entire Codex lifetime, not wt launcher exit.
6. Multiple concurrent sessions have separate window identity; same-session overlap rejected.
7. Terminal close, logout, crash, version mismatch, lost child and stale PID fail visibly with truthful outcomes.
8. Prior unattended scheduling, quota resets, saves, recovery and default model behavior remain unchanged.
9. Isolated worker tests, full Flutter tests, BLACK-PUDDLE native acceptance, and adversarial review pass before enabling by default.

## Important status

This is a capability spike, not finished scheduling integration. It does not reattach to an existing hidden exec run or claim to reveal its questions. Native terminal launch has not been validated on BLACK-PUDDLE.

## BP197 root-cause and safety review

- BLACK-PUDDLE confirmed the installed Codex CLI (`codex-cli 0.166.0`) and `wt.exe` are available. The launch refusal arose because Scheduler job `CodexResume-20261105-1737-8fea70e0` reserved the saved session. Reservation is expected behavior, **not** a broken installation.
- Earlier CI tested the Windows command line but never tested the on-device execution owner's availability. A probe that starts another `codex resume` cannot verify reattachment to the existing `codex exec --json resume` process.
- This branch provides `-StatusSaved` to report `BLOCKED` versus `ELIGIBLE_FOR_PREVIEW` without creating a process. `ELIGIBLE_FOR_PREVIEW` does not guarantee ownership; Codex's own writer lock remains authoritative.
- The current hidden worker has no interactive console to restore. Its task must finish normally; never kill or bypass a writer merely to get a prettier terminal. The future interactive mode must own the actual Codex TUI from launch and have a task lifecycle that tracks it.
- **Important Microsoft Terminal behavior:** targeting an existing named window with `wt -w NAME new-tab` **adds a tab**; it does not reattach to the already-running Codex process. Future **Open Terminal** must focus the verified existing OS window instead of using the new-tab command a second time.
- **Do not repeatedly run the launcher while an owner is active.** These blocked states are not errors to retry automatically. Product messages should distinguish `BLOCKED`, `UNAVAILABLE`, `ERROR`, and `LAUNCH_REQUESTED`. Never report the last as proof the interactive UI opened.
- Official sources: https://learn.chatgpt.com/docs/cli/reference ; https://learn.chatgpt.com/docs/non-interactive-mode ; https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments ; https://learn.chatgpt.com/docs/app-server

