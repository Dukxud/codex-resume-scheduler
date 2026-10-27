// Regression: the GUI launcher and Task Scheduler runner must both handle the
// application's unsigned PowerShell source without changing machine policy.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

test('both entrypoints use process-scoped PowerShell execution policy', () => {
  const launcher = fs.readFileSync(path.join(root, 'Start-Codex-Scheduler.cmd'), 'utf8');
  const scheduler = fs.readFileSync(path.join(root, 'CodexResumeScheduler.ps1'), 'utf8');
  assert.match(launcher, /pwsh\.exe\s+[^\r\n]*-ExecutionPolicy Bypass\s+-File/);
  assert.match(scheduler, /\$runnerArgs\s*=\s*'[^']*-ExecutionPolicy Bypass\s+-File/);
  assert.match(scheduler, /\$saved\.Actions\[0\]\.Arguments\s+-notmatch\s+'[^']*-ExecutionPolicy\\s\+Bypass/);
});
