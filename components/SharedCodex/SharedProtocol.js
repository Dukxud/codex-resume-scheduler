"use strict";
// A single, stream-owned Codex App Server. All UI clients talk to this
// controller, never spawn a second Codex writer.
const {EventEmitter} = require("node:events");
const {createInterface} = require("node:readline");

const interactiveRequests = new Set([
  "item/commandExecution/requestApproval",
  "item/fileChange/requestApproval",
  "item/permissions/requestApproval",
  "item/tool/requestUserInput",
  "mcpServer/elicitation/request"
]);
const maxRequestBytes = 1024 * 1024;
function isRequestId(value) {
  return (typeof value === "number" && Number.isSafeInteger(value)) ||
    (typeof value === "string" && value.length > 0 && value.length <= 128);
}
function validateAnswer(method, answer) {
  if (!answer || typeof answer !== "object" || Array.isArray(answer)) return false;
  if (method === "item/tool/requestUserInput") {
    return answer.answers && typeof answer.answers === "object" &&
      !Array.isArray(answer.answers) && Object.keys(answer.answers).length <= 8 &&
      Object.values(answer.answers).every(value => Array.isArray(value?.answers) &&
        value.answers.length <= 8 && value.answers.every(s => typeof s === "string" && s.length <= 8000));
  }
  if (method === "item/commandExecution/requestApproval" ||
      method === "item/fileChange/requestApproval") {
    return ["accept", "acceptForSession", "decline", "cancel"].includes(answer.decision);
  }
  if (method === "item/permissions/requestApproval") {
    // Do not fabricate elevated permissions on behalf of a human.
    return answer.permissions && typeof answer.permissions === "object" &&
      (answer.scope === undefined || ["turn","session"].includes(answer.scope));
  }
  if (method === "mcpServer/elicitation/request") {
    return ["accept","decline","cancel"].includes(answer.action) &&
      (answer.action !== "accept" || answer.content !== undefined);
  }
  return false;
}
class CodexSharedProtocol extends EventEmitter {
  constructor(input, output) {
    super();
    this.output = output;
    this.pendingReplies = new Map();
    this.questions = new Map();
    this.nextId = 1;
    this.closed = false;
    this.lines = createInterface({input, crlfDelay: Infinity});
    this.lines.on("line", line => {
      if (Buffer.byteLength(line, "utf8") > maxRequestBytes) {
        this.emit("fatal", new Error("Oversized Codex App Server frame."));
        return;
      }
      let msg;
      try { msg = JSON.parse(line); } catch {
        this.emit("fatal", new Error("Malformed Codex App Server frame."));
        return;
      }
      this.onMessage(msg);
    });
    input.on("error", err => this.emit("fatal", err));
  }
  send(obj) {
    if (this.closed) throw new Error("Codex server connection closed.");
    this.output.write(JSON.stringify(obj) + "\n");
  }
  request(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("Codex server connection closed."));
    if (this.pendingReplies.size >= 64) return Promise.reject(new Error("Too many pending Codex requests."));
    const id = this.nextId++;
    const promise = new Promise((resolve, reject) => {
      this.pendingReplies.set(id, {resolve, reject});
    });
    try {this.send({id,method,params});}catch(error){
      this.pendingReplies.delete(id);
      return Promise.reject(error);
    }
    return promise;
  }
  onMessage(msg) {
    if (!msg || typeof msg !== "object" || Array.isArray(msg)) return;
    if (isRequestId(msg.id) && !msg.method) {
      const waiting = this.pendingReplies.get(msg.id);
      if (waiting) {
        this.pendingReplies.delete(msg.id);
        if (msg.error) waiting.reject(new Error(String(msg.error.message || "Codex RPC failed.")));
        else waiting.resolve(msg.result);
      }
      return;
    }
    if (typeof msg.method !== "string") return;
    if (isRequestId(msg.id)) {
      if (!interactiveRequests.has(msg.method)) {
        // Never silently accept tools, token refresh or unknown privileges.
        this.send({id:msg.id,error:{code:-32601,message:"Interactive host operation unsupported."}});
        this.emit("unsupportedRequest", {method:msg.method});
        return;
      }
      const key = String(msg.id);
      if (this.questions.has(key)) {
        this.emit("fatal", new Error("Duplicate pending Codex request ID."));
        return;
      }
      this.questions.set(key, {id:msg.id,method:msg.method,params:msg.params || {}});
      this.emit("question", this.questions.get(key));
      return;
    }
    if (msg.method === "serverRequest/resolved") {
      const id = msg.params?.requestId;
      if (isRequestId(id)) {
        this.questions.delete(String(id));
        this.emit("resolved", String(id));
      }
    }
    this.emit("notification", msg);
  }
  answer(id, result) {
    const key = String(id);
    const question = this.questions.get(key);
    if (!question) throw new Error("Question no longer pending.");
    if (!validateAnswer(question.method, result)) throw new Error("Invalid answer for Codex question.");
    this.send({id:question.id,result});
    this.questions.delete(key);
    this.emit("answered", key);
  }
  close() {
    if (this.closed) return;
    this.closed = true;
    this.lines.close();
    for (const request of this.pendingReplies.values()) request.reject(new Error("Codex server disconnected."));
    this.pendingReplies.clear();
    this.questions.clear();
  }
}
module.exports = {CodexSharedProtocol, validateAnswer, interactiveRequests};
