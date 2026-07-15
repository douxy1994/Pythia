function endpoint(baseURL) {
  const base = String(baseURL || "https://api.openai.com/v1").replace(/\/+$/, "");
  return base.endsWith("/chat/completions") ? base : `${base}/chat/completions`;
}

module.exports.translate = async function translate(request, context) {
  const { text, sourceLanguage, targetLanguage } = request.input;
  const { apiKey, baseURL, model } = context.config;
  if (!apiKey) throw new Error("AUTHENTICATION_FAILED: 请先配置 API Key。");

  const response = await context.fetch(endpoint(baseURL), {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    signal: context.signal,
    body: JSON.stringify({
      model: model || "gpt-4o-mini",
      stream: false,
      messages: [
        {
          role: "system",
          content: "You are a translation engine. Return only the translated text."
        },
        {
          role: "user",
          content: `Translate from ${sourceLanguage} to ${targetLanguage}:\n\n${text}`
        }
      ]
    })
  });

  const payload = await response.json();
  if (!response.ok) {
    const message = payload.error && payload.error.message
      ? payload.error.message
      : `HTTP ${response.status}`;
    throw new Error(`NETWORK_ERROR: ${message}`);
  }
  const translated = payload.choices?.[0]?.message?.content?.trim();
  if (!translated) throw new Error("INVALID_RESPONSE: 服务未返回译文。");
  return { success: true, data: { text: translated } };
};
