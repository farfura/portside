import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var ports: PortStore
    let back: () -> Void
    @State private var loginItemTick = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: back) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                        Text("Back").font(.system(size: 12, weight: .regular))
                    }
                    .foregroundStyle(Theme.secondary)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                Spacer()
                Text("SETTINGS")
                    .font(Theme.text(11, .medium))
                    .tracking(1.6)
                    .foregroundStyle(Theme.text)
                Spacer()
                Color.clear.frame(width: 60, height: 28)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(Rectangle().fill(Theme.stroke).frame(height: 1), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    repoSection
                    appsSection
                    portsSection
                    sharingSection
                    generalSection
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Sections

    private var repoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Repo Radar folders")
            VStack(spacing: 0) {
                if settings.scanRoots.isEmpty {
                    Text("No folders yet. Add the places where your projects live.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                ForEach(Array(settings.scanRoots.enumerated()), id: \.element) { index, root in
                    if index > 0 { Divider().overlay(Theme.stroke) }
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(Theme.amber)
                        Text(root).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        IconButton(symbol: "minus", tint: Theme.coral, help: "Stop scanning this folder", size: 22, filled: false) {
                            settings.scanRoots.removeAll { $0 == root }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
            .card()

            HStack {
                PillButton(title: "Add folder", symbol: "plus", tint: Theme.amber) { FolderPicker.addFolders() }
                Spacer()
                Text("Depth").font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                Stepper(value: $settings.scanDepth, in: 1...6) {
                    Text(verbatim: "\(settings.scanDepth)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(width: 18)
                }
                .help("How many folder levels below each root to search for repos")
            }
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Open projects with")
            VStack(spacing: 0) {
                AppPickerRow(label: "Editor", selection: $settings.editorBundleID, options: ExternalApps.installedEditors)
                Divider().overlay(Theme.stroke)
                AppPickerRow(label: "Terminal", selection: $settings.terminalBundleID, options: ExternalApps.installedTerminals)
            }
            .card()
        }
    }

    private var portsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Ports")
            VStack(spacing: 0) {
                ToggleRow(title: "Show system and app ports", subtitle: "AirPlay, Spotify, editor helpers and friends", isOn: $settings.showSystemPorts)
                Divider().overlay(Theme.stroke)
                ToggleRow(title: "Server count in menu bar", subtitle: "Shows how many dev servers are live", isOn: $settings.showCountInMenuBar)
            }
            .card()
        }
    }

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Public sharing")
            VStack(alignment: .leading, spacing: 10) {
                if let path = ports.cloudflaredPath {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.mint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("cloudflared is ready").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                            Text(path).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.tertiary)
                        }
                    }
                } else {
                    InstallCloudflaredView()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("General")
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Appearance").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("Paper, night, or match the Mac")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                    Spacer(minLength: 8)
                    AppearancePicker(selection: $settings.appearance)
                }
                .padding(12)
                Divider().overlay(Theme.stroke)
                ToggleRow(
                    title: "Launch at login",
                    subtitle: "Keep Portside in your menu bar",
                    isOn: Binding(
                        get: { _ = loginItemTick; return SMAppService.mainApp.status == .enabled },
                        set: { enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                Toast.shared.show("Move Portside to Applications first", symbol: "exclamationmark.triangle.fill")
                            }
                            loginItemTick.toggle()
                        }
                    )
                )
                Divider().overlay(Theme.stroke)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Portside").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    PillButton(title: "Quit", symbol: "power", tint: Theme.coral) { NSApp.terminate(nil) }
                }
                .padding(12)
            }
            .card()
        }
    }
}

struct AppearancePicker: View {
    @Binding var selection: AppSettings.Appearance

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppSettings.Appearance.allCases) { mode in
                let selected = selection == mode
                Button {
                    selection = mode
                } label: {
                    Text(mode.title)
                        .font(Theme.text(11, .medium))
                        .foregroundStyle(selected ? Theme.onSail : Theme.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(selected ? Theme.sail : Color.clear)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Theme.strokeStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.mint)
        }
        .padding(12)
    }
}

struct AppPickerRow: View {
    let label: String
    @Binding var selection: String
    let options: [ExternalApp]

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Menu {
                ForEach(options) { app in
                    Button {
                        selection = app.bundleID
                    } label: {
                        if let icon = ExternalApps.icon(for: app.bundleID) {
                            Label { Text(app.name) } icon: { Image(nsImage: resized(icon)) }
                        } else {
                            Text(app.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    if let icon = ExternalApps.icon(for: selection) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                    }
                    Text(ExternalApps.app(for: selection)?.name ?? "Choose")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Theme.strokeStrong, lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}
