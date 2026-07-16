globalThis.ResponseType = Object.freeze({ Text: "Text", Json: "Json", JSON: "Json" });
globalThis.Body = Object.freeze({
  json: (payload) => ({ type: "Json", payload }),
  form: (payload) => ({ type: "Form", payload }),
  text: (payload) => ({ type: "Text", payload })
});
const DEFAULT_BASE_URL = "https://api.qnaigc.com/v1";
const DEFAULT_MODEL = "z-ai/glm-4.5-air-free";

function normalizeRequestUrl(baseURL) {
    let url = (baseURL || DEFAULT_BASE_URL).trim();
    if (!url) {
        url = DEFAULT_BASE_URL;
    }
    if (!/^https?:\/\//i.test(url)) {
        url = `https://${url}`;
    }
    url = url.replace(/\/+$/, "");
    if (/^https?:\/\/api\.qnaigc\.com$/i.test(url)) {
        return `${url}/v1/chat/completions`;
    }
    if (!url.endsWith("/chat/completions")) {
        url = `${url}/chat/completions`;
    }
    return url;
}

function parseNumber(value, defaultValue, min, max) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
        return defaultValue;
    }
    return Math.min(Math.max(parsed, min), max);
}

function stripWrappingQuotes(value) {
    return value
        .trim()
        .replace(/^```[a-zA-Z]*\n?/, "")
        .replace(/\n?```$/, "")
        .replace(/^["'“”‘’]|["'“”‘’]$/g, "")
        .trim();
}

function extractMessageContent(result) {
    const content = result && result.choices && result.choices[0] && result.choices[0].message && result.choices[0].message.content;
    if (typeof content === "string") {
        return content;
    }
    if (Array.isArray(content)) {
        return content
            .map((item) => {
                if (typeof item === "string") {
                    return item;
                }
                if (item && typeof item.text === "string") {
                    return item.text;
                }
                return "";
            })
            .join("");
    }
    return "";
}

function buildPrompt(text, from, to, detect) {
    const source = from && from !== "auto" ? from : (detect && detect !== "auto" ? detect : "the detected source language");
    return [
        `Translate the following text from ${source} to ${to}.`,
        "",
        "Requirements:",
        "- Return only the translated text.",
        "- Do not add explanations, notes, alternatives, markdown fences, or quotation marks.",
        "- Preserve line breaks, lists, placeholders, URLs, code snippets, and formatting as much as possible.",
        "- Keep names, numbers, and symbols faithful to the original text.",
        "",
        "Text:",
        text
    ].join("\n");
}

async function requestJson(utils, url, headers, payload) {
    if (utils.tauriFetch) {
        return await utils.tauriFetch(url, {
            method: "POST",
            url,
            headers,
            body: {
                type: "Json",
                payload
            }
        });
    }

    if (utils.http && utils.http.fetch && utils.http.Body) {
        const { fetch, Body } = utils.http;
        return await fetch(url, {
            method: "POST",
            headers,
            body: Body.json(payload)
        });
    }

    throw new Error("Pot plugin runtime does not provide a supported HTTP client.");
}

async function translate(text, from, to, options) {
    const { config, detect, utils } = options;
    const {
        apiKey,
        baseURL,
        model,
        temperature,
        maxTokens
    } = config;

    if (!apiKey || !apiKey.trim()) {
        throw new Error("Please configure your Zhipu API Key first.");
    }
    if (!to || to === "auto") {
        throw new Error("Target language cannot be auto.");
    }

    const requestUrl = normalizeRequestUrl(baseURL);
    const selectedModel = (model || DEFAULT_MODEL).trim() || DEFAULT_MODEL;
    const temp = parseNumber(temperature, 0.1, 0, 2);
    const maxOutputTokens = Math.round(parseNumber(maxTokens, 4096, 1, 131072));

    const payload = {
        model: selectedModel,
        messages: [
            {
                role: "system",
                content: "You are a professional translation engine. Translate accurately and naturally, and output only the translated text."
            },
            {
                role: "user",
                content: buildPrompt(text, from, to, detect)
            }
        ],
        stream: false,
        temperature: temp,
        max_tokens: maxOutputTokens
    };

    const res = await requestJson(utils, requestUrl, {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey.trim()}`
    }, payload);

    if (!res.ok) {
        throw `Http Request Error\nHttp Status: ${res.status}\n${JSON.stringify(res.data)}`;
    }

    const result = res.data;
    const content = extractMessageContent(result);
    if (content.trim()) {
        return stripWrappingQuotes(content);
    }

    throw `Invalid response format\n${JSON.stringify(result)}`;
}
