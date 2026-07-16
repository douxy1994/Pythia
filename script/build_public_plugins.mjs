#!/usr/bin/env node

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { deflateRawSync } from "node:zlib";
import {
  readFileSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repository = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pluginsRoot = join(repository, "Plugins");
const sourcesRoot = join(pluginsRoot, "Sources");
const sharedWrapper = readFileSync(
  join(sourcesRoot, "shared", "long-text-wrapper.js"),
  "utf8",
);
const catalogPath = join(pluginsRoot, "catalog.json");
const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));

const crcTable = Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let bit = 0; bit < 8; bit += 1) {
    crc = (crc >>> 1) ^ ((crc & 1) ? 0xEDB88320 : 0);
  }
  return crc >>> 0;
});

function crc32(data) {
  let crc = 0xFFFFFFFF;
  for (const value of data) {
    crc = (crc >>> 8) ^ crcTable[(crc ^ value) & 0xFF];
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function zipArchive(files) {
  const localParts = [];
  const centralParts = [];
  let offset = 0;

  for (const file of files) {
    const name = Buffer.from(file.name, "utf8");
    const content = Buffer.isBuffer(file.content)
      ? file.content
      : Buffer.from(file.content);
    const compressed = deflateRawSync(content, { level: 9 });
    const checksum = crc32(content);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034B50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(0, 10);
    local.writeUInt16LE(33, 12);
    local.writeUInt32LE(checksum, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(content.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    localParts.push(local, name, compressed);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014B50, 0);
    central.writeUInt16LE(0x0314, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(8, 10);
    central.writeUInt16LE(0, 12);
    central.writeUInt16LE(33, 14);
    central.writeUInt32LE(checksum, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(content.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt16LE(0, 30);
    central.writeUInt16LE(0, 32);
    central.writeUInt16LE(0, 34);
    central.writeUInt16LE(0, 36);
    central.writeUInt32LE((0o100644 << 16) >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    centralParts.push(central, name);
    offset += local.length + name.length + compressed.length;
  }

  const centralDirectory = Buffer.concat(centralParts);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054B50, 0);
  end.writeUInt16LE(0, 4);
  end.writeUInt16LE(0, 6);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(centralDirectory.length, 12);
  end.writeUInt32LE(offset, 16);
  end.writeUInt16LE(0, 20);
  return Buffer.concat([...localParts, centralDirectory, end]);
}

function packageBaseName(fileName) {
  return fileName.replace(/-\d+\.\d+\.\d+\.pythia$/i, "");
}

for (const fileName of readdirSync(pluginsRoot)) {
  if (fileName.endsWith(".pythia")) unlinkSync(join(pluginsRoot, fileName));
}

for (const item of catalog.packages) {
  const baseName = packageBaseName(item.file);
  const sourceDirectory = join(sourcesRoot, baseName);
  assert.ok(statSync(sourceDirectory).isDirectory(), `missing source directory ${baseName}`);

  const manifestPath = join(sourceDirectory, "manifest.json");
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  assert.equal(manifest.id, item.id, `${baseName} changed plugin id`);
  assert.equal(manifest.entry, "main.js", `${baseName} must use main.js`);

  const provider = readFileSync(join(sourceDirectory, "provider.js"), "utf8").trimEnd();
  const mainJavaScript = `${provider}\n\n${sharedWrapper.trim()}\n`;
  const files = readdirSync(sourceDirectory)
    .filter((name) => name !== "provider.js")
    .map((name) => {
      const path = join(sourceDirectory, name);
      assert.ok(statSync(path).isFile(), `${baseName}/${name} must be a file`);
      return { name, content: readFileSync(path) };
    });
  files.push({ name: "main.js", content: Buffer.from(mainJavaScript) });
  files.sort((left, right) => left.name.localeCompare(right.name));

  const archive = zipArchive(files);
  const outputName = `${baseName}-${manifest.version}.pythia`;
  const outputPath = join(pluginsRoot, outputName);
  const stagingPath = `${outputPath}.tmp`;
  writeFileSync(stagingPath, archive, { mode: 0o644 });
  renameSync(stagingPath, outputPath);

  item.version = manifest.version;
  item.file = basename(outputPath);
  item.sha256 = createHash("sha256").update(archive).digest("hex");
}

catalog.generatedAt = new Date().toISOString().slice(0, 10);
writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`);
console.log(`Built ${catalog.packages.length} deterministic public Pythia plugin packages.`);
