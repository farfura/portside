import Foundation

/// Small, dependable wrapper around Process for running CLI tools (lsof, ps, git, docker, brew).
enum Shell {
    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
    }

    /// GUI apps launched from Finder get a minimal PATH, so we add the usual developer locations.
    static let searchPath: [String] = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin",
        "/usr/local/bin", "/usr/local/sbin",
        "/usr/bin", "/bin", "/usr/sbin", "/sbin",
    ]

    static var pathEnv: String {
        var seen = Set<String>()
        var parts: [String] = []
        let existing = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for p in searchPath + existing where !p.isEmpty && !seen.contains(p) {
            seen.insert(p)
            parts.append(p)
        }
        return parts.joined(separator: ":")
    }

    static func which(_ name: String) -> String? {
        let home = NSHomeDirectory()
        let extra = [home + "/.local/bin", home + "/bin", home + "/.docker/bin", "/Applications/Docker.app/Contents/Resources/bin"]
        for dir in searchPath + extra {
            let candidate = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static var git: String { which("git") ?? "/usr/bin/git" }

    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: String? = nil,
        env: [String: String] = [:],
        timeout: TimeInterval = 15
    ) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = pathEnv
        for (key, value) in env { environment[key] = value }
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return Output(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        // Drain stderr concurrently so a chatty process can never deadlock on a full pipe.
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let killer = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: killer)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        killer.cancel()

        return Output(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self)
        )
    }
}

/// Reference holder so background closures never mutate captured local variables.
final class DataBox {
    var data = Data()
}

final class Counter {
    private let lock = NSLock()
    private(set) var value = 0
    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}
