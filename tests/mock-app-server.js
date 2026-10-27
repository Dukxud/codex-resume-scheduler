"use strict";
const readline = require("node:readline");
const rl = readline.createInterface({ input: process.stdin });
let initialized = false;
rl.on("line", line => {
  const msg = JSON.parse(line);
  if (msg.method === "initialize" && msg.id === 1) {
    process.stdout.write(JSON.stringify({ id: 1, result: { userAgent: "mock" } }) + "\n");
  } else if (msg.method === "initialized") {
    initialized = true;
  } else if (msg.method === "account/rateLimits/read" && msg.id === 2 && initialized) {
    process.stdout.write(JSON.stringify({ id: 2, result: { rateLimits: {
      primary: { usedPercent: 100, windowDurationMins: 300, resetsAt: Math.floor(Date.now() / 1000) + 200 },
    } } }) + "\n");
  }
});
