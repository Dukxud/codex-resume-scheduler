'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const ps=fs.readFileSync(path.join(__dirname,'..','CodexResumeScheduler.ps1'),'utf8');
test('scheduled jobs retain explicit model, reasoning and repo on limit retries',()=>{
 for(const f of ['sessionId','repo','branch','model','effort','access','message'])assert.match(ps,new RegExp(`${f}=\\$Job\\.${f}`));
 assert.match(ps,/\$argsList\s*=\s*@\('exec','--json','-m',\$model/);
 assert.match(ps,/\$attempt\s*=\s*\[int\]\$Job.retryAttempt\s*\+\s*1/);
 assert.match(ps,/\$attempt\s+-gt\s+4/);
 assert.match(ps,/Schedule-LimitRetry\s+\$job/);
 assert.match(ps,/--events\s+\$events\s+--cli-js/);
});
test('installing a job brings the usage and decision helpers',()=>{
 assert.match(ps, /@\('CodexUsage\.js','CodexRetry\.js','CodexData\.ps1','CodexDashboard\.ps1','CodexScheduler\.exe'\)/);
 assert.match(ps, /--run-job/);
});
