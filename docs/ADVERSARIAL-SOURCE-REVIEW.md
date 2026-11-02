# Adversarial source review — v1.16 development branch

## Scope and verification

This pass examined the current GUI entrypoint, worker, data readers, scheduling and cancellation paths, repository lookup, quota/model controllers, renderer adapters, and all ten reusable module implementations and export manifests.

No CI tests were used or checked during this pass. The review used source inspection and dependency/contract consistency checks only. No Windows PowerShell, Task Scheduler, WebView2 rendering, real Codex account, or antivirus execution was performed.

## Corrected defects

1. Browse previously wrote an obsolete Selection.dataQueued property. It now invalidates the queue owned by Async.dataQueued.
2. Direct WPF bars created without WebView2 were never registered for live appearance changes. They are now tracked, recolored in place, and removed with their owner.
3. The generic FlowingProgress module previously commandeered ElementHost.Tag. Its percentage is now held in module-owned weak-key state; other programs can use Tag independently.
4. Native WPF material updates now target a named FlowFill template element rather than relying on a positional visual-tree index.
5. CodexData repository and pending-task readers no longer depend on an ambient appDir global. The async dispatcher passes AppDirectory explicitly. Session-ID validation is local to its reader.
6. An error saving a draft or refreshing the interface after validated task registration no longer reports scheduling as failed. Cancellation refreshes the list even when subsequent cleanup fails.
7. A broken hexadecimal color validator introduced during source editing was identified and corrected before completion.

## Architectural judgment

All ten module implementations were inspected for Codex and UI-state imports, and their function exports were compared with their definitions and manifests. No such dependency or export discrepancy was found. The scheduled worker dispatches before UI initialization and does not load application UI modules.

The application-specific WinForms controllers still coordinate through shared application-owned controls and state. They are intentionally not offered as reusable library modules. The general-purpose components are independently importable within PowerShell; visual and scheduled-task components remain Windows-specific.

## Residual risk and acceptance boundary

- Native WPF live recoloring and its module-owned state have not been executed on Windows in this pass.
- Actual Task Scheduler registration, retry scheduling, failure propagation, account switching, and WebView2 process recovery have not been observed on the target computer.
- The backend can omit or conflict on workspace identity. Auto-resume must fail closed rather than guess.
- The preview remains unsigned. Actual antivirus behavior and production signing need separate verification.
- SHA-256 worker snapshots detect accidental drift, but do not authenticate against a same-user attacker able to change both job metadata and files.
- Older pinned-runtime folders are not automatically garbage-collected. Safe cleanup requires proof that no registered task still refers to them.

**Disposition:** Keep PR #16 in draft. The source-level correction is complete; runtime and distribution acceptance are not established without Windows execution. This review intentionally did not use CI.
