import SwiftUI
import AppKit

struct ReposView: View {
    @EnvironmentObject private var repos: RepoStore
    @EnvironmentObject private var settings: AppSettings
    let openSettings: () -> Void
    @State private var query = ""
    @State private var onlyAttention = true
    @State private var expanded: String?

    private var filtered: [RepoStatus] {
        repos.repos.filter { repo in
            (!onlyAttention || repo.needsAttention || !query.isEmpty)
                && (query.isEmpty || repo.name.localizedCaseInsensitiveContains(query) || repo.branch.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                SearchField(text: $query, prompt: "Search \(repos.repos.count) repos")
                FilterToggle(onlyAttention: $onlyAttention, count: repos.attentionCount)
                IconButton(
                    symbol: "arrow.down.circle",
                    tint: Theme.sky,
                    help: "Fetch every remote so behind counts are fresh",
                    size: 30
                ) { repos.fetchAll() }
                .opacity(repos.isFetching ? 0.4 : 1)
                .overlay { if repos.isFetching { ProgressView().controlSize(.small) } }
                .disabled(repos.isFetching)
            }
            .padding(.horizontal, 18)

            if !repos.repos.isEmpty {
                SummaryStrip(repos: repos.repos)
                    .padding(.horizontal, 18)
            }

            ScrollView {
                LazyVStack(spacing: 6) {
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
        if settings.scanRoots.isEmpty {
            VStack(spacing: 16) {
                EmptyState(
                    symbol: "folder.badge.plus",
                    title: "Point me at your code",
                    message: "Choose the folders where your projects live. Portside finds every git repo inside and keeps an eye on them.",
                    tint: Theme.amber
                )
                PillButton(title: "Choose folders", symbol: "folder.badge.plus", tint: Theme.amber, prominent: true) {
                    FolderPicker.addFolders()
                }
            }
            .padding(.top, 24)
        } else if !repos.hasScannedOnce {
            ForEach(0..<4, id: \.self) { _ in SkeletonRow() }
        } else if repos.repos.isEmpty {
            VStack(spacing: 16) {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: "No repos found yet",
                    message: "Nothing with a .git folder inside \(settings.scanRoots.joined(separator: ", ")). Add the folder where you keep your projects.",
                    tint: Theme.amber
                )
                PillButton(title: "Add a folder", symbol: "folder.badge.plus", tint: Theme.amber, prominent: true) {
                    FolderPicker.addFolders()
                }
            }
            .padding(.top, 24)
        } else if filtered.isEmpty {
            VStack(spacing: 16) {
                EmptyState(
                    symbol: query.isEmpty ? "checkmark.seal.fill" : "magnifyingglass",
                    title: query.isEmpty ? "Everything is shipped" : "No matches",
                    message: query.isEmpty
                        ? "All \(repos.repos.count) repos are committed, pushed and up to date. Go touch grass."
                        : "No repo or branch matches \u{201C}\(query)\u{201D}.",
                    tint: Theme.mint
                )
                if query.isEmpty {
                    PillButton(title: "Show all repos", symbol: "list.bullet", tint: Theme.text) {
                        withAnimation(.snappy) { onlyAttention = false }
                    }
                }
            }
            .padding(.top, 24)
        } else {
            ForEach(filtered) { repo in
                RepoRow(repo: repo, expanded: expanded == repo.id) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        expanded = expanded == repo.id ? nil : repo.id
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

struct FilterToggle: View {
    @Binding var onlyAttention: Bool
    let count: Int
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(.snappy) { onlyAttention.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: onlyAttention ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11, weight: .semibold))
                Text(onlyAttention ? "Needs you" : "All")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(onlyAttention || hovering ? Theme.text : Theme.secondary)
            .padding(.horizontal, 2)
            .frame(height: 30)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(onlyAttention ? Theme.text : Color.clear)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(onlyAttention ? "Showing repos that need attention" : "Showing every repo")
    }
}

struct SummaryStrip: View {
    let repos: [RepoStatus]

    var body: some View {
        let dirty = repos.filter { $0.changeCount > 0 }.count
        let unpushed = repos.filter { $0.ahead > 0 || $0.isUnpublished }.count
        let behind = repos.filter { $0.behind > 0 }.count
        let stashed = repos.filter { $0.stashes > 0 }.count

        HStack(spacing: 0) {
            Stat(value: dirty, label: "uncommitted", tint: Theme.amber)
            Stat(value: unpushed, label: "unpushed", tint: Theme.sail)
            Stat(value: behind, label: "behind", tint: Theme.sky)
            Stat(value: stashed, label: "stashed", tint: Theme.violet)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
    }

    struct Stat: View {
        let value: Int
        let label: String
        var tint: Color = Theme.text

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(value)")
                    .font(Theme.mono(18, weight: .regular))
                    .foregroundStyle(value > 0 ? tint : Theme.tertiary)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(value > 0 ? tint.opacity(0.85) : Theme.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        }
    }
}

struct RepoRow: View {
    @EnvironmentObject private var repos: RepoStore
    @EnvironmentObject private var settings: AppSettings
    let repo: RepoStatus
    let expanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Rectangle()
                    .fill(repo.state.color)
                    .frame(width: 2, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text(repo.name)
                            .font(Theme.text(13, .medium))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        BranchPill(name: repo.isDetached ? "detached" : repo.branch)
                    }
                    chips
                }

                Spacer(minLength: 6)

                if hovering || expanded {
                    HStack(spacing: 4) {
                        AppIconButton(bundleID: settings.editorBundleID, help: "Open in \(settings.editor?.name ?? "editor")", size: 26) {
                            ExternalApps.open(path: repo.path, with: settings.editorBundleID)
                        }
                        AppIconButton(bundleID: settings.terminalBundleID, help: "Open in \(settings.terminal?.name ?? "terminal")", size: 26) {
                            ExternalApps.open(path: repo.path, with: settings.terminalBundleID)
                        }
                        IconButton(symbol: "folder", help: "Reveal in Finder", size: 26) { ExternalApps.reveal(repo.path) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    Text(Format.ago(repo.lastCommitDate))
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if expanded {
                details
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering || expanded ? Theme.surfaceHover : Theme.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { value in withAnimation(.easeOut(duration: 0.14)) { hovering = value } }
    }

    private var chips: some View {
        HStack(spacing: 5) {
            if repo.conflicts > 0 {
                Pill(text: "\(repo.conflicts) conflict\(repo.conflicts == 1 ? "" : "s")", symbol: "exclamationmark.triangle.fill", tint: Theme.coral)
            }
            if repo.changeCount > 0 {
                Pill(text: "\(repo.changeCount) change\(repo.changeCount == 1 ? "" : "s")", symbol: "pencil", tint: Theme.amber)
                    .help(repo.changeBreakdown)
            }
            if repo.ahead > 0 {
                Pill(text: "\(repo.ahead) to push", symbol: "arrow.up", tint: Theme.mint)
            }
            if repo.isUnpublished {
                Pill(text: "never pushed", symbol: "icloud.slash", tint: Theme.violet)
            }
            if repo.behind > 0 {
                Pill(text: "\(repo.behind) behind", symbol: "arrow.down", tint: Theme.sky)
            }
            if repo.stashes > 0 {
                Pill(text: "\(repo.stashes) stashed", symbol: "tray.full.fill", tint: Theme.secondary)
            }
            if repo.state == .clean {
                Pill(text: repo.hasRemote ? "up to date" : "local only", symbol: repo.hasRemote ? "checkmark" : "internaldrive", tint: Theme.tertiary)
            }
            if let error = repo.error {
                Pill(text: "git error", symbol: "xmark.octagon.fill", tint: Theme.coral).help(error)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Theme.stroke).frame(height: 1)

            if let subject = repo.lastCommitSubject {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "smallcircle.filled.circle").font(.system(size: 10)).foregroundStyle(Theme.tertiary).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(subject).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(2)
                        if let date = repo.lastCommitDate {
                            (Text("Last commit ") + Text(date, style: .relative) + Text(" ago"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.tertiary)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                Text(repo.displayPath)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let upstream = repo.upstream {
                    Spacer()
                    Text(upstream).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.tertiary).lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                if let web = repo.webURL {
                    PillButton(title: repo.remoteHostName, symbol: "arrow.up.right", tint: Theme.text) { ExternalApps.openURL(web) }
                }
                if repo.hasRemote {
                    PillButton(
                        title: "Fetch",
                        symbol: "arrow.down.circle",
                        tint: Theme.sky,
                        isLoading: repos.fetchingPaths.contains(repo.path)
                    ) { repos.fetch(repo) }
                }
                Spacer()
                IconButton(symbol: "doc.on.doc", help: "Copy path", size: 30) {
                    Clipboard.copy(repo.path, toast: "Path copied")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }
}

struct BranchPill: View {
    let name: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 8.5, weight: .bold))
            Text(name).font(.system(size: 10.5, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
        .frame(maxWidth: 150, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum FolderPicker {
    static func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders that contain your git projects"
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let home = NSHomeDirectory()
        var roots = AppSettings.shared.scanRoots
        for url in panel.urls {
            var path = url.path
            if path.hasPrefix(home) { path = "~" + String(path.dropFirst(home.count)) }
            if !roots.contains(path) { roots.append(path) }
        }
        AppSettings.shared.scanRoots = roots
    }
}
