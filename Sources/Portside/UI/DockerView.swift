import SwiftUI
import AppKit

struct DockerView: View {
    @EnvironmentObject private var docker: DockerStore
    @State private var query = ""
    @State private var onlyRunning = true
    @State private var expanded: String?

    private var filtered: [DockerContainer] {
        docker.containers.filter { container in
            (!onlyRunning || container.isRunning || !query.isEmpty) && container.matches(query)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                SearchField(text: $query, prompt: "Search containers, images or ports")
                FilterToggle(
                    onlyAttention: $onlyRunning,
                    count: docker.running.count,
                    onLabel: "Running",
                    offLabel: "All",
                    onHelp: "Showing running containers",
                    offHelp: "Showing every container, stopped ones too"
                )
            }
            .padding(.horizontal, 18)

            if docker.availability == .ready && !docker.containers.isEmpty {
                DockerSummary(containers: docker.containers)
                    .padding(.horizontal, 18)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    content
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch docker.availability {
        case .unknown:
            ForEach(0..<3, id: \.self) { _ in SkeletonRow() }
        case .notInstalled:
            EmptyState(
                symbol: "shippingbox",
                title: "Docker isn't installed",
                message: "Install Docker Desktop, OrbStack or Colima and your containers show up here.",
                tint: Theme.sky
            )
            .padding(.top, 24)
        case .daemonDown:
            VStack(alignment: .leading, spacing: 16) {
                EmptyState(
                    symbol: "shippingbox",
                    title: "Docker isn't running",
                    message: "The Docker CLI is here but the engine isn't answering. Start it and containers appear within a few seconds.",
                    tint: Theme.sky
                )
                if let app = docker.engineAppName {
                    PillButton(title: "Start \(app)", symbol: "play.fill", tint: Theme.sky, prominent: true) {
                        docker.launchEngine()
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.top, 24)
        case .ready:
            if docker.containers.isEmpty {
                EmptyState(
                    symbol: "shippingbox",
                    title: "No containers",
                    message: "Run docker compose up or docker run and they show up here.",
                    tint: Theme.sky
                )
                .padding(.top, 24)
            } else if filtered.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    EmptyState(
                        symbol: "magnifyingglass",
                        title: query.isEmpty ? "Nothing running" : "No matches",
                        message: query.isEmpty
                            ? "\(Format.plural(docker.containers.count, "container")) exist, none are running."
                            : "No container, image or port matches \u{201C}\(query)\u{201D}.",
                        tint: Theme.sky
                    )
                    if query.isEmpty {
                        PillButton(title: "Show stopped containers", symbol: "list.bullet", tint: Theme.text) {
                            withAnimation(.snappy) { onlyRunning = false }
                        }
                        .padding(.horizontal, 6)
                    }
                }
                .padding(.top, 24)
            } else {
                ForEach(DockerStore.groups(filtered)) { group in
                    DockerGroupHeader(group: group)
                        .padding(.top, 8)
                        .padding(.horizontal, 6)
                    ForEach(group.containers) { container in
                        ContainerRow(container: container, expanded: expanded == container.id) {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                expanded = expanded == container.id ? nil : container.id
                            }
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
    }
}

struct DockerSummary: View {
    let containers: [DockerContainer]

    var body: some View {
        let running = containers.filter(\.isRunning).count
        let stopped = containers.filter { $0.state == "exited" || $0.state == "created" || $0.state == "dead" }.count
        let projects = Set(containers.compactMap(\.composeProject)).count
        let published = Set(containers.filter(\.isRunning).flatMap { $0.ports.map(\.hostPort) }).count

        HStack(spacing: 0) {
            SummaryStrip.Stat(value: running, label: "running", tint: Theme.mint)
            SummaryStrip.Stat(value: stopped, label: "stopped", tint: Theme.secondary)
            SummaryStrip.Stat(value: projects, label: "compose", tint: Theme.sky)
            SummaryStrip.Stat(value: published, label: "ports", tint: Theme.sail)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }
}

struct DockerGroupHeader: View {
    @EnvironmentObject private var settings: AppSettings
    let group: DockerGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.project == nil ? "shippingbox" : "square.stack.3d.up.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.sky)
            Text((group.project ?? "Standalone").uppercased())
                .font(Theme.text(10, .medium))
                .tracking(1.3)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
            Text(verbatim: "\(group.runningCount)/\(group.containers.count)")
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.tertiary)
                .help("\(group.runningCount) of \(group.containers.count) running")
            Spacer()
            if let dir = group.workingDir, FileManager.default.fileExists(atPath: dir) {
                AppIconButton(bundleID: settings.editorBundleID, help: "Open \(dir) in \(settings.editor?.name ?? "editor")", size: 22) {
                    ExternalApps.open(path: dir, with: settings.editorBundleID)
                }
                AppIconButton(bundleID: settings.terminalBundleID, help: "Open in \(settings.terminal?.name ?? "terminal")", size: 22) {
                    ExternalApps.open(path: dir, with: settings.terminalBundleID)
                }
            }
        }
        .frame(height: 22)
    }
}

struct ContainerRow: View {
    @EnvironmentObject private var docker: DockerStore
    let container: DockerContainer
    let expanded: Bool
    let toggle: () -> Void
    @State private var hovering = false
    @State private var confirmStop = false

    private var busy: Bool { docker.busyIDs.contains(container.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Rectangle()
                    .fill(container.stateColor)
                    .frame(width: 2, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(container.displayName)
                            .font(Theme.text(13, .medium))
                            .foregroundStyle(container.isRunning ? Theme.text : Theme.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if container.tech != .docker {
                            Text(container.tech.name)
                                .font(Theme.text(11))
                                .foregroundStyle(Theme.sky)
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(container.ports.prefix(3)) { mapping in
                            PortChip(mapping: mapping, active: container.isRunning)
                        }
                        if container.ports.count > 3 {
                            Text(verbatim: "+\(container.ports.count - 3)")
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.tertiary)
                        }
                        Text(container.status)
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if busy {
                    ProgressView().controlSize(.small)
                } else if hovering || expanded {
                    actions.transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if expanded {
                details.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering || expanded ? Theme.surfaceHover : Theme.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.14)) { hovering = value }
            if !value { confirmStop = false }
        }
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if container.isRunning {
                if let url = container.ports.first(where: { $0.url != nil })?.url {
                    IconButton(symbol: "safari.fill", image: BrowserIcon.image, help: "Open \(url.absoluteString)", size: 26) {
                        ExternalApps.openURL(url)
                    }
                }
                IconButton(symbol: "arrow.clockwise", tint: Theme.sky, help: "Restart", size: 26) {
                    docker.perform(.restart, on: container)
                }
                IconButton(
                    symbol: confirmStop ? "exclamationmark.triangle.fill" : "stop.circle.fill",
                    tint: Theme.coral,
                    secondaryTint: Theme.coral.opacity(0.45),
                    help: confirmStop ? "Click again to stop it" : "Stop container",
                    size: 26
                ) {
                    if confirmStop {
                        docker.perform(.stop, on: container)
                        confirmStop = false
                    } else {
                        withAnimation(.snappy) { confirmStop = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { confirmStop = false } }
                    }
                }
            } else if container.isPaused {
                IconButton(symbol: "playpause.fill", tint: Theme.mint, help: "Resume", size: 26) {
                    docker.perform(.unpause, on: container)
                }
            } else {
                IconButton(symbol: "play.circle.fill", tint: Theme.mint, secondaryTint: Theme.mint.opacity(0.4), help: "Start container", size: 26) {
                    docker.perform(.start, on: container)
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 9) {
            Rectangle().fill(Theme.stroke).frame(height: 1)

            detailLine("shippingbox", container.image)
            detailLine("number", container.shortID)
            if container.composeService != nil {
                detailLine("tag", container.name)
            }
            if let dir = container.workingDir {
                detailLine("folder", (dir as NSString).abbreviatingWithTildeInPath)
            }
            if !container.ports.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(container.ports) { mapping in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                            Text(verbatim: "localhost:\(mapping.hostPort) → \(mapping.containerPort)/\(mapping.proto)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                PillButton(title: "Copy logs command", symbol: "text.alignleft", tint: Theme.text) {
                    Clipboard.copy("docker logs -f \(container.name)", toast: "Logs command copied")
                }
                PillButton(title: "Copy shell command", symbol: "terminal", tint: Theme.text) {
                    Clipboard.copy("docker exec -it \(container.name) sh", toast: "Shell command copied")
                }
                Spacer()
                IconButton(symbol: "doc.on.doc", help: "Copy container ID", size: 28) {
                    Clipboard.copy(container.id, toast: "Container ID copied")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private func detailLine(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(Theme.tertiary).frame(width: 12)
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct PortChip: View {
    let mapping: DockerPortMapping
    let active: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = mapping.url { ExternalApps.openURL(url) }
        } label: {
            Text(verbatim: ":\(mapping.hostPort)")
                .font(Theme.mono(10.5, weight: .semibold))
                .foregroundStyle(active ? Theme.sail : Theme.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill((active ? Theme.sail : Theme.tertiary).opacity(hovering ? 0.26 : 0.14))
                )
        }
        .buttonStyle(.plain)
        .disabled(!active || mapping.url == nil)
        .onHover { hovering = $0 }
        .help("localhost:\(mapping.hostPort) → container \(mapping.containerPort)/\(mapping.proto)")
    }
}
