import SwiftUI
import AppKit

enum Theme {
    // Sea chart: mist by day, the icon's navy by night. Sail cyan is the brand.
    static let bg = dynamic(light: (0.935, 0.968, 0.970), dark: (0.055, 0.078, 0.110))
    static let surface = dynamic(light: (0.875, 0.935, 0.940), dark: (0.095, 0.125, 0.165))
    static let surfaceHover = dynamic(light: (0.800, 0.895, 0.905), dark: (0.135, 0.175, 0.220))
    static let stroke = dynamic(light: (0.040, 0.220, 0.260, 0.14), dark: (0.55, 0.85, 0.90, 0.14))
    static let strokeStrong = dynamic(light: (0.020, 0.280, 0.340, 0.32), dark: (0.55, 0.85, 0.90, 0.30))
    static let text = dynamic(light: (0.045, 0.110, 0.130), dark: (0.920, 0.960, 0.970))
    static let secondary = dynamic(light: (0.120, 0.260, 0.300), dark: (0.700, 0.820, 0.850))
    static let tertiary = dynamic(light: (0.250, 0.390, 0.430), dark: (0.500, 0.640, 0.690))

    static let sail = dynamic(light: (0.000, 0.480, 0.560), dark: (0.380, 0.900, 0.930))
    static let onSail = dynamic(light: (0.970, 0.990, 0.990), dark: (0.040, 0.090, 0.110))
    static let mint = dynamic(light: (0.000, 0.480, 0.340), dark: (0.450, 0.900, 0.640))
    static let sky = dynamic(light: (0.100, 0.320, 0.780), dark: (0.550, 0.740, 1.000))
    static let violet = dynamic(light: (0.640, 0.140, 0.460), dark: (0.980, 0.550, 0.780))
    static let amber = dynamic(light: (0.760, 0.400, 0.000), dark: (1.000, 0.780, 0.360))
    static let coral = dynamic(light: (0.800, 0.160, 0.180), dark: (1.000, 0.480, 0.420))

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        dynamic(light: (light.0, light.1, light.2, 1), dark: (dark.0, dark.1, dark.2, 1))
    }

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        let day = NSColor(srgbRed: light.0, green: light.1, blue: light.2, alpha: light.3)
        let night = NSColor(srgbRed: dark.0, green: dark.1, blue: dark.2, alpha: dark.3)
        let named = NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? night : day
        })
        return Color(nsColor: named)
    }

    static let brand = LinearGradient(
        colors: [sail, sky, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .semibold, .heavy, .black:
            name = "Avenir Next Demi Bold"
        case .medium:
            name = "Avenir Next Medium"
        default:
            name = "Avenir Next"
        }
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func methodColor(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return sky
        case "POST": return mint
        case "PUT", "PATCH": return amber
        case "DELETE": return coral
        default: return secondary
        }
    }

    static func statusColor(_ status: Int?) -> Color {
        guard let status else { return tertiary }
        switch status {
        case 100..<300: return mint
        case 300..<400: return sky
        case 400..<500: return amber
        default: return coral
        }
    }
}

// MARK: - Backdrop

struct Backdrop: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

struct NoiseOverlay: View {
    var body: some View { Color.clear.allowsHitTesting(false) }
}

// MARK: - Card

struct CardBackground: ViewModifier {
    var hovering: Bool
    var radius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(hovering ? Theme.surfaceHover : Theme.surface)
            )
            .overlay(alignment: .leading) {
                if let tint {
                    Rectangle()
                        .fill(tint)
                        .frame(width: 2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.strokeStrong, lineWidth: 1)
            )
    }
}

extension View {
    func card(hovering: Bool = false, radius: CGFloat = 2, tint: Color? = nil) -> some View {
        modifier(CardBackground(hovering: hovering, radius: radius, tint: tint))
    }
}

// MARK: - Small components

struct Pill: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = Theme.secondary
    var mono = false

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
            }
            Text(text)
                .font(mono ? Theme.mono(11) : Theme.text(11, .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .fixedSize()
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false
    var size: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color.opacity(pulsing ? 1 : 0.9))
            .frame(width: max(5, size * 0.7), height: size)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

enum BrowserIcon {
    static let image: NSImage? = {
        guard let page = URL(string: "http://localhost"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: page) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }()
}

struct IconButton: View {
    let symbol: String
    var tint: Color = Theme.text
    var secondaryTint: Color? = nil
    var image: NSImage? = nil
    var multicolor = false
    var help: String = ""
    var size: CGFloat = 28
    var rotation: Double = 0
    var filled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size - 8, height: size - 8)
                } else if multicolor {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: size * 0.52))
                        .rotationEffect(.degrees(rotation))
                } else if let secondaryTint {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(tint, secondaryTint)
                        .font(.system(size: size * 0.46, weight: .semibold))
                        .rotationEffect(.degrees(rotation))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(rotation))
                        .foregroundStyle(hovering ? tint : tint.opacity(0.8))
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(hovering ? Theme.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct AppIconButton: View {
    let bundleID: String
    var help: String
    var size: CGFloat = 28
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let icon = ExternalApps.icon(for: bundleID) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: size - 10, height: size - 10)
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(hovering ? Theme.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.text
    var prominent = false
    var isLoading = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().controlSize(.mini).tint(prominent ? Theme.onSail : tint)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(Theme.text(12, .medium)).lineLimit(1)
            }
            .foregroundStyle(prominent ? Theme.onSail : tint)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(prominent ? Theme.sail.opacity(hovering ? 1 : 0.92) : (hovering ? Theme.surfaceHover : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.strokeStrong, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .disabled(isLoading)
    }
}

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(Theme.text(10, .medium))
                .tracking(1.3)
                .foregroundStyle(Theme.tertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

struct AppGlyph: View {
    var size: CGFloat = 32

    var body: some View {
        Text("P")
            .font(Theme.text(size * 0.48, .medium))
            .foregroundStyle(Theme.bg)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 2).fill(Theme.text))
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Theme.tertiary))
                .textFieldStyle(.plain)
                .font(Theme.text(13))
                .foregroundStyle(Theme.text)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 30)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.strokeStrong).frame(height: 1)
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Theme.secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(tint)
                .frame(width: 18, height: 2)
            Text(title)
                .font(Theme.text(18, .medium))
                .foregroundStyle(Theme.text)
            Text(message)
                .font(Theme.text(12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

struct ToastView: View {
    let message: Toast.Message

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.mint)
            Text(message.text).font(Theme.text(12, .medium)).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 2).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.strokeStrong, lineWidth: 1))
        .shadow(color: Theme.text.opacity(0.08), radius: 8, y: 3)
    }
}

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Theme.text.opacity(0.05), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
