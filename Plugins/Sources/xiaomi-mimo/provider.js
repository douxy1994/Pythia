globalThis.ResponseType = Object.freeze({ Text: "Text", Json: "Json", JSON: "Json" });
globalThis.Body = Object.freeze({
  json: (payload) => ({ type: "Json", payload }),
  form: (payload) => ({ type: "Form", payload }),
  text: (payload) => ({ type: "Text", payload })
});
const DEFAULT_OPENAI_BASE_URL = "https://token-plan-cn.xiaomimimo.com/v1";
const DEFAULT_ANTHROPIC_BASE_URL = "https://token-plan-cn.xiaomimimo.com/anthropic";
const DEFAULT_MODEL = "mimo-v2.5-pro";
const DEFAULT_MAX_TOKENS = 2048;

const LANGUAGE_NAMES = {
    auto: "the detected source language",
    "zh-CN": "Simplified Chinese",
    "zh-TW": "Traditional Chinese",
    en: "English",
    ja: "Japanese",
    ko: "Korean",
    fr: "French",
    es: "Spanish",
    ru: "Russian",
    de: "German",
    it: "Italian",
    tr: "Turkish",
    "pt-PT": "Portuguese (Portugal)",
    "pt-BR": "Portuguese (Brazil)",
    vi: "Vietnamese",
    id: "Indonesian",
    th: "Thai",
    ms: "Malay",
    ar: "Arabic",
    hi: "Hindi",
    "mn-Cyrl": "Mongolian (Cyrillic)",
    "mn-Mong": "Mongolian (Mongolian script)",
    km: "Khmer",
    "nb-NO": "Norwegian Bokmal",
    "nn-NO": "Norwegian Nynorsk",
    fa: "Persian"
};

async function translate(text, from, to, options) {
    const { config, detect, utils } = options;
    const { tauriFetch: fetch } = utils;

    const protocol = normalizeProtocol(config.protocol, config.baseUrl);
    const apiKey = getRequiredConfig(config.apiKey, "API Key");
    const model = normalizeString(config.model, DEFAULT_MODEL);
    const maxTokens = normalizePositiveInteger(config.maxTokens, DEFAULT_MAX_TOKENS);
    const authMode = normalizeString(config.authMode, "api-key").toLowerCase();
    const fromLanguage = from === "auto" ? languageName(detect || from) : languageName(from);
    const toLanguage = languageName(to);

    const headers = buildHeaders(apiKey, authMode);
    const prompt = buildPrompt(text, fromLanguage, toLanguage);

    if (protocol === "anthropic") {
        return callAnthropic(fetch, config.baseUrl, headers, model, maxTokens, prompt);
    }

    return callOpenAI(fetch, config.baseUrl, headers, model, maxTokens, prompt);
}

async function callOpenAI(fetch, baseUrl, headers, model, maxTokens, prompt) {
    const url = buildOpenAIEndpoint(baseUrl);
    const body = {
        model,
        messages: [
            {
                role: "system",
                content: [
                    "You are a professional translation engine.",
                    "Translate faithfully and naturally.",
                    "Preserve meaning, line breaks, markdown, punctuation, numbers, URLs, and code blocks.",
                    "Return only the translated text. Do not add explanations, quotes, labels, or notes."
                ].join(" ")
            },
            {
                role: "user",
                content: prompt
            }
        ],
        temperature: 0.1,
        top_p: 0.95,
        stream: false,
        max_completion_tokens: maxTokens,
        thinking: {
            type: "disabled"
        }
    };

    const res = await fetch(url, {
        method: "POST",
        url,
        headers,
        body: {
            type: "Json",
            payload: body
        }
    });

    if (!res.ok) {
        throw formatHttpError(res);
    }

    const message = res.data && res.data.choices && res.data.choices[0] && res.data.choices[0].message;
    const result = extractText(message && (message.content || message.reasoning_content));

    if (!result) {
        throw `MiMo OpenAI response has no translated text\n${safeJson(res.data)}`;
    }

    return cleanResult(result);
}

async function callAnthropic(fetch, baseUrl, headers, model, maxTokens, prompt) {
    const url = buildAnthropicEndpoint(baseUrl);
    const body = {
        model,
        max_tokens: maxTokens,
        system: [
            "You are a professional translation engine.",
            "Translate faithfully and naturally.",
            "Preserve meaning, line breaks, markdown, punctuation, numbers, URLs, and code blocks.",
            "Return only the translated text. Do not add explanations, quotes, labels, or notes."
        ].join(" "),
        messages: [
            {
                role: "user",
                content: [
                    {
                        type: "text",
                        text: prompt
                    }
                ]
            }
        ],
        temperature: 0.1,
        top_p: 0.95,
        stream: false,
        thinking: {
            type: "disabled"
        }
    };

    const res = await fetch(url, {
        method: "POST",
        url,
        headers,
        body: {
            type: "Json",
            payload: body
        }
    });

    if (!res.ok) {
        throw formatHttpError(res);
    }

    const result = extractAnthropicText(res.data);

    if (!result) {
        throw `MiMo Anthropic response has no translated text\n${safeJson(res.data)}`;
    }

    return cleanResult(result);
}

