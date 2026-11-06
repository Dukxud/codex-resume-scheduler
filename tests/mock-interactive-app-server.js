'use strict';
// Deterministic fake Codex protocol process for tests ONLY. No network/model calls.
const readline=require('node:readline');
const rl=readline.createInterface({input:process.stdin});
const SESSION='11111111-2222-3333-4444-555555555555';
let initialized=false;let pending=false;let turnCount=0;
function send(x){process.stdout.write(JSON.stringify(x)+'\n');}
rl.on('line',line=>{
  const m=JSON.parse(line);
  if(m.method==='initialize'){
    send({id:m.id,result:{userAgent:'fixture'}});
  }else if(m.method==='initialized'){
    initialized=true;
  }else if(m.method==='thread/resume'&&initialized){
    if(m.params.threadId!==SESSION)return send({id:m.id,error:{message:'Wrong original thread'}});
    send({id:m.id,result:{thread:{id:SESSION}}});
  }else if(m.method==='turn/start'&&initialized){
    turnCount++;
    if(turnCount!==1)return send({id:m.id,error:{message:'Second owner turn forbidden'}});
    send({id:m.id,result:{turn:{id:'22222222-2222-3333-4444-555555555555'}}});
    send({method:'turn/started',params:{threadId:SESSION,turn:{id:'22222222-2222-3333-4444-555555555555'}}});
    send({method:'item/agentMessage/delta',params:{delta:'I need approval before changing files.'}});
    pending=true;
    send({id:71,method:'item/commandExecution/requestApproval',params:{threadId:SESSION,command:'git status',reason:'Fixture approval request'}});
  }else if(m.id===71&&pending){
    pending=false;
    if(m.result?.decision!=='accept'&&m.result?.decision!=='decline')return send({method:'error',params:{message:'Invalid decision'}});
    send({method:'item/agentMessage/delta',params:{delta:'Approval received: '+m.result.decision}});
    send({method:'turn/completed',params:{threadId:SESSION,turn:{status:'completed'}}});
  }
});
