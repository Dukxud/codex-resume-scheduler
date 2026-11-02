'use strict';
// These checks protect the Windows Forms presentation contract. They do not
// replace a live GUI test on Windows at different display scaling settings.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = ['CodexUiForms.ps1','CodexUiSelection.ps1','CodexUiPending.ps1','CodexUiUsage.ps1','CodexUiRefresh.ps1','CodexUiActions.ps1'].map(f=>fs.readFileSync(path.resolve(__dirname, '..', f),'utf8')).join('\n');
function namedFunction(name) {
  const begin = source.indexOf(`function ${name} {`);
  assert.ok(begin >= 0, `${name} should exist`);
  const nextFunction = source.indexOf('\nfunction ', begin + 10);
  const nextSection = source.indexOf('\n$dataPoll', begin + 10);
  const ends = [nextFunction, nextSection].filter(i => i >= 0);
  return source.slice(begin, ends.length ? Math.min(...ends) : undefined);
}

test('model and effort are grouped and schedule action is distinct', () => {
  assert.match(source, /New-DesktopWindow -Title 'Codex Resume Scheduler v1\.[0-9]+\.[0-9]+'/);
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
  assert.match(fn, /\$row\.Cells\[4\]\.ToolTipText/);
  assert.match(fn, /\$pending\.Text = "Upcoming runs/);
  assert.match(fn, /\$emptyRuns\.Visible = \$false/);
  assert.match(fn, /Update-DashboardLayout/);
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

test('dashboard shares the pending snapshot and renders distinct countdown and quota bars', () => {
  const dash = fs.readFileSync(path.resolve(__dirname, '..', 'CodexDashboard.ps1'), 'utf8');
  assert.match(source, /Columns\.Add\('Countdown','Time to run'\)/);
  assert.match(source, /\$grid\.RowTemplate\.Height = 54/);
  assert.match(source, /\$script:ui\.Usage\.usageRequestedModel = \$chosen/);
  assert.match(source, /compactMode = \[bool\]\$script:ui\.Dashboard\.compactToggle\.Checked/);
  assert.match(dash, /Get-RunCountdownPercent/);
  assert.match(dash, /\$grid\.Add_CellPainting/);
  assert.match(dash, /Set-AeroProgress \$script:ui\.Dashboard\.compactRunTrack \$percent/);
  assert.match(dash, /New-AeroProgressBar \$script:ui\.Dashboard\.compactRunPanel/);
  assert.match(dash, /Sync-DashboardRunBars/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactRunHeading\.Visible = \$compact -and \$script:ui\.Dashboard\.pendingSnapshot\.Count -gt 0/);
  assert.match(dash, /\$form\.ClientSize/);
  assert.match(source, /New-AeroProgressBar \$card 12 44 400 17 'quota'/);
  assert.match(source, /Set-AeroProgress \$Card.Bar \$remaining/);
  assert.match(dash, /New-AeroProgressBar \$grid 0 0 100 15 'time'/);
  assert.doesNotMatch(dash, /Draw-SchedulerProgress/);
});

test('compact switch occupies dedicated header space in both layouts', () => {
  const dash = fs.readFileSync(path.resolve(__dirname, '..', 'CodexDashboard.ps1'), 'utf8');
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Appearance = \[System\.Windows\.Forms\.Appearance\]::Button/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Text = 'Compact mode: OFF'/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Text = 'Compact mode: ON'/);
  assert.match(dash, /\$script:ui\.Dashboard\.compactToggle\.Location = \[System\.Drawing\.Point\]::new\(298,13\)/);
  assert.match(dash, /\$subtitle\.Visible = \$false/);
  assert.match(dash, /\$heading\.Width = 270/);
});
