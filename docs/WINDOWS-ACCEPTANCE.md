# Manual Windows acceptance gate — v1.16

This checklist is for BLACK-PUDDLE, against the exact current PR #16 commit. It is NOT a CI run. No automated CI validation is being requested or claimed.

Record the exact Git commit SHA and mark each item PASS, FAIL, or NOT TESTED. Preserve specific error messages and screenshots for failures. NOT TESTED is not PASS.

## Required behavior

1. Launch using Start-Codex-Scheduler.vbs. The graphical interface opens without leaving a terminal window, and existing preferences remain intact.
2. Switch between full and compact mode. The next-run indicator, quota bars, and pending list display correct information. Resize and scroll; progress bars follow their cells and disappear when rows are removed.
3. With WebView2 enabled, inspect the approved Aero Liquid material at fixed percentages. Its fluid animation continues without changing the authoritative percentage. Switch presets and a custom hex color on live bars; verify the chosen appearance actually changes.
4. Start a separate process with CODEX_BAR_RENDERER=wpf. All bars remain visible using the WPF fallback; live color changes work without losing percentages, flickering into blank controls, or creating duplicate bars.
5. In a controlled developer session, simulate a single WebView2 renderer failure, then check that WPF recovery preserves value, follows resize/scroll, accepts further updates, and cleans up after removal. Do not kill unrelated browser processes.
6. Independently import only the packaged components/AeroProgress module into an unrelated Windows Forms application, without loading Codex code. Set custom consumer metadata in Control.Tag; create and update a progress view; query Get-AeroProgressViewStatus. Verify that the consumer's Tag is unchanged.
7. Schedule one real, non-destructive Codex session with the intended local time and account. Inspect Windows Task Scheduler: one registered task, correct session identity, pinned worker snapshot, and no visible console.
8. Allow a benign scheduled session to complete and inspect Recent results: completed means actual success; failure preserves the Codex exit code. A verified quota postponement is deferred and names the next task, never completed.
9. Cancel a pending task: it disappears from Windows Task Scheduler and the interface, records cancelled, and does not reappear after refreshing.
10. Change accounts or workspaces before an account-bound unattended retry. The runner must refuse execution under another identity. Missing or conflicting workspace identity must fail closed.
11. Check the result-history screen and repository suggestions after adding many completed result records; those records must not hide valid scheduled-job evidence.
12. Verify unsigned engineering preview warnings and antivirus treatment without disabling Bitdefender. Confirm that an ordinary push or merge cannot publish a GitHub release.

## Gate

Do not merge PR #16 until all relevant behavior has been verified on the same candidate commit and no critical security or functionality defect remains. A preview may remain unsigned; a production release must not be published until separately authorized, signed and verified.

After acceptance, squash-merge PR #16 into main and close PR #14 and PR #15 as superseded. Do not publish a production release as part of that merge.
