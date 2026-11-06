'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const {spawn}=require('node:child_process');
const {transact}=require('../interactive/owner-client.js');

const SESSION='11111111-2222-3333-4444-555555555555';
const RUNNER=path.resolve(__dirname,'../interactive/run-owner.js');
const MOCK=path.resolve(__dirname,'mock-interactive-app-server.js');
const NAME='CodexResume-20261105-1737-8fea70e0';
async function waitFor(predicate,timeoutMs=5000){
  const until=Date.now()+timeoutMs;
  while(Date.now()<until){
    if(await predicate())return;
    await new Promise(resolve=>setTimeout(resolve,30));
  }
  throw Error('Timed out waiting for fixture owner');
}
function fixture(dir,session=SESSION){
  const job=path.join(dir,NAME+'.json');
  const control=path.join(dir,NAME+'.interactive.json');
  fs.writeFileSync(job,JSON.stringify({
    executionMode:'interactive',sessionId:session,
    repo:process.cwd(),message:'Fixture work only',
    model:'gpt-6',effort:'high',access:'workspace-write',
  }));
  const child=spawn(process.execPath,[RUNNER,'--job',job,'--cli-js',MOCK],{
    stdio:['ignore','pipe','pipe'],
  });
  const errors=[];
  child.stderr.on('data',x=>errors.push(x.toString()));
  return {child,control,errors};
}
async function finish(child){
  return await Promise.race([
    new Promise((resolve,reject)=>{
      child.once('error',reject);
      child.once('close',resolve);
    }),
    new Promise((_,reject)=>setTimeout(()=>{
      child.kill();reject(Error('Fixture owner failed to complete'));
    },5000)),
  ]);
}
test('scheduled owner remains alive through prompt, supports reconnect, then exits truthfully',async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'continuum-run-'));
  const {child,control,errors}=fixture(dir);
  try{
    await waitFor(()=>fs.existsSync(control));
    const first=await transact({descriptor:control,action:'snapshot'});
    await waitFor(async()=>{
      const value=await transact({descriptor:control,action:'snapshot'});
      return value.pending.length===1;
    });
    const second=await transact({descriptor:control,action:'snapshot'});
    assert.equal(second.sessionId,SESSION);
    assert.equal(second.pending.length,1);
    assert.equal(child.exitCode,null,'owner stays alive awaiting response');
    await transact({descriptor:control,action:'respond',payload:{
      id:second.pending[0].id,response:{decision:'accept'},
    }});
    await waitFor(async()=>{
      const value=await transact({descriptor:control,action:'snapshot'});
      return value.phase==='awaitingUser';
    });
    assert.equal(child.exitCode,null,'owner remains available for ordinary conversational replies');
    await transact({descriptor:control,action:'message',payload:{
      text:'I approve that approach. Please continue in this same conversation.',
    }});
    await waitFor(async()=>{
      const value=await transact({descriptor:control,action:'snapshot'});
      return value.phase==='awaitingUser';
    });
    await transact({descriptor:control,action:'finish'});
    assert.equal(await finish(child),0,errors.join(''));
    assert.equal(fs.existsSync(control),false,'owner descriptor removed after exit');
  }finally{
    child.kill();fs.rmSync(dir,{recursive:true,force:true});
  }
});
test('wrong thread refusal cannot produce completed outcome',async()=>{
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'continuum-run-'));
  const {child,control}=fixture(dir,'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
  try{
    const result=await finish(child);
    assert.notEqual(result,0);
    assert.equal(fs.existsSync(control),false);
  }finally{child.kill();fs.rmSync(dir,{recursive:true,force:true});}
});
