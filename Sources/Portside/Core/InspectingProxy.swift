import Foundation
import Network

/// A tiny reverse proxy on 127.0.0.1 that sits between cloudflared and the dev server.
/// It records every request and response so they can be inspected and replayed.
final class InspectingProxy {
    let targetHost: String
    let targetPort: UInt16
    let queue = DispatchQueue(label: "app.portside.proxy", qos: .userInitiated)
    var onEntry: ((TrafficEntry) -> Void)?
    private(set) var listenPort: UInt16?
    private var listener: NWListener?
    private var exchanges: [ObjectIdentifier: ProxyExchange] = [:]
    private var startReported = false

    init(targetHost: String, targetPort: UInt16) {
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    func start(_ completion: @escaping (Result<UInt16, Error>) -> Void) {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        do {
            let listener = try NWListener(using: parameters)
            startReported = false
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard !self.startReported else { return }
                    self.startReported = true
                    let port = listener?.port?.rawValue ?? 0
                    self.listenPort = port
                    DispatchQueue.main.async { completion(.success(port)) }
                case .failed(let error):
                    guard !self.startReported else { return }
                    self.startReported = true
                    DispatchQueue.main.async { completion(.failure(error)) }
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async {
            let all = Array(self.exchanges.values)
            self.exchanges.removeAll()
            all.forEach { $0.cancel() }
        }
    }

    func emit(_ entry: TrafficEntry) {
        let handler = onEntry
        DispatchQueue.main.async { handler?(entry) }
    }

    func replay(_ original: TrafficEntry) {
        var entry = TrafficEntry(
            method: original.method,
            path: original.path,
            requestHeaders: original.requestHeaders,
            requestBody: original.requestBody,
            forwardedRequest: original.forwardedRequest
        )
        entry.isReplay = true
        emit(entry)
        let started = Date()
        RawHTTPClient.send(original.forwardedRequest, host: targetHost, port: targetPort, queue: queue) { [weak self] data, error in
            var done = entry
            done.duration = Date().timeIntervalSince(started)
            if let data { done.apply(response: data) }
            if let error, done.status == nil { done.error = error }
            self?.emit(done)
        }
    }

    private func accept(_ connection: NWConnection) {
        let exchange = ProxyExchange(client: connection, proxy: self)
        let key = ObjectIdentifier(exchange)
        exchanges[key] = exchange
        exchange.onFinish = { [weak self] in self?.exchanges[key] = nil }
        exchange.start()
    }
}

/// Handles one client connection: read a request, forward it, stream the response back, log both.
final class ProxyExchange {
    private let client: NWConnection
    private weak var proxy: InspectingProxy?
    private let queue: DispatchQueue
    private let targetHost: String
    private let targetPort: UInt16

    private var upstream: NWConnection?
    private var pipe: PipePair?
    private var requestBuffer = Data()
    private var sentContinue = false
    private var entry: TrafficEntry?
    private var started = Date()
    private var responseLog = Data()
    private var responseTruncated = false
    private var pendingHead = Data()
    private var headForwarded = false
    private var responded = false
    private var done = false
    var onFinish: (() -> Void)?

    private static let logCap = 2 * 1024 * 1024
    private static let requestCap = 64 * 1024 * 1024

    init(client: NWConnection, proxy: InspectingProxy) {
        self.client = client
        self.proxy = proxy
        self.queue = proxy.queue
        self.targetHost = proxy.targetHost
        self.targetPort = proxy.targetPort
    }

    func start() {
        client.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.finish()
            default: break
            }
        }
        client.start(queue: queue)
        readRequest()
    }

    func cancel() { finish() }

    // MARK: Request

    private func readRequest() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.done else { return }
            if let data, !data.isEmpty { self.requestBuffer.append(data) }

