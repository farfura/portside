import Foundation

struct HeaderField: Hashable {
    var name: String
    var value: String
}

/// Minimal HTTP/1.1 parsing, just enough for an inspecting reverse proxy.
enum HTTP {
    static let crlf = Data([0x0D, 0x0A])
    static let headEnd = Data([0x0D, 0x0A, 0x0D, 0x0A])

    struct Request {
        var method: String
        var target: String
        var version: String
        var headers: [HeaderField]
        var body: Data
        var totalLength: Int

        func header(_ name: String) -> String? { HTTP.value(name, in: headers) }

        var isUpgrade: Bool {
            guard header("upgrade") != nil else { return false }
            return header("connection")?.lowercased().contains("upgrade") ?? false
        }
    }

    struct Response {
        var status: Int
        var reason: String
        var headers: [HeaderField]
        var body: Data
    }

    enum RequestParse {
        case needMore(expectsContinue: Bool)
        case invalid
        case complete(Request)
    }

    static func value(_ name: String, in headers: [HeaderField]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    static func splitHead(_ data: Data) -> (lines: [String], bodyStart: Int)? {
        guard let range = data.range(of: headEnd) else { return nil }
        let headData = data.subdata(in: data.startIndex..<range.lowerBound)
        let text = String(data: headData, encoding: .isoLatin1) ?? String(decoding: headData, as: UTF8.self)
        return (text.components(separatedBy: "\r\n"), range.upperBound - data.startIndex)
    }

    static func parseHeaders<S: Sequence>(_ lines: S) -> [HeaderField] where S.Element == String {
        var result: [HeaderField] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { result.append(HeaderField(name: name, value: value)) }
        }
        return result
    }

    /// `data` must start at index 0 (a freshly built buffer).
    static func parseRequest(_ data: Data) -> RequestParse {
        guard let head = splitHead(data) else {
            return data.count > 1_000_000 ? .invalid : .needMore(expectsContinue: false)
        }
        let parts = head.lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3 else { return .invalid }

        let headers = parseHeaders(head.lines.dropFirst())
        var request = Request(
            method: String(parts[0]),
            target: String(parts[1]),
            version: String(parts[2]),
            headers: headers,
            body: Data(),
            totalLength: head.bodyStart
        )
        let expectsContinue = request.header("expect")?.lowercased() == "100-continue"

        if let te = request.header("transfer-encoding"), te.lowercased().contains("chunked") {
            guard let decoded = decodeChunked(data, from: head.bodyStart) else { return .needMore(expectsContinue: expectsContinue) }
            request.body = decoded.body
            request.totalLength = decoded.end
        } else if let lengthText = request.header("content-length"),
                  let length = Int(lengthText.trimmingCharacters(in: .whitespaces)), length > 0 {
            guard data.count >= head.bodyStart + length else { return .needMore(expectsContinue: expectsContinue) }
            request.body = data.subdata(in: head.bodyStart..<(head.bodyStart + length))
            request.totalLength = head.bodyStart + length
        }
        return .complete(request)
    }

    static func parseResponse(_ data: Data) -> Response? {
        guard let head = splitHead(data) else { return nil }
        let parts = head.lines[0].split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, let code = Int(parts[1]) else { return nil }
        let headers = parseHeaders(head.lines.dropFirst())
        var body = data.count > head.bodyStart ? data.subdata(in: head.bodyStart..<data.count) : Data()
        if let te = value("transfer-encoding", in: headers), te.lowercased().contains("chunked"),
           let decoded = decodeChunked(body, from: 0) {
            body = decoded.body
        }
        return Response(status: code, reason: parts.count > 2 ? String(parts[2]) : "", headers: headers, body: body)
    }

    /// Decodes a chunked body that starts at `start`. Returns nil while incomplete.
    static func decodeChunked(_ data: Data, from start: Int) -> (body: Data, end: Int)? {
        var index = data.startIndex + start
        var out = Data()
        while true {
            guard index <= data.endIndex,
                  let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else { return nil }
            let sizeLine = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
            let hex = sizeLine.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard let size = Int(hex, radix: 16) else { return nil }
            index = lineEnd.upperBound
            if size == 0 {
                while true {
                    guard let trailerEnd = data.range(of: crlf, in: index..<data.endIndex) else { return nil }
                    let isBlank = trailerEnd.lowerBound == index
                    index = trailerEnd.upperBound
                    if isBlank { return (out, index - data.startIndex) }
                }
            }
            guard data.endIndex - index >= size + 2 else { return nil }
            out.append(data[index..<(index + size)])
            index += size + 2
        }
    }

    static func serializeHead(startLine: String, headers: [HeaderField]) -> Data {
        var text = startLine + "\r\n"
        for header in headers { text += "\(header.name): \(header.value)\r\n" }
        text += "\r\n"
        return text.data(using: .isoLatin1) ?? Data(text.utf8)
    }

    /// Rewrites a response head (without the trailing blank line) so the connection closes after it.
    static func closingResponseHead(_ head: Data) -> Data {
        let text = String(data: head, encoding: .isoLatin1) ?? String(decoding: head, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return head }
        let start = lines.removeFirst()
        let kept = lines.filter { line in
            let name = line.split(separator: ":", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            return name != "connection" && name != "keep-alive"
        }
        let rebuilt = ([start] + kept + ["Connection: close"]).joined(separator: "\r\n")
        return rebuilt.data(using: .isoLatin1) ?? Data(rebuilt.utf8)
    }

    static func errorPage(status: Int, title: String, message: String) -> Data {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>\(status) \(title)</title>
        <style>
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0e1015;color:#e8eaf0;font:15px/1.5 -apple-system,BlinkMacSystemFont,Inter,sans-serif}
        .card{max-width:440px;padding:36px;border-radius:20px;background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08)}
        .code{font:600 44px ui-monospace,SFMono-Regular,Menlo,monospace;background:linear-gradient(90deg,#3de6b8,#5cbcff);-webkit-background-clip:text;color:transparent}
        h1{font-size:18px;margin:6px 0 8px}p{color:#9aa0ad;margin:0}small{display:block;margin-top:22px;color:#5c6270}
        </style></head><body><div class="card"><div class="code">\(status)</div><h1>\(title)</h1><p>\(message)</p><small>Served by Portside</small></div></body></html>
        """
        return Data(html.utf8)
    }
}

// MARK: - Traffic entries

struct TrafficEntry: Identifiable, Hashable {
    let id: UUID
    let startedAt: Date
    var method: String
    var path: String
    var requestHeaders: [HeaderField]
    var requestBody: Data
    var forwardedRequest: Data
    var status: Int? = nil
    var reason: String? = nil
    var responseHeaders: [HeaderField] = []
    var responseBody: Data = Data()
    var responseTruncated = false
    var duration: TimeInterval? = nil
    var isReplay = false
    var isWebSocket = false
    var error: String? = nil

    init(method: String, path: String, requestHeaders: [HeaderField], requestBody: Data, forwardedRequest: Data) {
        self.id = UUID()
        self.startedAt = Date()
        self.method = method
        self.path = path
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.forwardedRequest = forwardedRequest
    }

    var isPending: Bool { status == nil && error == nil }

    mutating func apply(response data: Data) {
        if let parsed = HTTP.parseResponse(data) {
            status = parsed.status
            reason = parsed.reason
            responseHeaders = parsed.headers
            responseBody = parsed.body
        } else {
            error = "The server closed the connection without a valid HTTP response"
        }
    }
}
