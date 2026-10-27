#!/usr/bin/env node
"use strict";

// Read Codex's official app-server account/rateLimits/read endpoint.
// This tool never reads auth.json, sends a prompt, or modifies a session.
const { spawn } = require("node:child_process");
const readline = require("node:readline");
const path = require("node:path");
const fs = require("node:fs");

function describeWindow(window, slot) {
  if (!window) return null;
  const duration = window.windowDurationMins;
  const label = duration === 300 ? "5-hour" : duration === 10080 ? "Weekly" :
    typeof duration === "number" ? `${duration}-minute` : slot;
  return {
    label,
    usedPercent: typeof window.usedPercent === "number" && Number.isFinite(window.usedPercent) ? window.usedPercent : null,
    remainingPercent: typeof window.usedPercent === "number" && Number.isFinite(window.usedPercent)
      ? Math.max(0, Math.min(100, 100 - window.usedPercent)) : null,
    resetsAt: Number.isSafeInteger(window.resetsAt) ? window.resetsAt : null,
  };
}

function summarizeRateLimits(result, now = Math.floor(Date.now() / 1000)) {
  const buckets = result.rateLimitsByLimitId;
  const rates = (buckets && buckets.codex) || result.rateLimits;
  if (!rates) throw new Error("Codex returned no rate-limit data.");
  const windows = [describeWindow(rates.primary, "Primary"), describeWindow(rates.secondary, "Secondary")].filter(Boolean);
  const ordinaryUsageAllowed = typeof result.ordinaryUsageAllowed === "boolean" ? result.ordinaryUsageAllowed : null;
  const limitReachedType = rates.rateLimitReachedType ?? null;
  const future = windows.filter(w => w.resetsAt !== null && w.resetsAt > now);
  const exhausted = future.filter(w => w.usedPercent !== null && w.usedPercent >= 100);
  let recommendedResetAt = null;
  let recommendationKind = null;
  if (exhausted.length) {
    // When both limits are exhausted, both must reset; the later time wins.
    recommendedResetAt = Math.max(...exhausted.map(w => w.resetsAt));
    recommendationKind = "exhausted-window";
  } else if (ordinaryUsageAllowed !== false && !limitReachedType && future.length) {
    // No blocking limit established: offer the next window reset, not an unblock promise.
    recommendedResetAt = Math.min(...future.map(w => w.resetsAt));
    recommendationKind = "next-window";
  }
  return { ok: true, checkedAt: new Date(now * 1000).toISOString(), ordinaryUsageAllowed,
    limitReachedType, windows, recommendedResetAt, recommendationKind };
}

function readRateLimits(cliJs, timeoutMs = 18000) {
  return new Promise((resolve, reject) => {
    const subprocess = spawn(process.execPath, [cliJs, "app-server", "--listen", "stdio://"], {
      stdio: ["pipe", "pipe", "pipe"], windowsHide: true,
    });
    let settled = false;
    let stderr = "";
    const timer = setTimeout(() => fail(new Error("Codex usage request timed out.")), timeoutMs);
    const lines = readline.createInterface({ input: subprocess.stdout });
    function finish(error, data) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      lines.close();
      subprocess.stdin.on("error", () => {});
      subprocess.stdin.end();
      if (!subprocess.killed) subprocess.kill();
      if (error) reject(error); else resolve(data);
    }
    function fail(error) { finish(error); }
    function send(value) {
      if (!settled) subprocess.stdin.write(JSON.stringify(value) + "\n");
    }
    subprocess.on("error", fail);
    subprocess.stdin.on("error", fail);
    subprocess.on("exit", code => {
      if (!settled) fail(new Error(`Codex app-server exited (${code}). ${stderr.slice(-300)}`.trim()));
    });
    subprocess.stderr.on("data", part => { stderr = (stderr + part.toString()).slice(-1000); });
    lines.on("line", line => {
      let reply;
      try { reply = JSON.parse(line); } catch { return; }
      if (reply.id === 1) {
        if (reply.error) return fail(new Error(reply.error.message || "Codex initialization failed."));
        send({ method: "initialized", params: {} });
        send({ id: 2, method: "account/rateLimits/read" });
      } else if (reply.id === 2) {
        if (reply.error) return fail(new Error(reply.error.message || "Codex rejected the usage request."));
        try { finish(null, summarizeRateLimits(reply.result || {})); } catch (error) { fail(error); }
      }
    });
    send({ id: 1, method: "initialize", params: {
      clientInfo: { name: "codex_resume_scheduler", title: "Codex Resume Scheduler", version: "1.3.0" },
    } });
  });
}

async function main() {
  const flag = process.argv.indexOf("--cli-js");
  const cliJs = flag >= 0 ? process.argv[flag + 1] : null;
  if (!cliJs || !fs.existsSync(cliJs) || path.extname(cliJs).toLowerCase() !== ".js") {
    throw new Error("Codex npm CLI entry not found. Install Codex with npm or provide --cli-js.");
  }
  const snapshot = await readRateLimits(path.resolve(cliJs));
  process.stdout.write(JSON.stringify(snapshot) + "\n");
}

if (require.main === module) {
  main().catch(error => {
    // Error output is structured; no account credentials or raw backend payloads.
    process.stdout.write(JSON.stringify({ ok: false, error: error.message }) + "\n");
    process.exitCode = 1;
  });
}

module.exports = { describeWindow, summarizeRateLimits, readRateLimits };