            switch HTTP.parseRequest(self.requestBuffer) {
            case .complete(let request):
                self.handle(request)
            case .invalid:
                self.respond(status: 400, reason: "Bad Request", message: "Portside couldn't read this request.")
            case .needMore(let expectsContinue):
                if isComplete || error != nil {
                    self.finish()
                    return
                }
                if self.requestBuffer.count > ProxyExchange.requestCap {
                    self.respond(status: 413, reason: "Payload Too Large", message: "Requests over 64 MB aren't supported through Portside.")
                    return
                }
                if expectsContinue && !self.sentContinue {
                    self.sentContinue = true
                    self.client.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                }
                self.readRequest()
            }
        }
    }

    private func handle(_ request: HTTP.Request) {
        let upgrade = request.isUpgrade
        let originalHost = request.header("host")

        let dropped: Set<String> = upgrade
            ? ["host", "proxy-connection"]
            : ["host", "connection", "keep-alive", "proxy-connection", "transfer-encoding", "content-length",
               "accept-encoding", "expect", "upgrade", "te", "trailer"]

        var headers = request.headers.filter { !dropped.contains($0.name.lowercased()) }
        // Present the request as local traffic so dev servers with host checks (Vite, webpack) accept it.
        headers.insert(HeaderField(name: "Host", value: "localhost:\(targetPort)"), at: 0)
        if let originalHost, request.header("x-forwarded-host") == nil {
            headers.append(HeaderField(name: "X-Forwarded-Host", value: originalHost))
        }
        if request.header("x-forwarded-proto") == nil {
            headers.append(HeaderField(name: "X-Forwarded-Proto", value: "https"))
        }

        var body = Data()
        if !upgrade {
            headers.append(HeaderField(name: "Connection", value: "close"))
            if !request.body.isEmpty || ["POST", "PUT", "PATCH"].contains(request.method.uppercased()) {
                headers.append(HeaderField(name: "Content-Length", value: String(request.body.count)))
            }
            body = request.body
        }

        var raw = HTTP.serializeHead(startLine: "\(request.method) \(request.target) \(request.version)", headers: headers)
        raw.append(body)
        if upgrade, request.totalLength < requestBuffer.count {
            raw.append(requestBuffer.subdata(in: request.totalLength..<requestBuffer.count))
        }

        var newEntry = TrafficEntry(
            method: request.method,
            path: request.target,
            requestHeaders: request.headers,
            requestBody: request.body,
            forwardedRequest: raw
        )
        newEntry.isWebSocket = upgrade
        entry = newEntry
        started = Date()
        proxy?.emit(newEntry)

        guard let port = NWEndpoint.Port(rawValue: targetPort) else {
            respond(status: 502, reason: "Bad Gateway", message: "Invalid target port.")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(targetHost), port: port, using: .tcp)
        upstream = connection

        if upgrade {
            startWebSocketRelay(connection, initial: raw)
            return
        }

        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.done else { return }
            switch state {
            case .ready:
                connection.send(content: raw, completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    self.queue.async {
                        if let error { self.failUpstream(error.localizedDescription) } else { self.receiveUpstream() }
                    }
                })
            case .waiting(let error), .failed(let error):
                self.failUpstream(error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: Response

    private func receiveUpstream() {
        guard let connection = upstream, !done else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.done else { return }

            if let data, !data.isEmpty {
                self.record(data)
                var toSend: Data?
                if self.headForwarded {
                    toSend = data
                } else {
                    self.pendingHead.append(data)
                    if let range = self.pendingHead.range(of: HTTP.headEnd) {
                        let head = self.pendingHead.subdata(in: 0..<range.lowerBound)
                        var out = HTTP.closingResponseHead(head)
                        out.append(HTTP.headEnd)
                        if range.upperBound < self.pendingHead.count {
                            out.append(self.pendingHead.subdata(in: range.upperBound..<self.pendingHead.count))
                        }
                        self.pendingHead = Data()
                        self.headForwarded = true
                        toSend = out
                    } else if self.pendingHead.count > 512 * 1024 || isComplete {
                        toSend = self.pendingHead
                        self.pendingHead = Data()
                        self.headForwarded = true
                    }
                }

                if let toSend {
                    self.client.send(content: toSend, completion: .contentProcessed { [weak self] sendError in
                        guard let self else { return }
                        if sendError != nil {
                            self.completeResponse(error: "The visitor disconnected")
                        } else if isComplete {
                            self.completeResponse(error: nil)
                        } else {
                            self.receiveUpstream()
                        }
                    })
                    return
                }
            }

            if isComplete {
                self.completeResponse(error: nil)
            } else if let error {
                self.completeResponse(error: error.localizedDescription)
            } else {
                self.receiveUpstream()
            }
        }
    }

    private func record(_ data: Data) {
        let room = ProxyExchange.logCap - responseLog.count
        if room <= 0 {
            responseTruncated = true
        } else if data.count > room {
            responseLog.append(data.prefix(room))
            responseTruncated = true
        } else {
            responseLog.append(data)
        }
    }

    private func completeResponse(error: String?) {
        guard !done, !responded else { return }
        responded = true

        if var current = entry {
            current.duration = Date().timeIntervalSince(started)
            if let parsed = HTTP.parseResponse(responseLog) {
                current.status = parsed.status
                current.reason = parsed.reason
                current.responseHeaders = parsed.headers
                current.responseBody = parsed.body
            } else {
                current.error = error ?? "Empty response from localhost:\(targetPort)"
            }
            current.responseTruncated = responseTruncated
            entry = current
            proxy?.emit(current)
        }

        let leftover = pendingHead
        pendingHead = Data()
        if !leftover.isEmpty {
            client.send(content: leftover, completion: .contentProcessed { [weak self] _ in self?.finish() })
        } else {
            client.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in self?.finish() })
        }
    }

    private func failUpstream(_ message: String) {
        guard !done, !responded else { return }
        if headForwarded {
            completeResponse(error: message)
        } else {
            respond(status: 502, reason: "Bad Gateway", message: "Nothing is answering on localhost:\(targetPort) right now. Is your dev server still running?")
        }
    }

    private func respond(status: Int, reason: String, message: String) {
        guard !done, !responded else { return }
        responded = true
        let html = HTTP.errorPage(status: status, title: reason, message: message)
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.count)\r\nConnection: close\r\nX-Served-By: Portside\r\n\r\n"
        var data = Data(head.utf8)
        data.append(html)

        if var current = entry {
            current.status = status
            current.reason = reason
            current.error = message
            current.duration = Date().timeIntervalSince(started)
            current.responseBody = html
            current.responseHeaders = [HeaderField(name: "Content-Type", value: "text/html; charset=utf-8")]
            entry = current
            proxy?.emit(current)
        }
        client.send(content: data, completion: .contentProcessed { [weak self] _ in self?.finish() })
    }

    // MARK: WebSockets (HMR and friends)

    private func startWebSocketRelay(_ connection: NWConnection, initial: Data) {
        let pair = PipePair(a: client, b: connection, queue: queue, aAlreadyStarted: true)
        pipe = pair
        pair.initialToB = initial
        pair.onFirstBToA = { [weak self] data in
            guard let self, var current = self.entry else { return }
            if let parsed = HTTP.parseResponse(data) {
                current.status = parsed.status
                current.reason = parsed.reason
                current.responseHeaders = parsed.headers
            } else {
                current.status = 101
                current.reason = "Switching Protocols"
            }
            current.duration = Date().timeIntervalSince(self.started)
            self.entry = current
            self.proxy?.emit(current)
        }
        pair.onClose = { [weak self] in self?.finish() }
        pair.start()
    }

    // MARK: Teardown

    private func finish() {
        guard !done else { return }
        done = true
        pipe?.close()
        upstream?.cancel()
        client.cancel()
        if var current = entry, current.isPending {
            current.error = "Connection closed before a response"
            current.duration = Date().timeIntervalSince(started)
            proxy?.emit(current)
        }
        let callback = onFinish
        onFinish = nil
        callback?()
    }
}
