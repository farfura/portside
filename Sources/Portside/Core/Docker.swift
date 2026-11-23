import SwiftUI
import AppKit

// MARK: - Model

struct DockerPortMapping: Hashable, Identifiable {
    let hostIP: String
    let hostPort: Int
    let containerPort: Int
    let proto: String

    var id: String { "\(hostPort)/\(proto)" }
    var url: URL? { proto == "tcp" ? URL(string: "http://localhost:\(hostPort)") : nil }
}

struct DockerContainer: Identifiable, Hashable {
    let id: String
    var name: String
    var image: String
    var state: String
    var status: String
    var ports: [DockerPortMapping]
    var composeProject: String?
    var composeService: String?
    var workingDir: String?
    var runningFor: String

    var shortID: String { String(id.prefix(12)) }
    var isRunning: Bool { state == "running" }
    var isPaused: Bool { state == "paused" }

    var tech: Tech {
        let firstPort = ports.first?.containerPort ?? 0
        return PortScanner.techForContainer("\(name) \(image)", port: firstPort)
    }

    var stateColor: Color {
        switch state {
        case "running": return status.contains("unhealthy") ? Theme.amber : Theme.mint
        case "paused", "restarting": return Theme.amber
        case "dead": return Theme.coral
        case "exited":
            // "Exited (0)" is a clean stop, anything else crashed.
            return status.hasPrefix("Exited (0)") ? Theme.strokeStrong : Theme.coral
        default: return Theme.strokeStrong
        }
    }

    /// Compose service name when available, it reads better than "project-service-1".
    var displayName: String { composeService ?? name }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !q.isEmpty else { return true }
        if let number = Int(q) {
            return ports.contains { String($0.hostPort).hasPrefix(String(number)) || String($0.containerPort).hasPrefix(String(number)) }
        }
        return [name, image, composeProject ?? "", composeService ?? "", shortID, workingDir ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }
}

struct DockerGroup: Identifiable {
    let id: String
    let project: String?
    let workingDir: String?
    var containers: [DockerContainer]

    var runningCount: Int { containers.filter(\.isRunning).count }
}

// MARK: - CLI

enum DockerCLI {
    static let separator = "\u{1F}"

    /// One line per container, fields split by the ASCII unit separator so names and
    /// statuses with spaces or tabs can never shift columns.
    static let format = [
        "{{.ID}}", "{{.Names}}", "{{.Image}}", "{{.State}}", "{{.Status}}", "{{.Ports}}",
        "{{.Label \"com.docker.compose.project\"}}",
        "{{.Label \"com.docker.compose.service\"}}",
        "{{.Label \"com.docker.compose.project.working_dir\"}}",
        "{{.RunningFor}}",
    ].joined(separator: separator)

    enum Result {
        case notInstalled
        case daemonDown(String)
        case ok([DockerContainer])
    }

    static func list() -> Result {
        guard let docker = Shell.which("docker") else { return .notInstalled }
        let out = Shell.run(docker, ["ps", "-a", "--no-trunc", "--format", format], timeout: 6)
        guard out.ok else {
            let message = out.stderr.split(separator: "\n").first.map(String.init) ?? "docker ps failed"
            return .daemonDown(message)
        }
        let containers = out.stdout.split(separator: "\n").compactMap { parse(String($0)) }
        return .ok(containers)
    }

    static func parse(_ line: String) -> DockerContainer? {
        let f = line.components(separatedBy: separator)
        guard f.count >= 10, !f[0].isEmpty else { return nil }
        func nonEmpty(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t == "<no value>" ? nil : t
        }
        return DockerContainer(
            id: f[0],
            name: f[1],
            image: f[2],
            state: f[3].lowercased(),
            status: f[4],
            ports: parsePorts(f[5]),
            composeProject: nonEmpty(f[6]),
            composeService: nonEmpty(f[7]),
            workingDir: nonEmpty(f[8]),
            runningFor: f[9]
        )
    }

    /// Parses "0.0.0.0:5432->5432/tcp, :::5432->5432/tcp, 6379/tcp".
    /// Only published ports are kept, deduplicated across IPv4 and IPv6.
    static func parsePorts(_ text: String) -> [DockerPortMapping] {
        var seen = Set<String>()
        var result: [DockerPortMapping] = []
        for raw in text.split(separator: ",") {
            let entry = raw.trimmingCharacters(in: .whitespaces)
            guard let arrow = entry.range(of: "->") else { continue }
            let left = entry[..<arrow.lowerBound]
            let right = entry[arrow.upperBound...]
            guard let colon = left.lastIndex(of: ":") else { continue }
            let hostIP = String(left[..<colon])
            let hostPortText = left[left.index(after: colon)...]
            let rightParts = right.split(separator: "/")
            let proto = rightParts.count > 1 ? String(rightParts[1]) : "tcp"
            // Ranges like 8000-8002->8000-8002/tcp: show the first port.
            guard let hostPort = Int(hostPortText.split(separator: "-").first ?? ""),
                  let containerPort = Int(rightParts.first?.split(separator: "-").first ?? "") else { continue }
            let key = "\(hostPort)/\(proto)"
            if seen.insert(key).inserted {
                result.append(DockerPortMapping(hostIP: hostIP, hostPort: hostPort, containerPort: containerPort, proto: proto))
            }
        }
        return result.sorted { $0.hostPort < $1.hostPort }
    }

