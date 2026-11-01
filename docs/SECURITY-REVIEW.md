# Security and code-quality review — v1.15.0 candidate

## Scope and evidence

Reviewed the actual Windows launchers, scheduled-task flow, WebView2 host, release workflow, dependency staging, local settings and data logs, and progress-bar component boundaries. Windows CI and static tests are acceptance gates. **This is not a malware-free certification, penetration test, or proof of Bitdefender's specific detection.** Collect the detection name/sample hash from the affected machine to establish that cause.

## Material findings and changes

| Finding | Risk | Action |
|---|---|---|
| `wscript.exe` starts a hidden `pwsh.exe` with `-ExecutionPolicy Bypass` | Resembles script malware; signature checks intentionally bypassed | Production packaging now **requires trusted Authenticode signing** and removes that switch from both launchers. Unsigned previews remain marked explicitly and retain existing behavior to avoid breaking preview users. |
| Unsigned first-party scripts, despite bundled Microsoft DLLs | Publisher identity not established; SmartScreen/AV may intervene | New fail-closed code-signing script signs every shipped `.ps1`, `.psm1`, `.psd1` with SHA256 and timestamp, verifies identity and refuses self-signed public releases. **Not yet signed:** no publisher certificate is connected. |
| SDK NuGet downloaded without a verified content digest | Dependency corruption / substitution risk | Exact SDK version plus an audited, fixed SHA-256 digest verified before extraction. No network access from the running renderer. |
| VBS launches unqualified `pwsh.exe` from the project/repository working directory | Local executable-search hijack by placing a malicious `pwsh.exe` near task files | Both GUI and scheduled-run VBS wrappers now require the official PowerShell 7 executable at the absolute `Program Files\PowerShell\7\pwsh.exe` path. No fallback to arbitrary PATH entries. |
| Shader host and scheduler heavily coupled | Hard to reuse, review or test independently | Extracted `AeroProgress` module: four explicit functions with host-supplied data/paths. The scheduler retains a small adapter and WPF fallback. Separate component ZIP generated. |
| Embedded local browser could navigate/request permissions | Unexpected web/content access | Module blocks navigation except its expected local asset, blocks pop-ups, denies permissions, disables DevTools and browser shortcuts, and retains existing content security policy. |
| Releases had no file inventory | Poor integrity auditing | SHA-256 manifest generated **after** script signing in both scheduler and component ZIPs. Hash manifests detect accidental changes; without a trusted signature they do not authenticate the publisher. |
| Silent antivirus-related failures | No reliable evidence distinguishing policy, AV, runtime or app crash | Added read-only diagnostics (file hashes, signature status, relevant recent Windows event IDs). Does not collect prompts, tokens or scheduler job files and does not disable security products. |

## Residual risk and honest limits

- **Standard PowerShell installation required:** Both launchers now require PowerShell 7 installed beneath `C:\Program Files\PowerShell\7`. A portable or non-standard install must be adapted explicitly; a silent PATH fallback would reintroduce the hijack risk.
- **Certificate required:** Production builds will now fail rather than silently publish unsigned. Someone must establish an external publisher identity and provision a trusted code-signing certificate on the signing machine. Azure Artifact Signing can be integrated once an account and validated identity exist; it has a recurring cost. The current GitHub-hosted Windows runner does **not** have your private signing key or service access. Even an internal or locally trusted certificate that passes on one machine may not be trusted on other users' computers; verify the publisher chain publicly before shipping. Do not put private keys or plaintext PFX passwords into the repository.
- **The `.vbs` launcher itself is still script-based.** PowerShell Authenticode does not sign it as a first-party PS script. Even with signed PowerShell payloads, WScript/hidden-PowerShell heuristics may remain. A future **signed native bootstrapper or Microsoft Store distribution** would remove that pattern; this change deliberately avoids introducing an unsigned new executable that could make things worse.
- **Antivirus-specific evidence remains absent.** Bitdefender can terminate Chromium WebView2 child processes, producing a blank widget or crash, independently of SmartScreen. The AeroProgress module reports process failure; the scheduler adapter replaces the failed view with a WPF fallback. Windows-specific renderer failures still require on-device verification.
- Scheduled jobs run unattended and may invoke Codex with `--dangerously-bypass-approvals-and-sandbox` **only after an explicit user-selected YOLO mode and confirmation**. This remains inherently high risk. Run as an ordinary limited Windows user; avoid scheduling full-access jobs on untrusted repositories.
- Scheduled job JSON, prompts, session metadata and transcripts are stored within user-writable LocalAppData. Same-user tampering and sensitive log retention are outside this component pass. Never upload raw scheduler logs or job JSON publicly.
- The v1.15.0 review splits GUI presentation, background reads, event actions, lifecycle, and a separate CLI runner. The general-purpose modules carry no Codex or GUI orchestration state. A future application-specific UI rewrite should remain separately reviewable.
- Checksums do not replace signatures. SmartScreen reputation is separate from an Authenticode signature; signed new releases can still be flagged until positive reputation develops.

