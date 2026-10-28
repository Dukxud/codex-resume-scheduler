'use strict';
// These checks protect the Windows Forms presentation contract. They do not
// replace a live GUI test on Windows at different display scaling settings.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.resolve(__dirname, '..', 'CodexResumeScheduler.ps1'), 'utf8');
function namedFunction(name) {
  const begin = source.indexOf(`function ${name} {`);
  assert.ok(begin >= 0, `${name} should exist`);
  const nextFunction = source.indexOf('\nfunction ', begin + 10);
  const nextSection = source.indexOf('\n$dataPoll', begin + 10);
  const ends = [nextFunction, nextSection].filter(i => i >= 0);
  return source.slice(begin, ends.length ? Math.min(...ends) : undefined);
}

test('model and effort are grouped and schedule action is distinct', () => {
  assert.match(source, /\$form\.Text = 'Codex Resume Scheduler v1\.8'/);
  assert.match(source, /\$modelBox\.Location = \[System\.Drawing\.Point\]::new\(155,199\)/);
  assert.match(source, /\$effortBox\.Location = \[System\.Drawing\.Point\]::new\(597,199\)/);
  assert.match(source, /\$accessBox\.Location = \[System\.Drawing\.Point\]::new\(597,154\)/);
  assert.match(source, /\$schedule = Add-Button 'Schedule once' 720 274 178/);
  assert.match(source, /\$autoResumeCheck\.Text = 'Retry if Codex hits a usage limit \(max 4\)'/);
});

test('pending list shows recognizable project and preserves full task identity', () => {
  const fn = namedFunction('Apply-PendingList');
  assert.match(fn, /\$project = if \(\$path/);
  assert.match(fn, /\$row\.Tag = \$item\.Name/);
  assert.match(fn, /\$row\.Cells\[3\]\.ToolTipText/);
  assert.match(fn, /\$pending\.Text = "Upcoming runs/);
  assert.match(fn, /\$emptyRuns\.Visible = \(\$Items\.Count -eq 0\)/);
  assert.doesNotMatch(fn, /Update-Status/);
  assert.match(source, /\$cancelRun\.Enabled = \$false/);
});

test('background result does not override an entered root and list refresh retains it', () => {
  const lookup = source.slice(source.indexOf("'selection' {", source.indexOf('$dataPoll.Add_Tick')));
  assert.match(lookup, /if \(-not \[string\]::IsNullOrWhiteSpace\(\$repoBox\.Text\)\) \{ break \}/);
  const sessions = namedFunction('Apply-SessionList');
  assert.match(sessions, /if \(\$selectedId -and \$chosen -and -not \[string\]::IsNullOrWhiteSpace\(\$repoBox\.Text\)\)/);
});

test('usage reports remaining and keeps reset as an explicit action', () => {
  assert.match(source, /Usage remaining/);
  assert.match(source, /% remaining' -f \$remaining/);
  assert.match(source, /\$useReset\.Add_Click\(/);
  assert.match(source, /Next reset is informational/);
});