    @discardableResult
    static func run(_ verb: String, _ id: String) -> Shell.Output {
        guard let docker = Shell.which("docker") else {
            return Shell.Output(status: -1, stdout: "", stderr: "docker not found")
        }
        return Shell.run(docker, [verb, id], timeout: 40)
    }
}

// MARK: - Store

final class DockerStore: ObservableObject {
    static let shared = DockerStore()

    enum Availability: Equatable {
        case unknown, notInstalled, daemonDown(String), ready
    }

    enum Action: String {
        case start, stop, restart, pause, unpause

        var pastTense: String {
            switch self {
            case .start: return "Started"
            case .stop: return "Stopped"
            case .restart: return "Restarted"
            case .pause: return "Paused"
            case .unpause: return "Resumed"
            }
        }
    }

    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var lastScan: Date?
    @Published private(set) var busyIDs: Set<String> = []

    private var isScanning = false
    private var panelVisible = false
    private var timer: Timer?

    var running: [DockerContainer] { containers.filter(\.isRunning) }

    func start() {
        refresh()
        schedule()
    }

    func setPanelVisible(_ visible: Bool) {
        panelVisible = visible
        schedule()
        if visible { refresh() }
    }

    private func schedule() {
        timer?.invalidate()
        let interval: TimeInterval = panelVisible ? 4 : 30
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !isScanning else { return }
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = DockerCLI.list()
            DispatchQueue.main.async {
                self.isScanning = false
                self.lastScan = Date()
                switch result {
                case .notInstalled:
                    self.setAvailability(.notInstalled)
                    self.setContainers([])
                case .daemonDown(let message):
                    self.setAvailability(.daemonDown(message))
                    self.setContainers([])
                case .ok(let list):
                    self.setAvailability(.ready)
                    self.setContainers(Self.sorted(list))
                }
            }
        }
    }

    private func setAvailability(_ value: Availability) {
        if availability != value { availability = value }
    }

    private func setContainers(_ list: [DockerContainer]) {
        if list != containers {
            withAnimation(.snappy) { containers = list }
        }
    }

    private static func sorted(_ list: [DockerContainer]) -> [DockerContainer] {
        list.sorted { a, b in
            if a.isRunning != b.isRunning { return a.isRunning }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Containers grouped by compose project; standalone containers come last.
    static func groups(_ list: [DockerContainer]) -> [DockerGroup] {
        var byProject: [String: DockerGroup] = [:]
        var standalone: [DockerContainer] = []
        for container in list {
            if let project = container.composeProject {
                byProject[project, default: DockerGroup(id: "compose:" + project, project: project, workingDir: container.workingDir, containers: [])]
                    .containers.append(container)
            } else {
                standalone.append(container)
            }
        }
        var groups = byProject.values.sorted { a, b in
            if (a.runningCount > 0) != (b.runningCount > 0) { return a.runningCount > 0 }
            return (a.project ?? "").localizedStandardCompare(b.project ?? "") == .orderedAscending
        }
        if !standalone.isEmpty {
            groups.append(DockerGroup(id: "standalone", project: nil, workingDir: nil, containers: standalone))
        }
        return groups
    }

    func perform(_ action: Action, on container: DockerContainer) {
        guard !busyIDs.contains(container.id) else { return }
        busyIDs.insert(container.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let out = DockerCLI.run(action.rawValue, container.id)
            DispatchQueue.main.async {
                self.busyIDs.remove(container.id)
                if out.ok {
                    Toast.shared.show("\(action.pastTense) \(container.displayName)", symbol: "shippingbox.fill")
                } else {
                    Toast.shared.show("Couldn't \(action.rawValue) \(container.displayName)", symbol: "exclamationmark.triangle.fill")
                }
                self.refresh()
            }
        }
    }

    /// Bundle IDs of apps that run a Docker engine on macOS.
    private static let engineApps = ["com.docker.docker", "dev.kdrag0n.MacVirt", "com.github.abiosoft.colima", "io.rancherdesktop.app"]

    var engineAppName: String? {
        for id in Self.engineApps {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url.deletingPathExtension().lastPathComponent
            }
        }
        return nil
    }

    func launchEngine() {
        for id in Self.engineApps {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                Toast.shared.show("Starting \(url.deletingPathExtension().lastPathComponent)", symbol: "shippingbox.fill")
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { self.refresh() }
                return
            }
        }
    }
}
