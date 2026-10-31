// GUI startup must not keep a console open. Scheduled jobs run hidden and log output.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

test('both GUI launchers use hidden process-scoped PowerShell', () => {
  const cmd = fs.readFileSync(path.join(root, 'Start-Codex-Scheduler.cmd'), 'utf8');
  const vbs = fs.readFileSync(path.join(root, 'Start-Codex-Scheduler.vbs'), 'utf8');
  assert.match(cmd, /wscript\.exe/);
  assert.match(cmd, /start "" pwsh\.exe[^\r\n]*-WindowStyle Hidden[^\r\n]*-ExecutionPolicy Bypass\s+-File/);
  assert.match(vbs, /pwsh\.exe[^\r\n]*-WindowStyle Hidden[^\r\n]*-ExecutionPolicy Bypass\s+-File/);
  assert.match(vbs, /shell\.Run command, 0, False/);
});

test('scheduled runners close automatically and retain process-scoped execution policy', () => {
  const source = fs.readFileSync(path.join(root, 'CodexResumeScheduler.ps1'), 'utf8');
  assert.match(source, /\$runnerArgs\s*=\s*'[^']*-WindowStyle Hidden\s+-ExecutionPolicy Bypass\s+-File/);
  assert.match(source, /\$arguments\s*=\s*'[^']*-WindowStyle Hidden\s+-ExecutionPolicy Bypass\s+-File/);
  assert.doesNotMatch(source, /-NoExit/);
  assert.match(source, /Start-Transcript/);
  assert.match(source, /Add-Content -LiteralPath \$target/);
  assert.match(source, /\$saved\.Actions\[0\]\.Arguments\s+-notmatch\s+'[^']*-ExecutionPolicy\\s\+Bypass/);
});
