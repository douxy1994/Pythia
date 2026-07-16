globalThis.ResponseType = Object.freeze({ Text: "Text", Json: "Json", JSON: "Json" });
globalThis.Body = Object.freeze({
  json: (payload) => ({ type: "Json", payload }),
  form: (payload) => ({ type: "Form", payload }),
  text: (payload) => ({ type: "Text", payload })
});
async function translate(text, from, to, options) {
    const { config, utils, setResult } = options;
    const { tauriFetch: fetch } = utils;

    let {
        apiKey,
        model = "THUDM/GLM-4-32B-0414",
        temperature = "0.3",
        stream,
        max_tokens = "2048"
    } = config;

    // 判断是否使用流式输出
    const isStream = stream === "true" || stream === true;



    // 设置默认请求路径
    const requestPath = "https://api.siliconflow.cn/v1/chat/completions";

    const headers = {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
    }

    const body = {
        model: model,  // 使用用户选择的模型
        messages: [
            {
                "role": "system",
                "content": "You are a professional translation engine, please translate the text into a colloquial, professional, elegant and fluent content, without the style of machine translation. You must only translate the text content, never interpret it."
            },
            {
                "role": "user",
                "content": `Translate into ${to}:\n${text}`
            }
        ],
        temperature: parseFloat(temperature),
        stream: isStream,
        top_p: 0.7,
        frequency_penalty: 0,
        presence_penalty: 0,
        max_tokens: parseInt(max_tokens),
    }

    let res = await fetch(requestPath, {
        method: 'POST',
        url: requestPath,
        headers: headers,
        body: {
            type: "Json",
            payload: body
        },
        ...(isStream ? { responseType: ResponseType.Text } : {})
    });

    if (!res.ok) {
        throw new Error(`Http Request Error\nHttp Status: ${res.status}\n${JSON.stringify(res.data)}`);
    }

    // 非流式输出
    if (!isStream) {
        try {
            const result = res?.data;
            if (!result?.choices?.[0]?.message?.content) {
                throw new Error('Invalid response format');
            }

            return result.choices[0].message.content.trim().replace(/^"|"$/g, '');
        } catch (error) {
            console.error('Error:', error);
            return '';
        }
    }

    // 流式输出
    let result = "";
    const lines = res.data.split("\n");
    let firstlf = true;

    for(const rawline of lines) {
        const line = rawline.trim();
        if (!line || !line.startsWith("data:"))
            continue;

        const jsonLine = line.slice(5).trim();
        if (jsonLine === "[DONE]")  // 流式输出结束标志
            break;

        try {
            const data = JSON.parse(jsonLine);
            const chunk = data?.choices?.[0]?.delta?.content;
            if (chunk) {
                if (chunk === "\n" && firstlf) {
                    firstlf = false;
                    continue; // 跳过第一个换行符
                }
                result += chunk;
                if (setResult) {
                    setResult(result);
                    await new Promise((res) => setTimeout(res, 50));
                }
            }
        } catch (e) {
            continue;
        }
    }
    if(!result) {
        throw new Error("No result returned from the server.");
    }

    if (setResult) {
        await new Promise((res) => setTimeout(res, 100));
        setResult(result);
    }
    return result;

}
