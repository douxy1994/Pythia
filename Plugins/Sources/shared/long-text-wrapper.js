const __pythiaLegacyTranslate = translate;

// Keep individual requests comfortably below common model output limits. Long
// documents are translated sequentially so ordering and provider rate limits
// remain predictable.
const __PYTHIA_CHUNK_LIMIT = 1800;
const __PYTHIA_RETRY_DELAYS_MS = [0, 750, 2000, 5000, 10000, 18000];

function __pythiaErrorText(error) {
  if (typeof error === "string") return error;
  if (error && typeof error.message === "string") return error.message;
  try { return JSON.stringify(error); } catch (_) { return String(error); }
}

function __pythiaIsRetryable(error) {
  const message = __pythiaErrorText(error);
  const statusMatch = message.match(/(?:http\s+status|status(?:\s+code)?)\s*[:=]?\s*(\d{3})/i);
  if (statusMatch) {
    const status = Number(statusMatch[1]);
    if ([408, 409, 425, 429, 500, 502, 503, 504].includes(status)) return true;
  }
  return /fetch failed|network|socket|tls|econnreset|econnrefused|etimedout|eai_again|enotfound|epipe|und_err|temporar|rate limit|too many requests|timed?\s*out|timeout|abort/i.test(message);
}

function __pythiaRetryDelay(error, attempt) {
  const message = __pythiaErrorText(error);
  const milliseconds = message.match(/retry[_ -]?after[_ -]?ms["':=\s]+(\d+)/i);
  if (milliseconds) return Math.min(60000, Math.max(750, Number(milliseconds[1])));
  const seconds = message.match(/retry-after\s*:\s*([0-9.]+)/i);
  if (seconds) return Math.min(60000, Math.max(750, Number(seconds[1]) * 1000));
  return __PYTHIA_RETRY_DELAYS_MS[attempt] || 0;
}

function __pythiaAbortError() {
  const error = new Error("Plugin translation was cancelled.");
  error.name = "AbortError";
  return error;
}

function __pythiaSleep(delay, signal) {
  if (!delay) return Promise.resolve();
  return new Promise((resolve, reject) => {
    if (signal && signal.aborted) {
      reject(__pythiaAbortError());
      return;
    }
    let settled = false;
    const finish = (callback) => {
      if (settled) return;
      settled = true;
      if (signal && typeof signal.removeEventListener === "function") {
        signal.removeEventListener("abort", onAbort);
      }
      callback();
    };
    const timer = setTimeout(() => finish(resolve), delay);
    const onAbort = () => {
      clearTimeout(timer);
      finish(() => reject(__pythiaAbortError()));
    };
    if (signal && typeof signal.addEventListener === "function") {
      signal.addEventListener("abort", onAbort, { once: true });
    }
  });
}

function __pythiaSplitText(text, limit = __PYTHIA_CHUNK_LIMIT) {
  if (text.length <= limit) return [text];
  const chunks = [];
  let cursor = 0;
  while (cursor < text.length) {
    const hardEnd = Math.min(text.length, cursor + limit);
    if (hardEnd === text.length) {
      chunks.push(text.slice(cursor));
      break;
    }

    const window = text.slice(cursor, hardEnd);
    const minimumBoundary = Math.floor(limit * 0.55);
    const boundaryPattern = /(?:\r?\n)+|[。！？!?；;：:]\s*|[.]\s+|[,，]\s*/g;
    let match;
    let preferredEnd = -1;
    while ((match = boundaryPattern.exec(window)) !== null) {
      const candidate = match.index + match[0].length;
      if (candidate >= minimumBoundary) preferredEnd = candidate;
      if (match[0].length === 0) boundaryPattern.lastIndex += 1;
    }

    let end = preferredEnd > 0 ? cursor + preferredEnd : hardEnd;
    const previous = text.charCodeAt(end - 1);
    const next = text.charCodeAt(end);
    if (previous >= 0xD800 && previous <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF) {
      end -= 1;
    }
    if (end <= cursor) end = hardEnd;
    chunks.push(text.slice(cursor, end));
    cursor = end;
  }
  return chunks;
}

function __pythiaWhitespaceEnvelope(chunk) {
  const leading = (chunk.match(/^\s+/) || [""])[0];
  const remainder = chunk.slice(leading.length);
  const trailing = (remainder.match(/\s+$/) || [""])[0];
  return {
    leading,
    core: remainder.slice(0, remainder.length - trailing.length),
    trailing
  };
}

async function __pythiaTranslateChunk(chunk, invoke, signal, index, total) {
  const envelope = __pythiaWhitespaceEnvelope(chunk);
  if (!envelope.core) return chunk;

  let lastError;
  for (let attempt = 0; attempt < __PYTHIA_RETRY_DELAYS_MS.length; attempt += 1) {
    if (signal && signal.aborted) throw __pythiaAbortError();
    if (attempt > 0) await __pythiaSleep(__pythiaRetryDelay(lastError, attempt), signal);
    try {
      const value = await invoke(envelope.core);
      const translated = typeof value === "string" ? value.trim() : String(value ?? "").trim();
      if (!translated) throw new Error("Plugin returned an empty translation.");
      return `${envelope.leading}${translated}${envelope.trailing}`;
    } catch (error) {
      lastError = error;
      if ((signal && signal.aborted) || !__pythiaIsRetryable(error) || attempt === __PYTHIA_RETRY_DELAYS_MS.length - 1) {
        break;
      }
    }
  }

  const detail = __pythiaErrorText(lastError);
  throw new Error(`Translation chunk ${index + 1}/${total} failed: ${detail}`);
}

async function __pythiaTranslateLongText(text, invoke, signal) {
  const chunks = __pythiaSplitText(text);
  const translated = [];
  for (let index = 0; index < chunks.length; index += 1) {
    translated.push(await __pythiaTranslateChunk(chunks[index], invoke, signal, index, chunks.length));
  }
  return translated.join("");
}

async function __pythiaCompatFetch(context, url, options = {}) {
  const headers = { ...(options.headers || {}) };
  let body = options.body;
  if (body && typeof body === "object" && Object.prototype.hasOwnProperty.call(body, "type")) {
    if (body.type === "Json") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) {
        headers["Content-Type"] = "application/json";
      }
      body = JSON.stringify(body.payload);
    } else if (body.type === "Form") {
      if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) {
        headers["Content-Type"] = "application/x-www-form-urlencoded";
      }
      body = new URLSearchParams(body.payload || {}).toString();
    } else {
      body = String(body.payload ?? "");
    }
  } else if (body && typeof body === "object") {
    if (!Object.keys(headers).some((key) => key.toLowerCase() === "content-type")) {
      headers["Content-Type"] = "application/json";
    }
    body = JSON.stringify(body);
  }

  const fetchOptions = { method: options.method || "GET", headers, body };
  if (context.signal) fetchOptions.signal = context.signal;
  const response = await context.fetch(url, fetchOptions);
  const responseText = await response.text();
  const responseHeaders = Object.fromEntries(response.headers.entries());
  if (!response.ok && [408, 409, 425, 429, 500, 502, 503, 504].includes(response.status)) {
    const retryAfter = response.headers.get("retry-after");
    const retryLine = retryAfter ? `\nRetry-After: ${retryAfter}` : "";
    throw new Error(`HTTP Status: ${response.status}${retryLine}\n${responseText.slice(0, 32768)}`);
  }
  const wantsText = options.responseType === "Text" || options.responseType === "text";
  let data = responseText;
  if (!wantsText) {
    try { data = responseText ? JSON.parse(responseText) : null; } catch (_) {}
  }
  return {
    ok: response.ok,
    status: response.status,
    url: response.url,
    data,
    headers: responseHeaders
  };
}

module.exports.translate = async function pythiaConvertedTranslate(request, context) {
  const input = request && request.input ? request.input : {};
  const compatFetch = (url, options) => __pythiaCompatFetch(context, url, options);
  const utils = {
    tauriFetch: compatFetch,
    http: { fetch: compatFetch, Body: globalThis.Body }
  };
  const invoke = (chunk) => __pythiaLegacyTranslate(
    chunk,
    String(input.sourceLanguage || "auto"),
    String(input.targetLanguage || "zh-CN"),
    {
      config: context.config || {},
      detect: input.detectedLanguage || input.sourceLanguage || "auto",
      utils,
      setResult: () => {}
    }
  );
  return await __pythiaTranslateLongText(String(input.text || ""), invoke, context.signal);
};
