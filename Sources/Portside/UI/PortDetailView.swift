import SwiftUI
import AppKit

struct PortDetailView: View {
    @EnvironmentObject private var ports: PortStore
    @EnvironmentObject private var settings: AppSettings
    let portNumber: Int
    let back: () -> Void
    @State private var panel: DetailPanel?
    @State private var confirmKill = false

    init(portNumber: Int, initialPanel: DetailPanel?, back: @escaping () -> Void) {
        self.portNumber = portNumber
        self.back = back
        _panel = State(initialValue: initialPanel)
    }

    private var port: ListeningPort? {
        ports.ports.first { $0.port == portNumber && !$0.isSystem } ?? ports.ports.first { $0.port == portNumber }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let port {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        hero(port)
                        actionGrid(port)
                        if panel == .phone {
                            PhonePanel(port: port)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if panel == .share {
                            SharePanel(port: port)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        infoCard(port)
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
                EmptyState(
                    symbol: "moon.zzz.fill",
                    title: "Port \(portNumber) went quiet",
                    message: "The process listening here has stopped. If you restart it on the same port, this page comes back to life.",
                    tint: Theme.coral
                )
                Spacer()
            }
        }
        .onAppear { ports.probeHealth(force: true) }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                    Text("Ports").font(.system(size: 12, weight: .regular))
                }
                .foregroundStyle(Theme.secondary)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .keyboardShortcut("[", modifiers: .command)

            Spacer()

            if let port {
                if let root = port.projectRoot {
                    AppIconButton(bundleID: settings.editorBundleID, help: "Open \(port.projectName ?? "project") in \(settings.editor?.name ?? "editor")") {
                        ExternalApps.open(path: root, with: settings.editorBundleID)
                    }
                    AppIconButton(bundleID: settings.terminalBundleID, help: "Open in \(settings.terminal?.name ?? "terminal")") {
                        ExternalApps.open(path: root, with: settings.terminalBundleID)
                    }
                    IconButton(symbol: "folder", help: "Reveal in Finder") { ExternalApps.reveal(root) }
                }
                PillButton(
                    title: confirmKill ? "Really stop?" : "Stop",
                    symbol: confirmKill ? "exclamationmark.triangle.fill" : "stop.fill",
                    tint: Theme.coral
                ) {
                    if confirmKill {
                        ports.terminate(port)
                        confirmKill = false
                    } else {
                        withAnimation(.snappy) { confirmKill = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { withAnimation { confirmKill = false } }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .bottom)
    }

    // MARK: Hero

    private func hero(_ port: ListeningPort) -> some View {
        let health = ports.health[port.port]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(verbatim: ":\(port.port)")
                    .font(Theme.mono(34, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let health {
                    Text(health.longLabel)
                        .font(Theme.text(12))
                        .foregroundStyle(health.color)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(port.displayName)
                    .font(Theme.text(15, .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(port.tech.name + "  ·  pid " + String(port.pid))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: Actions

    private func actionGrid(_ port: ListeningPort) -> some View {
        let tunnel = ports.tunnels[port.port]
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ActionTile(symbol: "safari.fill", image: BrowserIcon.image, title: "Open in browser", subtitle: port.localURLString, tint: Theme.sky) {
                ExternalApps.openURL(port.localURL)
            }
            ActionTile(symbol: "link", title: "Copy local URL", subtitle: "Paste it anywhere", tint: Theme.sail, secondary: Theme.sky) {
                Clipboard.copy(port.localURLString, toast: "Local URL copied")
            }
            ActionTile(
                symbol: "iphone.gen3",
                title: "Open on phone",
                subtitle: ports.bridges[port.port] != nil || port.isLANReachable ? "Scan the QR code" : "Same WiFi, one scan",
                tint: Theme.mint,
                secondary: Theme.sail,
                active: panel == .phone
            ) {
                togglePanel(.phone)
                if panel == .phone { ports.enablePhoneAccess(for: port) }
            }
            ActionTile(
                symbol: "globe.americas.fill",
                multicolor: true,
                title: tunnel?.isLive == true ? "Shared publicly" : "Share publicly",
                subtitle: tunnel?.isLive == true ? "Live HTTPS link" : "HTTPS link + inspector",
                tint: Theme.violet,
                active: panel == .share || tunnel?.isLive == true
            ) {
                togglePanel(.share)
            }
        }
    }

    private func togglePanel(_ value: DetailPanel) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            panel = panel == value ? nil : value
        }
    }

    // MARK: Info

    private func infoCard(_ port: ListeningPort) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoRow(label: "Command", value: port.commandLine, mono: true, lines: 3) {
                Clipboard.copy(port.commandLine, toast: "Command copied")
            }
            Divider().overlay(Theme.stroke)
            if let root = port.projectRoot {
                InfoRow(label: "Project", value: (root as NSString).abbreviatingWithTildeInPath, mono: true, lines: 2) {
                    Clipboard.copy(root, toast: "Path copied")
                }
                Divider().overlay(Theme.stroke)
            }
            InfoRow(label: "Listening on", value: port.bindingDescription, mono: false, lines: 2, copy: nil)
            if !port.isLANReachable {
                Divider().overlay(Theme.stroke)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.tertiary).padding(.top, 2)
                    Text("This server only accepts connections from this Mac. Portside can relay it to your phone without changing its config.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
            }
        }
        .card()
    }
}

// MARK: - Building blocks

struct ActionTile: View {
    let symbol: String
    var image: NSImage? = nil
    var multicolor = false
    let title: String
    let subtitle: String
    let tint: Color
    var secondary: Color? = nil
    var active = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                tileIcon
                Text(title)
                    .font(Theme.text(13, .medium))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active || hovering ? Theme.surfaceHover : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active ? tint : Theme.strokeStrong, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { value in withAnimation(.easeOut(duration: 0.12)) { hovering = value } }
    }

    @ViewBuilder
    private var tileIcon: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
        } else if multicolor {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 20))
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, secondary ?? tint.opacity(0.45))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 22, height: 22)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false
    var lines = 1
    var copy: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: mono ? .monospaced : .default))
                .foregroundStyle(Theme.secondary)
                .lineLimit(lines)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let copy {
                Button(action: copy) {
                    Image(systemName: "doc.on.doc").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help("Copy")
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

// MARK: - Phone panel

struct PhonePanel: View {
    @EnvironmentObject private var ports: PortStore
    let port: ListeningPort

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Open on your phone", systemImage: "iphone.gen3")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                if ports.bridges[port.port] != nil {
                    Button("Stop relay") { ports.disablePhoneAccess(for: port.port) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
            }

            if ports.lanIP == nil {
                HStack(spacing: 10) {
                    Image(systemName: "wifi.slash").font(.system(size: 16)).foregroundStyle(Theme.amber)
                    Text("Connect this Mac to WiFi or Ethernet so your phone can reach it.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                }
            } else if let url = ports.phoneURL(for: port) {
                HStack(alignment: .center, spacing: 16) {
                    QRImage(text: url)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan with your camera")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(url)
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.mint)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            PillButton(title: "Copy", symbol: "doc.on.doc", tint: Theme.text) {
                                Clipboard.copy(url, toast: "Phone URL copied")
                            }
                        }
                        Text(port.isLANReachable
                             ? "Your phone needs to be on the same network."
                             : "Relayed by Portside, since this server only listens on localhost. Same network required.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if let bridge = ports.bridges[port.port] {
                BridgeStatusView(bridge: bridge)
            } else {
                PillButton(title: "Start relay", symbol: "dot.radiowaves.left.and.right", tint: Theme.mint, prominent: true) {
                    ports.enablePhoneAccess(for: port)
                }
            }
        }
        .padding(14)
        .card(tint: Theme.mint)
    }
}

struct BridgeStatusView: View {
    @ObservedObject var bridge: LANBridge

    var body: some View {
        switch bridge.state {
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Opening a relay on your network").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
        case .ready:
            Text("Relay ready").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        case .failed(let message):
            Text("Couldn't open a relay: \(message)").font(.system(size: 11.5)).foregroundStyle(Theme.coral)
        }
    }
}

struct QRImage: View {
    let text: String
    var size: CGFloat = 132

    var body: some View {
        Group {
            if let image = QRCode.image(for: text) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: size - 16, height: size - 16)
            } else {
                Image(systemName: "qrcode").font(.system(size: 40)).foregroundStyle(.black)
            }
        }
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.white))
    }
}

