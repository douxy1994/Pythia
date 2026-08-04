#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pluginsRoot = join(repository, "Plugins");
const catalog = JSON.parse(readFileSync(join(pluginsRoot, "catalog.json"), "utf8"));
const longText = Array.from({ length: 96 }, (_, index) => (
  `第 ${index + 1} 段用于验证长文本翻译。It contains English, 中文、数字 ${index + 1} and punctuation, `
  + "so the splitter can choose a semantic boundary instead of cutting a Unicode character."
)).join("\n\n");

const wrapperSource = readFileSync(
  join(pluginsRoot, "Sources", "shared", "long-text-wrapper.js"),
  "utf8",
);
let observedChunks = [];
const wrapperModule = { exports: {} };
const wrapperSandbox = vm.createContext({
  module: wrapperModule,
  exports: wrapperModule.exports,
  translate: async (text) => {
    observedChunks.push(text);
    return text;
  },
  console,
  URL,
  URLSearchParams,
  TextEncoder,
  TextDecoder,
  AbortController,
  AbortSignal,
  Headers,
  setTimeout,
  clearTimeout,
});
new vm.Script(wrapperSource, { filename: "long-text-wrapper.js" }).runInContext(wrapperSandbox);

for (const numericToken of [
  "1.24",
  "-1.24",
  ".24",
  "1,240.50",
  "1\u202F240,50",
  "2026-07-19",
  "6.02e-23",
]) {
  observedChunks = [];
  const prefixLength = 1798;
  const source = `${"A".repeat(prefixLength)}${numericToken}${"B".repeat(1900)}`;
  const result = await wrapperModule.exports.translate({
    schemaVersion: "1.0",
    requestId: `numeric-boundary-${numericToken}`,
    type: "translate",
    input: {
      text: source,
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
      detectedLanguage: "en",
    },
  }, {
    config: Object.freeze({}),
    signal: new AbortController().signal,
    fetch: async () => { throw new Error("fixture must not use fetch"); },
  });
  assert.equal(result, source, `${numericToken} changed during chunk recombination`);
  assert.ok(
    observedChunks.some((chunk) => chunk.includes(numericToken)),
    `${numericToken} was split across translation chunks`,
  );
}

function defaultConfiguration(manifest) {
  return Object.fromEntries(manifest.configuration.map((field) => [
    field.key,
    field.type === "secret" ? "test-credential-not-real" : String(field.defaultValue ?? ""),
  ]));
}

function responseBody(sequence) {
  return JSON.stringify({
    choices: [{ message: { content: `[[translated-${sequence}]]` } }],
  });
}

for (const item of catalog.packages) {
  const stage = mkdtempSync(join(tmpdir(), "pythia-long-text-test-"));
  try {
    execFileSync("tar", ["-xf", join(pluginsRoot, item.file), "-C", stage]);
    const manifest = JSON.parse(readFileSync(join(stage, "manifest.json"), "utf8"));
    const source = readFileSync(join(stage, manifest.entry), "utf8");
    const moduleObject = { exports: {} };
    const sandbox = vm.createContext({
      module: moduleObject,
      exports: moduleObject.exports,
      console,
      URL,
      URLSearchParams,
      TextEncoder,
      TextDecoder,
      AbortController,
      AbortSignal,
      Headers,
      setTimeout,
      clearTimeout,
    });
    new vm.Script(source, { filename: `${item.file}/main.js` }).runInContext(sandbox);
    const handler = moduleObject.exports.translate;
    assert.equal(typeof handler, "function", `${item.file} has no translate handler`);

    let fetchCalls = 0;
    let successfulCalls = 0;
    let largestBody = 0;
    const controller = new AbortController();
    const context = {
      config: Object.freeze(defaultConfiguration(manifest)),
      signal: controller.signal,
      fetch: async (url, options = {}) => {
        fetchCalls += 1;
        const body = String(options.body ?? "");
        largestBody = Math.max(largestBody, body.length);
        if (fetchCalls === 1) throw new TypeError("fetch failed");
        successfulCalls += 1;
        return {
          ok: true,
          status: 200,
          url: String(url),
          headers: new Headers({ "content-type": "application/json" }),
          text: async () => responseBody(successfulCalls),
        };
      },
    };
    const result = await handler({
      schemaVersion: "1.0",
      requestId: `long-text-${manifest.id}`,
      type: "translate",
      input: {
        text: longText,
        sourceLanguage: "auto",
        targetLanguage: "en",
        detectedLanguage: "zh-CN",
      },
    }, context);

    assert.ok(successfulCalls >= 5, `${item.file} did not split the long document`);
    assert.equal(fetchCalls, successfulCalls + 1, `${item.file} did not retry fetch failed exactly once`);
    assert.ok(largestBody < 5000, `${item.file} sent an oversized chunk (${largestBody} chars)`);
    const sequence = [...String(result).matchAll(/\[\[translated-(\d+)\]\]/g)]
      .map((match) => Number(match[1]));
    assert.deepEqual(
      sequence,
      Array.from({ length: successfulCalls }, (_, index) => index + 1),
      `${item.file} changed chunk order`,
    );
    console.log(`${item.file}: ${successfulCalls} chunks, transient fetch retry passed.`);
  } finally {
    rmSync(stage, { recursive: true, force: true });
  }
}

console.log("All public plugins passed long-text splitting and retry tests.");
