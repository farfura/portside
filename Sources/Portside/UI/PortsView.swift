import SwiftUI
import AppKit

struct PortsView: View {
    @EnvironmentObject private var ports: PortStore
    @EnvironmentObject private var settings: AppSettings
    let open: (ListeningPort, DetailPanel?) -> Void
    @State private var query = ""

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A bare port number the user typed, e.g. "3000" or ":3000".
    private var searchedPort: Int? {
        let q = query.trimmingCharacters(in: .whitespaces)
        return Int(q.hasPrefix(":") ? String(q.dropFirst()) : q)
    }

    var body: some View {
        VStack(spacing: 10) {
            SearchField(text: $query, prompt: "Find by port number or project name")
                .padding(.horizontal, 18)

            ScrollView {
                if isSearching {
                    searchResults
                } else {
                    allPorts
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var searchResults: some View {
        // Search everything, system ports included, so "what is on :5000" always has an answer.
        let matches = ports.ports.filter { $0.matches(query) }
        let stopped = ports.recentlyStopped.filter { $0.port.matches(query) }

        return LazyVStack(alignment: .leading, spacing: 6) {
            if matches.isEmpty && stopped.isEmpty {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: searchedPort.map { "Port \($0) is free" } ?? "No matches",
                    message: searchedPort != nil
                        ? "Nothing is listening on a port starting with \u{201C}\(query)\u{201D}."
                        : "No running server, project or container matches \u{201C}\(query)\u{201D}.",
                    tint: searchedPort != nil ? Theme.mint : Theme.secondary
                )
                .padding(.top, 28)
                .padding(.horizontal, 12)
            } else {
                ForEach(matches) { port in
                    PortRow(port: port, open: open, compact: port.isSystem)
                        .transition(.opacity)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                if !stopped.isEmpty {
                    SectionLabel("Recently stopped")
                        .padding(.top, 18)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 6)
                    ForEach(stopped) { StoppedRow(stopped: $0) }
                }
            }
        }
        .padding(.bottom, 14)
    }

    private var allPorts: some View {
        let dev = ports.devPorts
        let system = ports.systemPorts

        return LazyVStack(alignment: .leading, spacing: 6) {
            if dev.isEmpty && ports.recentlyStopped.isEmpty {
                if ports.lastScan == nil {
                    ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
                } else {
                    EmptyState(
                        symbol: "circle.dotted",
                        title: "No servers running",
                        message: "Start one with npm run dev, docker compose up, or anything else. It shows up here on the next scan."
                    )
                    .padding(.top, 28)
                    .padding(.horizontal, 12)
                }
            } else {
                ForEach(dev) { port in
                    PortRow(port: port, open: open)
                        .transition(.opacity)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }

            if !ports.recentlyStopped.isEmpty {
                SectionLabel("Recently stopped")
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                ForEach(ports.recentlyStopped) { stopped in
                    StoppedRow(stopped: stopped)
                }
            }

            if settings.showSystemPorts && !system.isEmpty {
                SectionLabel("System and apps", trailing: "\(system.count)")
                    .padding(.top, 18)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 6)
                ForEach(system) { port in
                    PortRow(port: port, open: open, compact: true)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 14)
    }
}

struct PortRow: View {
    @EnvironmentObject private var ports: PortStore
    let port: ListeningPort
    let open: (ListeningPort, DetailPanel?) -> Void
    var compact = false
    @State private var hovering = false
    @State private var confirmKill = false

    var body: some View {
        let health = ports.health[port.port]
        let tunnel = ports.tunnels[port.port]
        let bridged = ports.bridges[port.port] != nil

        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: ":\(port.port)")
                .font(Theme.mono(compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(Theme.sail)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Theme.sail.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(port.displayName)
                        .font(Theme.text(13, .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if tunnel?.isLive == true {
                        LedgerMark("public", color: Theme.violet)
                    } else if tunnel?.status == .starting {
                        LedgerMark("sharing", color: Theme.violet)
                    }
                    if bridged {
                        LedgerMark("phone", color: Theme.sky)
                    }
                }
                HStack(spacing: 0) {
                    Text(port.tech.name)
                        .foregroundStyle(Theme.sky)
                    Text("  ·  ")
                        .foregroundStyle(Theme.tertiary)
                    Text(verbatim: "pid \(port.pid)")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.tertiary)
                    if port.isLANReachable {
                        Text("  ·  lan")
                            .foregroundStyle(Theme.mint)
                    }
                }
                .font(Theme.text(11))
                .lineLimit(1)
            }

            Spacer(minLength: 6)

            if hovering && !compact {
                HStack(spacing: 0) {
                    IconButton(symbol: "safari.fill", image: BrowserIcon.image, help: "Open in browser", size: 26) {
                        ExternalApps.openURL(port.localURL)
                    }
                    IconButton(symbol: "qrcode", tint: Theme.mint, secondaryTint: Theme.sail, help: "Open on your phone", size: 26) {
                        ports.enablePhoneAccess(for: port)
                        open(port, .phone)
                    }
                    IconButton(symbol: "globe.americas.fill", multicolor: true, help: "Share publicly", size: 26) {
                        ports.share(port)
                        open(port, .share)
                    }
                    IconButton(
                        symbol: confirmKill ? "exclamationmark.triangle.fill" : "xmark.circle.fill",
                        tint: Theme.coral,
                        secondaryTint: Theme.coral.opacity(0.45),
                        help: confirmKill ? "Click again to stop it" : "Stop this process",
                        size: 26
                    ) {
                        if confirmKill {
                            ports.terminate(port)
                            confirmKill = false
                        } else {
                            withAnimation(.snappy) { confirmKill = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { confirmKill = false } }
                        }
                    }
                }
                .transition(.opacity)
            } else if let health, !compact {
                Text(health.shortLabel)
                    .font(Theme.mono(10, weight: .semibold))
                    .foregroundStyle(health.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(health.color.opacity(0.16))
                    .clipShape(Capsule())
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 7 : 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture { open(port, nil) }
        .onHover { value in
            withAnimation(.easeOut(duration: 0.14)) { hovering = value }
            if !value { confirmKill = false }
        }
    }
}

struct StoppedRow: View {
    @EnvironmentObject private var ports: PortStore
    let stopped: StoppedPort
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: ":\(stopped.port.port)")
                .font(Theme.mono(12, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .strikethrough(true, color: Theme.coral.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Theme.coral.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(stopped.port.displayName)
                    .font(Theme.text(13))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                (Text("Stopped ") + Text(stopped.stoppedAt, style: .relative) + Text(" ago"))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if hovering {
                if let root = stopped.port.projectRoot {
                    IconButton(symbol: "terminal", tint: Theme.text, help: "Open the project in your terminal", size: 24) {
                        ExternalApps.open(path: root, with: AppSettings.shared.terminalBundleID)
                    }
                }
                IconButton(symbol: "xmark", tint: Theme.secondary, help: "Dismiss", size: 24) {
                    ports.dismissStopped(stopped)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
        )
        .padding(.horizontal, 12)
        .onHover { hovering = $0 }
    }
}

private struct LedgerMark: View {
    let text: String
    var color: Color = Theme.secondary
    init(_ text: String, color: Color = Theme.secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.text(9, .medium))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1).fill(Theme.surfaceHover).frame(width: 52, height: 12)
            RoundedRectangle(cornerRadius: 1).fill(Theme.stroke).frame(width: 1, height: 28)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 1).fill(Theme.surfaceHover).frame(width: 120, height: 10)
                RoundedRectangle(cornerRadius: 1).fill(Theme.surface).frame(width: 80, height: 8)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .shimmer()
    }
}