// MARK: - Share panel

struct SharePanel: View {
    @EnvironmentObject private var ports: PortStore
    let port: ListeningPort

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Share publicly", systemImage: "globe")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.text)

            if ports.cloudflaredPath == nil {
                InstallCloudflaredView()
            } else if let session = ports.tunnels[port.port] {
                TunnelCard(session: session, port: port)
            } else {
                Text("Get a temporary HTTPS link for :\(String(port.port)) through a free Cloudflare quick tunnel. Every request is recorded so you can inspect and replay webhooks.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: "Create public link", symbol: "bolt.fill", tint: Theme.violet, prominent: true) {
                    ports.share(port)
                }
            }
        }
        .padding(14)
        .card(tint: Theme.violet)
    }
}

struct TunnelCard: View {
    @EnvironmentObject private var ports: PortStore
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var session: TunnelSession
    let port: ListeningPort
    @State private var showQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch session.status {
            case .starting:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Opening a tunnel through Cloudflare").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("Usually takes 3 to 8 seconds").font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .card(radius: 10)
                .shimmer()

            case .live(let url):
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("LIVE")
                            .font(Theme.text(10, .medium))
                            .tracking(1.1)
                            .foregroundStyle(Theme.violet)
                        Spacer()
                        (Text("since ") + Text(session.startedAt, style: .time))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                    Text(url.absoluteString)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        PillButton(title: "Copy link", symbol: "doc.on.doc", tint: Theme.violet, prominent: true) {
                            Clipboard.copy(url.absoluteString, toast: "Public link copied")
                        }
                        PillButton(title: "Open", symbol: "arrow.up.right", tint: Theme.text) { ExternalApps.openURL(url) }
                        IconButton(symbol: "qrcode", tint: Theme.text, help: "Show QR code", size: 30) {
                            withAnimation(.snappy) { showQR.toggle() }
                        }
                    }
                    if showQR {
                        HStack {
                            Spacer()
                            QRImage(text: url.absoluteString, size: 150)
                            Spacer()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    Text("New links can take a few seconds before they resolve everywhere.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .padding(12)
                .card(radius: 10)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Couldn't open the tunnel", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                    Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    PillButton(title: "Try again", symbol: "arrow.clockwise", tint: Theme.violet, prominent: true) { ports.share(port) }
                }
                .padding(12)
                .card(radius: 10)

            case .stopped:
                HStack {
                    Text("Sharing stopped").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondary)
                    Spacer()
                    PillButton(title: "Share again", symbol: "globe", tint: Theme.violet, prominent: true) { ports.share(port) }
                }
            }

