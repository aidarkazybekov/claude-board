import AppKit
import SwiftUI

// MARK: - Color helpers

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }

    /// A color that follows the window's light or dark appearance.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Hex {
    /// Mixes `a` toward `b` by `t` (0…1), per channel.
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) * (1 - t) + ch(b, s) * t).rounded()) << s }
        return m(16) | m(8) | m(0)
    }

    static func css(_ v: UInt32) -> String { String(format: "#%06X", v) }
}

// MARK: - Studio design tokens

/// The Studio look: bright ground, black ink and pill buttons, soft per-project tints, coral only for
/// what needs you. Every color has a dark-mode twin.
enum Studio {
    static let groundHex: (UInt32, UInt32) = (0xF4F5F9, 0x111217)
    static let surfaceHex: (UInt32, UInt32) = (0xFFFFFF, 0x1B1D24)

    static let ground = Color.dyn(groundHex.0, groundHex.1)
    static let surface = Color.dyn(surfaceHex.0, surfaceHex.1)
    /// Fields, chips and wells sitting on a white surface.
    static let well = Color.dyn(0xF4F5F9, 0x252832)
    static let ink = Color.dyn(0x14161F, 0xEEEFF4)
    static let ink2 = Color.dyn(0x3E4252, 0xC3C7D3)
    static let muted = Color.dyn(0x5F6475, 0x9499AB)
    static let faint = Color.dyn(0x8A8FA0, 0x6E7386)
    static let line = Color.dyn(0xE7E9F0, 0x2C2F3A)
    /// Text on the black (or, in dark mode, white) primary fill.
    static let onInk = Color.dyn(0xFFFFFF, 0x14161F)

    static let coral = Color(hex: 0xFF6A3D)
    static let coralBg = Color.dyn(0xFFF0EA, 0x3A2118)
    static let coralInk = Color.dyn(0xA33A12, 0xFF9C7A)

    static let live = Color.dyn(0x1FA37A, 0x3DD3A0)
    static let liveBg = Color.dyn(0xE2F6EF, 0x163329)
    static let blue = Color.dyn(0x3D6FE0, 0x7FA2F2)
    static let blueBg = Color.dyn(0xEAF1FE, 0x1C2840)
    static let blueInk = Color.dyn(0x2A55B8, 0x9FB9F5)
    static let doneInk = Color.dyn(0x16735F, 0x63D5B3)
    static let doneBg = Color.dyn(0xE7F8F3, 0x15302A)

    // Type: SF Pro Rounded for headings and numbers, SF Pro for reading text.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func text(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }

    static let radiusCard: CGFloat = 18
    static let radiusPanel: CGFloat = 22
}

// MARK: - Buttons

struct StudioButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, coral, white }
    var kind: Kind = .primary
    var size: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Studio.text(size, kind == .quiet ? .semibold : .bold))
            .lineLimit(1)
            .padding(.horizontal, kind == .quiet ? 6 : size * 1.1)
            .padding(.vertical, size * 0.55)
            .foregroundStyle(fg)
            .background(Capsule().fill(bg))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var fg: Color {
        switch kind {
        case .primary: return Studio.onInk
        case .secondary, .white: return Studio.ink
        case .quiet: return Studio.ink2
        case .coral: return .white
        }
    }

    private var bg: Color {
        switch kind {
        case .primary: return Studio.ink
        case .secondary: return Studio.well
        case .white: return Studio.surface
        case .quiet: return .clear
        case .coral: return Studio.coral
        }
    }
}

extension ButtonStyle where Self == StudioButtonStyle {
    static var studio: StudioButtonStyle { StudioButtonStyle() }
    static func studio(_ kind: StudioButtonStyle.Kind, size: CGFloat = 13) -> StudioButtonStyle { StudioButtonStyle(kind: kind, size: size) }
}

/// Round icon button (28pt) on a white or well background.
struct CircleIconButton: View {
    let symbol: String
    let help: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(filled ? Studio.onInk : Studio.ink)
                .background(Circle().fill(filled ? Studio.ink : Studio.surface))
                .overlay(Circle().stroke(Studio.line, lineWidth: filled ? 0 : 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Surfaces

extension View {
    /// White rounded card on the Studio ground.
    func studioCard(radius: CGFloat = Studio.radiusCard, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Studio.surface))
    }

    func studioWell(radius: CGFloat = 14, padding: CGFloat = 12) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Studio.well))
    }
}

