import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var scanRoots: [String] {
        didSet {
            defaults.set(scanRoots, forKey: "scanRoots")
            RepoStore.shared.refresh(rediscover: true)
        }
    }
    @Published var scanDepth: Int {
        didSet {
            defaults.set(scanDepth, forKey: "scanDepth")
            RepoStore.shared.refresh(rediscover: true)
        }
    }
    @Published var editorBundleID: String { didSet { defaults.set(editorBundleID, forKey: "editor") } }
    @Published var terminalBundleID: String { didSet { defaults.set(terminalBundleID, forKey: "terminal") } }
    @Published var showSystemPorts: Bool { didSet { defaults.set(showSystemPorts, forKey: "showSystemPorts") } }
    @Published var showCountInMenuBar: Bool { didSet { defaults.set(showCountInMenuBar, forKey: "showCountInMenuBar") } }
    @Published var appearance: Appearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    /// Nil follows the Mac. Light and dark pin the panel.
    var preferredScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var resolvedScheme: ColorScheme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? .dark : .light
        }
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private var themeObserver: NSObjectProtocol?

    init() {
        scanRoots = defaults.stringArray(forKey: "scanRoots") ?? AppSettings.defaultRoots()
        let depth = defaults.integer(forKey: "scanDepth")
        scanDepth = depth == 0 ? 3 : depth
        editorBundleID = defaults.string(forKey: "editor") ?? (ExternalApps.editors.first { ExternalApps.isInstalled($0.bundleID) }?.bundleID ?? "com.apple.TextEdit")
        terminalBundleID = defaults.string(forKey: "terminal") ?? (ExternalApps.terminals.first { ExternalApps.isInstalled($0.bundleID) }?.bundleID ?? "com.apple.Terminal")
        showSystemPorts = defaults.bool(forKey: "showSystemPorts")
        showCountInMenuBar = defaults.object(forKey: "showCountInMenuBar") as? Bool ?? true
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .light
    }

    func startObservingSystemTheme() {
        guard themeObserver == nil else { return }
        themeObserver = DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.appearance == .system else { return }
            self.objectWillChange.send()
        }
    }

    /// Common code folders inside home. Desktop and Documents are left out on purpose,
    /// because touching them triggers a macOS privacy prompt on first launch.
    static func defaultRoots() -> [String] {
        let wanted: Set<String> = ["developer", "projects", "code", "dev", "src", "repos", "sites", "github", "workspace", "work", "git", "personal"]
        let home = NSHomeDirectory()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        return names
            .filter { wanted.contains($0.lowercased()) }
            .sorted()
            .map { "~/" + $0 }
    }

    var editor: ExternalApp? { ExternalApps.app(for: editorBundleID) }
    var terminal: ExternalApp? { ExternalApps.app(for: terminalBundleID) }
}

// MARK: - External apps

struct ExternalApp: Identifiable, Hashable {
    let name: String
    let bundleID: String
    var id: String { bundleID }
}

enum ExternalApps {
    static let editors: [ExternalApp] = [
        ExternalApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        ExternalApp(name: "VS Code", bundleID: "com.microsoft.VSCode"),
        ExternalApp(name: "Windsurf", bundleID: "com.exafunction.windsurf"),
        ExternalApp(name: "Zed", bundleID: "dev.zed.Zed"),
        ExternalApp(name: "Xcode", bundleID: "com.apple.dt.Xcode"),
        ExternalApp(name: "Sublime Text", bundleID: "com.sublimetext.4"),
        ExternalApp(name: "WebStorm", bundleID: "com.jetbrains.WebStorm"),
        ExternalApp(name: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij"),
        ExternalApp(name: "Nova", bundleID: "com.panic.Nova"),
        ExternalApp(name: "VS Code Insiders", bundleID: "com.microsoft.VSCodeInsiders"),
    ]

    static let terminals: [ExternalApp] = [
        ExternalApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        ExternalApp(name: "iTerm", bundleID: "com.googlecode.iterm2"),
        ExternalApp(name: "Warp", bundleID: "dev.warp.Warp-Stable"),
        ExternalApp(name: "WezTerm", bundleID: "com.github.wez.wezterm"),
        ExternalApp(name: "Terminal", bundleID: "com.apple.Terminal"),
    ]

    private static var iconCache: [String: NSImage] = [:]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func isInstalled(_ bundleID: String) -> Bool { url(for: bundleID) != nil }

    static func app(for bundleID: String) -> ExternalApp? {
        (editors + terminals).first { $0.bundleID == bundleID }
    }

    static var installedEditors: [ExternalApp] { editors.filter { isInstalled($0.bundleID) } }
    static var installedTerminals: [ExternalApp] { terminals.filter { isInstalled($0.bundleID) } }

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = url(for: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 64, height: 64)
        iconCache[bundleID] = image
        return image
    }

    static func open(path: String, with bundleID: String) {
        let folder = URL(fileURLWithPath: path)
        guard let appURL = url(for: bundleID) else {
            NSWorkspace.shared.open(folder)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: configuration) { _, error in
            if error != nil {
                DispatchQueue.main.async { Toast.shared.show("Couldn't open that app", symbol: "exclamationmark.triangle.fill") }
            }
        }
    }

    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    static func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Clipboard and toasts

enum Clipboard {
    static func copy(_ text: String, toast: String = "Copied") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.shared.show(toast, symbol: "doc.on.doc.fill")
    }
}

final class Toast: ObservableObject {
    static let shared = Toast()

    struct Message: Equatable {
        let id = UUID()
        let text: String
        let symbol: String
    }

    @Published private(set) var message: Message?
    private var dismissWork: DispatchWorkItem?

    func show(_ text: String, symbol: String = "checkmark.circle.fill") {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            message = Message(text: text, symbol: symbol)
        }
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) { self?.message = nil }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }
}

// MARK: - QR codes

enum QRCode {
    private static let context = CIContext()
    private static var cache: [String: NSImage] = [:]

    static func image(for text: String) -> NSImage? {
        if let cached = cache[text] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = max(1, floor(600 / output.extent.width))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
        cache[text] = image
        return image
    }
}

// MARK: - Formatting

enum Format {
    static func ago(_ date: Date?) -> String {
        guard let date else { return "" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        if seconds < 86_400 * 14 { return "\(seconds / 86_400)d" }
        if seconds < 86_400 * 60 { return "\(seconds / (86_400 * 7))w" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval else { return "" }
        let ms = interval * 1000
        if ms < 1000 { return "\(Int(ms.rounded()))ms" }
        return String(format: "%.2fs", interval)
    }

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func plural(_ count: Int, _ word: String) -> String {
        "\(count) \(word)\(count == 1 ? "" : "s")"
    }
}
