import SwiftUI

enum Palette {
    static let projectColors: [Color] = [
        Color(red: 0.25, green: 0.47, blue: 0.95),  // blue
        Color(red: 0.58, green: 0.36, blue: 0.90),  // violet
        Color(red: 0.90, green: 0.33, blue: 0.55),  // pink
        Color(red: 0.95, green: 0.55, blue: 0.20),  // orange
        Color(red: 0.13, green: 0.64, blue: 0.64),  // teal
        Color(red: 0.30, green: 0.66, blue: 0.33),  // green
        Color(red: 0.36, green: 0.40, blue: 0.85),  // indigo
        Color(red: 0.75, green: 0.55, blue: 0.20),  // amber
        Color(red: 0.55, green: 0.45, blue: 0.38),  // brown
        Color(red: 0.20, green: 0.62, blue: 0.85),  // cyan
    ]

    static let projectHex = ["#4078F2", "#945CE6", "#E6548C", "#F28C33", "#21A3A3", "#4DA854", "#5C66D9", "#BF8C33", "#8C7361", "#339ED9"]

    static func project(_ i: Int) -> Color { projectColors[((i % projectColors.count) + projectColors.count) % projectColors.count] }

    static func status(_ s: TaskStatus) -> Color {
        switch s {
        case .backlog: return Color(nsColor: .tertiaryLabelColor)
        case .todo: return Color(red: 0.45, green: 0.50, blue: 0.60)
        case .inProgress: return Color(red: 0.22, green: 0.50, blue: 0.96)
        case .needsYou: return Color(red: 0.96, green: 0.55, blue: 0.12)
        case .done: return Color(red: 0.24, green: 0.66, blue: 0.36)
        }
    }

    static func priority(_ p: Priority) -> Color {
        switch p {
        case .none: return .secondary
        case .low: return Color(red: 0.45, green: 0.55, blue: 0.70)
        case .medium: return Color(red: 0.85, green: 0.65, blue: 0.10)
        case .high: return Color(red: 0.95, green: 0.45, blue: 0.15)
        case .urgent: return Color(red: 0.90, green: 0.20, blue: 0.20)
        }
    }
}

struct ProjectChip: View {
    let info: ProjectInfo
    var showWorkspace = false

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(Palette.project(info.colorIndex)).frame(width: 7, height: 7)
            Text(showWorkspace && info.workspace != info.name && info.workspace != "Other" ? "\(info.workspace) / \(info.name)" : info.name)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Palette.project(info.colorIndex).opacity(0.12), in: Capsule())
    }
}

struct StatusBadge: View {
    let status: TaskStatus
    var overridden = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbol)
            Text(status.title)
            if overridden {
                Image(systemName: "hand.point.up.left.fill").font(.system(size: 8)).help("Set by you")
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Palette.status(status))
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Palette.status(status).opacity(0.13), in: Capsule())
    }
}

struct PriorityIcon: View {
    let priority: Priority
    var body: some View {
        if priority != .none {
            Image(systemName: priority.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.priority(priority))
                .help("\(priority.title) priority")
        }
    }
}

/// Green dot for an open session; it pulses while Claude is busy. The pulse is a Core Animation
/// layer animation: it runs in the render server, so it costs no main-thread work or relayout
/// (a SwiftUI `repeatForever` animation here kept the app at ~25% CPU).
struct LiveDot: View {
    var busy: Bool

    var body: some View {
        PulseDot(busy: busy)
            .frame(width: 7, height: 7)
            .help(busy ? "Claude is working in this session now" : "Session open, idle")
            .accessibilityLabel(busy ? "Claude is working" : "Session open")
    }
}

private struct PulseDot: NSViewRepresentable {
    var busy: Bool
    func makeNSView(context: Context) -> PulseDotView { PulseDotView() }
    func updateNSView(_ v: PulseDotView, context: Context) { v.busy = busy }
}

