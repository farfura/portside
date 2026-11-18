import SwiftUI
import AppKit

struct TrafficWindow: View {
    @EnvironmentObject private var ports: PortStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let sessions = ports.tunnels.values.sorted { $0.targetPort < $1.targetPort }

        ZStack {
            Backdrop()
            if sessions.isEmpty {
                EmptyState(
                    symbol: "waveform.path.ecg",
                    title: "Nothing shared yet",
                    message: "Share a port publicly from the Portside menu. Every request that comes through the link shows up here, ready to inspect and replay.",
                    tint: Theme.violet
                )
            } else {
                let current = sessions.first { $0.targetPort == ports.inspectorPort } ?? sessions[0]
                TrafficSessionView(session: current, sessions: sessions)
                    .id(current.targetPort)
            }
        }
        .frame(minWidth: 880, minHeight: 540)
        .font(Theme.text(13))
        .environment(\.colorScheme, settings.resolvedScheme)
        .preferredColorScheme(settings.preferredScheme)
    }
}

struct TrafficSessionView: View {
    @EnvironmentObject private var ports: PortStore
    @ObservedObject var session: TunnelSession
    let sessions: [TunnelSession]
    @State private var selectedID: UUID?
    @State private var filter = ""

    private var visibleEntries: [TrafficEntry] {
        guard !filter.isEmpty else { return session.entries }
        return session.entries.filter {
            $0.path.localizedCaseInsensitiveContains(filter)
                || $0.method.localizedCaseInsensitiveContains(filter)
                || ($0.status.map { String($0).hasPrefix(filter) } ?? false)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                SearchField(text: $filter, prompt: "Filter by path, method or status")
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                list
            }
            .frame(width: 420)
            .background(Theme.surface)

            Rectangle().fill(Theme.stroke).frame(width: 1)

            Group {
                if let id = selectedID, let entry = session.entries.first(where: { $0.id == id }) {
                    TrafficDetailView(entry: entry, session: session)
                        .id(entry.id)
                } else {
                    EmptyState(
                        symbol: "cursorarrow.click.2",
                        title: session.entries.isEmpty ? "Waiting for traffic" : "Pick a request",
                        message: session.entries.isEmpty
                            ? "Open your public link or point a webhook at it. Requests stream in live."
                            : "Select a request on the left to see headers and bodies, then replay it against localhost with one click.",
                        tint: Theme.violet
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if selectedID == nil { selectedID = session.entries.first?.id } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(sessions) { other in
                        Button(":\(String(other.targetPort))  \(other.isLive ? "live" : "stopped")") {
                            ports.inspectorPort = other.targetPort
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        StatusDot(color: session.isLive ? Theme.violet : Theme.tertiary, pulsing: session.isLive, size: 7)
                        Text(verbatim: ":\(session.targetPort)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.text)
                        if sessions.count > 1 {
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Spacer()

                Text(Format.plural(session.entries.count, "request"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                IconButton(symbol: "trash", tint: Theme.coral, help: "Clear the log", size: 26) {
                    withAnimation(.snappy) {
                        session.clear()
                        selectedID = nil
                    }
                }
            }

            if let url = session.publicURL {
                HStack(spacing: 6) {
                    Image(systemName: "globe").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.violet)
                    Text(url.absoluteString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    IconButton(symbol: "doc.on.doc", help: "Copy public link", size: 22, filled: false) {
                        Clipboard.copy(url.absoluteString, toast: "Public link copied")
                    }
                }
            } else {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var statusText: String {
        switch session.status {
        case .starting: return "Connecting to Cloudflare"
        case .failed(let message): return message
        case .stopped: return "Sharing stopped. The log stays here until you clear it."
        case .live: return ""
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(visibleEntries) { entry in
                    TrafficListRow(entry: entry, selected: entry.id == selectedID)
                        .onTapGesture { selectedID = entry.id }
                }
            }
            .padding(6)
        }
        .scrollIndicators(.automatic)
    }
}

struct TrafficListRow: View {
    let entry: TrafficEntry
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.method)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.methodColor(entry.method))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(Format.clock.string(from: entry.startedAt))
                    if entry.isReplay { Text("replay").foregroundStyle(Theme.violet) }
                    if entry.isWebSocket { Text("websocket").foregroundStyle(Theme.sky) }
                    if !entry.requestBody.isEmpty { Text(Format.bytes(entry.requestBody.count)) }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.tertiary)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                if entry.isPending {
                    ProgressView().controlSize(.mini)
                } else if let status = entry.status {
                    Text(String(status))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.statusColor(status))
                } else {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.coral)
                }
                Text(Format.duration(entry.duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Theme.surface : (hovering ? Theme.surfaceHover : Color.clear))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(selected ? Theme.violet : Color.clear)
                .frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct TrafficDetailView: View {
    let entry: TrafficEntry
    @ObservedObject var session: TunnelSession
    @State private var showResponse = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(entry.method)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.methodColor(entry.method))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.methodColor(entry.method).opacity(0.14)))
                    Text(entry.path)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                }
                HStack(spacing: 8) {
                    if let status = entry.status {
                        Pill(text: "\(status) \(entry.reason ?? "")", tint: Theme.statusColor(status), mono: true)
                    } else if entry.isPending {
                        Pill(text: "pending", tint: Theme.tertiary)
                    }
                    if let duration = entry.duration {
                        Pill(text: Format.duration(duration), symbol: "timer", tint: Theme.secondary, mono: true)
                    }
                    Pill(text: Format.clock.string(from: entry.startedAt), symbol: "clock", tint: Theme.secondary, mono: true)
                    if entry.isReplay { Pill(text: "replay", symbol: "arrow.clockwise", tint: Theme.violet) }
                    Spacer()
                    if !entry.isWebSocket {
                        PillButton(title: "Copy as cURL", symbol: "terminal", tint: Theme.text) {
                            Clipboard.copy(curl, toast: "cURL copied")
                        }
                        PillButton(title: "Replay", symbol: "arrow.clockwise", tint: Theme.violet, prominent: true) {
                            session.replay(entry)
                            Toast.shared.show("Replayed against localhost:\(String(session.targetPort))", symbol: "arrow.clockwise")
                        }
                    }
                }
                if let error = entry.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.coral)
                }

