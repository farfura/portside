import SwiftUI
import Combine
import Darwin

final class PortStore: ObservableObject {
    static let shared = PortStore()

    @Published private(set) var ports: [ListeningPort] = []
    @Published private(set) var health: [Int: Health] = [:]
    @Published private(set) var recentlyStopped: [StoppedPort] = []
    @Published private(set) var lastScan: Date?
    @Published private(set) var lanIP: String?
    @Published private(set) var bridges: [Int: LANBridge] = [:]
    @Published private(set) var tunnels: [Int: TunnelSession] = [:]
    @Published private(set) var cloudflaredPath: String?
    @Published private(set) var isInstallingCloudflared = false
    @Published private(set) var installError: String?
    @Published var inspectorPort: Int?

    private var isScanning = false
    private var hasScannedOnce = false
    private var panelVisible = false
    private var timer: Timer?
    private var lastProbe: Date = .distantPast
    private var intentionallyKilled: Set<Int> = []
    private var cancellables: [Int: AnyCancellable] = [:]
    private var bridgeCancellables: [Int: AnyCancellable] = [:]

    var devPorts: [ListeningPort] { ports.filter { !$0.isSystem } }
    var systemPorts: [ListeningPort] { ports.filter(\.isSystem) }
    var hasLiveShares: Bool { tunnels.values.contains { $0.isLive } }
    var brewPath: String? { Shell.which("brew") }

    func start() {
        cloudflaredPath = Shell.which("cloudflared")
        lanIP = NetworkInfo.lanIPv4()
        refresh()
        schedule()
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        schedule()
        if visible {
            refresh()
            probeHealth(force: false)
            cloudflaredPath = Shell.which("cloudflared")
        }
    }

    private func schedule() {
        timer?.invalidate()
        let interval: TimeInterval = panelVisible ? 3 : 20
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Scanning

    func refresh(probe: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = PortScanner.scan()
            let ip = NetworkInfo.lanIPv4()
            DispatchQueue.main.async {
                self.apply(result)
                if self.lanIP != ip { self.lanIP = ip }
                self.lastScan = Date()
                self.isScanning = false
                if probe { self.probeHealth(force: true) }
            }
        }
    }

    private func apply(_ result: [ListeningPort]) {
        let previousDev = devPorts
        let newDevPortNumbers = Set(result.filter { !$0.isSystem }.map(\.port))

        if hasScannedOnce {
            var stopped = recentlyStopped
            for old in previousDev where !newDevPortNumbers.contains(old.port) {
                if intentionallyKilled.contains(old.port) { continue }
                if !stopped.contains(where: { $0.port.port == old.port }) {
                    stopped.insert(StoppedPort(port: old, stoppedAt: Date()), at: 0)
                }
            }
            stopped.removeAll { newDevPortNumbers.contains($0.port.port) || Date().timeIntervalSince($0.stoppedAt) > 180 }
            if stopped != recentlyStopped {
                withAnimation(.snappy) { recentlyStopped = stopped }
            }
            intentionallyKilled.subtract(intentionallyKilled.filter { !newDevPortNumbers.contains($0) })
        }
        hasScannedOnce = true

        if result != ports {
            withAnimation(.snappy) { ports = result }
        }

        // Probe brand new servers once so their dot means something right away.
        let unprobed = result.filter { !$0.isSystem && health[$0.port] == nil }
        if !unprobed.isEmpty { probe(unprobed) }

        // Forget health for ports that are gone.
        let live = Set(result.map(\.port))
        let staleHealth = health.keys.filter { !live.contains($0) }
        if !staleHealth.isEmpty { staleHealth.forEach { health[$0] = nil } }
    }

    func probeHealth(force: Bool) {
        guard force || Date().timeIntervalSince(lastProbe) > 8 else { return }
        lastProbe = Date()
        probe(devPorts)
    }

    private func probe(_ targets: [ListeningPort]) {
        for port in targets {
            if health[port.port] == nil { health[port.port] = .checking }
            HealthChecker.shared.check(port) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.ports.contains(where: { $0.port == port.port }) else { return }
                    if self.health[port.port] != result {
                        withAnimation(.easeOut(duration: 0.2)) { self.health[port.port] = result }
                    }
                }
            }
        }
    }

    func dismissStopped(_ stopped: StoppedPort) {
        withAnimation(.snappy) { recentlyStopped.removeAll { $0.id == stopped.id } }
    }

    // MARK: Actions

    func terminate(_ port: ListeningPort) {
        intentionallyKilled.insert(port.port)
        let pid = port.pid
        Darwin.kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.refresh() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if Darwin.kill(pid, 0) == 0 { Darwin.kill(pid, SIGKILL) }
            self.refresh()
        }
        Toast.shared.show("Stopped :\(port.port)", symbol: "xmark.circle.fill")
    }

    // MARK: Phone access

    func phoneURL(for port: ListeningPort) -> String? {
        guard let ip = lanIP else { return nil }
        if port.isLANReachable { return "http://\(ip):\(port.port)" }
        if let bridgePort = bridges[port.port]?.port { return "http://\(ip):\(bridgePort)" }
        return nil
    }

    func enablePhoneAccess(for port: ListeningPort) {
        guard !port.isLANReachable, bridges[port.port] == nil else { return }
        let bridge = LANBridge(targetHost: port.loopbackHost, targetPort: UInt16(clamping: port.port))
        bridgeCancellables[port.port] = bridge.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        bridges[port.port] = bridge
        bridge.start()
    }

    func disablePhoneAccess(for portNumber: Int) {
        bridges[portNumber]?.stop()
        bridges[portNumber] = nil
        bridgeCancellables[portNumber] = nil
    }

    // MARK: Public sharing

    func share(_ port: ListeningPort) {
        cloudflaredPath = cloudflaredPath ?? Shell.which("cloudflared")
        guard let cloudflared = cloudflaredPath else { return }
        if let existing = tunnels[port.port] {
            if existing.isActive { return }
            existing.start(cloudflared: cloudflared)
            return
        }
        let session = TunnelSession(targetPort: port.port, targetHost: port.loopbackHost)
        cancellables[port.port] = session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        tunnels[port.port] = session
        inspectorPort = port.port
        session.start(cloudflared: cloudflared)
    }

    func stopSharing(_ portNumber: Int) {
        tunnels[portNumber]?.stop()
        objectWillChange.send()
    }

    func removeSession(_ portNumber: Int) {
        tunnels[portNumber]?.shutdown()
        tunnels[portNumber] = nil
        cancellables[portNumber] = nil
    }

    func installCloudflared() {
        guard let brew = brewPath, !isInstallingCloudflared else { return }
        isInstallingCloudflared = true
        installError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Shell.run(brew, ["install", "cloudflared"], env: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1"], timeout: 900)
            DispatchQueue.main.async {
                self.isInstallingCloudflared = false
                self.cloudflaredPath = Shell.which("cloudflared")
                if self.cloudflaredPath == nil {
                    let detail = result.stderr.split(separator: "\n").last.map(String.init) ?? "Unknown error"
                    self.installError = "Install failed: \(detail)"
                } else {
                    Toast.shared.show("cloudflared installed", symbol: "checkmark.circle.fill")
                }
            }
        }
    }

    func rescanTools() {
        cloudflaredPath = Shell.which("cloudflared")
    }

    func shutdown() {
        tunnels.values.forEach { $0.shutdown() }
        bridges.values.forEach { $0.stop() }
    }
}
