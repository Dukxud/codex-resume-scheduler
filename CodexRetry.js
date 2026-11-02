#!/usr/bin/env node
'use strict';
// Pure turn-failure decision. Actual scheduling remains in the PowerShell runner.
const fs=require('node:fs');
const path=require('node:path');
const {isLimitErrorLine,readCodexState}=require('./CodexUsage.js');
function failureSeen(events) {return events.split(/\r?\n/).some(line=>isLimitErrorLine(line));}
function decide(events, snapshot, now=Math.floor(Date.now()/1000), exitCode=1) {
  if(exitCode===0)return {kind:'not-limit',reason:'Codex completed successfully; no retry permitted.'};
  if(!failureSeen(events))return {kind:'not-limit',reason:'Codex did not report a usage-limit failure.'};
  if(!snapshot?.ok || !snapshot.selectionVerified)return {kind:'unknown',reason:'No reliable model-to-quota mapping.'};
  if(snapshot.recommendationKind!=='exhausted-window'||!Number.isSafeInteger(snapshot.recommendedResetAt)||snapshot.recommendedResetAt<=now)
    return {kind:'unknown',reason:snapshot.blockedReason||'No reliable active quota reset.'};
  return {kind:'retry',resetAt:snapshot.recommendedResetAt,runAt:snapshot.recommendedResetAt+120,bucketId:snapshot.bucketId,accountId:snapshot.accountId||null,
    windows:snapshot.windows.filter(w=>w.usedPercent>=100).map(w=>({label:w.label,resetsAt:w.resetsAt})),
    reason:'Confirmed usage-limit failure and future applicable reset.'};
}
async function main(){
  const val=k=>{const i=process.argv.indexOf(k);return i>=0?process.argv[i+1]:null;};
  const cli=val('--cli-js'), eventsFile=val('--events'), model=val('--model');
  const exitText=val('--exit-code'),exitCode=Number(exitText);
  if(exitText===null||!Number.isSafeInteger(exitCode)||exitCode<0)throw Error('Explicit Codex process exit code is required.');
  if(!cli||!eventsFile||!model)throw Error('Required: --cli-js, --events, --model');
  const events=fs.readFileSync(eventsFile,'utf8');
  if(exitCode===0||!failureSeen(events)){process.stdout.write(JSON.stringify({kind:'not-limit'})+'\n');return;}
  const snapshot=await readCodexState(path.resolve(cli),{model,catalog:false});
  process.stdout.write(JSON.stringify(decide(events,snapshot,Math.floor(Date.now()/1000),exitCode))+'\n');
}
if(require.main===module)main().catch(e=>{process.stdout.write(JSON.stringify({kind:'unknown',reason:e.message})+'\n');process.exitCode=1;});
module.exports={failureSeen,decide};