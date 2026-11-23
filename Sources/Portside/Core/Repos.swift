import SwiftUI

// MARK: - Model

struct RepoStatus: Identifiable, Hashable {
    enum State: Int, Comparable {
        case conflict = 0, dirty, unpushed, unpublished, behind, stashed, clean

        static func < (lhs: State, rhs: State) -> Bool { lhs.rawValue < rhs.rawValue }

        var color: Color {
            switch self {
            case .conflict: return Theme.coral
            case .dirty: return Theme.amber
            case .unpushed: return Theme.mint
            case .unpublished: return Theme.violet
            case .behind: return Theme.sky
            case .stashed: return Theme.secondary
            case .clean: return Theme.strokeStrong
            }
        }
    }

    let path: String
    var name: String
    var branch: String = ""
    var upstream: String?
    var ahead = 0
    var behind = 0
    var staged = 0
    var modified = 0
    var untracked = 0
    var conflicts = 0
    var stashes = 0
    var isDetached = false
    var hasCommits = true
    var lastCommitDate: Date?
    var lastCommitSubject: String?
    var remoteURL: String?
    var webURL: URL?
    var error: String?
    /// The project this repo belongs to. A project is either the repo itself, an outer repo
    /// that contains it, or a plain folder holding several repos side by side.
    var projectPath: String = ""

    var id: String { path }
    var projectName: String { (projectPath as NSString).lastPathComponent }
    var isGrouped: Bool { !projectPath.isEmpty && projectPath != path }

    /// The repo's path relative to its project, used as its label inside a project group.
    var relativeName: String {
        guard isGrouped, path.hasPrefix(projectPath + "/") else { return name }
        return String(path.dropFirst(projectPath.count + 1))
    }
    var changeCount: Int { staged + modified + untracked }
    var hasRemote: Bool { remoteURL != nil }
    var isUnpublished: Bool { hasRemote && upstream == nil && hasCommits && !isDetached }

    var state: State {
        if conflicts > 0 { return .conflict }
        if changeCount > 0 { return .dirty }
        if ahead > 0 { return .unpushed }
        if isUnpublished { return .unpublished }
        if behind > 0 { return .behind }
        if stashes > 0 { return .stashed }
        return .clean
    }

    var needsAttention: Bool { state != .clean }

    var displayPath: String { (path as NSString).abbreviatingWithTildeInPath }

    var remoteHostName: String {
        guard let host = webURL?.host?.lowercased() else { return "Remote" }
        if host.contains("github") { return "GitHub" }
        if host.contains("gitlab") { return "GitLab" }
        if host.contains("bitbucket") { return "Bitbucket" }
        return host
    }

