'use strict';
// Enforce dependency direction: reusable components -> platform only; Codex -> reusable.
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const read=file=>fs.readFileSync(path.join(root,file),'utf8');
const modules=['AeroProgress','Countdown','SettingsStore','RuntimeBundle','OneTimeTasks',
  'GitRepository','JobOutcomes','WindowShell','ProgressHost','FlowingProgress'];
const ui=['CodexUiForms.ps1','CodexUiSelection.ps1','CodexUiPending.ps1','CodexUiUsage.ps1','CodexUiRefresh.ps1','CodexUiActions.ps1','CodexUiLifecycle.ps1','CodexDashboard.ps1'];
test('every independently importable component is explicitly manifested and Codex-free',()=>{
 for(const name of modules){
   const source=read('components/'+name+'/'+name+'.psm1');
   const manifest=read('components/'+name+'/'+name+'.psd1');
   assert.match(manifest,/RootModule\s*=/,name);
   assert.match(manifest,/FunctionsToExport\s*=/,name);
   assert.match(source,/Export-ModuleMember -Function/,name);
   assert.doesNotMatch(source,/\bCodex(?:Resume|Scheduler|Ui|Data|Usage|Retry)\b/i,name+' depends on Codex');
   assert.doesNotMatch(source,/\$script:ui(?:\.|\b)/,name+' depends on UI state');
 }
});
test('worker loads no GUI, CodexData or ambient session globals',()=>{
 const worker=read('CodexRunEngine.ps1');
 const main=read('CodexResumeScheduler.ps1');
 assert.doesNotMatch(worker,/CodexUi|CodexDashboard|System\.Windows\.Forms|\$sessionIdPattern|Get-RepositoryRoot\b/);
 assert.match(worker,/Get-GitRepositoryRoot/);
 assert.match(worker,/Import-Module.+GitRepository/);
 assert.match(worker,/Import-Module.+JobOutcomes/);
 const run=main.indexOf('if ($RunJob) {');
 const uiImport=main.indexOf("'CodexUiState.ps1'");
 assert.ok(run>=0 && uiImport>run,'worker must exit before any UI module loads');
});
test('UI state ownership is explicit and cross-file categories are declared',()=>{
 const groups=new Set(['Selection','Usage','Preferences','Dashboard']);
 for(const file of ui){
   const source=read(file);
   for(const match of source.matchAll(/\$script:([A-Za-z_]\w*)/g)){
     const name=match[1];
     if(name==='ui'){
       const rest=source.slice(match.index);
       const group=rest.match(/^\$script:ui\.([A-Za-z]+)/)?.[1];
       assert.ok(groups.has(group),file+' references unowned UI group');
     }else{
       assert.ok(name==='aeroAppearance'||name==='aeroHealthTimer',file+' uses unowned script variable '+name);
     }
   }
 }
});
test('scheduled runtime snapshot excludes every GUI module',()=>{
 const worker=read('CodexRunEngine.ps1');
 const runtime=worker.match(/function Get-CodexRuntimeFiles\s*\{([\s\S]*?)\n\}/)?.[1];
 assert.ok(runtime,'runtime dependency manifest missing');
 for(const file of ['CodexResumeScheduler.ps1','CodexRunEngine.ps1','CodexUsage.js','CodexRetry.js',
                     'components/RuntimeBundle/RuntimeBundle.psm1','components/GitRepository/GitRepository.psm1',
                     'components/JobOutcomes/JobOutcomes.psm1','components/SettingsStore/SettingsStore.psm1']){
   assert.ok(runtime.includes("'"+file+"'"),'worker missing '+file);
 }
 assert.doesNotMatch(runtime,/CodexUiForms|CodexUiState|CodexDashboard|CodexData|AeroBar\.html/);
});

test('pending jobs never mix with result histories and countdowns do not scan pending list for every row',()=>{
 const data=read('CodexData.ps1'),store=read('CodexJobStore.ps1'),dash=read('CodexDashboard.ps1');
 assert.match(data,/Get-CodexJobPayloadFiles/);
 assert.match(store,/\.result\\\.json/);
 assert.match(store,/Get-CodexRunHistory/);
 assert.match(dash,/pendingIndex/);
 assert.doesNotMatch(dash,/pendingSnapshot\s*\|\s*Where-Object/);
});
test('run history is user-visible and retry linking is persistent',()=>{
 assert.match(read('CodexUiForms.ps1'),/\$recentResults = Add-Button/);
 assert.match(read('CodexUiActions.ps1'),/Show-CodexRunHistoryDialog/);
 assert.match(read('CodexRunEngine.ps1'),/NextJob \(\[string\]\$nextJob\)/);
});
