'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const path=require('node:path');
const {summarizeRateLimits,describeWindow,normalizeModels,readCodexState,isLimitErrorLine}=require('../CodexUsage.js');
const {decide,failureSeen}=require('../CodexRetry.js');
const now=1793000000;const win=(used,delta,duration=300)=>({usedPercent:used,resetsAt:now+delta,windowDurationMins:duration});
const bucket=(used,delta,model,duration=300)=>({normalModelSlug:model,primary:win(used,delta,duration)});
test('multiple active 5-hour and weekly windows use last blocking reset',()=>{
 const v=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimits:{primary:win(100,300),secondary:win(100,2000,10080)}},now,'new-model');
 assert.equal(v.recommendedResetAt,now+2000);assert.equal(v.recommendationKind,'exhausted-window');
 assert.equal(v.windows[1].label,'Weekly');
});
test('unknown quota binding never borrows reset from another model',()=>{
 const v=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimitsByLimitId:{terra:bucket(100,100,'terra'),luna:bucket(100,300,'luna')}},now,'sol');
 assert.equal(v.recommendedResetAt,null);assert.equal(v.selectionVerified,false);
});
test('per-model bucket overrides unrelated exhausted bucket',()=>{
 const rates={ordinaryUsageAllowed:true,rateLimitsByLimitId:{astra:bucket(100,200,'astra'),sol:bucket(25,400,'sol')}};
 const v=summarizeRateLimits(rates,now,'sol');assert.equal(v.bucketId,'sol');assert.equal(v.recommendationKind,'next-window');
 assert.equal(v.recommendedResetAt,now+400);
});
test('no inferred time when exhausted window lacks reset or backend restricts without exhaustion',()=>{
 const a=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimits:{primary:{usedPercent:100}}},now,'any');
 const b=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimits:{primary:win(20,200)}},now,'any');
 assert.equal(a.recommendedResetAt,null);assert.equal(b.recommendedResetAt,null);
});
test('spend controls cannot be treated as a timed quota',()=>{
 const a=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimits:{...bucket(100,300,'model'),spendControlReached:true}},now,'model');
 assert.equal(a.recommendedResetAt,null);
});
test('dynamic model and reasoning catalog retains unknown effort ids',()=>{
 assert.deepEqual(normalizeModels([{data:[{id:'future',displayName:'Future',isDefault:true,defaultReasoningEffort:'superdeep',supportedReasoningEfforts:[{reasoningEffort:'superdeep'}]}]}])[0].efforts,['superdeep']);
});
test('app-server discovery and rate limits work using same handshake',async()=>{
 const v=await readCodexState(path.join(__dirname,'mock-app-server.js'));
 assert.equal(v.models.length,2);assert.equal(v.models[0].id,'gpt-6-astra');
 assert.equal(v.recommendationKind,'exhausted-window');
});
test('only actual structured limit errors trigger retry analysis',()=>{
 assert.equal(isLimitErrorLine(JSON.stringify({type:'user',message:'usage limit'})),false);
 assert.equal(isLimitErrorLine(JSON.stringify({type:'turn.failed',error:{message:'Usage limit exceeded'}})),true);
 assert.equal(failureSeen('ERROR: You have hit your usage limit'),true);
 assert.equal(failureSeen('ERROR: unsupported model'),false);
});
test('retries only with actual error and verified future reset',()=>{
 const snapshot=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimits:{primary:win(100,600)}},now,'any');
 const error='{"type":"turn.failed","error":{"message":"Usage limit exceeded"}}';
 assert.equal(decide(error,snapshot,now).runAt,now+720);
 assert.equal(decide(error,snapshot,now,0).kind,'not-limit'); // even a stale error event cannot retry a successful command
 assert.equal(decide('complete',snapshot,now).kind,'not-limit');
 assert.equal(decide(error,{...snapshot,selectionVerified:false},now).kind,'unknown');
});
test('quota percentages are remaining and bounded',()=>{
 assert.equal(describeWindow({usedPercent:75},'Primary').remainingPercent,25);
 assert.equal(describeWindow({usedPercent:111},'Primary').remainingPercent,0);
});
test('single explicitly model-labelled bucket is not automatically treated as a global quota',()=>{
 const s=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimitsByLimitId:{luna:bucket(100,300,'luna')}},now,'astra');
 assert.equal(s.selectionVerified,false);assert.equal(s.recommendedResetAt,null);
});
test('unknown backend payload fails safely and never synthesizes a reset',()=>{
 const s=summarizeRateLimits({rateLimitsByLimitId:{a:{primary:{usedPercent:'100',resetsAt:'tomorrow'}}}},now,'a');
 assert.equal(s.recommendedResetAt,null);assert.equal(s.canAttempt,false);
});

test('workspace-credit and spend-control blockers are not treated as timed usage resets',()=>{
 const v=summarizeRateLimits({ordinaryUsageAllowed:false,rateLimits:{primary:win(100,600),rateLimitReachedType:'workspace_member_usage_limit_reached'}},now,'model');
 assert.equal(v.recommendedResetAt,null);
});

test('retry assessment includes the freshly verified account identity',()=>{
 const snapshot=summarizeRateLimits({accountId:'account-abc',ordinaryUsageAllowed:false,rateLimits:{primary:win(100,600)}},now,'model');
 const error='{"type":"turn.failed","error":{"message":"Usage limit exceeded"}}';
 assert.equal(decide(error,snapshot,now,17).accountId,'account-abc');
});