                Picker("", selection: $showResponse) {
                    Text("Request").tag(false)
                    Text("Response").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            .padding(18)

            Rectangle().fill(Theme.stroke).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if showResponse {
                        HeadersBlock(title: "Response headers", headers: entry.responseHeaders)
                        BodyBlock(
                            title: "Response body",
                            data: entry.responseBody,
                            contentType: HTTP.value("content-type", in: entry.responseHeaders),
                            truncated: entry.responseTruncated
                        )
                    } else {
                        HeadersBlock(title: "Request headers", headers: entry.requestHeaders)
                        BodyBlock(
                            title: "Request body",
                            data: entry.requestBody,
                            contentType: HTTP.value("content-type", in: entry.requestHeaders),
                            truncated: false
                        )
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { showResponse = !entry.isPending }
    }

    private var curl: String {
        func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let skip: Set<String> = ["host", "content-length", "connection", "accept-encoding", "cf-ray", "cf-connecting-ip", "cf-ipcountry", "cf-visitor", "cdn-loop", "x-forwarded-for", "x-forwarded-proto", "x-forwarded-host"]
        var parts = ["curl", "-X", entry.method, quote("http://localhost:\(session.targetPort)\(entry.path)")]
        for header in entry.requestHeaders where !skip.contains(header.name.lowercased()) {
            parts.append("-H")
            parts.append(quote("\(header.name): \(header.value)"))
        }
        if !entry.requestBody.isEmpty {
            parts.append("--data-binary")
            parts.append(quote(String(decoding: entry.requestBody, as: UTF8.self)))
        }
        return parts.joined(separator: " ")
    }
}

struct HeadersBlock: View {
    let title: String
    let headers: [HeaderField]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title, trailing: headers.isEmpty ? nil : String(headers.count))
            if headers.isEmpty {
                Text("None").font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                        HStack(alignment: .top, spacing: 12) {
                            Text(header.name)
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.sky)
                                .frame(width: 210, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(header.value)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(index.isMultiple(of: 2) ? Theme.surface : Color.clear)
                    }
                }
                .card(radius: 10)
            }
        }
    }
}

struct BodyBlock: View {
    let title: String
    let data: Data
    let contentType: String?
    let truncated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title, trailing: data.isEmpty ? nil : Format.bytes(data.count) + (truncated ? " (truncated)" : ""))
            if data.isEmpty {
                Text("Empty").font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            } else if let text = rendered {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(Theme.text.opacity(0.88))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .card(radius: 10)
                HStack {
                    Spacer()
                    PillButton(title: "Copy body", symbol: "doc.on.doc", tint: Theme.text) {
                        Clipboard.copy(text, toast: "Body copied")
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.zipper").foregroundStyle(Theme.tertiary)
                    Text("Binary content, \(Format.bytes(data.count))\(contentType.map { ", " + $0 } ?? "")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: 10)
            }
        }
    }

    private var rendered: String? {
        let type = contentType?.lowercased() ?? ""
        if type.contains("json") || data.first == UInt8(ascii: "{") || data.first == UInt8(ascii: "[") {
            if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
               let text = String(data: pretty, encoding: .utf8) {
                return clip(text)
            }
        }
        if type.contains("x-www-form-urlencoded"), let raw = String(data: data, encoding: .utf8) {
            let lines = raw.split(separator: "&").map { pair -> String in
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
                return kv.count == 2 ? "\(kv[0]) = \(kv[1])" : kv.first ?? ""
            }
            return clip(lines.joined(separator: "\n"))
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let controlCount = text.unicodeScalars.prefix(2000).filter { $0.value < 9 || ($0.value > 13 && $0.value < 32) }.count
        return controlCount > 4 ? nil : clip(text)
    }

    private func clip(_ text: String) -> String {
        text.count > 200_000 ? String(text.prefix(200_000)) + "\n\n(clipped for display)" : text
    }
}
