import SwiftUI

// MARK: - Tech detection

enum Tech: String, CaseIterable {
    case next, vite, nest, react, astro, nuxt, remix, svelte, angular, expo, storybook, webpack
    case rails, django, fastapi, flask, python, laravel, php
    case node, bun, deno, go, rust, java, dotnet
    case postgres, mysql, redis, mongo, elastic
    case docker, cloudflared, ngrok
    case unknown

    var name: String {
        switch self {
        case .next: return "Next.js"
        case .vite: return "Vite"
        case .nest: return "NestJS"
        case .react: return "React"
        case .astro: return "Astro"
        case .nuxt: return "Nuxt"
        case .remix: return "Remix"
        case .svelte: return "SvelteKit"
        case .angular: return "Angular"
        case .expo: return "Expo / Metro"
        case .storybook: return "Storybook"
        case .webpack: return "Webpack"
        case .rails: return "Rails"
        case .django: return "Django"
        case .fastapi: return "FastAPI"
        case .flask: return "Flask"
        case .python: return "Python"
        case .laravel: return "Laravel"
        case .php: return "PHP"
        case .node: return "Node.js"
        case .bun: return "Bun"
        case .deno: return "Deno"
        case .go: return "Go"
        case .rust: return "Rust"
        case .java: return "Java"
        case .dotnet: return ".NET"
        case .postgres: return "PostgreSQL"
        case .mysql: return "MySQL"
        case .redis: return "Redis"
        case .mongo: return "MongoDB"
        case .elastic: return "Elasticsearch"
        case .docker: return "Docker"
        case .cloudflared: return "cloudflared"
        case .ngrok: return "ngrok"
        case .unknown: return "Process"
        }
    }

    var symbol: String {
        switch self {
        case .next: return "n.square.fill"
        case .vite: return "bolt.fill"
        case .nest: return "bird.fill"
        case .react: return "atom"
        case .astro: return "sparkles"
        case .nuxt: return "triangle.fill"
        case .remix: return "r.square.fill"
        case .svelte: return "s.square.fill"
        case .angular: return "a.square.fill"
        case .expo: return "iphone"
        case .storybook: return "book.closed.fill"
        case .webpack: return "square.3.layers.3d"
        case .rails: return "tram.fill"
        case .django: return "d.square.fill"
        case .fastapi: return "f.square.fill"
        case .flask: return "drop.fill"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .laravel: return "l.square.fill"
        case .php: return "p.square.fill"
        case .node: return "hexagon.fill"
        case .bun: return "circle.hexagongrid.fill"
        case .deno: return "d.circle.fill"
        case .go: return "g.square.fill"
        case .rust: return "gearshape.fill"
        case .java: return "cup.and.saucer.fill"
        case .dotnet: return "number.square.fill"
        case .postgres: return "cylinder.split.1x2.fill"
        case .mysql: return "cylinder.fill"
        case .redis: return "square.stack.3d.up.fill"
        case .mongo: return "leaf.fill"
        case .elastic: return "magnifyingglass"
        case .docker: return "shippingbox.fill"
        case .cloudflared: return "cloud.fill"
        case .ngrok: return "point.3.connected.trianglepath.dotted"
        case .unknown: return "network"
        }
    }

    var color: Color {
        switch self {
        case .next: return Color(white: 0.92)
        case .vite: return Color(red: 0.74, green: 0.55, blue: 1.0)
        case .nest: return Color(red: 0.95, green: 0.27, blue: 0.40)
        case .react, .expo: return Color(red: 0.38, green: 0.85, blue: 0.98)
        case .astro: return Color(red: 1.0, green: 0.45, blue: 0.25)
        case .nuxt, .mongo: return Color(red: 0.25, green: 0.86, blue: 0.55)
        case .remix: return Color(white: 0.85)
        case .svelte: return Color(red: 1.0, green: 0.40, blue: 0.20)
        case .angular: return Color(red: 0.92, green: 0.20, blue: 0.35)
        case .storybook: return Color(red: 1.0, green: 0.30, blue: 0.55)
        case .webpack: return Color(red: 0.55, green: 0.80, blue: 1.0)
        case .rails, .laravel: return Color(red: 0.95, green: 0.30, blue: 0.30)
        case .django: return Color(red: 0.20, green: 0.70, blue: 0.45)
        case .fastapi: return Color(red: 0.10, green: 0.75, blue: 0.65)
        case .flask, .python: return Color(red: 1.0, green: 0.82, blue: 0.30)
        case .php: return Color(red: 0.55, green: 0.55, blue: 0.95)
        case .node: return Color(red: 0.45, green: 0.80, blue: 0.35)
        case .bun: return Color(red: 0.98, green: 0.85, blue: 0.70)
        case .deno: return Color(white: 0.85)
        case .go: return Color(red: 0.30, green: 0.80, blue: 0.90)
        case .rust: return Color(red: 0.90, green: 0.55, blue: 0.35)
        case .java: return Color(red: 0.95, green: 0.55, blue: 0.25)
        case .dotnet: return Color(red: 0.55, green: 0.40, blue: 0.95)
        case .postgres: return Color(red: 0.45, green: 0.62, blue: 0.95)
        case .mysql: return Color(red: 0.30, green: 0.60, blue: 0.85)
        case .redis: return Color(red: 0.95, green: 0.30, blue: 0.25)
        case .elastic: return Color(red: 1.0, green: 0.80, blue: 0.25)
        case .docker: return Color(red: 0.20, green: 0.60, blue: 1.0)
        case .cloudflared: return Color(red: 1.0, green: 0.55, blue: 0.20)
        case .ngrok: return Color(red: 0.40, green: 0.50, blue: 1.0)
        case .unknown: return Color(white: 0.6)
        }
    }

