import Foundation
import Darwin

/// Finds every TCP port in LISTEN state for the current user and enriches it with
/// the process command line, working directory, project and framework.
enum PortScanner {
    private static let lock = NSLock()
    private static var processCache: [Int32: (name: String, command: String, cwd: String?)] = [:]
    private static var dockerCache: (date: Date, map: [Int: String])?

    /// Ports that speak a non HTTP protocol, so we never send them HTTP probes.
    static let servicePorts: Set<Int> = [22, 25, 53, 1433, 1521, 2181, 3306, 5432, 5672, 6379, 6380, 9042, 9092, 9200, 9300, 11211, 15672, 27017, 27018, 26257, 33060]

    private static let systemNames: Set<String> = [
        "controlcenter", "rapportd", "sharingd", "airplayxpchelper", "remoted", "identityservicesd",
        "remindd", "spotify", "figma_agent", "adobe", "dropbox", "raycast", "1password", "setappagent",
        "logioptionsplus_agent", "steam_osx", "discord", "slack", "zoom.us",
    ]

    static func isLoopback(_ host: String) -> Bool {
        host.hasPrefix("127.") || host == "[::1]" || host == "localhost" || host == "::1"
    }

    static func scan() -> [ListeningPort] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let result = Shell.run("/usr/sbin/lsof", ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"], timeout: 8)

        var byKey: [String: ListeningPort] = [:]
        var pid: Int32 = 0
        var command = ""

        for rawLine in result.stdout.split(separator: "\n") {
            guard let field = rawLine.first else { continue }
            let value = String(rawLine.dropFirst())
            switch field {
            case "p":
                pid = Int32(value) ?? 0
            case "c":
                command = value
            case "n":
                guard pid != ownPID, let parsed = parseName(value) else { continue }
                let key = "\(pid):\(parsed.port)"
                if var existing = byKey[key] {
                    existing.addresses.insert(parsed.host)
                    byKey[key] = existing
                } else {
                    byKey[key] = ListeningPort(port: parsed.port, pid: pid, processName: command, addresses: [parsed.host])
                }
            default:
                break
            }
        }

        var ports = Array(byKey.values)
        enrich(&ports)
        return ports.sorted { lhs, rhs in
            if lhs.isSystem != rhs.isSystem { return !lhs.isSystem }
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            return lhs.pid < rhs.pid
        }
    }

