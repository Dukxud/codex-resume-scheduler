'use strict';
// One Codex app-server owner; multiple read-only subscribers and one answered
// prompt at a time. This module has no scheduler/UI dependencies.
const {EventEmitter}=require('node:events');
const {spawn}=require('node:child_process');
const readline=require('node:readline');

const UUID=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const PROMPTS=new Set([
  'item/commandExecution/requestApproval',
  'item/fileChange/requestApproval',
  'item/tool/requestUserInput',
  'tool/requestUserInput',
  'item/permissions/requestApproval',
  'mcpServer/elicitation/request',
]);
const MAX_PENDING=16;
const MAX_HISTORY=128;
const MAX_LINE=2*1024*1024;

function isObject(value) {
  return value!==null && typeof value==='object' && !Array.isArray(value);
}
function requireRun(run) {
  if(!isObject(run)||!UUID.test(run.sessionId||'')) throw Error('Invalid original conversation ID');
  if(typeof run.cwd!=='string'||!require('node:path').isAbsolute(run.cwd)) throw Error('Invalid absolute workspace path');
  if(typeof run.message!=='string'||!run.message.trim()||run.message.length>16000) throw Error('Invalid instruction');
  if(!/^[a-zA-Z0-9][\w.-]{0,100}$/.test(run.model||'')) throw Error('Invalid model');
  if(!/^[a-zA-Z][a-zA-Z0-9_-]{0,40}$/.test(run.effort||'')) throw Error('Invalid reasoning effort');
  if(!['read-only','workspace-write'].includes(run.access)) throw Error('Interactive owner does not support unrestricted access.');
  return run;
}
function policy(access) {
  return access==='read-only' ? {type:'readOnly'} :
    {type:'workspaceWrite',writableRoots:[],networkAccess:false,excludeTmpdirEnvVar:false,excludeSlashTmp:false};
}

