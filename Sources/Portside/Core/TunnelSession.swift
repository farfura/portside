import Foundation
import Darwin

/// One public share: an inspecting proxy plus a Cloudflare quick tunnel pointing at it.
final class TunnelSession: ObservableObject, Identifiable {
    enum Status: Equatable {
        case starting
        case live(URL)
        case failed(String)
        case stopped
    }

    let targetPort: Int
    let targetHost: String
    let startedAt = Date()
    var id: Int { targetPort }

    @Published private(set) var status: Status = .starting
    @Published private(set) var entries: [TrafficEntry] = []
    @Published private(set) var logLines: [String] = []

    private var proxy: InspectingProxy?
    private var process: Process?
    private var outputBuffer = ""
    private var timeoutWork: DispatchWorkItem?
    private static let maxEntries = 500

    init(targetPort: Int, targetHost: String) {
        self.targetPort = targetPort
        self.targetHost = targetHost
    }

    var publicURL: URL? {
        if case .live(let url) = status { return url }
        return nil
    }

    var isLive: Bool { publicURL != nil }

    var isActive: Bool {
        switch status {
        case .starting, .live: return true
        default: return false
        }
    }

    var requestCount: Int { entries.count }

    // MARK: Lifecycle

    func start(cloudflared: String) {
        teardown(hard: true)
        status = .starting
        outputBuffer = ""
        logLines = []

        let proxy = InspectingProxy(targetHost: targetHost, targetPort: UInt16(clamping: targetPort))
        proxy.onEntry = { [weak self] entry in self?.upsert(entry) }
        self.proxy = proxy
        proxy.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let port):
                self.launch(cloudflared: cloudflared, proxyPort: port)
            case .failure(let error):
                self.status = .failed("Couldn't start the local inspector: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        status = .stopped
        teardown(hard: false)
    }

    /// Called when the app quits: kill immediately so no tunnel is left behind.
    func shutdown() {
        status = .stopped
        teardown(hard: true)
    }

    private func teardown(hard: Bool) {
        timeoutWork?.cancel()
        timeoutWork = nil
        proxy?.stop()
        guard let process else { return }
        self.process = nil
        let pid = process.processIdentifier
        if process.isRunning {
            if hard {
                kill(pid, SIGKILL)
            } else {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                    if process.isRunning { kill(pid, SIGKILL) }
                }
            }
        }
    }

    private func launch(cloudflared: String, proxyPort: UInt16) {
        guard status == .starting else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cloudflared)
        process.arguments = ["tunnel", "--no-autoupdate", "--protocol", "http2", "--url", "http://127.0.0.1:\(proxyPort)"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Shell.pathEnv
        process.environment = environment

        let errPipe = Pipe()
        let outPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = outPipe
        process.standardInput = FileHandle.nullDevice

        let reader: @Sendable (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(text) }
        }
        errPipe.fileHandleForReading.readabilityHandler = reader
        outPipe.fileHandleForReading.readabilityHandler = reader

        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self, self.process === finished else { return }
                switch self.status {
                case .stopped, .failed:
                    return
                default:
                    self.status = .failed(self.lastErrorLine() ?? "cloudflared stopped unexpectedly (exit code \(finished.terminationStatus)).")
                    self.proxy?.stop()
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            status = .failed("Couldn't launch cloudflared: \(error.localizedDescription)")
            proxy?.stop()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.status == .starting else { return }
            self.status = .failed("Cloudflare didn't hand out a link in time. Check your internet connection and try again.")
            self.teardown(hard: false)
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: work)
    }

    private func consume(_ text: String) {
        outputBuffer += text
        if outputBuffer.count > 40_000 { outputBuffer = String(outputBuffer.suffix(20_000)) }

        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { logLines.append(trimmed) }
        }
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }

        if status == .starting,
           let range = outputBuffer.range(of: #"https://[a-z0-9-]+\.trycloudflare\.com"#, options: .regularExpression),
           let url = URL(string: String(outputBuffer[range])) {
            timeoutWork?.cancel()
            status = .live(url)
        }
    }

    private func lastErrorLine() -> String? {
        guard let line = logLines.last(where: { $0.contains(" ERR ") || $0.lowercased().contains("error") }) else { return nil }
        if let range = line.range(of: " ERR ") {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    // MARK: Traffic

    private func upsert(_ entry: TrafficEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.insert(entry, at: 0)
            if entries.count > TunnelSession.maxEntries { entries.removeLast(entries.count - TunnelSession.maxEntries) }
        }
    }

    func replay(_ entry: TrafficEntry) {
        if proxy == nil {
            let fresh = InspectingProxy(targetHost: targetHost, targetPort: UInt16(clamping: targetPort))
            fresh.onEntry = { [weak self] entry in self?.upsert(entry) }
            proxy = fresh
        }
        proxy?.replay(entry)
    }

    func clear() {
        entries.removeAll()
    }
}