    var changeBreakdown: String {
        var parts: [String] = []
        if staged > 0 { parts.append("\(staged) staged") }
        if modified > 0 { parts.append("\(modified) modified") }
        if untracked > 0 { parts.append("\(untracked) untracked") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Scanner

enum RepoScanner {
    private static let skipNames: Set<String> = [
        "node_modules", ".build", "build", "dist", "out", "Pods", "vendor", "DerivedData", "Library",
        "Applications", "Movies", "Music", "Pictures", "target", "venv", "__pycache__", "bower_components",
        "Carthage", ".next", ".nuxt", "coverage", "tmp",
    ]

    private static let gitEnv = [
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_TERMINAL_PROMPT": "0",
        "LC_ALL": "C",
    ]

    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    /// Folders directly inside home that are never walked when home itself is a root:
    /// they are huge, or macOS shows a privacy prompt the moment we touch them.
    /// Add one explicitly in Settings to scan it.
    private static let homeSkipNames: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library", "Applications", "Movies", "Music",
        "Pictures", "Public", "Creative Cloud Files", "Dropbox", "Google Drive", "OneDrive",
    ]

    /// Extra levels we look inside a repo for nested, independent repos.
    private static let nestedDepth = 2

    enum GitMarker { case none, repo, submodule }

    /// A real repo has a `.git` folder or a `.git` file pointing at a worktree.
    /// Submodules also use a `.git` file, but they belong to their parent repo.
    static func gitMarker(at url: URL) -> GitMarker {
        let git = url.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: git.path, isDirectory: &isDir) else { return .none }
        if isDir.boolValue {
            return FileManager.default.fileExists(atPath: git.appendingPathComponent("HEAD").path) ? .repo : .none
        }
        guard let text = try? String(contentsOf: git, encoding: .utf8), text.hasPrefix("gitdir:") else { return .none }
        return text.contains("/modules/") ? .submodule : .repo
    }

    static func discover(roots: [String], maxDepth: Int) -> [String] {
        var found = Set<String>()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path

        func walk(_ url: URL, depth: Int, limit: Int) {
            if found.count >= 600 { return }
            var limit = limit
            switch gitMarker(at: url) {
            case .repo:
                found.insert(url.standardizedFileURL.path)
                // Keep looking inside: a project repo can hold other independent repos.
                limit = max(limit, depth + nestedDepth)
            case .submodule:
                return
            case .none:
                break
            }
            guard depth < limit,
                  let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
            let isHome = url.standardizedFileURL.path == home
            for child in children {
                let name = child.lastPathComponent
                guard let values = try? child.resourceValues(forKeys: Set(keys)),
                      values.isDirectory == true,
                      values.isSymbolicLink != true,
                      values.isPackage != true,
                      !skipNames.contains(name),
                      !(isHome && homeSkipNames.contains(name)) else { continue }
                walk(child, depth: depth + 1, limit: limit)
            }
        }

        for root in roots {
            let url = URL(fileURLWithPath: expand(root))
            walk(url, depth: 0, limit: maxDepth)
        }
        return found.sorted()
    }

    /// Maps each repo to its project:
    /// * a repo inside another repo belongs to the outermost one,
    /// * sibling repos in the same plain folder (not a scan root, not home) share that folder,
    /// * anything else is its own project.
    /// Folder names people use to hold many unrelated projects, never a project themselves.
    private static let containerNames: Set<String> = [
        "projects", "project", "code", "dev", "developer", "repos", "repositories", "src", "sites",
        "github", "gitlab", "workspace", "workspaces", "work", "git", "personal", "clients", "sandbox", "playground",
    ]

    static func projectPaths(for repos: [String], roots: [String]) -> [String: String] {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let rootSet = Set(roots.map { URL(fileURLWithPath: expand($0)).standardizedFileURL.path })
        let sorted = repos.sorted()

        var outer: [String: String] = [:]
        var topLevel: [String] = []
        for path in sorted {
            if let container = topLevel.first(where: { path.hasPrefix($0 + "/") }) {
                outer[path] = container
            } else {
                topLevel.append(path)
            }
        }

        var byParent: [String: [String]] = [:]
        for path in topLevel {
            byParent[(path as NSString).deletingLastPathComponent, default: []].append(path)
        }

        var result: [String: String] = [:]
        for path in topLevel {
            let parent = (path as NSString).deletingLastPathComponent
            let siblings = byParent[parent]?.count ?? 0
            let isContainer = containerNames.contains((parent as NSString).lastPathComponent.lowercased())
            let groupable = siblings >= 2 && !isContainer && !rootSet.contains(parent) && parent != home && parent != "/"
            result[path] = groupable ? parent : path
        }
        for (path, container) in outer {
            result[path] = result[container] ?? container
        }
        return result
    }

    static func statuses(for paths: [String]) -> [RepoStatus] {
        guard !paths.isEmpty else { return [] }
        let collector = StatusCollector(count: paths.count)
        DispatchQueue.concurrentPerform(iterations: paths.count) { index in
            collector.set(status(for: paths[index]), at: index)
        }
        return collector.results
    }

    static func status(for path: String) -> RepoStatus {
        let git = Shell.git
        var repo = RepoStatus(path: path, name: (path as NSString).lastPathComponent)

        var out = Shell.run(git, ["-C", path, "status", "--porcelain=v2", "--branch", "--show-stash"], env: gitEnv, timeout: 12)
        if !out.ok && out.stderr.contains("show-stash") {
            out = Shell.run(git, ["-C", path, "status", "--porcelain=v2", "--branch"], env: gitEnv, timeout: 12)
        }
        guard out.ok else {
            repo.error = out.stderr.split(separator: "\n").first.map(String.init) ?? "git status failed"
            return repo
        }

        for line in out.stdout.split(separator: "\n") {
            if line.hasPrefix("# branch.oid ") {
                repo.hasCommits = !line.hasSuffix("(initial)")
            } else if line.hasPrefix("# branch.head ") {
                let head = String(line.dropFirst("# branch.head ".count))
                repo.isDetached = head == "(detached)"
                repo.branch = head
            } else if line.hasPrefix("# branch.upstream ") {
                repo.upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                if parts.count == 2 {
                    repo.ahead = Int(parts[0].dropFirst()) ?? 0
                    repo.behind = Int(parts[1].dropFirst()) ?? 0
                }
            } else if line.hasPrefix("# stash ") {
                repo.stashes = Int(line.dropFirst("# stash ".count)) ?? 0
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") {
                let fields = line.split(separator: " ", maxSplits: 2)
                if fields.count >= 2 {
                    let xy = Array(fields[1])
                    if xy.count == 2 {
                        if xy[0] != "." { repo.staged += 1 }
                        if xy[1] != "." { repo.modified += 1 }
                    }
                }
            } else if line.hasPrefix("u ") {
                repo.conflicts += 1
            } else if line.hasPrefix("? ") {
                repo.untracked += 1
            }
        }

        if repo.hasCommits {
            let log = Shell.run(git, ["-C", path, "log", "-1", "--format=%ct%x09%s"], env: gitEnv, timeout: 6)
            if log.ok {
                let parts = log.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t", maxSplits: 1)
                if let seconds = parts.first.flatMap({ TimeInterval($0) }) {
                    repo.lastCommitDate = Date(timeIntervalSince1970: seconds)
                }
                if parts.count > 1 { repo.lastCommitSubject = String(parts[1]) }
            }
        }

        let remote = Shell.run(git, ["-C", path, "config", "--get", "remote.origin.url"], env: gitEnv, timeout: 4)
        if remote.ok {
            let url = remote.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty {
                repo.remoteURL = url
                repo.webURL = webURL(from: url)
            }
        } else {
            // No "origin", but maybe another remote exists.
            let remotes = Shell.run(git, ["-C", path, "remote"], env: gitEnv, timeout: 4)
            if let first = remotes.stdout.split(separator: "\n").first {
                let other = Shell.run(git, ["-C", path, "config", "--get", "remote.\(first).url"], env: gitEnv, timeout: 4)
                let url = other.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !url.isEmpty {
                    repo.remoteURL = url
                    repo.webURL = webURL(from: url)
                }
            }
        }
        return repo
    }

    static func webURL(from remote: String) -> URL? {
        var s = remote
        if s.hasPrefix("git@") {
            let rest = s.dropFirst(4)
            guard let colon = rest.firstIndex(of: ":") else { return nil }
            s = "https://" + String(rest[..<colon]) + "/" + String(rest[rest.index(after: colon)...])
        } else if s.hasPrefix("ssh://") {
            var rest = s.dropFirst("ssh://".count)
            if let at = rest.firstIndex(of: "@") { rest = rest[rest.index(after: at)...] }
            s = "https://" + String(rest)
            if let url = URL(string: s), let host = url.host {
                s = "https://" + host + url.path
            }
        } else if s.hasPrefix("http://") || s.hasPrefix("https://") {
            if let url = URL(string: s), let host = url.host {
                s = "https://" + host + url.path
            }
        } else {
            return nil
        }
        if s.hasSuffix(".git") { s.removeLast(4) }
        return URL(string: s)
    }

    static func fetch(_ path: String) -> Bool {
        var env = gitEnv
        env["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=8"
        return Shell.run(Shell.git, ["-C", path, "fetch", "--all", "--prune", "--quiet"], env: env, timeout: 45).ok
    }
}

private final class StatusCollector {
    private let lock = NSLock()
    private var storage: [RepoStatus?]

    init(count: Int) { storage = Array(repeating: nil, count: count) }

    func set(_ status: RepoStatus, at index: Int) {
        lock.lock()
        storage[index] = status
        lock.unlock()
    }

    var results: [RepoStatus] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap { $0 }
    }
}

// MARK: - Store

final class RepoStore: ObservableObject {
    static let shared = RepoStore()