function buildPrompt(text, fromLanguage, toLanguage) {
    return [
        `Translate the following text from ${fromLanguage} to ${toLanguage}.`,
        "Output only the translation.",
        "",
        "<text>",
        text,
        "</text>"
    ].join("\n");
}

function buildHeaders(apiKey, authMode) {
    const headers = {
        "Content-Type": "application/json"
    };

    if (authMode === "bearer" || authMode === "authorization") {
        headers.Authorization = `Bearer ${apiKey}`;
    } else {
        headers["api-key"] = apiKey;
    }

    return headers;
}

function buildOpenAIEndpoint(baseUrl) {
    const normalized = normalizeUrl(baseUrl || DEFAULT_OPENAI_BASE_URL);

    if (normalized.endsWith("/anthropic/v1/messages")) {
        return normalized.replace(/\/anthropic\/v1\/messages$/, "/v1/chat/completions");
    }

    if (normalized.endsWith("/anthropic")) {
        return normalized.replace(/\/anthropic$/, "/v1/chat/completions");
    }

    if (normalized.endsWith("/chat/completions")) {
        return normalized;
    }

    if (normalized.endsWith("/v1")) {
        return `${normalized}/chat/completions`;
    }

    return `${normalized}/v1/chat/completions`;
}

function buildAnthropicEndpoint(baseUrl) {
    const normalized = normalizeUrl(baseUrl || DEFAULT_ANTHROPIC_BASE_URL);

    if (normalized.endsWith("/v1/chat/completions")) {
        return normalized.replace(/\/v1\/chat\/completions$/, "/anthropic/v1/messages");
    }

    if (normalized.endsWith("/v1/messages")) {
        return normalized;
    }

    if (normalized.endsWith("/messages")) {
        return normalized;
    }

    if (!normalized.includes("/anthropic") && normalized.endsWith("/v1")) {
        return `${normalized.slice(0, -3)}/anthropic/v1/messages`;
    }

    if (normalized.endsWith("/v1")) {
        return `${normalized}/messages`;
    }

    return `${normalized}/v1/messages`;
}

function normalizeProtocol(protocol, baseUrl) {
    const value = normalizeString(protocol, "").toLowerCase();

    if (value === "anthropic") {
        return "anthropic";
    }

    if (value === "openai") {
        return "openai";
    }

    return normalizeString(baseUrl, "").toLowerCase().includes("/anthropic") ? "anthropic" : "openai";
}

function normalizeUrl(url) {
    const trimmed = normalizeString(url, "");
    const withProtocol = trimmed.startsWith("http://") || trimmed.startsWith("https://") ? trimmed : `https://${trimmed}`;
    return withProtocol.replace(/\/+$/, "");
}

function normalizeString(value, fallback) {
    if (typeof value !== "string") {
        return fallback;
    }

    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : fallback;
}

function normalizePositiveInteger(value, fallback) {
    const number = Number.parseInt(value, 10);
    return Number.isFinite(number) && number > 0 ? number : fallback;
}

function getRequiredConfig(value, name) {
    const trimmed = normalizeString(value, "");

    if (!trimmed) {
        throw `Missing required config: ${name}`;
    }

    return trimmed;
}

function languageName(code) {
    return LANGUAGE_NAMES[code] || code || "the detected source language";
}

function extractAnthropicText(data) {
    if (!data || !Array.isArray(data.content)) {
        return "";
    }

    return data.content
        .map((item) => {
            if (!item) {
                return "";
            }

            if (typeof item === "string") {
                return item;
            }

            return item.text || "";
        })
        .filter(Boolean)
        .join("\n");
}

function extractText(value) {
    if (!value) {
        return "";
    }

    if (typeof value === "string") {
        return value;
    }

    if (Array.isArray(value)) {
        return value
            .map((item) => {
                if (typeof item === "string") {
                    return item;
                }

                return item && (item.text || item.content || "");
            })
            .filter(Boolean)
            .join("\n");
    }

    return "";
}

function cleanResult(value) {
    return value.trim().replace(/^["'`]+|["'`]+$/g, "").trim();
}

function formatHttpError(res) {
    return `Http Request Error\nHttp Status: ${res.status}\n${safeJson(res.data)}`;
}

function safeJson(value) {
    try {
        return JSON.stringify(value);
    } catch (error) {
        return String(value);
    }
}
