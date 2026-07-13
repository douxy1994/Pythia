import Foundation
import Network

final class PythiaHTTPServer {
    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.douxy.pythia.http")
    private let maxRequestBytes = 10 * 1024 * 1024
    private(set) var activePort: UInt16?
    var onTranslateRequest: ((String, @escaping (Result<String, Error>) -> Void) -> Void)?
    var onSelectionTranslate: (() -> Void)?
    var onInputTranslate: (() -> Void)?
    var onOCRRecognize: (() -> Void)?
    var onOCRTranslate: (() -> Void)?
    var onConfig: (() -> Void)?

    @discardableResult
    func start(port: UInt16 = 60828) -> String? {
        if listener != nil, activePort == port { return nil }
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            activePort = nil
            return "外部服务端口 \(port) 无效"
        }
        do {
            let listener = try NWListener(using: .tcp, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: serverQueue)
            self.listener = listener
            activePort = port
            return nil
        } catch {
            NSLog("Pythia HTTP server failed: \(error.localizedDescription)")
            activePort = nil
            return "外部服务端口 \(port) 启动失败：\(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        activePort = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: serverQueue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data else {
                self.respond(connection, status: "400 Bad Request", body: "Bad Request")
                return
            }
            var next = buffer
            next.append(data)
            guard next.count <= self.maxRequestBytes else {
                self.respond(connection, status: "413 Payload Too Large", body: "Request body is too large")
                return
            }
            if let request = self.parseCompleteRequest(next) {
                self.route(
                    connection: connection,
                    method: request.method,
                    path: request.path,
                    body: request.body
                )
                return
            }
            self.receiveRequest(connection, buffer: next)
        }
    }

    private func parseCompleteRequest(_ data: Data) -> (method: String, path: String, body: String)? {
        let marker = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: marker),
              let header = String(data: data[..<headerRange.lowerBound], encoding: .utf8)
        else {
            return nil
        }
        let bodyStart = headerRange.upperBound
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let path = parts.dropFirst().first.map(String.init) ?? "/"
        let headers = lines.dropFirst().reduce(into: [String: String]()) { result, line in
            guard let separator = line.firstIndex(of: ":") else { return }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            result[key] = value
        }
        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        guard data.count >= bodyStart + contentLength else {
            return nil
        }
        let bodyData = data[bodyStart..<bodyStart + contentLength]
        let body = String(data: bodyData, encoding: .utf8) ?? ""
        let decodedBody: String
        if headers["content-type"]?.lowercased().contains("application/x-www-form-urlencoded") == true {
            decodedBody = body.removingPercentEncoding ?? body
        } else {
            decodedBody = body
        }
        return (method, path, decodedBody)
    }

    private func route(connection: NWConnection, method: String, path: String, body: String) {
        let cleanPath = path.components(separatedBy: "?").first ?? path
        switch cleanPath {
        case "/", "/translate":
            if method.uppercased() == "POST" {
                DispatchQueue.main.async {
                    self.onTranslateRequest?(body) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let text):
                                self.respond(connection, status: "200 OK", body: text)
                            case .failure(let error):
                                self.respond(connection, status: "500 Internal Server Error", body: error.localizedDescription)
                            }
                        }
                    }
                }
            } else {
                respond(connection, status: "200 OK", body: "Pythia")
            }
        case "/selection_translate":
            DispatchQueue.main.async { self.onSelectionTranslate?() }
            respond(connection, status: "200 OK", body: "OK")
        case "/input_translate":
            DispatchQueue.main.async { self.onInputTranslate?() }
            respond(connection, status: "200 OK", body: "OK")
        case "/ocr_recognize":
            DispatchQueue.main.async { self.onOCRRecognize?() }
            respond(connection, status: "200 OK", body: "OK")
        case "/ocr_translate":
            DispatchQueue.main.async { self.onOCRTranslate?() }
            respond(connection, status: "200 OK", body: "OK")
        case "/config":
            DispatchQueue.main.async { self.onConfig?() }
            respond(connection, status: "200 OK", body: "OK")
        default:
            respond(connection, status: "404 Not Found", body: "Not Found")
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
