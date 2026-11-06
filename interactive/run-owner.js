#!/usr/bin/env node
'use strict';
// Launched by the existing, validated PowerShell Scheduler worker.
// The Scheduler worker MUST hold the per-thread mutex until this exits.
const fs=require('node:fs');
const path=require('node:path');
const {randomUUID}=require('node:crypto');
const {InteractiveOwner}=require('./interactive-owner.js');
const {OwnerMirror}=require('./owner-mirror.js');

function parseArgs(args){
  if(args.length!==4||args[0]!=='--job'||args[2]!=='--cli-js')
    throw Error('Expected --job FILE --cli-js FILE');
  const jobFile=path.resolve(args[1]),cliJs=path.resolve(args[3]);
  if(!fs.statSync(jobFile).isFile()||!fs.statSync(cliJs).isFile())
    throw Error('Missing pinned Codex job or CLI entrypoint');
  return {jobFile,cliJs};
}
function loadRun(jobFile){
  const job=JSON.parse(fs.readFileSync(jobFile,'utf8'));
  if(job.executionMode!=='interactive')throw Error('Job was not scheduled as interactive');
  // No alternate conversation, no fallback to hidden codex exec, no fork.
  return {
    sessionId:job.sessionId,cwd:job.repo,message:job.message,
    model:job.model,effort:job.effort,access:job.access,
  };
}
function descriptorPath(jobFile){
  return path.join(path.dirname(jobFile),path.basename(jobFile,'.json')+'.interactive.json');
}
function pipePath(name){
  const part=name.replace(/[^a-zA-Z0-9_-]/g,'');
  if(process.platform==='win32')return '\\\\.\\pipe\\continuum-'+part+'-'+randomUUID();
  return path.join(require('node:os').tmpdir(),'continuum-'+part+'-'+randomUUID()+'.sock');
}
async function main(args){
  const {jobFile,cliJs}=parseArgs(args);
  const run=loadRun(jobFile);
  const name=path.basename(jobFile,'.json');
  if(!/^CodexResume-\d{8}-\d{4}-[0-9a-f]{8}$/i.test(name))
    throw Error('Unrecognized scheduler job identity');
  const descriptor=descriptorPath(jobFile);
  const owner=new InteractiveOwner({cliJs});
  const mirror=new OwnerMirror(owner,{pipe:pipePath(name)});
  let registered=false;
  let turnFinished;
  const completed=new Promise(resolve=>{turnFinished=resolve;});
  let outcome=null;
  owner.on('event',event=>{
    if(event.type==='turnCompleted'){
      outcome=event.params?.turn?.status==='completed'?'completed':'failed';
      turnFinished();
    }else if(event.type==='closed'){
      if(!outcome)outcome='lost';
      turnFinished();
    }
  });
  try{
    await mirror.listen();
    // Exclusive creation refuses stale/unreconciled pointers. Windows user
    // profile ACL is required; mode 0600 additionally protects Unix test hosts.
    const info={
      schema:1,job:name,sessionId:run.sessionId,
      pipe:mirror.pipe,secret:mirror.secret,
      ownerPid:process.pid,createdAt:new Date().toISOString(),
    };
    fs.writeFileSync(descriptor,JSON.stringify(info),{flag:'wx',mode:0o600});
    registered=true;
    await owner.start(run);
    await completed;
    return outcome==='completed'?0:1;
  }finally{
    // Remove discoverability before closing the owner; no hidden second run.
    if(registered){
      try{fs.unlinkSync(descriptor)}catch{/* Fail closed if stale */ }
    }
    await mirror.close();
    owner.terminate();
  }
}
if(require.main===module){
  main(process.argv.slice(2)).then(code=>{
    process.exitCode=code;
  },error=>{
    // Never dump prompts or job instructions into the task transcript.
    process.stderr.write('Interactive owner could not complete: '+error.message+'\n');
    process.exitCode=1;
  });
}
module.exports={parseArgs,loadRun,descriptorPath,pipePath,main};