    var isDatabase: Bool {
        switch self {
        case .postgres, .mysql, .redis, .mongo, .elastic: return true
        default: return false
        }
    }

    static func detect(process: String, command: String) -> Tech {
        let p = process.lowercased()
        let c = command.lowercased()
        func has(_ s: String) -> Bool { c.contains(s) }

        if p.hasPrefix("com.docker") || p.contains("docker") || p == "vpnkit-bridge" { return .docker }
        if p.contains("postgres") || has("bin/postgres") { return .postgres }
        if p.contains("mysqld") || p.contains("mariadb") { return .mysql }
        if p.contains("redis") { return .redis }
        if p.contains("mongod") { return .mongo }
        if p.contains("elasticsearch") || has("elasticsearch") { return .elastic }
        if p.contains("cloudflared") { return .cloudflared }
        if p.contains("ngrok") { return .ngrok }

        if p.hasPrefix("next-server") || has("next-server") || has("next dev") || has("next start") || has("/next/dist") { return .next }
        if has("storybook") { return .storybook }
        if has("vite") { return .vite }
        if has("@nestjs") || has("nest start") || has("/nest ") { return .nest }
        if has("expo") || has("metro") || has("react-native") { return .expo }
        if has("astro") { return .astro }
        if has("nuxt") { return .nuxt }
        if has("remix") { return .remix }
        if has("svelte") { return .svelte }
        if has("ng serve") || has("@angular") { return .angular }
        if has("react-scripts") { return .react }
        if has("webpack") { return .webpack }
        if has("artisan") { return .laravel }
        if has("rails") || has("puma") { return .rails }
        if has("manage.py") || has("django") { return .django }
        if has("uvicorn") || has("fastapi") { return .fastapi }
        if has("flask") { return .flask }
        if p.hasPrefix("python") || has("python") { return .python }
        if p == "php" || has("bin/php") { return .php }
        if p == "bun" || has("bun ") { return .bun }
        if p == "deno" { return .deno }
        if p == "node" || has("bin/node") || has("node ") { return .node }
        if p.contains("java") { return .java }
        if p == "dotnet" { return .dotnet }
        if has("target/debug") || has("target/release") || has("cargo") { return .rust }
        if has("go-build") || has("/go/") { return .go }
        return .unknown
    }
}

// MARK: - Listening port

struct ListeningPort: Identifiable, Hashable {
    let port: Int
    let pid: Int32
    var processName: String
    var addresses: Set<String>
    var commandLine: String = ""
    var cwd: String? = nil
    var projectRoot: String? = nil
    var projectName: String? = nil
    var containerName: String? = nil
    var tech: Tech = .unknown
    var isSystem: Bool = false

    var id: String { "\(pid):\(port)" }

    var isLANReachable: Bool { addresses.contains { !PortScanner.isLoopback($0) } }

    /// The loopback address that actually reaches this server.
    var loopbackHost: String {
        let reachesV4 = addresses.contains { $0 == "*" || $0.contains(".") || $0 == "[::]" }
        return reachesV4 ? "127.0.0.1" : "::1"
    }

    var displayName: String {
        if let containerName { return containerName }
        if let projectName { return projectName }
        return tech == .unknown ? processName : tech.name
    }

    /// Search by port number (":30", "3000") or by any name: project, folder path,
    /// container, process or framework.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let digits = q.hasPrefix(":") ? String(q.dropFirst()) : q
        if !digits.isEmpty, digits.allSatisfy(\.isNumber) {
            return String(port).hasPrefix(digits)
        }
        let fields = [displayName, projectName ?? "", projectRoot ?? cwd ?? "", containerName ?? "", processName, tech.name]
        return fields.contains { $0.localizedCaseInsensitiveContains(q) }
    }

    var localURLString: String { "http://localhost:\(port)" }
    var localURL: URL { URL(string: localURLString)! }

    var bindingDescription: String {
        let sorted = addresses.sorted()
        return sorted.map { host -> String in
            switch host {
            case "*": return "all interfaces"
            case "127.0.0.1", "[::1]": return "\(host) (this Mac only)"
            default: return host
            }
        }.joined(separator: ", ")
    }
}

struct StoppedPort: Identifiable, Hashable {
    let port: ListeningPort
    let stoppedAt: Date
    var id: String { port.id + "@" + String(stoppedAt.timeIntervalSince1970) }
}

// MARK: - Health

enum Health: Equatable {
    case checking
    case up(code: Int, ms: Int)
    case serverError(code: Int, ms: Int)
    case service
    case slow
    case down

    var color: Color {
        switch self {
        case .checking: return Theme.tertiary
        case .up(let code, _):
            if code >= 400 { return Theme.amber }
            if code >= 300 { return Theme.sky }
            return Theme.mint
        case .serverError, .slow: return Theme.amber
        case .service: return Theme.sky
        case .down: return Theme.coral
        }
    }

    var isHealthy: Bool {
        switch self {
        case .up, .service: return true
        default: return false
        }
    }

    var shortLabel: String {
        switch self {
        case .checking: return "checking"
        case .up(let code, let ms): return "\(code) · \(ms)ms"
        case .serverError(let code, let ms): return "\(code) · \(ms)ms"
        case .service: return "listening"
        case .slow: return "not responding"
        case .down: return "refused"
        }
    }

    var longLabel: String {
        switch self {
        case .checking: return "Checking"
        case .up(let code, let ms): return "Responding \(code) in \(ms)ms"
        case .serverError(let code, _): return "Server error \(code)"
        case .service: return "Accepting connections"
        case .slow: return "Not responding to HTTP"
        case .down: return "Refusing connections"
        }
    }
}