class InteractiveOwner extends EventEmitter {
  constructor({cliJs,spawnChild=spawn,timeoutMs=15000}){
    super();
    if(typeof cliJs!=='string'||!cliJs)throw Error('Codex CLI entrypoint required');
    this.cliJs=cliJs;this.spawnChild=spawnChild;this.timeoutMs=timeoutMs;
    this.child=null;this.started=false;this.closed=false;this.phase='idle';
    this.nextId=1;this.requests=new Map();this.prompts=new Map();
    this.history=[];this.run=null;this.turnId=null;this.turnStatus=null;
  }
  event(message){
    if(this.closed && message.type!=='closed')return;
    this.history.push(message);
    if(this.history.length>MAX_HISTORY)this.history.shift();
    this.emit('event',message);
  }
  send(message){
    if(!this.child||this.closed||this.child.stdin.destroyed)throw Error('Codex owner is unavailable');
    this.child.stdin.write(JSON.stringify(message)+'\n');
  }
  call(method,params){
    const id=this.nextId++;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{
        this.requests.delete(id);reject(Error('Codex '+method+' timed out'));
      },this.timeoutMs);
      this.requests.set(id,{resolve,reject,timer});
      try{this.send({id,method,params})}catch(error){
        clearTimeout(timer);this.requests.delete(id);reject(error);
      }
    });
  }
  ingest(line){
    if(Buffer.byteLength(line)>MAX_LINE){
      this.terminate(Error('Codex protocol message exceeded safe size'));return;
    }
    let m;
    try{m=JSON.parse(line)}catch{
      this.terminate(Error('Invalid Codex JSON-RPC stream'));return;
    }
    if(!isObject(m))return;
    if(Object.hasOwn(m,'id') && !Object.hasOwn(m,'method')){
      const waiter=this.requests.get(m.id);
      if(!waiter)return;
      this.requests.delete(m.id);clearTimeout(waiter.timer);
      if(m.error)waiter.reject(Error(m.error.message||'Codex rejected request'));
      else waiter.resolve(m.result||{});
      return;
    }
    if(typeof m.method!=='string')return;
    if(Object.hasOwn(m,'id')){
      if(!PROMPTS.has(m.method)){
        this.event({type:'unsupportedPrompt',method:m.method});
        // Never invent an approval response to an unknown server request.
        return;
      }
      if(this.prompts.size>=MAX_PENDING){
        this.terminate(Error('Too many unresolved interactive requests'));return;
      }
      const key=String(m.id);
      this.prompts.set(key,{id:m.id,method:m.method,params:m.params});
      this.phase='awaitingInput';
      this.event({type:'prompt',id:key,method:m.method,params:m.params});
      return;
    }
    if(m.method==='serverRequest/resolved'){
      const key=String(m.params?.requestId??'');
      if(this.prompts.delete(key))this.event({type:'promptResolved',id:key});
      if(this.prompts.size===0&&this.phase==='awaitingInput')this.phase='running';
      this.event({type:'notification',method:m.method,params:m.params});
    }else if(m.method==='turn/completed'){
      this.turnStatus=m.params?.turn?.status||'unknown';
      this.phase=this.turnStatus==='completed'?'awaitingUser':'failed';
      this.prompts.clear();
      this.event({type:'turnCompleted',params:m.params});
    }else if(m.method==='turn/started'){
      this.phase='running';this.event({type:'turnStarted',params:m.params});
    }else{
      // Forward the actual App Server event stream (including natural-language
      // questions). Clients must treat content as potentially sensitive.
      this.event({type:'notification',method:m.method,params:m.params});
    }
  }
  answer(id,response){
    if(!isObject(response))throw Error('Interactive response must be an object');
    const entry=this.prompts.get(String(id));
    if(!entry)throw Error('No matching unresolved Codex question');
    if(this.closed)throw Error('Codex owner is no longer running');
    if(entry.params?.threadId && entry.params.threadId!==this.run?.sessionId)
      throw Error('Codex prompt belongs to a different conversation');
    if(entry.params?.turnId && this.turnId && entry.params.turnId!==this.turnId)
      throw Error('Codex prompt belongs to a different turn');
    if(['item/commandExecution/requestApproval','item/fileChange/requestApproval'].includes(entry.method) &&
       !['accept','acceptForSession','decline','cancel'].includes(response.decision))
      throw Error('Unrecognized approval decision; advanced approvals are not yet supported.');
    this.send({id:entry.id,result:response});
    this.prompts.delete(String(id));
    if(this.prompts.size===0)this.phase='running';
    this.event({type:'promptAnswered',id:String(id),method:entry.method});
  }
  snapshot(){
    return {
      phase:this.phase,sessionId:this.run?.sessionId||null,turnId:this.turnId,turnStatus:this.turnStatus,
      pending:[...this.prompts].map(([id,p])=>({id,method:p.method,params:p.params})),
      events:this.history.slice(),
    };
  }
  async start(run){
    if(this.started)throw Error('Only one turn per owner instance');
    this.started=true;this.run=requireRun(run);this.phase='starting';
    const child=this.spawnChild(process.execPath,[this.cliJs,'app-server','--listen','stdio://'],{
      stdio:['pipe','pipe','pipe'],cwd:run.cwd,windowsHide:true,
    });
    this.child=child;
    const lines=readline.createInterface({input:child.stdout,crlfDelay:Infinity});
    lines.on('line',line=>this.ingest(line));
    child.on('error',error=>this.terminate(error));
    child.on('exit',code=>{
      this.terminate(Error('Codex App Server exited ('+code+')'));
    });
    child.stderr.on('data',()=>{}); // Drain stderr; never disclose auth/environment details.
    try{
      await this.call('initialize',{
        clientInfo:{name:'continuum_interactive_owner',title:'Continuum Interactive Owner',version:'0.1.0'},
        capabilities:{experimentalApi:true},
      });
      this.send({method:'initialized',params:{}});
      const resumed=await this.call('thread/resume',{threadId:run.sessionId,cwd:run.cwd});
      if(resumed.thread?.id!==run.sessionId)throw Error('Codex resumed a different conversation');
      const turn=await this.call('turn/start',{
        threadId:run.sessionId,
        input:[{type:'text',text:run.message}],
        cwd:run.cwd,model:run.model,effort:run.effort,
        approvalPolicy:'on-request',sandboxPolicy:policy(run.access),
      });
      if(!turn.turn?.id)throw Error('Codex did not return a turn identity');
      this.turnId=turn.turn.id;
      if(!this.turnStatus)this.phase=this.prompts.size?'awaitingInput':'running';
      this.event({type:'ownerReady',sessionId:run.sessionId,turnId:this.turnId});
      return this.snapshot();
    }catch(error){
      this.terminate(error);throw error;
    }
  }
  async message(text){
    if(this.closed||this.phase!=='awaitingUser'||this.prompts.size)
      throw Error('Codex has not finished its previous turn');
    if(typeof text!=='string'||!text.trim()||text.length>16000)
      throw Error('Invalid next user message');
    this.phase='startingTurn';
    this.turnStatus=null;
    try{
      const turn=await this.call('turn/start',{
        threadId:this.run.sessionId,
        input:[{type:'text',text}],
        cwd:this.run.cwd,model:this.run.model,effort:this.run.effort,
        approvalPolicy:'on-request',sandboxPolicy:policy(this.run.access),
      });
      if(!turn.turn?.id)throw Error('Codex did not return a new turn identity');
      this.turnId=turn.turn.id;
      if(!this.turnStatus)this.phase=this.prompts.size?'awaitingInput':'running';
      this.event({type:'nextTurn',turnId:this.turnId});
    }catch(error){
      this.phase='failed';this.event({type:'turnStartFailed',reason:error.message});
      throw error;
    }
  }
  finish(){
    if(this.closed||this.phase!=='awaitingUser'||this.prompts.size)
      throw Error('Cannot finish an active or unanswered Codex turn');
    this.phase='finishing';this.event({type:'finishRequested'});
  }
  async steer(text){
    if(this.closed||this.phase!=='running'||!this.turnId)
      throw Error('No active Codex turn can accept steering');
    if(typeof text!=='string'||!text.trim()||text.length>16000)
      throw Error('Invalid user message');
    const response=await this.call('turn/steer',{
      threadId:this.run.sessionId,expectedTurnId:this.turnId,
      input:[{type:'text',text}],
    });
    if(response.turnId!==this.turnId)throw Error('Codex returned a different active turn');
    this.event({type:'steered',turnId:this.turnId});
  }
  terminate(error){
    if(this.closed)return;
    this.closed=true;this.phase='closed';
    for(const req of this.requests.values()){
      clearTimeout(req.timer);req.reject(error||Error('Owner closed'));
    }
    this.requests.clear();this.prompts.clear();
    if(this.child && !this.child.killed)this.child.kill();
    this.event({type:'closed',reason:error?.message||'Codex owner closed'});
  }
}
module.exports={InteractiveOwner,PROMPTS,requireRun};
