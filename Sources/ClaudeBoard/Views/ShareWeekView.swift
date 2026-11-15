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

    /// Claude tickets created in `[start, end)`. Planned tasks and suggestions don't count as requests.
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
        case .week, .thisWeek: return "My week with Claude"
        case .month: return "My month with Claude"
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
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.80, green: 0.42, blue: 0.32), Color(red: 0.45, green: 0.25, blue: 0.55),
                                    Color(red: 0.14, green: 0.15, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.18), .clear], center: .topTrailing, startRadius: 10, endRadius: 360)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                    Text("ClaudeBoard").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Text("\(Self.range.string(from: s.start)) - \(Self.range.string(from: s.end.addingTimeInterval(-1)))")
                        .font(.system(size: 14, weight: .medium)).opacity(0.85)
                }

                Spacer(minLength: 18)
                Text(heading).font(.system(size: 22, weight: .semibold)).opacity(0.9)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(s.requests)").font(.system(size: 104, weight: .bold, design: .rounded)).monospacedDigit()
                    Text(s.requests == 1 ? "request" : "requests").font(.system(size: 28, weight: .semibold)).opacity(0.9)
                }
                .padding(.top, -4)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        tile(Fmt.duration(s.activeSeconds), "Claude active time")
                        tile("\(s.toolCalls)", "tool calls")
                    }
                    GridRow {
                        tile("\(s.files)", s.files == 1 ? "file edited" : "files edited")
                        tile("\(s.done)", "done")
                    }
                }
                .padding(.top, 14)

                VStack(alignment: .leading, spacing: 6) {
                    if let day = s.busiestDay, s.busiestCount > 1 {
                        Text("Busiest day: \(Self.weekday.string(from: day)), \(s.busiestCount) requests")
                    }
                    if showProjects, !s.projects.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(Array(s.projects.prefix(3).enumerated()), id: \.offset) { _, p in
                                HStack(spacing: 5) {
                                    RoundedRectangle(cornerRadius: 2).fill(Palette.project(p.colorIndex)).frame(width: 9, height: 9)
                                    Text("\(p.name) \(p.count)").lineLimit(1)
                                }
                            }
                        }
                    } else if !s.projects.isEmpty {
                        Text(s.projects.count == 1 ? "In 1 project" : "Across \(s.projects.count) projects")
                    }
                }
                .font(.system(size: 15, weight: .medium))
                .opacity(0.9)
                .padding(.top, 16)

                Spacer(minLength: 16)
                HStack {
                    Text("aidarkazybekov.github.io/claude-board").font(.system(size: 13, weight: .medium)).opacity(0.75)
                    Spacer()
                    Text("Free for Mac").font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            .padding(34)
        }
        .foregroundStyle(.white)
        .frame(width: 540, height: 540)
        .environment(\.colorScheme, .dark)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 13, weight: .medium)).opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
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
        let summary = WeekSummary.compute(items: store.items.filter { !$0.hidden }, project: store.project, start: start, end: end)
        let card = WeekCard(summary: summary, heading: period.heading, showProjects: showProjects)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Share your week").font(.title3.weight(.semibold))
                Spacer()
                Picker("Period", selection: $period) {
                    ForEach(SharePeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            HStack(alignment: .top, spacing: 20) {
                card
                    .scaleEffect(0.74, anchor: .topLeading)
                    .frame(width: 400, height: 400, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show project names", isOn: $showProjects)
                    Text("Off by default: project names can reveal client or private work. Prompts are never included.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    if let img = CardRenderer.image(card) {
                        ShareLink(item: Image(nsImage: img), preview: SharePreview(period.heading, image: Image(nsImage: img))) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button {
                        if let img = CardRenderer.image(card) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                            copied = true
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy Image", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        save(card)
                    } label: {
                        Label("Save PNG…", systemImage: "arrow.down.doc")
                    }
                    Spacer()
                    if summary.requests == 0 {
                        Text("No Claude requests in this period yet.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onChange(of: period) { _, _ in copied = false }
        .onChange(of: showProjects) { _, _ in copied = false }
    }

    private func save(_ card: WeekCard) {
        guard let data = CardRenderer.png(card) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "claude-week-\(df.string(from: Date())).png"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}
