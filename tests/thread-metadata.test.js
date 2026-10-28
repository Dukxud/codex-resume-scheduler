"use strict";
const test=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const {normalizeThreadRead,readThreadDirectory}=require('../CodexUsage.js');
const id='01234567-1234-4567-89ab-0123456789ab';
const mock=path.join(__dirname,'mock-app-server.js');
test('read-only thread/read uses handshake and preserves the saved cwd',async()=>{
  const result=await readThreadDirectory(mock,id,5000);
  assert.deepEqual(result,{ok:true,threadId:id,cwd:'C:\\Projects\\CodexSample'});
});
test('metadata must belong to the selected conversation',()=>{
  assert.throws(()=>normalizeThreadRead({thread:{id:'other',cwd:'C:\\evil'}},id),/unexpected thread/);
  assert.throws(()=>normalizeThreadRead({},id),/unexpected thread/);
});
test('missing cwd is not guessed',()=>{
  assert.deepEqual(normalizeThreadRead({thread:{id,cwd:null}},id),{ok:true,threadId:id,cwd:null});
  assert.deepEqual(normalizeThreadRead({thread:{id,cwd:'   '}},id),{ok:true,threadId:id,cwd:null});
});
test('invalid ids are rejected before starting Codex',async()=>{
  await assert.rejects(readThreadDirectory(mock,'../../unsafe',5000),/Invalid Codex conversation ID/);
});
