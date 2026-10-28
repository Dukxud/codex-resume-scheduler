#!/usr/bin/env node
"use strict";
// Codex App Server account/rateLimits/read and model/list. No login file access.
const { spawn } = require('node:child_process');
const readline = require('node:readline');
const path = require('node:path');
const fs = require('node:fs');

const validEpoch = n => Number.isSafeInteger(n) && n > 0 ? n : null;
function describeWindow(w, slot) {
  if (!w || typeof w !== 'object') return null;
  const d = w.windowDurationMins;
  const label = d === 300 ? '5-hour' : d === 10080 ? 'Weekly' : Number.isFinite(d) ? `${d}-minute` : slot;
  const pct = Number.isFinite(w.usedPercent) ? w.usedPercent : null;
  return { label, usedPercent: pct, remainingPercent: pct === null ? null : Math.max(0, Math.min(100, 100 - pct)), resetsAt: validEpoch(w.resetsAt) };
}
function normalizeModels(pages) {
  const seen = new Set();
  return pages.flatMap(page => Array.isArray(page.data) ? page.data : []).filter(m => {
    const id = m?.model || m?.id;
    if (typeof id !== 'string' || !id || seen.has(id) || m.hidden === true) return false;
    seen.add(id); return true;
  }).map(m => ({ id: m.model || m.id, name: m.displayName || m.model || m.id,
    defaultEffort: m.defaultReasoningEffort || null, isDefault: m.isDefault === true,
    efforts: Array.isArray(m.supportedReasoningEfforts) ? [...new Set(m.supportedReasoningEfforts.map(e => e?.reasoningEffort).filter(e => typeof e === 'string' && e && e !== 'ultra'))] : [] }));
}
function selectBucket(result, model) {
  const byId = result.rateLimitsByLimitId;
  const buckets = byId && typeof byId === 'object' ? Object.entries(byId).filter(([, v]) => v && typeof v === 'object') : [];
  if (!buckets.length) {
    const rate=result.rateLimits;
    return rate && (!model || !rate.normalModelSlug || rate.normalModelSlug===model) ? {id:rate.limitId||'default',rate,verified:true}:null;
  }
  if (buckets.length === 1) {
    const [id,rate] = buckets[0];
    if(model && rate.normalModelSlug && rate.normalModelSlug!==model)return null;
    return {id,rate,verified:true};
  }
  if (!model) return null;
  const matches = buckets.filter(([id, b]) => [id, b.limitId, b.normalModelSlug].includes(model));
  return matches.length === 1 ? { id: matches[0][0], rate: matches[0][1], verified: true } : null;
}
function summarizeRateLimits(result, now = Math.floor(Date.now()/1000), model = null) {
  const selected = selectBucket(result, model);
  const ordinaryUsageAllowed = typeof result.ordinaryUsageAllowed === 'boolean' ? result.ordinaryUsageAllowed : null;
  if (!selected) return { ok: true, ordinaryUsageAllowed, model, bucketId: null, selectionVerified: false,
    checkedAt: new Date(now*1000).toISOString(), accountId:result.accountId || null, windows: [], limitReachedType: null,
    recommendedResetAt: null, recommendationKind: null, canAttempt: false, blockedReason: 'Quota bucket cannot be attributed to the selected model.' };
  const rate = selected.rate;
  const windows = [describeWindow(rate.primary,'Primary'), describeWindow(rate.secondary,'Secondary')].filter(Boolean);
  const exhausted = windows.filter(w => w.usedPercent !== null && w.usedPercent >= 100);
  const isBlocked = ordinaryUsageAllowed === false || exhausted.length > 0 || !!rate.rateLimitReachedType || rate.spendControlReached === true;
  const resetKnown = exhausted.length > 0 && exhausted.every(w => w.resetsAt !== null && w.resetsAt > now);
  const recommendedResetAt = isBlocked && resetKnown && rate.spendControlReached !== true && (!rate.rateLimitReachedType || rate.rateLimitReachedType === 'rate_limit_reached')
    ? Math.max(...exhausted.map(w => w.resetsAt)) : null;
  const canAttempt = ordinaryUsageAllowed === true && !isBlocked;
  const future = windows.filter(w => w.resetsAt !== null && w.resetsAt > now);
  const nextReset = !isBlocked && future.length ? Math.min(...future.map(w => w.resetsAt)) : null;
  return { ok:true, checkedAt: new Date(now*1000).toISOString(), model, bucketId: selected.id, selectionVerified: true,
    ordinaryUsageAllowed, accountId: result.accountId || null, limitReachedType: rate.rateLimitReachedType || null, windows,
    recommendedResetAt: recommendedResetAt ?? nextReset,
    recommendationKind: recommendedResetAt !== null ? 'exhausted-window' : nextReset !== null ? 'next-window' : null,
    canAttempt, blockedReason: !isBlocked && ordinaryUsageAllowed !== true ? 'Backend usage permission unavailable.' :
      isBlocked && recommendedResetAt === null ? 'Usage restricted; no reliable applicable reset time.' : null };
}
function isLimitErrorLine(line) {
  let s = line;
  try {
    const event = JSON.parse(line);
    if (event.type === 'error' || event.type === 'turn.failed') s = event.message || event.error?.message || '';
    else return false; // Never mistake a user message or model output for an error.
  } catch {
    if (!/^\s*(?:ERROR\b|Error:|■\s*You.ve hit your usage limit)/i.test(line)) return false;
  }
  return /(?:usage limit|rate.limit|quota exceeded|too many requests)/i.test(s) &&
    !/(?:invalid model|unsupported effort)/i.test(s);
}
function readCodexState(cliJs, { model = null, timeoutMs = 18000, catalog = true, modelsOnly = false, threadId = null } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [cliJs, 'app-server', '--listen', 'stdio://'], { stdio:['pipe','pipe','pipe'], windowsHide:true });
    let settled = false, stderr = '', pages = [], catalogError = null, requestId = 1, stage = 'initialize';
    const lines = readline.createInterface({ input: child.stdout });
    const timer = setTimeout(() => finish(new Error('Codex App Server request timed out.')), timeoutMs);
    function finish(err, result) {
      if (settled) return;
      settled = true; clearTimeout(timer); lines.close();
      child.stdin.on('error', () => {}); child.stdin.end(); child.kill();
      if (err) reject(err); else resolve(result);
    }
    function send(data) { if (!settled) child.stdin.write(JSON.stringify(data)+'\n'); }
    function requestModels(cursor = null) {
      stage='models';requestId++;
      const params = {limit:100, includeHidden:false}; if(cursor) params.cursor=cursor;
      send({id:requestId,method:'model/list',params});
    }
    function requestRate() {stage='rate';requestId++;send({id:requestId,method:'account/rateLimits/read'});}
    function requestThread() {stage='thread';requestId++;send({id:requestId,method:'thread/read',params:{threadId}});}
    child.on('error',e=>finish(e)); child.stdin.on('error',e=>finish(e));
    child.on('exit',code=>{ if(!settled) finish(new Error(`Codex App Server exited (${code}). ${stderr.slice(-150)}`)); });
    child.stderr.on('data',p=>{stderr=(stderr+p.toString()).slice(-500);});
    lines.on('line', line=>{
      let msg;try{msg=JSON.parse(line);}catch{return;}
      if(msg.id!==requestId)return;
      if(stage==='initialize') {
        if(msg.error)return finish(new Error(msg.error.message||'Initialization failed'));
        send({method:'initialized',params:{}});if(threadId)requestThread();else if(catalog)requestModels();else requestRate();
      } else if(stage==='thread') {
        if(msg.error)return finish(new Error(msg.error.message||'Thread metadata unavailable'));
        try {finish(null,normalizeThreadRead(msg.result,threadId));}
        catch(e){finish(e);}
      } else if(stage==='models') {
        if(msg.error)catalogError=msg.error.message||'Model catalog unavailable';
        else {pages.push(msg.result||{});const cursor=msg.result?.nextCursor;
          if(typeof cursor==='string'&&cursor&&pages.length<20)return requestModels(cursor);
          if(typeof cursor==='string'&&cursor) catalogError='Model catalog pagination exceeded 20 pages.';
        }
        if(modelsOnly) {
          if(catalogError) return finish(new Error(catalogError));
          return finish(null,{ok:true,models:normalizeModels(pages)});
        }
        requestRate();
      } else if(stage==='rate') {
        if(msg.error)return finish(new Error(msg.error.message||'Codex rate-limit request rejected'));
        try {const models=normalizeModels(pages);const chosen=model || models.find(m=>m.isDefault)?.id || (models.length===1?models[0].id:null);
          const summary=summarizeRateLimits(msg.result||{},Math.floor(Date.now()/1000),chosen);
          finish(null,{...summary,models,catalogError});}
        catch(e){finish(e);}
      }
    });
    send({id:requestId,method:'initialize',params:{clientInfo:{name:'codex_resume_scheduler',title:'Codex Resume Scheduler',version:'1.4.0'}}});
  });
}
function readRateLimits(cliJs, timeoutMs=18000) {return readCodexState(cliJs,{timeoutMs,catalog:false});}
function normalizeThreadRead(result, expectedId) {
  const thread = result?.thread;
  if (!thread || thread.id !== expectedId) throw new Error('Codex returned unexpected thread metadata.');
  // thread/read does not resume a conversation or subscribe to turns.
  const cwd = typeof thread.cwd === 'string' && thread.cwd.trim() ? thread.cwd.trim() : null;
  return {ok:true, threadId:expectedId, cwd};
}
function readThreadDirectory(cliJs, threadId, timeoutMs=10000) {
  if (typeof threadId !== 'string' || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(threadId))
    return Promise.reject(new Error('Invalid Codex conversation ID.'));
  return readCodexState(cliJs,{threadId,timeoutMs,catalog:false});
}
async function main() {
  const flag=process.argv.indexOf('--cli-js'); const cliJs=flag>=0?process.argv[flag+1]:null;
  if(!cliJs||!fs.existsSync(cliJs)||path.extname(cliJs).toLowerCase()!=='.js')throw new Error('Codex npm CLI entry not found.');
  const modelFlag=process.argv.indexOf('--model'); const model=modelFlag>=0?process.argv[modelFlag+1]:null;
  const threadFlag=process.argv.indexOf('--thread-id');
  const threadId=threadFlag>=0?process.argv[threadFlag+1]:null;
  const state=threadFlag>=0
    ? await readThreadDirectory(path.resolve(cliJs),threadId)
    : await readCodexState(path.resolve(cliJs),{model,catalog:!process.argv.includes('--rates-only'),modelsOnly:process.argv.includes('--models-only')});
  process.stdout.write(JSON.stringify(state)+'\n');
}
if(require.main===module) main().catch(e=>{process.stdout.write(JSON.stringify({ok:false,error:e.message})+'\n');process.exitCode=1;});
module.exports={describeWindow,normalizeModels,selectBucket,summarizeRateLimits,isLimitErrorLine,readCodexState,readRateLimits,normalizeThreadRead,readThreadDirectory};
