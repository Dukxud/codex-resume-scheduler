'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');

test('launchers rely only on the Windows provided script host', () => {
  const cmd = fs.readFileSync(path.join(root, 'Start-Codex-Scheduler.cmd'), 'utf8');
  const gui = fs.readFileSync(path.join(root, 'Start-Codex-Scheduler.vbs'), 'utf8');
  const runner = fs.readFileSync(path.join(root, 'CodexRunJob.vbs'), 'utf8');
  assert.match(cmd, /wscript\.exe/);
  assert.match(gui, /CreateObject\("WScript\.Shell"\)/);
  assert.match(gui, /shell\.Run\(command,\s*0,\s*False\)/);
  assert.match(runner, /shell\.Run\(command,\s*0,\s*True\)/);
  assert.match(runner, /WScript\.Quit status/);
  for(const launcher of [gui,runner]) {
    assert.match(launcher,/pwsh = files\.BuildPath\(shell\.ExpandEnvironmentStrings\("%ProgramFiles%"\), "PowerShell\\7\\pwsh\.exe"\)/);
    assert.match(launcher,/command = Chr\(34\) & pwsh & Chr\(34\)/);
    assert.doesNotMatch(launcher,/command\s*=\s*"pwsh\.exe/i);
  }
  assert.match(runner, /-RunJob -JobFile/);
  assert.doesNotMatch(gui + runner + cmd, /CodexScheduler\.exe|CodexLauncher\.cs/);
  assert.equal(fs.existsSync(path.join(root, 'CodexLauncher.cs')), false);
});

test('scheduled jobs and retries use the installed Windows Script Host wrapper', () => {
  const engine = fs.readFileSync(path.join(root, 'CodexRunEngine.ps1'), 'utf8');
  const actions = fs.readFileSync(path.join(root, 'CodexUiActions.ps1'), 'utf8');
  assert.match(engine, /CodexRunJob\.vbs/);
  assert.match(engine, /Register-OneTimeTask/);
  assert.match(actions, /Register-OneTimeTask/);
  assert.match(engine, /Start-Transcript/);
  assert.doesNotMatch(engine + actions, /CodexScheduler\.exe|-NoExit/);
});

test('release version is displayed in the interface', () => {
  const source = fs.readFileSync(path.join(root, 'CodexUiForms.ps1'), 'utf8');
  const version = fs.readFileSync(path.join(root, 'VERSION'), 'utf8').trim();
  assert.ok(source.includes("Codex Resume Scheduler v" + version));
  assert.match(version, /^\d+\.\d+\.\d+$/);
});
