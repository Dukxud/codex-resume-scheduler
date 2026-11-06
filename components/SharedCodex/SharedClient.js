"use strict";
// A UI/terminal client for the *existing* shared controller.
// This never launches, resumes or forks a Codex process.
const fs=require("node:fs");
const path=require("node:path");
const net=require("node:net");
const readline=require("node:readline");
const jobName=/^CodexResume-\d{8}-\d{4}-[0-9a-f]{8}$/i;
function pathsFor(jobPath) {
 const name=path.basename(jobPath,".json");
 if(!jobName.test(name)||!path.isAbsolute(jobPath))throw new Error("Invalid scheduled job file.");
 return {
   control:path.join(path.dirname(jobPath),name+".shared-control.json"),
   state:path.join(path.dirname(jobPath),name+".shared-state.json")
 };
}
async function query(jobPath,action,id,result) {
 const files=pathsFor(jobPath);
 if(!fs.existsSync(files.control)) {
   if(action==="status"&&fs.existsSync(files.state))return {ok:true,state:JSON.parse(fs.readFileSync(files.state,"utf8")),offline:true};
   throw new Error("Shared controller is not running.");
 }
 const data=JSON.parse(fs.readFileSync(files.control,"utf8"));
 if(typeof data.pipe!=="string"||typeof data.auth!=="string"||!data.auth)throw new Error("Invalid controller identity.");
 return new Promise((resolve,reject)=>{
   const socket=net.createConnection(data.pipe);
   let bytes=0,text="";
   socket.setTimeout(5000,()=>socket.destroy(new Error("Shared controller timed out.")));
   socket.once("connect",()=>{
     socket.write(JSON.stringify({auth:data.auth,action,id,result})+"\n");
   });
   socket.on("data",chunk=>{
     bytes+=chunk.length;
     if(bytes>65536){socket.destroy(new Error("Controller response too large."));return;}
     text+=chunk.toString("utf8");
   });
   socket.once("end",()=>{
     try{
       const reply=JSON.parse(text.trim());
       if(!reply.ok)reject(new Error(reply.error||"Controller request failed."));
       else resolve(reply);
     }catch(error){reject(error);}
   });
   socket.once("error",reject);
 });
}
async function interactive(jobPath) {
 const rl=readline.createInterface({input:process.stdin,output:process.stdout});
 let last="";
 try{
   process.stdout.write("Connected to Continuum shared Codex owner. No second Codex process will start.\n");
   while(true){
     const response=await query(jobPath,"status");
     const state=response.state;
     if(state.status!==last) {
       process.stdout.write("\nStatus: "+state.status+"\n");
       last=state.status;
     }
     for(const q of state.questions||[]){
       if(q.id===interactive.lastQuestion)continue;
       interactive.lastQuestion=q.id;
       process.stdout.write("\nCodex needs input: "+q.method+"\n"+JSON.stringify(q.params,null,2)+"\n");
       process.stdout.write("Respond with a JSON object matching Codex's protocol (or Ctrl+C to leave it pending).\n");
       const line=await new Promise(resolve=>rl.question("> ",resolve));
       let answer;
       try{answer=JSON.parse(line);}catch{process.stdout.write("Invalid JSON; question remains pending.\n");continue;}
       try{await query(jobPath,"answer",q.id,answer);interactive.lastQuestion="";}
       catch(error){process.stdout.write("Answer refused: "+error.message+"\n");}
     }
     if(response.offline||["completed","failed"].includes(state.status))break;
     await new Promise(resolve=>setTimeout(resolve,1000));
   }
 }finally{rl.close();}
}
async function main(){
 const [jobPath,action,id,payload]=process.argv.slice(2);
 if(!jobPath||!["status","answer","follow"].includes(action))throw new Error("Usage: SharedClient JOB.json status|answer ID JSON|follow");
 if(action==="follow"){await interactive(jobPath);return;}
 const result=action==="answer"?JSON.parse(payload||"null"):undefined;
 const response=await query(jobPath,action,id,result);
 process.stdout.write(JSON.stringify(response)+"\n");
}
if(require.main===module)main().catch(e=>{process.stderr.write(e.message+"\n");process.exitCode=1;});
module.exports={query,pathsFor};
