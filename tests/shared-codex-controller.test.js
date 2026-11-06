"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const os=require("node:os");
const {spawn}=require("node:child_process");
const {query}=require("../components/SharedCodex/SharedClient.js");
const {sandboxFor}=require("../components/SharedCodex/SharedController.js");
const ROOT=path.resolve(__dirname,"..");
function sleep(ms){return new Promise(resolve=>setTimeout(resolve,ms));}
async function until(fn,ms=7000){
 const start=Date.now();
 while(Date.now()-start<ms){
   try{const result=await fn();if(result)return result;}catch{}
   await sleep(50);
 }
 throw new Error("Expected service condition not reached.");
}
test("shared owner blocks for user question; independent client answers original thread; no second writer",async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),"continuum-shared-"));
 const name="CodexResume-20261105-2138-aabbccdd";
 const jobPath=path.join(dir,name+".json");
 const cliJs=path.join(dir,"fake-codex.js");
 fs.writeFileSync(jobPath,JSON.stringify({
  sessionId:"11111111-2222-3333-4444-555555555555",
  repo:dir,model:"gpt-6",effort:"high",access:"workspace-write",message:"Continue."
 }));
 fs.writeFileSync(cliJs,[
 'const readline=require("node:readline");',
 'const rl=readline.createInterface({input:process.stdin});',
 'let started=false;',
 'const send=x=>process.stdout.write(JSON.stringify(x)+"\\n");',
 'rl.on("line",line=>{',
 ' const x=JSON.parse(line);',
 ' if(x.method==="initialize")send({id:x.id,result:{userAgent:"fake"}});',
 ' if(x.method==="thread/resume")send({id:x.id,result:{thread:{id:"11111111-2222-3333-4444-555555555555"}}});',
 ' if(x.method==="turn/start"){',
 '   if(started)throw Error("Second turn started");',
 '   started=true;',
 '   if(x.params.threadId!=="11111111-2222-3333-4444-555555555555")throw Error("Wrong thread");',
 '   if(x.params.sandboxPolicy.type!=="workspaceWrite")throw Error("Wrong sandbox");',
 '   send({id:x.id,result:{turn:{id:"turn-one"}}});',
 '   send({id:99,method:"item/tool/requestUserInput",params:{questions:[{id:"direction",header:"Choose direction"}]}});',
 ' }',
 ' if(x.id===99&&!x.method){',
 '   if(x.result.answers.direction.answers[0]!=="Proceed safely")throw Error("Wrong answer");',
 '   send({method:"turn/completed",params:{turn:{id:"turn-one",status:"completed"}}});',
 ' }',
 '});'
 ].join("\n").replace('+"\\\\n"','+"\\n"'));
 const proc=spawn(process.execPath,[path.join(ROOT,"components/SharedCodex/SharedController.js"),jobPath,cliJs],{
  stdio:["ignore","pipe","pipe"]});
 let stderr="";
 proc.stderr.on("data",c=>stderr+=String(c));
 try{
   const snapshot=await until(async()=>{
     const r=await query(jobPath,"status");
     return r.state.status==="waiting"?r.state:null;
   });
   assert.equal(snapshot.sessionId,"11111111-2222-3333-4444-555555555555");
   assert.equal(snapshot.questions.length,1);
   assert.equal(snapshot.questions[0].method,"item/tool/requestUserInput");
   assert.equal(proc.exitCode,null);
   await assert.rejects(query(jobPath,"answer",99,{answers:{direction:{answers:[false]}}}),/Invalid answer/);
   const answered=await query(jobPath,"answer",99,{answers:{direction:{answers:["Proceed safely"]}}});
   assert.equal(answered.ok,true);
   const exit=await Promise.race([
     new Promise(resolve=>proc.once("exit",resolve)),
     sleep(5000).then(()=>{throw new Error("Service did not finish after answer");})
   ]);
   assert.equal(exit,0,stderr);
   const end=await query(jobPath,"status");
   assert.equal(end.state.status,"completed");
   assert.equal(end.offline,true);
   assert.equal(fs.existsSync(path.join(dir,name+".shared-control.json")),false);
 }finally{
   if(proc.exitCode===null)proc.kill();
   await sleep(100);
   fs.rmSync(dir,{recursive:true,force:true});
 }
});
test("sandbox choices preserve requested permissions",()=>{
 assert.equal(sandboxFor("read-only").type,"readOnly");
 assert.equal(sandboxFor("workspace-write").type,"workspaceWrite");
 assert.equal(sandboxFor("yolo").type,"dangerFullAccess");
 assert.throws(()=>sandboxFor("bogus"),/Invalid/);
});
