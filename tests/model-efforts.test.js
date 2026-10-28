"use strict";
const test=require('node:test');
const assert=require('node:assert/strict');
const {normalizeModels,readCodexState}=require('../CodexUsage.js');
const path=require('node:path');
test('per-model efforts are not merged, and Ultra is excluded from ordinary reasoning tiers',()=>{
  const list=normalizeModels([{data:[
    {model:'gpt-6.1-sol', defaultReasoningEffort:'medium', supportedReasoningEfforts:[{reasoningEffort:'low'},{reasoningEffort:'max'},{reasoningEffort:'ultra'}]},
    {model:'gpt-6-luna', defaultReasoningEffort:'low', supportedReasoningEfforts:[{reasoningEffort:'low'},{reasoningEffort:'high'}]},
    {model:'future', defaultReasoningEffort:'deep', supportedReasoningEfforts:[{reasoningEffort:'deep'}]}
  ]}]);
  assert.deepEqual(list[0].efforts,['low','max']);
  assert.deepEqual(list[1].efforts,['low','high']);
  assert.deepEqual(list[2].efforts,['deep']);
});
test('models-only catalog discovery does not query account rate-limit service', async()=>{
 const state=await readCodexState(path.join(__dirname,'mock-app-server.js'),{modelsOnly:true});
 assert.equal(state.ok,true);
 assert.equal(state.models.length,2);
 assert.equal(state.bucketId,undefined);
});
