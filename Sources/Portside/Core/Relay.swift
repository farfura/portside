import Foundation
import Network

/// Pumps bytes in both directions between two TCP connections until either side closes.
final class PipePair {
    let a: NWConnection
    let b: NWConnection
    private let queue: DispatchQueue
    private let aAlreadyStarted: Bool
    var initialToB: Data?
    var onFirstBToA: ((Data) -> Void)?
    var onClose: (() -> Void)?
    private var closed = false
    private var sawBToA = false

    init(a: NWConnection, b: NWConnection, queue: DispatchQueue, aAlreadyStarted: Bool) {
        self.a = a
        self.b = b
        self.queue = queue
        self.aAlreadyStarted = aAlreadyStarted
    }

    func start() {
        a.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        b.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                if let initial = self.initialToB, !initial.isEmpty {
                    self.b.send(content: initial, completion: .contentProcessed { [weak self] error in
                        if error != nil { self?.close() } else { self?.beginPumping() }
                    })
                } else {
                    self.beginPumping()
                }
            case .waiting, .failed, .cancelled:
                self.close()
            default:
                break
            }
        }
        if !aAlreadyStarted { a.start(queue: queue) }
        b.start(queue: queue)
    }

    private func beginPumping() {
        pump(from: a, to: b, isBToA: false)
        pump(from: b, to: a, isBToA: true)
    }

    private func pump(from: NWConnection, to: NWConnection, isBToA: Bool) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                if isBToA && !self.sawBToA {
                    self.sawBToA = true
                    self.onFirstBToA?(data)
                }
                to.send(content: data, completion: .contentProcessed { [weak self] sendError in
                    guard let self else { return }
                    if sendError != nil || isComplete { self.close() } else { self.pump(from: from, to: to, isBToA: isBToA) }
                })
            } else if isComplete || error != nil {
                self.close()
            } else {
                self.pump(from: from, to: to, isBToA: isBToA)
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        a.cancel()
        b.cancel()
        let callback = onClose
        onClose = nil
        callback?()
    }
}

/// Relays a server that only listens on localhost to the local network, so a phone can open it.
final class LANBridge: ObservableObject {
    enum State: Equatable {
        case starting
        case ready(UInt16)
        case failed(String)
    }

    @Published private(set) var state: State = .starting
    let targetHost: String
    let targetPort: UInt16
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.portside.bridge", qos: .userInitiated)
    private var pairs: [ObjectIdentifier: PipePair] = [:]

    init(targetHost: String, targetPort: UInt16) {
        self.targetHost = targetHost
        self.targetPort = targetPort
    }

    var port: UInt16? {
        if case .ready(let port) = state { return port }
        return nil
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        do {
            // Try a memorable port first (3000 becomes 13000), otherwise any free port.
            let preferred = UInt16(clamping: Int(targetPort) + 10000)
            let listener: NWListener
            if preferred > 10000, preferred < 65000, let port = NWEndpoint.Port(rawValue: preferred), let l = try? NWListener(using: parameters, on: port) {
                listener = l
            } else {
                listener = try NWListener(using: parameters, on: .any)
            }
            configure(listener, allowFallback: true)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func configure(_ listener: NWListener, allowFallback: Bool) {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self, weak listener] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                let port = listener?.port?.rawValue ?? 0
                DispatchQueue.main.async { self.state = .ready(port) }
            case .failed(let error):
                listener?.cancel()
                if allowFallback, let fallback = try? NWListener(using: .tcp, on: .any) {
                    self.configure(fallback, allowFallback: false)
                } else {
                    DispatchQueue.main.async { self.state = .failed(error.localizedDescription) }
                }
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ incoming: NWConnection) {
        guard let port = NWEndpoint.Port(rawValue: targetPort) else { incoming.cancel(); return }
        let outgoing = NWConnection(host: NWEndpoint.Host(targetHost), port: port, using: .tcp)
        let pair = PipePair(a: incoming, b: outgoing, queue: queue, aAlreadyStarted: false)
        let key = ObjectIdentifier(pair)
        pairs[key] = pair
        pair.onClose = { [weak self] in self?.pairs[key] = nil }
        pair.start()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async {
            let all = Array(self.pairs.values)
            self.pairs.removeAll()
            all.forEach { $0.close() }
        }
    }
}

/// Sends one raw HTTP request and collects the full response (used for replays).
final class RawHTTPClient {
    private let connection: NWConnection
    private let request: Data
    private let port: UInt16
    private let queue: DispatchQueue
    private var buffer = Data()
    private var finished = false
    private var completion: ((Data?, String?) -> Void)?
    private var keepAlive: RawHTTPClient?

    private init(connection: NWConnection, request: Data, port: UInt16, queue: DispatchQueue, completion: @escaping (Data?, String?) -> Void) {
        self.connection = connection
        self.request = request
        self.port = port
        self.queue = queue
        self.completion = completion
    }

    static func send(_ request: Data, host: String, port: UInt16, queue: DispatchQueue, timeout: TimeInterval = 30, completion: @escaping (Data?, String?) -> Void) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            completion(nil, "Invalid port")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let client = RawHTTPClient(connection: connection, request: request, port: port, queue: queue, completion: completion)
        client.keepAlive = client
        client.start(timeout: timeout)
    }

    private func start(timeout: TimeInterval) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connection.send(content: self.request, completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if let error { self.finish(nil, error.localizedDescription) } else { self.receive() }
                })
            case .waiting(let error), .failed(let error):
                self.finish(nil, "Nothing answered on localhost:\(self.port) (\(error.localizedDescription))")
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self else { return }
            self.finish(self.buffer.isEmpty ? nil : self.buffer, self.buffer.isEmpty ? "Timed out after \(Int(timeout))s" : nil)
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if let chunk, self.buffer.count < 4 * 1024 * 1024 { self.buffer.append(chunk) }
            if isComplete {
                self.finish(self.buffer, self.buffer.isEmpty ? "Empty response" : nil)
            } else if let error {
                self.finish(self.buffer.isEmpty ? nil : self.buffer, self.buffer.isEmpty ? error.localizedDescription : nil)
            } else {
                self.receive()
            }
        }
    }

    private func finish(_ data: Data?, _ error: String?) {
        guard !finished else { return }
        finished = true
        connection.cancel()
        let callback = completion
        completion = nil
        keepAlive = nil
        callback?(data, error)
    }
}
