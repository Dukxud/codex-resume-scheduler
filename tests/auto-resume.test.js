'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const ps=fs.readFileSync(path.join(__dirname,'..','CodexRunEngine.ps1'),'utf8');
const ui=fs.readFileSync(path.join(__dirname,'..','CodexUiActions.ps1'),'utf8');
test('scheduled jobs retain explicit model, reasoning and repo on limit retries',()=>{
 for(const f of ['sessionId','repo','branch','model','effort','access','message'])assert.match(ps,new RegExp(`${f}=\\$Job\\.${f}`));
 assert.match(ps,/\$argsList\s*=\s*@\('exec','--json','-m',\$model/);
 assert.match(ps,/\$attempt\s*=\s*\[int\]\$Job.retryAttempt\s*\+\s*1/);
 assert.match(ps,/\$attempt\s+-gt\s+4/);
 assert.match(ps,/Schedule-LimitRetry\s+\$job/);
 assert.match(ps,/--events\s+\$events\s+--cli-js/);
});
test('installing a job brings the usage and decision helpers',()=>{
 assert.match(ps, /Get-CodexRuntimeFiles/);
 assert.match(ps, /runtimeFingerprint/);
 assert.match(ui, /Publish-ImmutableRuntime/);
 assert.match(ps, /CodexRunJob\.vbs/);
});

test('successful Codex executions never enter retry analysis and failures return nonzero',()=>{
 assert.match(ps,/if \(\$auto -and \$result -ne 0\)/);
 assert.match(ps,/--exit-code \$result/);
 assert.match(ps,/return \$\(if \(\[int\]\$result -eq 0\)/);
 assert.match(ps,/return 1\s+\} finally/);
});

test('account binding is checked before every automatic worker run',()=>{
 assert.match(ps,/if \(\$auto\) \{\s+\$state = Read-UsageState \$model/);
 assert.match(ps,/if \(-not \$state\.accountId -or \$job\.accountId -cne \$state\.accountId\)/);
});
