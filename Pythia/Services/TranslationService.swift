import CryptoKit
import Foundation

enum PythiaNetworkSession {
    static func dataTask(
        with url: URL,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        dataTask(with: URLRequest(url: url), completion: completion)
    }

    static func dataTask(
        with request: URLRequest,
        completion: @escaping (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let session = URLSession(configuration: configuration(for: request.url))
        let task = session.dataTask(with: requestWithProxyAuthorization(request)) { data, response, error in
            completion(data, response, error)
            session.finishTasksAndInvalidate()
        }
        return task
    }

    private static func configuration(for url: URL?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 1_200
        configuration.waitsForConnectivity = true
        if let proxy = proxyDictionary(for: url) {
            configuration.connectionProxyDictionary = proxy
        }
        return configuration
    }

    private static func proxyDictionary(for url: URL?) -> [AnyHashable: Any]? {
        let preferences = Preferences.shared
        let host = preferences.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = preferences.proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.proxyEnabled, !host.isEmpty, let port = Int(portText), port > 0 else {
            return nil
        }
        if let requestHost = url?.host, isNoProxyHost(requestHost, noProxy: preferences.noProxy) {
            return nil
        }
        return [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: port,
            kCFNetworkProxiesExceptionsList as String: noProxyList(preferences.noProxy),
        ]
    }

    private static func requestWithProxyAuthorization(_ request: URLRequest) -> URLRequest {
        let preferences = Preferences.shared
        guard preferences.proxyEnabled,
              !preferences.proxyUsername.isEmpty,
              !preferences.proxyPassword.isEmpty,
              let host = request.url?.host,
              !isNoProxyHost(host, noProxy: preferences.noProxy)
        else {
            return request
        }
        var updated = request
        if updated.value(forHTTPHeaderField: "Proxy-Authorization") == nil {
            let token = "\(preferences.proxyUsername):\(preferences.proxyPassword)"
                .data(using: .utf8)?
                .base64EncodedString() ?? ""
            updated.setValue("Basic \(token)", forHTTPHeaderField: "Proxy-Authorization")
        }
        return updated
    }

    private static func noProxyList(_ value: String) -> [String] {
        value
            .split { $0 == "," || $0 == ";" || $0 == "\n" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isNoProxyHost(_ host: String, noProxy: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else { return false }
        return noProxyList(noProxy).contains { entry in
            let token = entry.lowercased()
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")
                .split(separator: ":")
                .first
                .map(String.init) ?? ""
            if token == "*" { return true }
            if token.hasPrefix(".") {
                return normalizedHost.hasSuffix(token) || normalizedHost == String(token.dropFirst())
            }
            return normalizedHost == token || normalizedHost.hasSuffix(".\(token)")
        }
    }
}

final class TranslationService {
    static let shared = TranslationService()

    struct LanguagePair {
        let source: String
        let target: String
    }

    static func canonicalServiceIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("plugin:") {
            return trimmed
        }
        if let provider = PythiaProvider.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return provider.rawValue
        }
        return trimmed
    }

    func translateService(
        identifier: String,
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmed = Self.canonicalServiceIdentifier(identifier)
        let languages = Self.resolvedLanguages(text: text, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        if trimmed.lowercased().hasPrefix("plugin:") {
            translatePluginText(
                serviceIdentifier: trimmed,
                text: text,
                sourceLanguage: languages.source,
                targetLanguage: languages.target,
                completion: completion
            )
            return
        }
        guard let provider = PythiaProvider.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            completion(.failure(TranslationError.requestFailed("未知翻译服务：\(identifier)。")))
            return
        }
        translate(text: text, provider: provider, sourceLanguage: languages.source, targetLanguage: languages.target, completion: completion)
    }

    private func translatePluginText(
        serviceIdentifier: String,
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let chunks = Self.translationChunks(for: text, maxCharacters: 1_800)
        guard chunks.count > 1 else {
            PluginManager.shared.translate(
                serviceIdentifier: serviceIdentifier,
                text: text,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                completion: completion
            )
            return
        }
        translatePluginChunks(
            chunks,
            serviceIdentifier: serviceIdentifier,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            index: 0,
            results: [],
            completion: completion
        )
    }

    private func translatePluginChunks(
        _ chunks: [String],
        serviceIdentifier: String,
        sourceLanguage: String,
        targetLanguage: String,
        index: Int,
        results: [String],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard index < chunks.count else {
            completion(.success(results.joined(separator: "\n\n")))
            return
        }
        PluginManager.shared.translate(
            serviceIdentifier: serviceIdentifier,
            text: chunks[index],
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let translated):
                self.translatePluginChunks(
                    chunks,
                    serviceIdentifier: serviceIdentifier,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    index: index + 1,
                    results: results + [translated],
                    completion: completion
                )
            case .failure(let error):
                completion(.failure(TranslationError.requestFailed("第 \(index + 1)/\(chunks.count) 段翻译失败：\(error.localizedDescription)")))
            }
        }
    }

    static func estimatedTranslationChunkCount(for text: String, maxCharacters: Int = 1_800) -> Int {
        max(1, translationChunks(for: text, maxCharacters: maxCharacters).count)
    }

    private static func translationChunks(for text: String, maxCharacters: Int) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.count > maxCharacters else {
            return [normalized.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
        }
        var chunks: [String] = []
        var current = ""

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            current = ""
        }

        for line in normalized.components(separatedBy: .newlines) {
            let segment = line + "\n"
            if segment.count > maxCharacters {
                flushCurrent()
                chunks.append(contentsOf: splitLongSegment(segment, maxCharacters: maxCharacters))
                continue
            }
            if current.count + segment.count > maxCharacters {
                flushCurrent()
            }
            current += segment
        }
        flushCurrent()
        return chunks
    }

    private static func splitLongSegment(_ text: String, maxCharacters: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        let preferredBreaks = CharacterSet(charactersIn: "。！？；.!?;\n")

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            current = ""
        }

        for character in text {
            current.append(character)
            let scalarBreak = character.unicodeScalars.contains { preferredBreaks.contains($0) }
            if current.count >= maxCharacters, scalarBreak {
                flushCurrent()
            } else if current.count >= maxCharacters + 400 {
                flushCurrent()
            }
        }
        flushCurrent()
        return chunks
    }

    func translate(
        text: String,
        provider: PythiaProvider,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(TranslationError.emptyInput))
            return
        }
        let languages = Self.resolvedLanguages(text: trimmed, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)

        switch provider {
        case .local:
            completion(.success("【本地预览】\n\(trimmed)"))
        case .google:
            translateWithGoogle(text: trimmed, sourceLanguage: languages.source, targetLanguage: languages.target, completion: completion)
        case .openAI:
            translateWithOpenAI(text: trimmed, sourceLanguage: languages.source, targetLanguage: languages.target, completion: completion)
        case .deepL:
            translateWithDeepL(text: trimmed, sourceLanguage: languages.source, targetLanguage: languages.target, completion: completion)
        case .baidu:
            translateWithBaidu(text: trimmed, sourceLanguage: languages.source, targetLanguage: languages.target, completion: completion)
        case .youdao:
            translateWithYoudao(text: trimmed, sourceLanguage: languages.source, targetLanguage: languages.target, completion: completion)
        case .libreTranslate:
            translateWithLibreTranslate(text: trimmed, sourceLanguage: languages.source, targetLanguage: languages.target, completion: completion)
        case .plugin:
            PluginManager.shared.translate(
                text: trimmed,
                sourceLanguage: languages.source,
                targetLanguage: languages.target,
                completion: completion
            )
        }
    }

    static func resolvedLanguages(text: String, sourceLanguage: String, targetLanguage: String) -> LanguagePair {
        let source = normalizedLanguageCode(sourceLanguage, fallback: "auto")
        let target = normalizedLanguageCode(targetLanguage, fallback: "zh-CN")
        guard isAutoLanguage(source) else {
            return LanguagePair(source: source, target: target)
        }
        let automaticTarget = AutomaticLanguagePolicy.targetLanguage(for: text, selectedTarget: target)
        guard containsChineseAndEnglish(text) else {
            return LanguagePair(source: source, target: automaticTarget)
        }
        if isEnglishLanguage(automaticTarget) {
            return LanguagePair(source: "zh-CN", target: automaticTarget)
        }
        if isChineseLanguage(automaticTarget) {
            return LanguagePair(source: "en", target: automaticTarget)
        }
        return LanguagePair(source: source, target: automaticTarget)
    }

    static func containsChineseAndEnglish(_ text: String) -> Bool {
        var hasChinese = false
        var hasEnglish = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x20000...0x2A6DF).contains(value) {
                hasChinese = true
            } else if (0x0041...0x005A).contains(value) || (0x0061...0x007A).contains(value) {
                hasEnglish = true
            }
            if hasChinese && hasEnglish { return true }
        }
        return false
    }

    private static func normalizedLanguageCode(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func isAutoLanguage(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "auto"
    }

    private static func isChineseLanguage(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("zh")
    }

    private static func isEnglishLanguage(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("en")
    }

    private func translateWithGoogle(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: sourceLanguage.isEmpty ? "auto" : sourceLanguage),
            URLQueryItem(name: "tl", value: targetLanguage.isEmpty ? "zh-CN" : targetLanguage),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url else {
            completion(.failure(TranslationError.invalidResponse))
            return
        }
        PythiaNetworkSession.dataTask(with: url) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                let sentences = json.first as? [[Any]]
            else {
                completion(.failure(TranslationError.invalidResponse))
                return
            }
            let translated = sentences.compactMap { $0.first as? String }.joined()
            completion(.success(translated))
        }.resume()
    }

    private func translateWithOpenAI(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let preferences = Preferences.shared
        guard !preferences.openAIKey.isEmpty else {
            completion(.failure(TranslationError.missingKey("OpenAI API Key")))
            return
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(preferences.openAIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let prompt = "Translate the following text from \(sourceLanguage) to \(targetLanguage). Return only the translation.\n\n\(text)"
        let body: [String: Any] = [
            "model": preferences.openAIModel,
            "messages": [
                ["role": "system", "content": "You are a concise translation engine."],
                ["role": "user", "content": prompt],
            ],
            "temperature": 0.2,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        PythiaNetworkSession.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(http.statusCode)"
                completion(.failure(TranslationError.requestFailed(message)))
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                completion(.failure(TranslationError.invalidResponse))
                return
            }
            completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }

    private func translateWithDeepL(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let key = Preferences.shared.deepLKey
        guard !key.isEmpty else {
            completion(.failure(TranslationError.missingKey("DeepL API Key")))
            return
        }
        var request = URLRequest(url: URL(string: "https://api-free.deepl.com/v2/translate")!)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let deeplTarget = targetLanguage.replacingOccurrences(of: "-", with: "_").uppercased()
        var items = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "target_lang", value: deeplTarget),
        ]
        if !sourceLanguage.isEmpty, sourceLanguage.lowercased() != "auto" {
            items.append(URLQueryItem(name: "source_lang", value: sourceLanguage.uppercased()))
        }
        var components = URLComponents()
        components.queryItems = items
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        PythiaNetworkSession.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(http.statusCode)"
                completion(.failure(TranslationError.requestFailed(message)))
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let translations = json["translations"] as? [[String: Any]],
                let result = translations.first?["text"] as? String
            else {
                completion(.failure(TranslationError.invalidResponse))
                return
            }
            completion(.success(result))
        }.resume()
    }

    private func translateWithBaidu(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let preferences = Preferences.shared
        guard !preferences.baiduAppID.isEmpty, !preferences.baiduSecret.isEmpty else {
            completion(.failure(TranslationError.missingKey("百度翻译 AppID/密钥")))
            return
        }
        let salt = String(Int(Date().timeIntervalSince1970))
        let from = normalizeBaiduLanguage(sourceLanguage)
        let to = normalizeBaiduLanguage(targetLanguage)
        let sign = md5(preferences.baiduAppID + text + salt + preferences.baiduSecret)
        var components = URLComponents(string: "https://fanyi-api.baidu.com/api/trans/vip/translate")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "appid", value: preferences.baiduAppID),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
        ]
        PythiaNetworkSession.dataTask(with: components.url!) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                completion(.failure(TranslationError.invalidResponse))
                return
            }
            if let errorMessage = json["error_msg"] as? String {
                completion(.failure(TranslationError.requestFailed(errorMessage)))
                return
            }
            let result = (json["trans_result"] as? [[String: Any]])?
                .compactMap { $0["dst"] as? String }
                .joined(separator: "\n") ?? ""
            result.isEmpty ? completion(.failure(TranslationError.invalidResponse)) : completion(.success(result))
        }.resume()
    }

    private func translateWithYoudao(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let preferences = Preferences.shared
        guard !preferences.youdaoAppKey.isEmpty, !preferences.youdaoSecret.isEmpty else {
            completion(.failure(TranslationError.missingKey("有道翻译 AppKey/密钥")))
            return
        }
        let salt = UUID().uuidString
        let currentTime = String(Int(Date().timeIntervalSince1970))
        let input = truncateForYoudao(text)
        let sign = sha256(preferences.youdaoAppKey + input + salt + currentTime + preferences.youdaoSecret)
        var components = URLComponents(string: "https://openapi.youdao.com/api")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: sourceLanguage.isEmpty ? "auto" : sourceLanguage),
            URLQueryItem(name: "to", value: targetLanguage.isEmpty ? "zh-CHS" : normalizeYoudaoLanguage(targetLanguage)),
            URLQueryItem(name: "appKey", value: preferences.youdaoAppKey),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
            URLQueryItem(name: "signType", value: "v3"),
            URLQueryItem(name: "curtime", value: currentTime),
        ]
        PythiaNetworkSession.dataTask(with: components.url!) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                completion(.failure(TranslationError.invalidResponse))
                return
            }
            if let code = json["errorCode"] as? String, code != "0" {
                completion(.failure(TranslationError.requestFailed("有道错误码：\(code)")))
                return
            }
            let result = (json["translation"] as? [String])?.joined(separator: "\n") ?? ""
            result.isEmpty ? completion(.failure(TranslationError.invalidResponse)) : completion(.success(result))
        }.resume()
    }

    private func translateWithLibreTranslate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let preferences = Preferences.shared
        guard let baseURL = URL(string: preferences.libreTranslateURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            completion(.failure(TranslationError.requestFailed("LibreTranslate URL 无效。")))
            return
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("translate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "q": text,
            "source": sourceLanguage.isEmpty ? "auto" : sourceLanguage,
            "target": normalizeSimpleLanguage(targetLanguage),
            "format": "text",
            "api_key": preferences.libreTranslateKey,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        PythiaNetworkSession.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? "HTTP \(http.statusCode)"
                completion(.failure(TranslationError.requestFailed(message)))
                return
            }
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let result = json["translatedText"] as? String
            else {
                completion(.failure(TranslationError.invalidResponse))
                return
            }
            completion(.success(result))
        }.resume()
    }

    private func md5(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func truncateForYoudao(_ value: String) -> String {
        if value.count <= 20 { return value }
        return String(value.prefix(10)) + String(value.count) + String(value.suffix(10))
    }

    private func normalizeSimpleLanguage(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.hasPrefix("zh") { return "zh" }
        if lower.hasPrefix("en") { return "en" }
        if lower.hasPrefix("ja") { return "ja" }
        if lower.hasPrefix("ko") { return "ko" }
        return lower.isEmpty ? "zh" : lower
    }

    private func normalizeBaiduLanguage(_ value: String) -> String {
        let lower = value.lowercased()
        if lower == "auto" || lower.isEmpty { return "auto" }
        if lower.hasPrefix("zh") { return "zh" }
        if lower.hasPrefix("en") { return "en" }
        if lower.hasPrefix("ja") { return "jp" }
        if lower.hasPrefix("ko") { return "kor" }
        return lower
    }

    private func normalizeYoudaoLanguage(_ value: String) -> String {
        let lower = value.lowercased()
        if lower.hasPrefix("zh") { return "zh-CHS" }
        if lower.hasPrefix("en") { return "en" }
        if lower.hasPrefix("ja") { return "ja" }
        if lower.hasPrefix("ko") { return "ko" }
        return lower
    }
}