    @Published private(set) var repos: [RepoStatus] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isFetching = false
    @Published private(set) var fetchingPaths: Set<String> = []
    @Published private(set) var lastScan: Date?
    @Published private(set) var hasScannedOnce = false

    private var discovered: [String] = []
    private var timer: Timer?
    private var pendingRediscover = false

    var attentionCount: Int { repos.filter(\.needsAttention).count }

    func start() {
        refresh(rediscover: true)
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh(rediscover: false) }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func panelOpened() {
        if let lastScan, Date().timeIntervalSince(lastScan) < 10 { return }
        refresh(rediscover: false)
    }

    func refresh(rediscover: Bool) {
        if isScanning {
            if rediscover { pendingRediscover = true }
            return
        }
        isScanning = true
        let roots = AppSettings.shared.scanRoots
        let depth = AppSettings.shared.scanDepth
        let known = discovered
        let needsDiscovery = rediscover || known.isEmpty

        DispatchQueue.global(qos: .userInitiated).async {
            let paths = needsDiscovery ? RepoScanner.discover(roots: roots, maxDepth: depth) : known.filter { FileManager.default.fileExists(atPath: $0 + "/.git") }
            var statuses = RepoScanner.statuses(for: paths)
            let projects = RepoScanner.projectPaths(for: paths, roots: roots)
            for i in statuses.indices { statuses[i].projectPath = projects[statuses[i].path] ?? statuses[i].path }
            let sorted = statuses.sorted { a, b in
                if a.state != b.state { return a.state < b.state }
                return (a.lastCommitDate ?? .distantPast) > (b.lastCommitDate ?? .distantPast)
            }
            DispatchQueue.main.async {
                self.discovered = paths
                if sorted != self.repos {
                    withAnimation(.snappy) { self.repos = sorted }
                }
                self.lastScan = Date()
                self.hasScannedOnce = true
                self.isScanning = false
                if self.pendingRediscover {
                    self.pendingRediscover = false
                    self.refresh(rediscover: true)
                }
            }
        }
    }

    func fetchAll() {
        guard !isFetching else { return }
        isFetching = true
        let paths = repos.filter(\.hasRemote).map(\.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let failed = Counter()
            DispatchQueue.concurrentPerform(iterations: paths.count) { index in
                if !RepoScanner.fetch(paths[index]) { failed.increment() }
            }
            let failures = failed.value
            DispatchQueue.main.async {
                self.isFetching = false
                if failures > 0 {
                    Toast.shared.show("Fetched, \(failures) repo\(failures == 1 ? "" : "s") couldn't reach remote", symbol: "exclamationmark.triangle.fill")
                } else {
                    Toast.shared.show("All remotes fetched", symbol: "checkmark.circle.fill")
                }
                self.refresh(rediscover: false)
            }
        }
    }

    func fetch(_ repo: RepoStatus) {
        guard !fetchingPaths.contains(repo.path) else { return }
        fetchingPaths.insert(repo.path)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = RepoScanner.fetch(repo.path)
            DispatchQueue.main.async {
                self.fetchingPaths.remove(repo.path)
                Toast.shared.show(ok ? "Fetched \(repo.name)" : "Couldn't reach the remote", symbol: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                self.refresh(rediscover: false)
            }
        }
    }
}
