import AppKit
import SwiftUI

/// "Share your week": a branded recap card of your work with Claude, made to be posted.
/// Privacy first: no prompt text ever, and project names stay hidden unless you turn them on.
struct WeekSummary: Equatable {
    struct ProjectCount: Equatable {
        var name: String
        var colorIndex: Int
        var count: Int
    }

    var start: Date
    var end: Date
    var requests = 0
    var followUps = 0
    var activeSeconds: Double = 0
    var toolCalls = 0
    var files = 0
    var done = 0
    var busiestDay: Date?
    var busiestCount = 0
    var projects: [ProjectCount] = []
    /// Agents that did the work, busiest first.
    var agents: [Agent] = []

    /// Agent tickets created in `[start, end)`. Planned tasks and suggestions don't count as requests.
    static func compute(items: [TaskItem], project: (String) -> ProjectInfo, start: Date, end: Date) -> WeekSummary {
        var s = WeekSummary(start: start, end: end)
        let cal = Calendar.current
        let tickets = items.filter { !$0.origin.isPlanned && $0.origin != .suggested && $0.createdAt >= start && $0.createdAt < end }
        s.requests = tickets.count
        s.followUps = tickets.reduce(0) { $0 + $1.followUps.count }
        s.activeSeconds = tickets.reduce(0) { $0 + ($1.stats.activeSeconds ?? 0) }
        s.toolCalls = tickets.reduce(0) { $0 + $1.stats.toolCalls }
        s.files = Set(tickets.flatMap(\.stats.filesTouched)).count
        s.done = tickets.filter { $0.status == .done }.count
        let byDay = Dictionary(grouping: tickets) { cal.startOfDay(for: $0.createdAt) }
        if let top = byDay.max(by: { ($0.value.count, $1.key) < ($1.value.count, $0.key) }) {
            s.busiestDay = top.key
            s.busiestCount = top.value.count
        }
        s.projects = Dictionary(grouping: tickets, by: \.projectID)
            .map { id, ts in
                let info = project(id)
                return ProjectCount(name: info.name, colorIndex: info.colorIndex, count: ts.count)
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        s.agents = Dictionary(grouping: tickets) { $0.agentKind ?? .claudeCode }
            .sorted { ($0.value.count, $1.key.rawValue) > ($1.value.count, $0.key.rawValue) }.map(\.key)
        return s
    }
}

enum SharePeriod: String, CaseIterable, Identifiable {
    case week, thisWeek, month
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: return "Last 7 days"
        case .thisWeek: return "This week"
        case .month: return "Last 30 days"
        }
    }
    var heading: String {
        switch self {
        case .week, .thisWeek: return "My week with AI agents"
        case .month: return "My month with AI agents"
        }
    }
    func range(now: Date = Date()) -> (Date, Date) {
        let cal = Calendar.current
        switch self {
        case .week: return (cal.startOfDay(for: now).addingTimeInterval(-6 * 86_400), now.addingTimeInterval(1))
        case .thisWeek: return (cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now, now.addingTimeInterval(1))
        case .month: return (cal.startOfDay(for: now).addingTimeInterval(-29 * 86_400), now.addingTimeInterval(1))
        }
    }
}

/// The card itself: 540x540 pt, rendered at 2x into a 1080x1080 PNG.
struct WeekCard: View {
    let summary: WeekSummary
    let heading: String
    let showProjects: Bool

    private static let range: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()
    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()

    var body: some View {
        let s = summary
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                Text("ClaudeBoard").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Self.range.string(from: s.start)) – \(Self.range.string(from: s.end.addingTimeInterval(-1)))")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Color(hex: 0xC9CCD8))

