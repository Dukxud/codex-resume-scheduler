"use strict";
// Runs as the ONLY writer of a scheduled conversation. A named-pipe control
// channel lets local views receive questions and answer without spawning Codex.
const fs = require("node:fs");
const path = require("node:path");
const net = require("node:net");
const crypto = require("node:crypto");
const {spawn} = require("node:child_process");
const {CodexSharedProtocol} = require("./SharedProtocol.js");

const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const taskName = /^CodexResume-\d{8}-\d{4}-[0-9a-f]{8}$/i;
function sandboxFor(access) {
  if(access === "read-only")return {type:"readOnly",networkAccess:false};
  if(access === "workspace-write")return {type:"workspaceWrite",writableRoots:[],networkAccess:false,
    excludeTmpdirEnvVar:false,excludeSlashTmp:false};
  if(access === "yolo")return {type:"dangerFullAccess"};
  throw new Error("Invalid shared-session sandbox.");
}
function validateJob(job) {
  if(!job || !UUID.test(job.sessionId) ||
     typeof job.repo !== "string" || !path.isAbsolute(job.repo) ||
     typeof job.message !== "string" || !job.message.trim() ||
     typeof job.model !== "string" || !/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$/.test(job.model) ||
     typeof job.effort !== "string" || !/^[a-zA-Z][a-zA-Z0-9_-]{0,40}$/.test(job.effort)){
    throw new Error("Invalid pinned shared Codex job.");
  }
  sandboxFor(job.access);
}
function atomicWrite(file, data) {
  const temp=file+"."+process.pid+".tmp";
  fs.writeFileSync(temp, JSON.stringify(data),{encoding:"utf8",mode:0o600,flag:"wx"});
  fs.renameSync(temp,file);
}
class SharedController {
  constructor({job,jobPath,cliJs,spawnServer=spawn}) {
    validateJob(job);
    const name=path.basename(jobPath,".json");
    if(!taskName.test(name)) throw new Error("Invalid scheduled job identity.");
    this.job=job;
    this.name=name;
    this.directory=path.dirname(jobPath);
    this.cliJs=cliJs;
    this.spawnServer=spawnServer;
    this.pipe=process.platform==="win32" ? "\\\\.\\pipe\\Continuum-"+name :
      path.join(this.directory,name+".sock");
    this.auth=crypto.randomBytes(32).toString("hex");
    this.controlFile=path.join(this.directory,name+".shared-control.json");
    this.stateFile=path.join(this.directory,name+".shared-state.json");
    this.status="starting";
    this.messages=[];
    this.questions=[];
    this.server=null;
    this.codex=null;
    this.protocol=null;
    this.turnId=null;
    this.ended=false;
    this.pendingCompletion=null;
    this.serverExited=false;
  }
  snapshot() {
    return {name:this.name,sessionId:this.job.sessionId,status:this.status,
      turnId:this.turnId,questions:this.questions,messages:this.messages.slice(-20),
      updatedAt:new Date().toISOString()};
  }
  publish() {
    this.questions=this.protocol ? [...this.protocol.questions.values()].map(q=>({
      id:String(q.id),method:q.method,params:q.params
    })) : [];
    atomicWrite(this.stateFile,this.snapshot());
  }
  append(message) {
    if(typeof message!=="string" || !message) return;
    this.messages.push(message.slice(-1500));
    if(this.messages.length>30)this.messages.shift();
    this.publish();
  }
  handleClient(socket) {
    let buffer="";
    socket.setTimeout(10000,()=>socket.destroy());
    socket.on("data",chunk=>{
      buffer+=chunk.toString("utf8");
      if(Buffer.byteLength(buffer)>65536){socket.destroy();return;}
      if(!buffer.includes("\n"))return;
      const line=buffer.slice(0,buffer.indexOf("\n"));
      buffer="";
      let response;
      try {
        const request=JSON.parse(line);
        const supplied=Buffer.from(String(request.auth||""),"utf8");
        const expected=Buffer.from(this.auth,"utf8");
        if(supplied.length!==expected.length || !crypto.timingSafeEqual(supplied,expected)) {
          throw new Error("Access denied.");
        }
        if(request.action==="status")response={ok:true,state:this.snapshot()};
        else if(request.action==="answer"){
          if(this.status!=="waiting" && this.status!=="running")throw new Error("Turn is not active.");
          this.protocol.answer(request.id,request.result);
          this.status=this.protocol.questions.size ? "waiting":"running";
          this.publish();
          response={ok:true,state:this.snapshot()};
        }else throw new Error("Unsupported control action.");
      }catch(error){response={ok:false,error:error.message};}
      socket.end(JSON.stringify(response)+"\n");
    });
    socket.on("error",()=>{});
  }
  async listen() {
    if(process.platform!=="win32" && fs.existsSync(this.pipe)) throw new Error("Control pipe already exists.");
    this.server=net.createServer(socket=>this.handleClient(socket));
    await new Promise((resolve,reject)=>{
      this.server.once("error",reject);
      this.server.listen(this.pipe,()=>{
        this.server.removeListener("error",reject);
        resolve();
      });
    });
    atomicWrite(this.controlFile,{pipe:this.pipe,auth:this.auth});
    this.publish();
  }
  async run() {
    await this.listen();
    try{
      // One child owns app-server for this scheduled turn. UI never starts it.
      this.codex=this.spawnServer(process.execPath,[this.cliJs,"app-server","--listen","stdio://"],
        {stdio:["pipe","pipe","pipe"],windowsHide:true,cwd:this.job.repo});
      this.protocol=new CodexSharedProtocol(this.codex.stdout,this.codex.stdin);
      this.protocol.on("question",()=>{
        this.status="waiting";this.publish();
      });
      this.protocol.on("answered",()=>{
        this.status=this.protocol.questions.size?"waiting":"running";this.publish();
      });
      this.protocol.on("resolved",()=>{
        this.status=this.protocol.questions.size?"waiting":"running";this.publish();
      });
      this.protocol.on("notification",msg=>{
        if(msg.method==="item/agentMessage/delta" && typeof msg.params?.delta==="string"){
          this.append(msg.params.delta);
        }else if(msg.method==="turn/completed"){
          const ended=msg.params?.turn;
          if(!ended?.id)return;
          // A very short turn may complete before its turn/start response
          // reaches us. Reconcile after receiving the authoritative ID.
          if(!this.turnId){this.pendingCompletion=ended;return;}
          if(ended.id!==this.turnId)return;
          this.status=ended.status==="completed"?"completed":"failed";
          this.ended=true;this.publish();
        }
      });
      this.codex.once("exit",()=>{this.serverExited=true;});
      this.codex.once("error",error=>{
        this.serverExited=true;
        this.append("Codex App Server transport failed.");
      });
      this.codex.stderr.on("data",()=>{}); // Never log potentially sensitive stderr.
      const initialized=await this.protocol.request("initialize",{
        clientInfo:{name:"continuum_shared",title:"Continuum Shared Session",version:"0.1.0"},
        capabilities:{experimentalApi:true}
      });
      if(!initialized)throw new Error("Codex App Server did not initialize.");
      this.protocol.send({method:"initialized",params:{}});
      const resumed=await this.protocol.request("thread/resume",{
        threadId:this.job.sessionId,cwd:this.job.repo,model:this.job.model,
        approvalPolicy:this.job.access==="yolo"?"never":"on-request",
        sandbox:sandboxFor(this.job.access)
      });
      if(resumed?.thread?.id!==this.job.sessionId)throw new Error("Codex resumed unexpected conversation.");
      const result=await this.protocol.request("turn/start",{
        threadId:this.job.sessionId,
        input:[{type:"text",text:this.job.message}],
        model:this.job.model,effort:this.job.effort,cwd:this.job.repo,
        approvalPolicy:this.job.access==="yolo"?"never":"on-request",
        sandboxPolicy:sandboxFor(this.job.access)
      });
      this.turnId=result?.turn?.id;
      if(!this.turnId)throw new Error("Codex did not return a turn identity.");
      if(this.pendingCompletion && this.pendingCompletion.id===this.turnId){
        this.status=this.pendingCompletion.status==="completed"?"completed":"failed";
        this.ended=true;
      }else{
        this.status=this.protocol.questions.size?"waiting":"running";
      }
      this.publish();
      // Preserve worker ownership until turn/completed; never interpret
      // turn/start acknowledgment or app-server disconnect as success.
      while(!this.ended){
        await new Promise(resolve=>setTimeout(resolve,200));
        if(this.serverExited)throw new Error("Codex server disconnected before turn completion.");
      }
      return this.status==="completed"?0:1;
    }catch(error){
      this.status="failed";
      this.append("Session controller failed: "+error.message);
      return 1;
    }finally{
      if(this.protocol)this.protocol.close();
      if(this.codex && this.codex.exitCode===null)this.codex.kill();
      if(this.server)await new Promise(resolve=>this.server.close(()=>resolve()));
      try{fs.unlinkSync(this.controlFile);}catch{}
      if(process.platform!=="win32")try{fs.unlinkSync(this.pipe);}catch{}
    }
  }
}
async function main() {
  const [jobPath,cliJs]=process.argv.slice(2);
  if(!jobPath||!cliJs||!path.isAbsolute(jobPath)||!path.isAbsolute(cliJs))throw new Error("Pinned job/CLI paths required.");
  const job=JSON.parse(fs.readFileSync(jobPath,"utf8"));
  const owner=new SharedController({job,jobPath,cliJs});
  const code=await owner.run();
  process.exitCode=code;
}
if(require.main===module)main().catch(error=>{process.stderr.write("Shared controller unavailable: "+error.message+"\n");process.exitCode=1;});
module.exports={SharedController,validateJob,sandboxFor};
