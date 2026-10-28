'use strict';
const readline=require('node:readline');
const rl=readline.createInterface({input:process.stdin});
let initialized=false;
rl.on('line',line=>{
  const m=JSON.parse(line);
  if(m.method==='initialize')process.stdout.write(JSON.stringify({id:m.id,result:{userAgent:'mock'}})+'\n');
  if(m.method==='initialized')initialized=true;
  if(m.method==='model/list'&&initialized)process.stdout.write(JSON.stringify({id:m.id,result:{data:[
    {model:'gpt-6-astra',displayName:'Astra',defaultReasoningEffort:'high',supportedReasoningEfforts:[{reasoningEffort:'low'},{reasoningEffort:'medium'},{reasoningEffort:'high'},{reasoningEffort:'xhigh'}],isDefault:true},
    {model:'gpt-6.1-sol',displayName:'Sol',defaultReasoningEffort:'medium',supportedReasoningEfforts:[{reasoningEffort:'medium'}]}],nextCursor:null}})+'\n');
  if(m.method==='thread/read'&&initialized)process.stdout.write(JSON.stringify({id:m.id,result:{thread:{id:m.params.threadId,cwd:process.env.MOCK_CODEX_CWD||'C:\\Projects\\CodexSample',status:{type:'notLoaded'},turns:[]}}})+'\n');
  if(m.method==='account/rateLimits/read'&&initialized)process.stdout.write(JSON.stringify({id:m.id,result:{ordinaryUsageAllowed:false,
    rateLimits:{limitId:'codex',primary:{usedPercent:100,windowDurationMins:300,resetsAt:Math.floor(Date.now()/1000)+200}}}})+'\n');
});
