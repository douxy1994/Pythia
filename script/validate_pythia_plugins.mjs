#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const examplesRoot = join(repository, "examples", "plugins");
const macRunner = join(repository, "Pythia", "Resources", "pythia-plugin-runner.cjs");
const windowsRunner = join(
  repository,
  "Windows",
  "Pythia.Windows",
  "assets",
  "pythia-plugin-runner.cjs",
);
const requiredFields = [
  "schemaVersion",
  "id",
  "name",
  "version",
  "description",
  "author",
  "type",
  "entry",
  "minimumPythiaVersion",
  "supportedPlatforms",
  "permissions",
  "configuration",
  "capabilities",
];

assert.deepEqual(
  readFileSync(windowsRunner),
  readFileSync(macRunner),
  "macOS and Windows plugin runners must remain byte-identical",
);

const packages = readdirSync(examplesRoot)
  .filter((name) => name.endsWith(".pythia"))
  .map((name) => join(examplesRoot, name))
  .filter((path) => statSync(path).isDirectory());
assert.equal(packages.length, 3, "exactly three complete examples are required");

for (const packagePath of packages) {
  const manifest = JSON.parse(readFileSync(join(packagePath, "manifest.json"), "utf8"));
  for (const field of requiredFields) {
    assert.ok(Object.hasOwn(manifest, field), `${packagePath} is missing ${field}`);
  }
  assert.equal(manifest.schemaVersion, "1.0");
  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]{2,127}$/);
  assert.match(manifest.version, /^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?$/);
  assert.equal(manifest.type, "translator");
  assert.ok(manifest.capabilities.includes("translate"));
  assert.ok(manifest.supportedPlatforms.includes("macos"));
  assert.ok(manifest.supportedPlatforms.includes("windows"));
  assert.ok(manifest.permissions.every((permission) => permission === "network"));
  assert.ok(!manifest.entry.startsWith("/") && !manifest.entry.split(/[\\/]/).includes(".."));
  const entryPath = join(packagePath, manifest.entry);
  execFileSync(process.execPath, ["--check", entryPath], { stdio: "pipe" });
  for (const field of manifest.configuration) {
    assert.match(field.key, /^[A-Za-z][A-Za-z0-9._-]{0,127}$/);
    assert.ok(["text", "secret", "select"].includes(field.type));
    if (field.type === "secret") {
      assert.ok(!field.defaultValue, `${manifest.id}/${field.key} contains a secret default`);
    }
  }
  const serialized = readFileSync(entryPath, "utf8") + JSON.stringify(manifest);
  assert.doesNotMatch(serialized, /-----BEGIN [A-Z ]*PRIVATE KEY-----/);
  assert.doesNotMatch(serialized, /\bsk-[A-Za-z0-9_-]{20,}\b/);
}

const request = JSON.stringify({
  schemaVersion: "1.0",
  requestId: "example-validation",
  type: "translate",
  input: {
    text: "  hello   world  ",
    sourceLanguage: "en",
    targetLanguage: "zh-CN",
    detectedLanguage: "en",
  },
  context: { platform: process.platform === "win32" ? "windows" : "macos", pythiaVersion: "1.0.0" },
});

function runExample(directory, config = {}) {
  return spawnSync(process.execPath, [macRunner, directory, "main.js"], {
    encoding: "utf8",
    env: {
      ...process.env,
      PYTHIA_PLUGIN_REQUEST: request,
      PYTHIA_PLUGIN_CONFIG: JSON.stringify(config),
      PYTHIA_PLUGIN_TIMEOUT_MS: "5000",
    },
  });
}

const echo = runExample(join(examplesRoot, "echo-translator.pythia"));
assert.equal(echo.status, 0, echo.stderr);
assert.equal(JSON.parse(echo.stdout).data.text, "[en->zh-CN]   hello   world  ");

const preprocessor = runExample(join(examplesRoot, "text-preprocessor.pythia"));
assert.equal(preprocessor.status, 0, preprocessor.stderr);
assert.equal(JSON.parse(preprocessor.stdout).data.text, "hello world");

const openAIWithoutSecret = runExample(
  join(examplesRoot, "openai-compatible-translator.pythia"),
  { baseURL: "https://api.openai.com/v1", model: "test-model" },
);
assert.notEqual(openAIWithoutSecret.status, 0);
assert.match(openAIWithoutSecret.stderr, /AUTHENTICATION_FAILED/);

console.log(`Validated ${packages.length} Pythia plugin examples and both bundled runners.`);

execFileSync(process.execPath, [join(repository, "script", "validate_public_plugins.mjs")], {
  stdio: "inherit",
});
