#!/usr/bin/env node

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdtempSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pluginsRoot = join(repository, "Plugins");
const catalogPath = join(pluginsRoot, "catalog.json");
const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));

assert.equal(catalog.schemaVersion, 1);
assert.equal(catalog.pythiaVersion, "1.0.0");
assert.equal(catalog.containsCredentials, false);
assert.ok(Array.isArray(catalog.packages));
assert.equal(catalog.packages.length, 6, "exactly six public plugins are required");

const files = readdirSync(pluginsRoot)
  .filter((name) => name.endsWith(".pythia"))
  .sort();
const catalogFiles = catalog.packages.map((item) => item.file).sort();
assert.deepEqual(files, catalogFiles, "catalog and public package files differ");

const requiredManifestFields = [
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

const forbiddenNames = new Set([
  "conversion.json",
  "info.json",
  "legacy-main.js",
  "plugin-configs.json",
  "plugin-state.json",
  "settings.json",
  "history.json",
]);

for (const item of catalog.packages) {
  assert.match(item.file, /^[A-Za-z0-9._-]+\.pythia$/);
  assert.match(item.sha256, /^[a-f0-9]{64}$/);
  const archive = join(pluginsRoot, item.file);
  assert.ok(statSync(archive).isFile(), `missing ${item.file}`);
  const digest = createHash("sha256").update(readFileSync(archive)).digest("hex");
  assert.equal(digest, item.sha256, `${item.file} checksum differs from catalog`);

  const entries = execFileSync("tar", ["-tf", archive], { encoding: "utf8" })
    .split(/\r?\n/)
    .filter(Boolean);
  assert.ok(entries.includes("manifest.json"), `${item.file} has no manifest.json`);
  assert.ok(entries.includes("main.js"), `${item.file} has no main.js`);
  assert.ok(entries.includes("LICENSE"), `${item.file} has no LICENSE`);
  for (const entry of entries) {
    const normalized = entry.replaceAll("\\", "/");
    assert.ok(!normalized.startsWith("/"), `${item.file} has an absolute path`);
    assert.ok(!normalized.split("/").includes(".."), `${item.file} has path traversal`);
    assert.ok(!forbiddenNames.has(basename(normalized)), `${item.file} contains ${entry}`);
    assert.ok(
      normalized === basename(normalized),
      `${item.file} must contain files at the package root only`,
    );
  }

  const stage = mkdtempSync(join(tmpdir(), "pythia-public-plugin-"));
  try {
    execFileSync("tar", ["-xf", archive, "-C", stage]);
    const manifest = JSON.parse(readFileSync(join(stage, "manifest.json"), "utf8"));
    for (const field of requiredManifestFields) {
      assert.ok(Object.hasOwn(manifest, field), `${item.file} is missing ${field}`);
    }
    assert.equal(manifest.id, item.id);
    assert.equal(manifest.version, item.version);
    assert.equal(manifest.schemaVersion, "1.0");
    assert.equal(manifest.type, "translator");
    assert.ok(manifest.capabilities.includes("translate"));
    assert.ok(manifest.supportedPlatforms.includes("macos"));
    assert.ok(manifest.supportedPlatforms.includes("windows"));
    assert.ok(manifest.permissions.every((permission) => permission === "network"));
    assert.equal(manifest.entry, "main.js");
    for (const field of manifest.configuration) {
      assert.ok(["text", "secret", "select"].includes(field.type));
      if (field.type === "secret") {
        assert.ok(!field.defaultValue, `${manifest.id}/${field.key} has a secret default`);
      }
    }

    const entry = readFileSync(join(stage, manifest.entry), "utf8");
    execFileSync(process.execPath, ["--check", join(stage, manifest.entry)]);
    const searchable = `${entry}\n${JSON.stringify(manifest)}`;
    assert.doesNotMatch(searchable, /-----BEGIN [A-Z ]*PRIVATE KEY-----/);
    assert.doesNotMatch(searchable, /\bsk-[A-Za-z0-9_-]{20,}\b/);
    assert.doesNotMatch(searchable, /\bgh[opusr]_[A-Za-z0-9]{20,}\b/);
    assert.doesNotMatch(searchable, /\bAKIA[0-9A-Z]{16}\b/);
  } finally {
    rmSync(stage, { recursive: true, force: true });
  }
}

console.log(`Validated ${catalog.packages.length} public Pythia plugin packages.`);
