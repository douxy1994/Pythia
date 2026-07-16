#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const runners = [
  join(repository, "Pythia", "Resources", "pythia-plugin-runner.cjs"),
  join(repository, "Windows", "Pythia.Windows", "assets", "pythia-plugin-runner.cjs"),
];
const pluginDirectory = mkdtempSync(join(tmpdir(), "pythia-runner-network-"));
writeFileSync(join(pluginDirectory, "manifest.json"), JSON.stringify({
  schemaVersion: "1.0",
  id: "plugin.test.runner-network",
  name: "Runner Network Test",
  version: "1.0.0",
  entry: "main.js",
  permissions: ["network"],
}));
writeFileSync(join(pluginDirectory, "main.js"), `
module.exports.translate = async function translate(request, context) {
  const response = await context.fetch(context.config.endpoint, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ text: request.input.text })
  });
  if (!response.ok) throw new Error("unexpected status " + response.status);
  return await response.text();
};
`);

let requests = 0;
let failUntil = 0;
const server = createServer((request, response) => {
  requests += 1;
  request.resume();
  if (requests <= failUntil) {
    request.socket.destroy();
    return;
  }
  response.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
  response.end("runner-ok");
});
await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
const address = server.address();
const endpoint = `http://127.0.0.1:${address.port}/translate`;

async function runRunner(runner) {
  failUntil = requests + 3;
  const requestId = `runner-${Date.now()}-${Math.random()}`;
  const request = {
    schemaVersion: "1.0",
    requestId,
    type: "translate",
    input: { text: "network retry", sourceLanguage: "en", targetLanguage: "zh-CN" },
  };
  const child = spawn(process.execPath, [runner, pluginDirectory, "main.js"], {
    env: {
      ...process.env,
      PYTHIA_PLUGIN_TIMEOUT_MS: "30000",
      PYTHIA_PLUGIN_REQUEST: JSON.stringify(request),
      PYTHIA_PLUGIN_CONFIG: JSON.stringify({ endpoint }),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  const exitCode = await new Promise((resolveExit, rejectExit) => {
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      rejectExit(new Error(`runner test timed out: ${runner}`));
    }, 20000);
    child.once("error", rejectExit);
    child.once("exit", (code) => {
      clearTimeout(timer);
      resolveExit(code);
    });
  });
  assert.equal(exitCode, 0, `${runner} failed: ${stderr}`);
  const response = JSON.parse(stdout);
  assert.equal(response.requestId, requestId);
  assert.equal(response.success, true);
  assert.equal(response.data.text, "runner-ok");
  assert.ok(requests >= failUntil + 1, `${runner} did not reach the native HTTP fallback`);
  console.log(`${runner}: fetch failures recovered through native HTTP fallback.`);
}

try {
  for (const runner of runners) await runRunner(runner);
} finally {
  await new Promise((resolveClose) => server.close(resolveClose));
  rmSync(pluginDirectory, { recursive: true, force: true });
}

console.log("macOS and Windows plugin runners passed network fallback tests.");
