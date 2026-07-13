import AppKit
import Foundation
import Vision

final class OCRService {
    static let shared = OCRService()

    func recognizeScreen(completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", "-c"]
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    completion(.failure(TranslationError.requestFailed("无法截取屏幕。请确认屏幕录制权限。")))
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.recognizeClipboardImage(completion: completion)
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    func recognizeClipboardImage(completion: @escaping (Result<String, Error>) -> Void) {
        guard
            let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            completion(.failure(TranslationError.requestFailed("剪贴板里没有图片。")))
            return
        }
        let services = Preferences.shared.recognizeServiceList
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !services.isEmpty else {
            completion(.failure(TranslationError.requestFailed("请先在设置中启用至少一个 OCR 服务。")))
            return
        }
        recognizeWithConfiguredServices(services, cgImage: cgImage, completion: completion)
    }

    private func recognizeWithConfiguredServices(
        _ services: [String],
        index: Int = 0,
        cgImage: CGImage,
        lastError: Error? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard index < services.count else {
            if let lastError {
                completion(.failure(TranslationError.requestFailed("所有 OCR 服务均未返回结果：\(lastError.localizedDescription)")))
            } else {
                completion(.failure(TranslationError.requestFailed("所有 OCR 服务均未返回结果。")))
            }
            return
        }

        let service = services[index]
        let serviceCompletion: (Result<String, Error>) -> Void = { result in
            switch result {
            case .success(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    let error = TranslationError.requestFailed("\(serviceDisplayName(service)) 未返回识别文本。")
                    self.recognizeWithConfiguredServices(services, index: index + 1, cgImage: cgImage, lastError: error, completion: completion)
                } else {
                    completion(.success(text))
                }
            case .failure(let error):
                self.recognizeWithConfiguredServices(services, index: index + 1, cgImage: cgImage, lastError: error, completion: completion)
            }
        }

        if service.lowercased().hasPrefix("plugin:") {
            recognizeWithLegacyPlugin(serviceIdentifier: service, cgImage: cgImage, completion: serviceCompletion)
        } else if service.lowercased() == "system ocr" {
            recognize(cgImage: cgImage, completion: serviceCompletion)
        } else {
            serviceCompletion(.failure(TranslationError.requestFailed("未知 OCR 服务：\(service)。")))
        }
    }

    private func recognizeWithLegacyPlugin(
        serviceIdentifier: String,
        cgImage: CGImage,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            completion(.failure(TranslationError.requestFailed("无法生成 OCR 插件所需的 PNG 图片数据。")))
            return
        }
        let base64 = pngData.base64EncodedString()
        PluginManager.shared.runLegacyService(
            serviceIdentifier: serviceIdentifier,
            expectedType: "recognize",
            input: base64,
            sourceLanguage: Preferences.shared.recognizeLanguage,
            targetLanguage: Preferences.shared.targetLanguage
        ) { result in
            switch result {
            case .success(let text):
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    completion(.failure(TranslationError.requestFailed("OCR 插件未返回识别文本。")))
                } else {
                    completion(.success(text))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func recognize(cgImage: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                completion(.failure(error))
                return
            }
            let text = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n") ?? ""
            completion(.success(text))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                completion(.failure(error))
            }
        }
    }
}

private func serviceDisplayName(_ identifier: String) -> String {
    PluginManager.shared.serviceOptions(for: "recognize").first(where: { $0.id == identifier })?.title ?? identifier
}