final class PulseDotView: NSView {
    private let dot = CAShapeLayer()
    private let ring = CAShapeLayer()
    var busy = false { didSet { if busy != oldValue { refresh() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(ring)
        layer?.addSublayer(dot)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        for l in [dot, ring] {
            l.frame = bounds
            l.path = CGPath(ellipseIn: bounds, transform: nil)
        }
    }

    private func refresh() {
        let green = NSColor.systemGreen
        dot.fillColor = (busy ? green : green.withAlphaComponent(0.45)).cgColor
        ring.fillColor = nil
        ring.strokeColor = green.withAlphaComponent(0.6).cgColor
        ring.lineWidth = 1.5
        ring.removeAllAnimations()
        guard busy, ProcessInfo.processInfo.environment["CLAUDEBOARD_NO_PULSE"] == nil else {
            ring.opacity = 0
            return
        }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 2.2
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.4
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        ring.opacity = 0
        ring.add(group, forKey: "pulse")
    }
}

struct KeyLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct OriginIcon: View {
    let origin: TaskOrigin
    var body: some View {
        switch origin {
        case .manual: Image(systemName: "person.crop.circle").help("Your task, saved on this Mac")
        case .file: Image(systemName: "doc.text").help("Your task, saved as a file in a backlog folder")
        case .suggested: Image(systemName: "lightbulb").help("Follow-up Claude suggested")
        case .history: Image(systemName: "clock.arrow.circlepath").help("Recovered from prompt history (transcript cleaned up)")
        case .prompt: Image(systemName: "sparkle").help("Request you gave Claude")
        }
    }
}

enum Fmt {
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func ago(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "now" }
        return relative.localizedString(for: d, relativeTo: Date())
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h \(s % 3600 / 60)m" }
        return "\(s / 86_400)d \(s % 86_400 / 3600)h"
    }

    static let dayHeader: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

enum Markdown {
    /// Inline markdown (bold, code, links) with headings and line breaks kept as plain lines.
    static func inline(_ text: String) -> AttributedString {
        let cleaned = reflow(text).split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            if l.hasPrefix("#") { l = l.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) }
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") { l = "☑ " + t.dropFirst(6) }
            else if t.hasPrefix("- [ ] ") { l = "☐ " + t.dropFirst(6) }
            else if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            return l
        }.joined(separator: "\n")
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                           failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: cleaned, options: opts)) ?? AttributedString(cleaned)
    }

    /// Joins hard-wrapped lines into paragraphs; keeps lists, headings, tables, quotes and code as they are.
    static func reflow(_ text: String) -> String {
        var out: [String] = []
        var inCode = false
        func isBlock(_ l: String) -> Bool {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return true }
            if t.hasPrefix("#") || t.hasPrefix("|") || t.hasPrefix(">") || t.hasPrefix("```") || t.hasPrefix("- ") || t.hasPrefix("* ")
                || t.hasPrefix("+ ") || t.hasPrefix("• ") { return true }
            if let dot = t.firstIndex(of: "."), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty { return true }
            return l.hasPrefix("    ")
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inCode.toggle(); out.append(line); continue }
            if inCode { out.append(line); continue }
            if let last = out.last, !isBlock(line), !last.trimmingCharacters(in: .whitespaces).isEmpty,
               !last.trimmingCharacters(in: .whitespaces).hasPrefix("#"), !last.trimmingCharacters(in: .whitespaces).hasPrefix("|"),
               !last.hasSuffix("  "), !last.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            {
                out[out.count - 1] = last + " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    /// One-line plain preview with markdown syntax removed.
    static func plain(_ text: String, limit: Int = 240) -> String {
        var s = text.replacingOccurrences(of: "\n", with: " ")
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\*\*|__|`|#+ |\|)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return PromptText.truncate(s.trimmingCharacters(in: .whitespaces), limit)
    }
}

/// Selectable long text with a "show more" toggle.
struct ExpandableText: View {
    let text: String
    var limit = 700
    var font: Font = .body
    var markdown = false
    @State private var expanded = false

    var body: some View {
        let shown = expanded || text.count <= limit ? text : String(text.prefix(limit)) + "…"
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if markdown { Text(Markdown.inline(shown)) } else { Text(shown) }
            }
                .font(font)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if text.count > limit {
                Button(expanded ? "Show less" : "Show all (\(text.count) chars)") { expanded.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}