            trafficPreview

            HStack(spacing: 6) {
                PillButton(title: "Traffic Inspector", symbol: "waveform.path.ecg", tint: Theme.text) {
                    ports.inspectorPort = port.port
                    openWindow(id: "traffic")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                if session.isActive {
                    PillButton(title: "Stop sharing", symbol: "stop.fill", tint: Theme.coral) {
                        ports.stopSharing(port.port)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trafficPreview: some View {
        if !session.entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Recent requests", trailing: String(session.entries.count))
                ForEach(session.entries.prefix(4)) { entry in
                    MiniTrafficRow(entry: entry)
                }
            }
        } else if session.isLive {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.tertiary)
                Text("Waiting for the first request").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            .padding(.vertical, 2)
        }
    }
}

struct MiniTrafficRow: View {
    let entry: TrafficEntry

    var body: some View {
        HStack(spacing: 8) {
            Text(entry.method)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.methodColor(entry.method))
                .frame(width: 44, alignment: .leading)
            Text(entry.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if entry.isPending {
                ProgressView().controlSize(.mini)
            } else if let status = entry.status {
                Text(String(status))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.statusColor(status))
            } else {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Theme.coral)
            }
            Text(Format.duration(entry.duration))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surface)
    }
}

struct InstallCloudflaredView: View {
    @EnvironmentObject private var ports: PortStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Public links use cloudflared, Cloudflare's free tunnel client. No account needed.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if ports.brewPath != nil {
                HStack(spacing: 8) {
                    PillButton(
                        title: ports.isInstallingCloudflared ? "Installing with Homebrew" : "Install cloudflared",
                        symbol: "arrow.down.circle.fill",
                        tint: Theme.violet,
                        prominent: true,
                        isLoading: ports.isInstallingCloudflared
                    ) {
                        ports.installCloudflared()
                    }
                    PillButton(title: "Check again", symbol: "arrow.clockwise", tint: Theme.text) { ports.rescanTools() }
                }
            } else {
                HStack(spacing: 8) {
                    PillButton(title: "Copy install command", symbol: "doc.on.doc", tint: Theme.violet, prominent: true) {
                        Clipboard.copy("brew install cloudflared", toast: "Command copied")
                    }
                    PillButton(title: "Download page", symbol: "arrow.up.right", tint: Theme.text) {
                        if let url = URL(string: "https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/") {
                            ExternalApps.openURL(url)
                        }
                    }
                }
            }
            if let error = ports.installError {
                Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.coral)
            }
        }
    }
}
