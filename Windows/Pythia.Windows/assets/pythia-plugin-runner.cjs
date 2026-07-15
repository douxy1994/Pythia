'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const pluginDirectory = path.resolve(process.argv[2] || '');
const entry = process.argv[3] || 'main.js';
const timeoutMs = Math.max(1000, Number(process.env.PYTHIA_PLUGIN_TIMEOUT_MS || 120000));
const request = JSON.parse(process.env.PYTHIA_PLUGIN_REQUEST || '{}');
const config = JSON.parse(process.env.PYTHIA_PLUGIN_CONFIG || '{}');
const manifest = JSON.parse(fs.readFileSync(path.join(pluginDirectory, 'manifest.json'), 'utf8'));
const entryPath = path.resolve(pluginDirectory, entry);

if (!entryPath.startsWith(`${pluginDirectory}${path.sep}`)) {
  throw new Error('Plugin entry escapes the plugin directory.');
}

const secretValues = Object.entries(config)
  .filter(([key, value]) => /key|secret|token|password/i.test(key) && String(value || '').length >= 4)
  .map(([, value]) => String(value));
const redact = (value) => {
  let text = String(value);
  for (const secret of secretValues) text = text.split(secret).join('[REDACTED]');
  return text;
};
const pluginConsole = Object.freeze({
  log: (...values) => console.error(values.map(redact).join(' ')),
  info: (...values) => console.error(values.map(redact).join(' ')),
  warn: (...values) => console.error(values.map(redact).join(' ')),
  error: (...values) => console.error(values.map(redact).join(' ')),
});

const permissions = new Set(Array.isArray(manifest.permissions) ? manifest.permissions : []);
const executionController = new AbortController();
const scopedFetch = async (input, options = {}) => {
  if (!permissions.has('network')) throw new Error('Plugin did not declare the network permission.');
  const target = new URL(String(input));
  if (target.protocol !== 'https:' && target.protocol !== 'http:') {
    throw new Error(`Unsupported network protocol: ${target.protocol}`);
  }
  const requestController = new AbortController();
  const timer = setTimeout(() => requestController.abort(), Math.min(timeoutMs, 60000));
  const signals = [executionController.signal, requestController.signal, options.signal].filter(Boolean);
  const signal = typeof AbortSignal.any === 'function' ? AbortSignal.any(signals) : requestController.signal;
  try {
    return await fetch(target, { ...options, signal });
  } finally {
    clearTimeout(timer);
  }
};

const moduleObject = { exports: {} };
const context = vm.createContext({
  module: moduleObject,
  exports: moduleObject.exports,
  console: pluginConsole,
  fetch: scopedFetch,
  URL,
  URLSearchParams,
  TextEncoder,
  TextDecoder,
  AbortController,
  AbortSignal,
  setTimeout,
  clearTimeout,
}, {
  name: `PythiaPlugin:${manifest.id || 'unknown'}`,
  codeGeneration: { strings: false, wasm: false },
});

const source = fs.readFileSync(entryPath, 'utf8');
new vm.Script(source, { filename: entryPath }).runInContext(context, { timeout: 5000 });
const exported = moduleObject.exports;
const handler = typeof exported === 'function'
  ? exported
  : (exported && (exported.translate || exported.default));
if (typeof handler !== 'function') {
  throw new Error('Plugin entry must export a function or a translate(request, context) function.');
}

let timeoutHandle;
const timeout = new Promise((_, reject) => {
  timeoutHandle = setTimeout(() => {
    executionController.abort();
    reject(new Error(`Plugin timed out after ${timeoutMs} ms.`));
  }, timeoutMs);
});

const normalizeResponse = (value) => {
  if (typeof value === 'string') {
    return { schemaVersion: '1.0', requestId: request.requestId, success: true, data: { text: value } };
  }
  if (value && typeof value === 'object' && typeof value.success === 'boolean') {
    return { schemaVersion: '1.0', requestId: request.requestId, ...value };
  }
  if (value && typeof value.text === 'string') {
    return { schemaVersion: '1.0', requestId: request.requestId, success: true, data: { text: value.text } };
  }
  throw new Error('Plugin returned an invalid response.');
};

(async () => {
  try {
    const result = await Promise.race([
      Promise.resolve(handler(request, Object.freeze({
        config: Object.freeze({ ...config }),
        fetch: scopedFetch,
        signal: executionController.signal,
      }))),
      timeout,
    ]);
    const output = JSON.stringify(normalizeResponse(result));
    if (Buffer.byteLength(output) > 8 * 1024 * 1024) throw new Error('Plugin response exceeds 8 MiB.');
    process.stdout.write(output);
  } catch (error) {
    const message = redact(error && error.message ? error.message : error);
    process.stderr.write(message);
    process.exitCode = 1;
  } finally {
    if (timeoutHandle) clearTimeout(timeoutHandle);
  }
})();
