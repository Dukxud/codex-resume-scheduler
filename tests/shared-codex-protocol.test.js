"use strict";
const assert = require("node:assert/strict");
const {PassThrough} = require("node:stream");
const {test} = require("node:test");
const {CodexSharedProtocol} = require("../components/SharedCodex/SharedProtocol.js");
function setup() {
 const incoming = new PassThrough(), outgoing = new PassThrough();
 const frames = [];
 outgoing.on("data", chunk => frames.push(...chunk.toString().trim().split("\n").map(JSON.parse)));
 const protocol = new CodexSharedProtocol(incoming, outgoing);
 return {incoming, frames, protocol, receive: message => incoming.write(JSON.stringify(message)+"\n")};
}
test("single controller starts/resumes one original conversation and correlates answers", async () => {
 const {protocol,receive,frames} = setup();
 const p = protocol.request("thread/resume",{threadId:"original"});
 assert.equal(frames[0].method,"thread/resume");
 receive({id:frames[0].id,result:{thread:{id:"original"}}});
 assert.equal((await p).thread.id,"original");
 receive({id:91,method:"item/tool/requestUserInput",params:{questions:[{id:"purpose",header:"Intent"}]}});
 assert.equal(protocol.questions.size,1);
 protocol.answer(91,{answers:{purpose:{answers:["Continue the original run"]}}});
 assert.deepEqual(frames[1],{id:91,result:{answers:{purpose:{answers:["Continue the original run"]}}}});
 assert.equal(protocol.questions.size,0);
 protocol.close();
});
test("approvals wait for explicit user action and cannot be silently accepted", () => {
 const {protocol,receive,frames} = setup();
 receive({id:"approval",method:"item/commandExecution/requestApproval",params:{command:"git status"}});
 assert.equal(frames.length,0);
 assert.throws(()=>protocol.answer("approval",{decision:"yes"}),/Invalid answer/);
 assert.equal(frames.length,0);
 protocol.answer("approval",{decision:"decline"});
 assert.deepEqual(frames[0],{id:"approval",result:{decision:"decline"}});
 assert.throws(()=>protocol.answer("approval",{decision:"accept"}),/no longer pending/);
 protocol.close();
});
test("unsafe server-to-client tools fail closed",()=>{
 const {protocol,receive,frames} = setup();
 receive({id:73,method:"item/tool/call",params:{tool:"arbitrary"}});
 assert.equal(frames[0].error.code,-32601);
 assert.equal(protocol.questions.size,0);
 protocol.close();
});
test("server resolution invalidates stale unanswered request",()=>{
 const {protocol,receive} = setup();
 receive({id:74,method:"item/fileChange/requestApproval",params:{}});
 receive({method:"serverRequest/resolved",params:{requestId:74}});
 assert.throws(()=>protocol.answer(74,{decision:"accept"}),/no longer pending/);
 protocol.close();
});
test("invalid permissions and malformed multiquestion answers fail closed",()=>{
 const {protocol,receive,frames} = setup();
 receive({id:1,method:"item/permissions/requestApproval",params:{}});
 assert.throws(()=>protocol.answer(1,{permissions:"all"}),/Invalid answer/);
 receive({id:2,method:"item/tool/requestUserInput",params:{}});
 assert.throws(()=>protocol.answer(2,{answers:{x:{answers:[15]}}}),/Invalid answer/);
 assert.equal(frames.length,0);
 protocol.close();
});
test("RPC errors do not mark turns successful", async()=>{
 const {protocol,receive,frames} = setup();
 const promise=protocol.request("turn/start",{threadId:"original"});
 receive({id:frames[0].id,error:{code:-32600,message:"active writer"}});
 await assert.rejects(promise,/active writer/);
 protocol.close();
});
