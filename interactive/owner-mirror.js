'use strict';
// A local, authenticated mirror transport. It never starts another Codex
// process and never grants clients unrestricted JSON-RPC access.
const net=require('node:net');
const {randomBytes,timingSafeEqual}=require('node:crypto');

const MAX_CLIENT_MESSAGE=64*1024;
const MAX_CLIENTS=6;

function equalSecret(expected,given){
  if(typeof given!=='string'||given.length!==expected.length)return false;
  return timingSafeEqual(Buffer.from(given),Buffer.from(expected));
}
function isRecord(value){
  return value && typeof value==='object' && !Array.isArray(value);
}
class OwnerMirror {
  constructor(owner,{pipe,secret=randomBytes(32).toString('hex')}={}){
    if(typeof pipe!=='string'||!pipe)throw Error('Local named pipe is required');
    if(typeof secret!=='string'||secret.length<32)throw Error('An unpredictable secret is required');
    this.owner=owner;this.pipe=pipe;this.secret=secret;
    this.connections=new Set();this.server=null;this.closed=false;
    this.broadcast=event=>{
      for(const client of this.connections){
        if(client.authorized)this.write(client,{kind:'event',event});
      }
    };
    owner.on('event',this.broadcast);
  }
  write(client,body){
    if(client.socket.destroyed)return;
    if(client.socket.writableLength>1024*1024){
      client.socket.destroy();return;
    }
    client.socket.write(JSON.stringify(body)+'\n');
  }
  async listen(){
    if(this.server)throw Error('Mirror already listening');
    this.server=net.createServer(socket=>this.attach(socket));
    return new Promise((resolve,reject)=>{
      this.server.once('error',reject);
      this.server.listen(this.pipe,()=>{this.server.off('error',reject);resolve();});
    });
  }
  attach(socket){
    if(this.closed||this.connections.size>=MAX_CLIENTS){socket.destroy();return}
    const client={socket,authorized:false,buffer:''};
    this.connections.add(client);
    const timer=setTimeout(()=>{if(!client.authorized)socket.destroy()},3000);
    socket.setEncoding('utf8');
    socket.on('data',chunk=>{
      client.buffer+=chunk;
      if(Buffer.byteLength(client.buffer)>MAX_CLIENT_MESSAGE){socket.destroy();return}
      let index;
      while((index=client.buffer.indexOf('\n'))>=0){
        const line=client.buffer.slice(0,index);client.buffer=client.buffer.slice(index+1);
        let message;
        try{message=JSON.parse(line)}catch{socket.destroy();return}
        if(!isRecord(message)){socket.destroy();return}
        if(!client.authorized){
          if(message.kind!=='hello'||!equalSecret(this.secret,message.secret)){socket.destroy();return}
          client.authorized=true;clearTimeout(timer);
          this.write(client,{kind:'snapshot',value:this.owner.snapshot()});
          continue;
        }
        if(message.kind==='snapshot'){
          this.write(client,{kind:'snapshot',value:this.owner.snapshot()});
        }else if(message.kind==='respond'){
          try{
            this.owner.answer(message.id,message.response);
            this.write(client,{kind:'ack',id:String(message.id)});
          }catch(error){
            this.write(client,{kind:'rejected',id:String(message.id),reason:error.message});
          }
        }else if(message.kind==='message'){
          this.owner.message(message.text).then(
            ()=>this.write(client,{kind:'ack',action:'message'}),
            error=>this.write(client,{kind:'rejected',action:'message',reason:error.message}),
          );
        }else if(message.kind==='finish'){
          try{
            this.owner.finish();
            this.write(client,{kind:'ack',action:'finish'});
          }catch(error){
            this.write(client,{kind:'rejected',action:'finish',reason:error.message});
          }
        }else if(message.kind==='steer'){
          // Explicit human input, routed to the existing active turn only.
          this.owner.steer(message.text).then(
            ()=>this.write(client,{kind:'ack',action:'steer'}),
            error=>this.write(client,{kind:'rejected',action:'steer',reason:error.message}),
          );
        }else{
          this.write(client,{kind:'rejected',reason:'Unsupported mirror action'});
        }
      }
    });
    socket.on('error',()=>{});
    socket.on('close',()=>{clearTimeout(timer);this.connections.delete(client)});
  }
  async close(){
    if(this.closed)return;
    this.closed=true;
    this.owner.off('event',this.broadcast);
    for(const c of this.connections)c.socket.destroy();
    this.connections.clear();
    if(this.server)await new Promise(resolve=>this.server.close(()=>resolve()));
  }
}
module.exports={OwnerMirror,equalSecret};
