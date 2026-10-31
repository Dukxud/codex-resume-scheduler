// GUI and scheduled Codex work must not create a terminal. The native
// Windows-subsystem launcher is the supported entrypoint in release packages.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

test('both desktop entrypoints use native Windows GUI launcher', () => {
  const cmd = fs.readFileSync(path.join(root, 'Start-Codex-Scheduler.cmd'), 'utf8');
  const vbs = fs.readFileSync(path.join(root, 'Start-Codex-Scheduler.vbs'), 'utf8');
  const launcher = fs.readFileSync(path.join(root, 'CodexLauncher.cs'), 'utf8');
  assert.match(cmd, /CodexScheduler\.exe/);
  assert.doesNotMatch(cmd, /start "" pwsh\.exe|WindowStyle Hidden/);
  assert.match(vbs, /CodexScheduler\.exe/);
  assert.doesNotMatch(vbs, /pwsh\.exe/);
  assert.match(launcher, /CreateNoWindow = true/);
  assert.match(launcher, /UseShellExecute = false/);
  assert.match(launcher, /ProcessWindowStyle\.Hidden/);
  assert.match(launcher, /--run-job/);
  assert.match(launcher, /process\.WaitForExit\(\)/);
});

test('Task Scheduler actions use native host for both original and retry jobs', () => {
  const source = fs.readFileSync(path.join(root, 'CodexResumeScheduler.ps1'), 'utf8');
  assert.match(source, /foreach \(\$helperFile in @\('CodexUsage\.js','CodexRetry\.js','CodexData\.ps1','CodexDashboard\.ps1','CodexScheduler\.exe'\)\)/);
  assert.match(source, /New-ScheduledTaskAction -Execute \$installedLauncher/);
  assert.match(source, /New-ScheduledTaskAction -Execute \$launcher/);
  assert.match(source, /--run-job/);
  assert.doesNotMatch(source, /-NoExit/);
  assert.match(source, /Start-Transcript/);
  assert.match(source, /Add-Content -LiteralPath \$target/);
});

test('GUI and executable show the same release version', () => {
  const source = fs.readFileSync(path.join(root, 'CodexResumeScheduler.ps1'), 'utf8');
  const launcher = fs.readFileSync(path.join(root, 'CodexLauncher.cs'), 'utf8');
  const version = fs.readFileSync(path.join(root, 'VERSION'), 'utf8').trim().replace(/\./g, '\\.');
  assert.match(source, new RegExp('Codex Resume Scheduler v' + version));
  assert.match(launcher, new RegExp('AssemblyVersion\\("' + version + '\\.0"\\)'));
});
