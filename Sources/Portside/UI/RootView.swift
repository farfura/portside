import SwiftUI
import AppKit

enum AppTab: String {
    case ports, repos
}

enum DetailPanel: Equatable {
    case phone, share
}

enum Route: Equatable {
    case home
    case port(Int, DetailPanel?)
    case settings
}

struct RootView: View {
    @EnvironmentObject private var ports: PortStore
    @EnvironmentObject private var repos: RepoStore
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var toast = Toast.shared
    @State private var tab: AppTab = .ports
    @State private var route: Route = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Backdrop()

            Group {
                switch route {
                case .home:
                    HomeView(
                        tab: $tab,
                        openPort: { port, panel in go(.port(port.port, panel)) },
                        openSettings: { go(.settings) }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                case .port(let number, let panel):
                    PortDetailView(portNumber: number, initialPanel: panel, back: { go(.home) })
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                case .settings:
                    SettingsView(back: { go(.home) })
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let message = toast.message {
                ToastView(message: message)
                    .padding(.bottom, 46)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(message.id)
            }
        }
        .frame(width: 440, height: 640)
        .clipped()
        .font(Theme.text(13))
        .environment(\.colorScheme, settings.resolvedScheme)
        .preferredColorScheme(settings.preferredScheme)
        .onAppear {
            ports.setPanelVisible(true)
            repos.panelOpened()
        }
        .onDisappear { ports.setPanelVisible(false) }
        .onExitCommand { if route != .home { go(.home) } }
    }

    private func go(_ next: Route) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { route = next }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var ports: PortStore
    @EnvironmentObject private var repos: RepoStore
    @Binding var tab: AppTab
    let openPort: (ListeningPort, DetailPanel?) -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(openSettings: openSettings)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Theme.brand
                .frame(height: 3)

            TabSwitcher(tab: $tab, portCount: ports.devPorts.count, repoCount: repos.attentionCount)

            ZStack {
                if tab == .ports {
                    PortsView(open: openPort)
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    ReposView(openSettings: openSettings)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()

            FooterView(tab: tab)
        }
    }
}

struct AppLogo: View {
    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.223, style: .continuous))
    }

    private static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return NSApp.applicationIconImage
    }()
}

struct HeaderView: View {
    @EnvironmentObject private var ports: PortStore
    @EnvironmentObject private var repos: RepoStore
    @EnvironmentObject private var settings: AppSettings
    let openSettings: () -> Void
    @State private var spin: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AppLogo(size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Portside")
                    .font(Theme.text(17, .medium))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: subtitle)
            }
            Spacer(minLength: 8)
            IconButton(
                symbol: settings.resolvedScheme == .dark ? "sun.max" : "moon",
                help: settings.resolvedScheme == .dark ? "Use light appearance" : "Use dark appearance"
            ) {
                settings.appearance = settings.resolvedScheme == .dark ? .light : .dark
            }
            IconButton(symbol: "arrow.clockwise", help: "Refresh  ⌘R", rotation: spin) {
                withAnimation(.easeInOut(duration: 0.7)) { spin += 360 }
                ports.refresh(probe: true)
                repos.refresh(rediscover: true)
            }
            .keyboardShortcut("r", modifiers: .command)
            IconButton(symbol: "gearshape", help: "Settings  ⌘,") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
    }

    private var subtitle: String {
        let live = ports.devPorts.count
        let attention = repos.attentionCount
        let portText = live == 0 ? "No servers running" : Format.plural(live, "server") + " live"
        let repoText = attention == 0 ? "repos all clear" : Format.plural(attention, "repo") + " need you"
        return portText + "  ·  " + repoText
    }
}

struct TabSwitcher: View {
    @Binding var tab: AppTab
    let portCount: Int
    let repoCount: Int

    var body: some View {
        HStack(spacing: 4) {
            segment(.ports, title: "Ports", count: portCount)
            segment(.repos, title: "Repos", count: repoCount)
        }
        .padding(3)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func segment(_ value: AppTab, title: String, count: Int) -> some View {
        let selected = tab == value
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { tab = value }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.text(13, .medium))
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(Theme.mono(11, weight: .semibold))
                        .foregroundStyle(selected ? Theme.onSail.opacity(0.85) : Theme.sail)
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(selected ? Theme.onSail : Theme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.sail : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FooterView: View {
    @EnvironmentObject private var ports: PortStore
    @EnvironmentObject private var repos: RepoStore
    let tab: AppTab

    var body: some View {
        HStack(spacing: 10) {
            if let date = tab == .ports ? ports.lastScan : repos.lastScan {
                (Text("Updated ") + Text(date, style: .relative) + Text(" ago"))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.tertiary)
            } else {
                Text("Scanning").font(Theme.text(11)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if let ip = ports.lanIP {
                Text(verbatim: ip)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.sail)
                    .help("This Mac on your local network")
            }
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(Theme.text(11, .medium))
                .foregroundStyle(Theme.secondary)
                .help("Quit Portside")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .top)
    }
}