            Spacer(minLength: 14)
            Text(heading).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Color(hex: 0xC9CCD8))
            Text("\(s.requests)").font(.system(size: 108, weight: .heavy, design: .rounded)).monospacedDigit()
                .tracking(-4)
                .padding(.top, -4)
            Text("\(s.requests == 1 ? "request" : "requests"), \(s.done) done").font(.system(size: 20, weight: .heavy, design: .rounded))
                .padding(.top, -6)

            HStack(spacing: 10) {
                tile(Fmt.duration(s.activeSeconds), "agent time", 0xEAF1FE)
                tile("\(s.toolCalls)", "tool calls", 0xF1EDFD)
                tile("\(s.files)", s.files == 1 ? "file edited" : "files edited", 0xE7F8F3)
            }
            .padding(.top, 18)

            Text(sentence(s))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xE3E5EC))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Spacer(minLength: 14)
            HStack {
                Text("aidarkazybekov.github.io/claude-board").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xC9CCD8))
                Spacer()
                Text("Free for Mac").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0x14161F))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(.white))
            }
        }
        .padding(34)
        .foregroundStyle(.white)
        .frame(width: 540, height: 540)
        .background(Color(hex: 0x14161F))
        .environment(\.colorScheme, .dark)
    }

    private func sentence(_ s: WeekSummary) -> String {
        var parts: [String] = []
        if let day = s.busiestDay, s.busiestCount > 1 { parts.append("Busiest day: \(Self.weekday.string(from: day)), \(s.busiestCount) requests.") }
        var with = ""
        if !s.agents.isEmpty {
            let names = s.agents.map(\.title)
            with = "With " + (names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!)
        }
        if showProjects, !s.projects.isEmpty {
            let top = s.projects.prefix(3).map { "\($0.name) \($0.count)" }.joined(separator: ", ")
            parts.append((with.isEmpty ? "" : with + ", in ") + top + ".")
        } else if !s.projects.isEmpty {
            parts.append((with.isEmpty ? "" : with + ", ") + (s.projects.count == 1 ? "in 1 project." : "across \(s.projects.count) projects."))
        } else if !with.isEmpty {
            parts.append(with + ".")
        }
        return parts.joined(separator: " ")
    }

    private func tile(_ value: String, _ label: String, _ bg: UInt32) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(hex: 0x3E4252))
        }
        .foregroundStyle(Color(hex: 0x14161F))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: bg)))
    }
}

/// Renders a card view to a 1080x1080 image.
@MainActor
enum CardRenderer {
    static func image(_ card: WeekCard) -> NSImage? {
        let r = ImageRenderer(content: card)
        r.scale = 2
        return r.nsImage
    }

    static func png(_ card: WeekCard) -> Data? {
        guard let img = image(card), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

struct ShareWeekSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var period: SharePeriod = .week
    @AppStorage("shareShowProjects") private var showProjects = false
    @State private var copied = false

    var body: some View {
        let (start, end) = period.range()
        let summary = WeekSummary.compute(items: store.visibleItems, project: store.project, start: start, end: end)
        let card = WeekCard(summary: summary, heading: period.heading, showProjects: showProjects)
        HStack(alignment: .top, spacing: 26) {
            card
                .scaleEffect(0.86, anchor: .topLeading)
                .frame(width: 540 * 0.86, height: 540 * 0.86, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 16) {
                Text("Share your week").font(Studio.display(24)).foregroundStyle(Studio.ink)
                Text("A picture of what your agents did. It counts agent requests only, not your own tasks. Prompts are never included.")
                    .font(Studio.text(13.5, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Period").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
                    PillTabs(selection: $period, items: SharePeriod.allCases.map { ($0, $0.title) }, size: 12)
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show project names").font(Studio.text(13.5, .bold)).foregroundStyle(Studio.ink)
                        Text("Off by default, so client and repo names stay private.").font(Studio.text(12, .medium)).foregroundStyle(Studio.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("Show project names", isOn: $showProjects).toggleStyle(.switch).labelsHidden().tint(Studio.ink)
                }
                .studioWell(radius: 16, padding: 12)
                if summary.requests == 0 {
                    Text("No agent requests in this period yet.").font(Studio.text(12.5, .semibold)).foregroundStyle(Studio.muted)
                }
                Spacer(minLength: 6)
                VStack(spacing: 8) {
                    if let img = CardRenderer.image(card) {
                        ShareLink(item: Image(nsImage: img), preview: SharePreview(period.heading, image: Image(nsImage: img))) {
                            Text("Share…").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.studio(.primary, size: 14))
                    }
                    HStack(spacing: 8) {
                        Button {
                            if let img = CardRenderer.image(card) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.writeObjects([img])
                                copied = true
                            }
                        } label: { Text(copied ? "Copied" : "Copy image").frame(maxWidth: .infinity) }
                            .buttonStyle(.studio(.secondary))
                        Button { save(card) } label: { Text("Save PNG…").frame(maxWidth: .infinity) }
                            .buttonStyle(.studio(.secondary))
                    }
                    Button("Done") { dismiss() }.buttonStyle(.studio(.quiet)).keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 380)
        }
        .padding(26)
        .background(Studio.surface)
        .onChange(of: period) { _, _ in copied = false }
        .onChange(of: showProjects) { _, _ in copied = false }
    }

    private func save(_ card: WeekCard) {
        guard let data = CardRenderer.png(card) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "agents-week-\(df.string(from: Date())).png"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}
