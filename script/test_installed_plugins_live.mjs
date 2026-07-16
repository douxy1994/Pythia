#!/usr/bin/env node

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const repository = resolve(import.meta.dirname, "..");
const support = join(homedir(), "Library", "Application Support", "Pythia");
const pluginsDirectory = join(support, "Plugins");
const credentialsPath = join(support, "credentials.json");
const configsPath = join(pluginsDirectory, "plugin-configs.json");
const appResources = "/Applications/Pythia.app/Contents/Resources";
const nodeRuntime = join(appResources, "runtime", "node");
const runner = join(appResources, "pythia-plugin-runner.cjs");
const catalog = JSON.parse(readFileSync(join(repository, "Plugins", "catalog.json"), "utf8"));
const credentials = JSON.parse(readFileSync(credentialsPath, "utf8"));
const storedConfigs = existsSync(configsPath)
  ? JSON.parse(readFileSync(configsPath, "utf8"))
  : {};
const generatedLongText = Array.from({ length: 28 }, (_, index) => (
  `第 ${index + 1} 段：Pythia 正在验证长文本翻译、段落顺序和网络恢复能力。`
  + "The translated result should remain complete, fluent, and ordered."
)).join("\n\n");
const testText = process.env.PYTHIA_LIVE_SHORT === "1"
  ? "请把这句话翻译成英文。"
  : generatedLongText;
const selectedPluginID = process.env.PYTHIA_LIVE_PLUGIN_ID || "";

assert.ok(existsSync(nodeRuntime), "installed Pythia Node runtime is missing");
assert.ok(existsSync(runner), "installed Pythia plugin runner is missing");

function pluginConfig(manifest) {
  const config = { ...(storedConfigs[manifest.id] || {}) };
  const secretValues = [];
  for (const field of manifest.configuration) {
    if ((config[field.key] === undefined || config[field.key] === "") && field.defaultValue !== undefined) {
      config[field.key] = String(field.defaultValue);
    }
    if (field.type === "secret") {
      const value = credentials[`plugins:${manifest.id}:${field.key}`];
      if (typeof value === "string" && value) {
        config[field.key] = value;
        secretValues.push(value);
      }
    }
  }
  return { config, secretValues };
}

function redact(text, values) {
  return values.reduce(
    (result, value) => value.length >= 4 ? result.split(value).join("[REDACTED]") : result,
    String(text),
  );
}

let tested = 0;
let skipped = 0;
const failures = [];
for (const item of catalog.packages) {
  if (selectedPluginID && item.id !== selectedPluginID) continue;
  const directory = join(pluginsDirectory, `${item.id}.pythia`);
  const manifest = JSON.parse(readFileSync(join(directory, "manifest.json"), "utf8"));
  const { config, secretValues } = pluginConfig(manifest);
  const missingSecrets = manifest.configuration
    .filter((field) => field.type === "secret" && field.required && !config[field.key])
    .map((field) => field.key);
  if (missingSecrets.length > 0) {
    skipped += 1;
    console.log(`${manifest.name}: skipped live request (missing ${missingSecrets.join(", ")}).`);
    continue;
  }

  const requestId = `live-${manifest.id}-${Date.now()}`;
  const request = {
    schemaVersion: "1.0",
    requestId,
    type: "translate",
    input: {
      text: testText,
      sourceLanguage: "auto",
      targetLanguage: "en",
      detectedLanguage: "zh-CN",
    },
    context: { platform: "macos", pythiaVersion: "1.0.0" },
  };
  const startedAt = Date.now();
  const result = spawnSync(nodeRuntime, [runner, directory, manifest.entry], {
    env: {
      ...process.env,
      PYTHIA_PLUGIN_TIMEOUT_MS: "600000",
      PYTHIA_PLUGIN_REQUEST: JSON.stringify(request),
      PYTHIA_PLUGIN_CONFIG: JSON.stringify(config),
    },
    encoding: "utf8",
    timeout: 620000,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.status !== 0) {
    const detail = redact(result.stderr || result.error || "plugin process failed", secretValues);
    failures.push(`${manifest.name}: ${detail}`);
    console.error(`${manifest.name}: live long-text translation failed after bounded retries.`);
    continue;
  }
  const response = JSON.parse(result.stdout);
  assert.equal(response.requestId, requestId, `${manifest.name} returned the wrong request id`);
  assert.equal(response.success, true, `${manifest.name} reported failure`);
  assert.ok(response.data.text.trim(), `${manifest.name} returned empty text`);
  tested += 1;
  console.log(`${manifest.name}: live long-text translation passed in ${Math.round((Date.now() - startedAt) / 1000)}s.`);
}

if (failures.length > 0) {
  throw new Error(`Live provider failures:\n${failures.join("\n")}`);
}
assert.ok(tested > 0, "no installed plugin had credentials for a live request");
console.log(`Live long-text verification passed for ${tested} plugins; ${skipped} skipped without credentials.`);
