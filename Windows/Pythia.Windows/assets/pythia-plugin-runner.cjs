'use strict';

const fs = require('fs');
const nodeHttp = require('http');
const nodeHttps = require('https');
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

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay));
const isRetryableNetworkError = (error) => {
  const code = error && (error.code || (error.cause && error.cause.code));
  const message = error && error.message ? error.message : String(error);
  return ['ECONNRESET', 'ETIMEDOUT', 'EAI_AGAIN', 'ENOTFOUND', 'ECONNREFUSED', 'EPIPE'].includes(code)
    || /fetch failed|network|socket|tls|und_err|timed?\s*out|timeout|abort/i.test(message);
};
const abortError = () => {
  const error = new Error('Plugin HTTP request was cancelled.');
  error.name = 'AbortError';
  return error;
};
const normalizeHeaders = (headers = {}) => {
  if (headers && typeof headers.entries === 'function') return Object.fromEntries(headers.entries());
  if (Array.isArray(headers)) return Object.fromEntries(headers);
  return { ...headers };
};
const normalizeBody = (body) => {
  if (body === undefined || body === null) return undefined;
  if (Buffer.isBuffer(body)) return body;
  if (typeof body === 'string') return Buffer.from(body);
  if (body instanceof URLSearchParams) return Buffer.from(body.toString());
  if (body instanceof ArrayBuffer) return Buffer.from(body);
  if (ArrayBuffer.isView(body)) return Buffer.from(body.buffer, body.byteOffset, body.byteLength);
  return Buffer.from(String(body));
};
const nativeResponse = (target, status, statusMessage, headers, data, redirected) => ({
  ok: status >= 200 && status < 300,
  status,
  statusText: statusMessage || '',
  url: target.toString(),
  redirected,
  headers: new Headers(headers),
  text: async () => data.toString('utf8'),
  json: async () => JSON.parse(data.toString('utf8')),
  arrayBuffer: async () => data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength),
});
const nativeRequest = (target, options, signal, requestTimeoutMs, redirectCount = 0) => new Promise((resolve, reject) => {
  const client = target.protocol === 'http:' ? nodeHttp : nodeHttps;
  const body = normalizeBody(options.body);
  const headers = normalizeHeaders(options.headers);
  if (body !== undefined && !Object.keys(headers).some((key) => key.toLowerCase() === 'content-length')) {
    headers['Content-Length'] = String(body.length);
  }

  let settled = false;
  const finish = (callback) => {
    if (settled) return;
    settled = true;
    if (signal && typeof signal.removeEventListener === 'function') {
      signal.removeEventListener('abort', onAbort);
    }
    callback();
  };
  const request = client.request({
    protocol: target.protocol,
    hostname: target.hostname,
    port: target.port || undefined,
    path: `${target.pathname}${target.search}`,
    method: options.method || 'GET',
    headers,
    timeout: requestTimeoutMs,
  }, (response) => {
    const status = response.statusCode || 0;
    const location = response.headers.location;
    if ([301, 302, 303, 307, 308].includes(status) && location && redirectCount < 3) {
      response.resume();
      const redirectedTarget = new URL(location, target);
      const redirectedOptions = status === 303
        ? { ...options, method: 'GET', body: undefined }
        : options;
      finish(() => resolve(nativeRequest(
        redirectedTarget,
        redirectedOptions,
        signal,
        requestTimeoutMs,
        redirectCount + 1,
      )));
      return;
    }

    const chunks = [];
    let size = 0;
    response.on('data', (chunk) => {
      size += chunk.length;
      if (size > 16 * 1024 * 1024) {
        const error = new Error('Plugin HTTP response exceeds 16 MiB.');
        response.destroy(error);
        finish(() => reject(error));
        return;
      }
      chunks.push(chunk);
    });
    response.on('end', () => finish(() => resolve(nativeResponse(
      target,
      status,
      response.statusMessage,
      response.headers,
      Buffer.concat(chunks),
      redirectCount > 0,
    ))));
  });
  request.on('timeout', () => request.destroy(new Error(`Plugin HTTP request timed out after ${Math.round(requestTimeoutMs / 1000)}s.`)));
  request.on('error', (error) => finish(() => reject(error)));
  const onAbort = () => request.destroy(abortError());
  if (signal && typeof signal.addEventListener === 'function') {
    if (signal.aborted) {
      request.destroy(abortError());
      return;
    }
    signal.addEventListener('abort', onAbort, { once: true });
  }
  if (body !== undefined) request.write(body);
  request.end();
});

const scopedFetch = async (input, options = {}) => {
  if (!permissions.has('network')) throw new Error('Plugin did not declare the network permission.');
  const target = new URL(String(input));
  if (target.protocol !== 'https:' && target.protocol !== 'http:') {
    throw new Error(`Unsupported network protocol: ${target.protocol}`);
  }
  const deadline = Date.now() + Math.max(30000, Math.min(timeoutMs, 180000));
  let lastError;
  for (let attempt = 0; attempt < 3 && typeof fetch === 'function'; attempt += 1) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) break;
    const requestController = new AbortController();
    const timer = setTimeout(() => requestController.abort(), Math.min(remaining, 60000));
    const signals = [executionController.signal, requestController.signal, options.signal].filter(Boolean);
    const signal = typeof AbortSignal.any === 'function' ? AbortSignal.any(signals) : requestController.signal;
    try {
      return await fetch(target, { ...options, signal });
    } catch (error) {
      lastError = error;
      if (executionController.signal.aborted || (options.signal && options.signal.aborted)) throw error;
      if (!isRetryableNetworkError(error) || attempt === 2) break;
      await sleep([250, 750][attempt] || 0);
    } finally {
      clearTimeout(timer);
    }
  }

  const remaining = deadline - Date.now();
  if (remaining > 0) {
    const signals = [executionController.signal, options.signal].filter(Boolean);
    const signal = typeof AbortSignal.any === 'function'
      ? AbortSignal.any(signals)
      : (options.signal || executionController.signal);
    try {
      return await nativeRequest(target, options, signal, remaining);
    } catch (error) {
      lastError = error;
    }
  }
  const detail = lastError && lastError.message ? lastError.message : String(lastError || 'request deadline exceeded');
  throw new Error(`Plugin HTTP request failed: ${target.toString()}: ${detail}`);
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