// MARK: - Pill tabs (view switcher, periods, segmented choices)

struct PillTabs<T: Hashable>: View {
    @Binding var selection: T
    let items: [(T, String)]
    var size: CGFloat = 13
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { value, title in
                let on = value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { selection = value }
                } label: {
                    Text(title)
                        .font(Studio.text(size, on ? .bold : .semibold))
                        .foregroundStyle(on ? Studio.onInk : Studio.ink2)
                        .padding(.horizontal, size * 1.15)
                        .padding(.vertical, size * 0.45)
                        .background {
                            if on { Capsule().fill(Studio.ink).matchedGeometryEffect(id: "pill", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Studio.surface))
        .overlay(Capsule().stroke(Studio.line, lineWidth: 1))
    }
}

// MARK: - Small pieces

/// Black circle with the agent's two letters.
struct AgentAvatar: View {
    let agent: Agent
    var size: CGFloat = 22

    var body: some View {
        Text(agent.mono)
            .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
            .foregroundStyle(Studio.onInk)
            .frame(width: size, height: size)
            .background(Circle().fill(Studio.ink))
            .accessibilityLabel(agent.title)
    }
}

/// White capsule with the agent's avatar and a label ("Codex", "Codex needs you").
struct AgentChip: View {
    let agent: Agent
    var text: String?
    var coral = false
    var onWell = false

    var body: some View {
        HStack(spacing: 6) {
            AgentAvatar(agent: agent, size: 18)
            Text(text ?? agent.title).lineLimit(1)
        }
        .font(Studio.text(12, .bold))
        .foregroundStyle(coral ? Studio.coralInk : Studio.ink)
        .padding(.leading, 3)
        .padding(.trailing, 10)
        .padding(.vertical, 2)
        .background(Capsule().fill(coral ? Studio.coralBg : (onWell ? Studio.surface : Studio.well)))
    }
}

/// Small white capsule for priority, labels and other tags on a tinted card.
struct Tag: View {
    let text: String
    var color: Color = Studio.ink
    var fill: Color = Studio.surface

    var body: some View {
        Text(text)
            .font(Studio.text(12, .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }
}

struct ProjectDot: View {
    let colorIndex: Int
    var size: CGFloat = 9
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
            .fill(Palette.project(colorIndex))
            .frame(width: size, height: size)
    }
}

/// Count in a small capsule; coral when something needs you.
struct CountPill: View {
    let n: Int
    var coral = false
    var body: some View {
        Text("\(n)")
            .font(Studio.text(12, .bold).monospacedDigit())
            .foregroundStyle(coral ? .white : Studio.muted)
            .padding(.horizontal, coral ? 8 : 0)
            .padding(.vertical, coral ? 1 : 0)
            .background(Capsule().fill(coral ? Studio.coral : .clear))
    }
}

/// Rounded search field for the header.
struct StudioSearchField: View {
    @Binding var text: String
    var prompt = "Search tasks, keys, prompts"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .bold)).foregroundStyle(Studio.muted)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Studio.text(13, .medium))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Studio.faint) }
                    .buttonStyle(.plain)
                    .help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Studio.surface))
        .overlay(Capsule().stroke(focused ? Studio.ink.opacity(0.5) : Studio.line, lineWidth: 1))
        .background {
            // ⌘F focuses the search field.
            Button("") { focused = true }.keyboardShortcut("f").opacity(0).allowsHitTesting(false)
        }
    }
}

/// Section title used on cards and panels.
struct CardTitle: View {
    let title: String
    var detail: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Studio.display(16, .heavy)).foregroundStyle(Studio.ink)
            if let detail { Text(detail).font(Studio.text(12.5, .semibold)).foregroundStyle(Studio.muted) }
        }
    }
}

/// Text field styled as a Studio well.
struct WellField: View {
    let title: String
    @Binding var text: String
    var prompt = ""
    var size: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty { Text(title).font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2) }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Studio.text(size, .medium))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Studio.well))
        }
    }
}