## Reusable component contract

`components/AeroProgress/AeroProgress.psd1` exposes `Test-AeroProgressColor`, `Test-AeroProgressSupport`, `New-AeroProgressView`, `Set-AeroProgressViewState`. Consumers supply their own parent, DLL/asset paths, state and storage. No Codex imports or Task Scheduler APIs. See `components/AeroProgress/README.md`.

## Building and authenticating

Development only (unsigned and labeled):

```powershell
./scripts/Prepare-AeroWebView2.ps1
./scripts/Package-CodexScheduler.ps1 -OutputDirectory ./Review -Preview
./scripts/Package-AeroComponent.ps1 -OutputDirectory ./Review -Preview
```

After a **trusted code-signing certificate with private key** is installed in the current user's Windows certificate store, a publication build can be produced locally:

```powershell
./scripts/Package-CodexScheduler.ps1 -OutputDirectory ./Signed -CertificateThumbprint '<publisher certificate thumbprint>' -TimestampServer 'http://<trusted TSA endpoint>'
```

The command signs and verifies all PowerShell files, strips the execution-policy override from signed launchers, then records final SHA256 hashes and builds the ZIP. If the cert/timestamp/verification is unavailable it fails. Never upload unsigned artifacts as signed releases.

## Finding the actual Bitdefender problem

Run `scripts/Get-SchedulerSecurityDiagnostics.ps1` locally (read-only), and obtain the *Bitdefender detection name*, blocked file path and quarantine/event timestamp from the Bitdefender UI. Compare to `SHA256SUMS.txt` and Windows crash events. A verified false positive can be submitted through Bitdefender's sample-review process. **Do not turn off antivirus or add blanket exclusions.**


## Added v1.15.0 review controls

- One-time scheduled runners are content-addressed, copied once, and verified against saved SHA-256 metadata at execution. Existing tasks are never silently updated to another version.
- Codex execution failures return nonzero process exit codes; Windows Script Host forwards them to Task Scheduler. Success explicitly blocks retry analysis.
- Automatic retries fail closed when the account ID is unknown or changed; backend identity can be optional, so users must disable Auto-resume if their account does not supply a reliable identity.
- WebView2-to-WPF recovered bars now follow scrolling and resizing, and both controls are disposed together. The existing visual regression suite remains necessary.
- Generic Task Scheduler, settings, countdown and runtime modules are independently packaged and can be imported without Codex. The package's PowerShell scripts remain unsigned in preview artifacts.
- Content-addressed snapshots do **not** prevent an attacker running as the same user from changing both the runtime files and their saved fingerprint; production trust continues to depend on authentic signed files and trusted distribution.

## Reuse hardening

- Unattended account binding comes from a rate-limit account ID when supplied, else a SHA-256 fingerprint of the ChatGPT account email via documented account/read. The email is never persisted. An identical email across multiple workspaces remains a limitation if the backend provides no workspace-specific ID.
- Worker imports generic GitRepository, not GUI session helpers or ambient variables. Task state is explicitly recorded as deferred, blocked, completed, failed, or cancelled.
- ProgressHost now owns recovery and disposal; WindowShell owns generic WinForms primitives; UI modules own an explicit state context.
- The unrelated-application integration test copies only reusable components and exercises them without scheduler code.
- The Aero browser process is still an independent WebView2 subprocess; the host uses a finite number of views proportional to visible scheduled rows, not total pending tasks.
