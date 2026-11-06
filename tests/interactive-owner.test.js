'use strict';
const assert=require('node:assert/strict');
const path=require('node:path');
const net=require('node:net');
const {randomUUID}=require('node:crypto');
const {test}=require('node:test');
const {InteractiveOwner}=require('../interactive/interactive-owner.js');
const {OwnerMirror}=require('../interactive/owner-mirror.js');

const SESSION='11111111-2222-3333-4444-555555555555';
const CWD=process.cwd();
const CLI=path.resolve(__dirname,'mock-interactive-app-server.js');
const RUN={sessionId:SESSION,cwd:CWD,message:'Test interactive approval',model:'gpt-6',effort:'high',access:'workspace-write'};
function endpoint(){
  return process.platform==='win32'
    ? '\\\\.\\pipe\\continuum-ci-'+randomUUID()
    : path.join(require('node:os').tmpdir(),'continuum-ci-'+randomUUID()+'.sock');
}
async function client(pipe,secret){
  const socket=net.connect(pipe);
  const messages=[];let buffer='';
  const listeners=[];
  function push(message){
    messages.push(message);
    for(const waiter of listeners.slice()){
      if(waiter.predicate(message)){
        listeners.splice(listeners.indexOf(waiter),1);
        clearTimeout(waiter.timer);
        waiter.resolve(message);
      }
    }
  }
  socket.on('data',chunk=>{
    buffer+=chunk.toString();
    let index;
    while((index=buffer.indexOf('\n'))>=0){
      const line=buffer.slice(0,index);buffer=buffer.slice(index+1);
      push(JSON.parse(line));
    }
  });
  const waitFor=(predicate,ms=4000)=>{
    const existing=messages.find(predicate);
    if(existing)return Promise.resolve(existing);
    return new Promise((resolve,reject)=>{
      const waiter={predicate,resolve,timer:null};
      waiter.timer=setTimeout(()=>{
        listeners.splice(listeners.indexOf(waiter),1);
        reject(Error('Timed out waiting for mirror event'));
      },ms);listeners.push(waiter);
    });
  };
  await new Promise((resolve,reject)=>{
    socket.once('connect',resolve);socket.once('error',reject);
  });
  socket.write(JSON.stringify({kind:'hello',secret})+'\n');
  await waitFor(m=>m.kind==='snapshot');
  return {socket,waitFor,messages,send:m=>socket.write(JSON.stringify(m)+'\n')};
}
test('single Codex process; multiple viewers; question replay and explicit answer',async()=>{
  let launches=0;
  const spawn=require('node:child_process').spawn;
  const owner=new InteractiveOwner({cliJs:CLI,spawnChild:(...a)=>{
    launches++;return spawn(...a);
  }});
  const mirror=new OwnerMirror(owner,{pipe:endpoint()});
  try{
    await mirror.listen();
    await owner.start(RUN);
    assert.equal(launches,1,'one Codex process');
    assert.equal(owner.snapshot().sessionId,SESSION);
    const a=await client(mirror.pipe,mirror.secret);
    const b=await client(mirror.pipe,mirror.secret);
    try{
      assert.equal(a.messages[0].value.phase,'awaitingInput');
      assert.equal(b.messages[0].value.pending.length,1);
      const prompt=b.messages[0].value.pending[0];
      assert.equal(prompt.method,'item/commandExecution/requestApproval');
      b.send({kind:'respond',id:prompt.id,response:{decision:'accept'}});
      await b.waitFor(m=>m.kind==='ack'&&m.id===prompt.id);
      await a.waitFor(m=>m.kind==='event'&&m.event.type==='turnCompleted');
      assert.equal(owner.snapshot().phase,'awaitingUser');
      assert.equal(launches,1,'viewers do not spawn additional writers');
      a.send({kind:'respond',id:prompt.id,response:{decision:'accept'}});
      await a.waitFor(m=>m.kind==='rejected');
      assert.equal(owner.snapshot().pending.length,0);
    }finally{a.socket.destroy();b.socket.destroy();}
  }finally{await mirror.close();owner.terminate();}
});
test('an unknown Codex server request fails closed and cannot gain approval',()=>{
  const owner=new InteractiveOwner({cliJs:CLI});
  owner.ingest(JSON.stringify({id:97,method:'unexpected/sensitivePermission',params:{}}));
  assert.equal(owner.snapshot().pending.length,0);
  assert.equal(owner.snapshot().events[0].type,'unsupportedPrompt');
  owner.terminate();
});
test('invalid run options never launch a process',async()=>{
  let launches=0;
  const owner=new InteractiveOwner({cliJs:CLI,spawnChild:()=>{
    launches++;throw Error('Do not launch');
  }});
  await assert.rejects(()=>owner.start({...RUN,access:'yolo'}),/unrestricted/);
  assert.equal(launches,0);
});
test('mirror rejects unauthenticated clients and arbitrary executable RPC',async()=>{
  const owner=new InteractiveOwner({cliJs:CLI});
  const mirror=new OwnerMirror(owner,{pipe:endpoint(),secret:'x'.repeat(64)});
  try{
    await mirror.listen();
    const raw=net.connect(mirror.pipe);
    await new Promise((resolve,reject)=>{
      raw.once('connect',resolve);raw.once('error',reject);
    });
    raw.write(JSON.stringify({kind:'hello',secret:'bad'})+'\n');
    await new Promise((resolve,reject)=>{
      raw.once('close',resolve);setTimeout(()=>reject(Error('Unauthenticated mirror socket stayed open')),3000);
    });
    const authorized=await client(mirror.pipe,mirror.secret);
    try{
      authorized.send({kind:'exec',command:'whoami'});
      const reply=await authorized.waitFor(m=>m.kind==='rejected');
      assert.match(reply.reason,/Unsupported/);
    }finally{authorized.socket.destroy();}
  }finally{await mirror.close();owner.terminate();}
});
