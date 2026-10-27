"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { summarizeRateLimits, describeWindow, readRateLimits } = require("../CodexUsage.js");
const path = require("node:path");

const time = 1793000000;
const window = (percent, delta, duration) => ({ usedPercent: percent, resetsAt: time + delta, windowDurationMins: duration });

test("shows both windows and uses latest reset when both are exhausted", () => {
  const v = summarizeRateLimits({ ordinaryUsageAllowed: false, rateLimits: {
    primary: window(100, 600, 300), secondary: window(100, 900, 10080), rateLimitReachedType: "primary",
  } }, time);
  assert.deepEqual(v.windows.map(w => w.label), ["5-hour", "Weekly"]);
  assert.equal(v.recommendedResetAt, time + 900);
  assert.equal(v.recommendationKind, "exhausted-window");
});

test("prefers codex bucket over another model meter", () => {
  const v = summarizeRateLimits({ rateLimits: { primary: window(10, 100, 60) },
    rateLimitsByLimitId: { codex: { primary: window(90, 300, 300) }, codex_other: { primary: window(100, 500, 60) } },
  }, time);
  assert.equal(v.windows[0].label, "5-hour");
  assert.equal(v.recommendedResetAt, time + 300);
  assert.equal(v.recommendationKind, "next-window");
});

test("doesn't infer an unblock time when backend disallows usage but windows aren't exhausted", () => {
  const v = summarizeRateLimits({ ordinaryUsageAllowed: false, rateLimits: { primary: window(40, 100, 300) } }, time);
  assert.equal(v.recommendedResetAt, null);
});

test("missing reset timestamps do not yield a schedule", () => {
  const v = summarizeRateLimits({ rateLimits: { primary: { usedPercent: 100, resetsAt: null } } }, time);
  assert.equal(v.recommendedResetAt, null);
});

test("reads Codex app-server with initialize and authenticated rateLimits request", async () => {
  const v = await readRateLimits(path.join(__dirname, "mock-app-server.js"), 3000);
  assert.equal(v.windows[0].usedPercent, 100);
  assert.equal(v.recommendationKind, "exhausted-window");
});


test("remaining quota is the complement of usage and is bounded", () => {
  assert.equal(describeWindow({ usedPercent: 73.5 }, "Primary").remainingPercent, 26.5);
  assert.equal(describeWindow({ usedPercent: 100 }, "Primary").remainingPercent, 0);
  assert.equal(describeWindow({ usedPercent: 110 }, "Primary").remainingPercent, 0);
  assert.equal(describeWindow({ usedPercent: -4 }, "Primary").remainingPercent, 100);
  assert.equal(describeWindow({ usedPercent: null }, "Primary").remainingPercent, null);
});
