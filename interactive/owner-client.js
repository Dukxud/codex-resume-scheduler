#!/usr/bin/env node
'use strict';
// One-shot authenticated client for bridge commands; optional streaming viewer.
// It only talks to an existing owner. It never executes or resumes Codex.
const fs=require('node:fs');
const net=require('node:net');

function parseArgs(args){
  if(args.length<3||args[0]!=='--descriptor'||!args[1]||args[2]!=='--action')
    throw Error('Expected --descriptor FILE --action snapshot|respond|steer|follow');
  if(!['snapshot','respond','steer','follow'].includes(args[3])||args.length!==4)
    throw Error('Unsupported mirror operation');
  return {descriptor:args[1],action:args[3]};
}
function openDescriptor(file){
  const d=JSON.parse(fs.readFileSync(file,'utf8'));
  if(d.schema!==1||typeof d.pipe!=='string'||typeof d.secret!=='string'||d.secret.length<32)
    throw Error('Invalid owner descriptor');
  return d;
}
function transact({descriptor,action,payload=null,timeoutMs=5000}){
  const d=openDescriptor(descriptor);
  return new Promise((resolve,reject)=>{
    const sock=net.connect(d.pipe);let done=false,buf='',authorized=false;
    const timer=setTimeout(()=>finish(Error('Existing Codex owner did not answer')),timeoutMs);
    function finish(error,response){
      if(done)return;
      done=true;clearTimeout(timer);sock.destroy();
      if(error)reject(error);else resolve(response);
    }
    sock.on('connect',()=>sock.write(JSON.stringify({kind:'hello',secret:d.secret})+'\n'));
    sock.on('error',error=>finish(Error('Existing owner is unavailable: '+error.code)));
    sock.on('close',()=>{if(!done)finish(Error('Existing owner closed the connection'))});
    sock.on('data',data=>{
      buf+=data.toString();
      if(Buffer.byteLength(buf)>4*1024*1024)return finish(Error('Mirror response too large'));
      let idx;
      while((idx=buf.indexOf('\n'))>=0){
        const line=buf.slice(0,idx);buf=buf.slice(idx+1);
        let m;try{m=JSON.parse(line)}catch{return finish(Error('Invalid owner response'))}
        if(!authorized){
          if(m.kind!=='snapshot')return finish(Error('Mirror authentication failed'));
          authorized=true;
          if(action==='snapshot')return finish(null,m.value);
          if(action==='follow'){
            // Streaming use belongs in a persistent viewer, not this one-shot
            // adapter. Keep this variant read-only.
            return finish(null,{snapshot:m.value,events:m.value.events});
          }
          sock.write(JSON.stringify({kind:action,...payload})+'\n');
          continue;
        }
        if(m.kind==='ack')return finish(null,{ok:true,id:m.id??null});
        if(m.kind==='rejected')return finish(Error(m.reason||'Owner rejected request'));
      }
    });
  });
}
async function readStdin(){
  const chunks=[];
  for await(const part of process.stdin){
    chunks.push(part);
    if(chunks.reduce((sum,b)=>sum+b.length,0)>65536)throw Error('Response input exceeds size limit');
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
async function main(args){
  const {descriptor,action}=parseArgs(args);
  const payload=action==='respond'||action==='steer'?await readStdin():null;
  const response=await transact({descriptor,action,payload});
  process.stdout.write(JSON.stringify({ok:true,result:response})+'\n');
}
if(require.main===module){
  main(process.argv.slice(2)).catch(error=>{
    process.stdout.write(JSON.stringify({ok:false,error:error.message})+'\n');
    process.exitCode=1;
  });
}
module.exports={transact,openDescriptor,parseArgs};