    private static func parseName(_ name: String) -> (host: String, port: Int)? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        let host = String(name[..<colon])
        guard let port = Int(name[name.index(after: colon)...]) else { return nil }
        return (host.isEmpty ? "*" : host, port)
    }

    // MARK: Enrichment

    private static func enrich(_ ports: inout [ListeningPort]) {
        let pids = Set(ports.map(\.pid))

        lock.lock()
        processCache = processCache.filter { pids.contains($0.key) }
        let missing = pids.filter { processCache[$0] == nil }
        lock.unlock()

        if !missing.isEmpty {
            let commands = commandLines(for: Array(missing))
            let cwds = workingDirectories(for: Array(missing))
            lock.lock()
            for pid in missing {
                let name = ports.first { $0.pid == pid }?.processName ?? ""
                processCache[pid] = (name, commands[pid] ?? name, cwds[pid])
            }
            lock.unlock()
        }

        let hasDocker = ports.contains { Tech.detect(process: $0.processName, command: "") == .docker }
        let dockerNames = hasDocker ? dockerPortNames() : [:]

        lock.lock()
        let cache = processCache
        lock.unlock()

        for i in ports.indices {
            let info = cache[ports[i].pid]
            let command = info?.command ?? ports[i].processName
            ports[i].commandLine = command
            ports[i].cwd = info?.cwd
            ports[i].tech = Tech.detect(process: ports[i].processName, command: command)

            if ports[i].tech == .docker, let container = dockerNames[ports[i].port] {
                ports[i].containerName = container
                ports[i].tech = techForContainer(container, port: ports[i].port)
            }

            if let cwd = info?.cwd, cwd != "/", cwd != NSHomeDirectory() {
                let root = projectRoot(from: cwd)
                ports[i].projectRoot = root
                ports[i].projectName = (root as NSString).lastPathComponent
            }

            ports[i].isSystem = isSystemProcess(ports[i])
        }
    }

    private static func isSystemProcess(_ port: ListeningPort) -> Bool {
        let c = port.commandLine
        let name = port.processName.lowercased()
        if port.containerName != nil || port.tech == .docker { return false }
        if port.tech.isDatabase { return false }
        if systemNames.contains(where: { name.hasPrefix($0) }) { return true }
        if c.hasPrefix("/System/") || c.hasPrefix("/usr/libexec/") || c.hasPrefix("/usr/sbin/") || c.hasPrefix("/Library/Apple/") { return true }
        if c.contains(".app/Contents/") { return true }
        if c.contains("/Library/Application Support/") || c.contains("/Library/PrivilegedHelperTools/") { return true }
        return false
    }

    static func techForContainer(_ name: String, port: Int) -> Tech {
        let n = name.lowercased()
        if n.contains("postgres") || port == 5432 { return .postgres }
        if n.contains("redis") || port == 6379 { return .redis }
        if n.contains("mysql") || n.contains("maria") || port == 3306 { return .mysql }
        if n.contains("mongo") || port == 27017 { return .mongo }
        if n.contains("elastic") || port == 9200 { return .elastic }
        return .docker
    }

    /// Walks up from the working directory to the nearest git root, falling back to the cwd.
    private static func projectRoot(from cwd: String) -> String {
        var url = URL(fileURLWithPath: cwd)
        let home = NSHomeDirectory()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.path }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path || parent.path == home || parent.path == "/" { break }
            url = parent
        }
        return cwd
    }

    private static func commandLines(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let out = Shell.run("/bin/ps", ["-ww", "-o", "pid=,command=", "-p", list], timeout: 5)
        var map: [Int32: String] = [:]
        for line in out.stdout.split(separator: "\n") {
            let trimmed = line.drop(while: { $0 == " " })
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            map[pid] = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    private static func workingDirectories(for pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        let out = Shell.run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-Fn"], timeout: 5)
        var map: [Int32: String] = [:]
        var current: Int32 = 0
        for line in out.stdout.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            if field == "p" { current = Int32(value) ?? 0 }
            if field == "n", current != 0 { map[current] = value }
        }
        return map
    }

    private static func dockerPortNames() -> [Int: String] {
        lock.lock()
        if let cached = dockerCache, Date().timeIntervalSince(cached.date) < 15 {
            lock.unlock()
            return cached.map
        }
        lock.unlock()

        var map: [Int: String] = [:]
        if let docker = Shell.which("docker") {
            let out = Shell.run(docker, ["ps", "--format", "{{.Names}}\t{{.Ports}}"], timeout: 4)
            if out.ok {
                for line in out.stdout.split(separator: "\n") {
                    let parts = line.split(separator: "\t", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let name = String(parts[0])
                    for mapping in parts[1].split(separator: ",") {
                        let m = mapping.trimmingCharacters(in: .whitespaces)
                        guard let arrow = m.range(of: "->") else { continue }
                        let left = m[..<arrow.lowerBound]
                        if let colon = left.lastIndex(of: ":"), let port = Int(left[left.index(after: colon)...]) {
                            map[port] = name
                        }
                    }
                }
            }
        }

        lock.lock()
        dockerCache = (Date(), map)
        lock.unlock()
        return map
    }
}

// MARK: - Health checks

final class HealthChecker: NSObject, URLSessionTaskDelegate {
    static let shared = HealthChecker()

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.5
        config.timeoutIntervalForResource = 3.5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Redirects count as healthy, so never follow them.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func check(_ port: ListeningPort, completion: @escaping (Health) -> Void) {
        if port.tech.isDatabase || PortScanner.servicePorts.contains(port.port) {
            completion(.service)
            return
        }
        let host = port.loopbackHost == "::1" ? "[::1]" : "127.0.0.1"
        guard let url = URL(string: "http://\(host):\(port.port)/") else { completion(.service); return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Portside health check", forHTTPHeaderField: "User-Agent")
        let started = Date()
        session.dataTask(with: request) { _, response, error in
            let ms = max(1, Int(Date().timeIntervalSince(started) * 1000))
            if let http = response as? HTTPURLResponse {
                completion(http.statusCode >= 500 ? .serverError(code: http.statusCode, ms: ms) : .up(code: http.statusCode, ms: ms))
            } else if let urlError = error as? URLError {
                switch urlError.code {
                case .cannotConnectToHost: completion(.down)
                case .timedOut: completion(.slow)
                default: completion(.service)
                }
            } else {
                completion(.service)
            }
        }.resume()
    }
}

// MARK: - Network info

enum NetworkInfo {
    /// The Mac's IPv4 address on the local network (WiFi or Ethernet).
    static func lanIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0,
                  let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if ip.hasPrefix("169.254.") { continue }
                candidates.append((String(cString: interface.ifa_name), ip))
            }
        }
        let preferred = candidates.first { $0.name == "en0" }
            ?? candidates.first { $0.name.hasPrefix("en") }
            ?? candidates.first { !$0.name.hasPrefix("utun") && !$0.name.hasPrefix("bridge") }
        return preferred?.ip
    }
}
