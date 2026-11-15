import SwiftUI

/// What ClaudeBoard found in the user's Claude history. Shown once right after onboarding (the
/// first "aha"), and any time from Help → What ClaudeBoard Found.
struct DiscoveryStats: Equatable {
    struct Top: Equatable {
        var id: String
        var name: String
        var colorIndex: Int
        var count: Int
    }

    var requests = 0
    var sessions = 0
    var projects = 0
    var since: Date?
    var waiting = 0
    var running = 0
    var busy = 0
    var plannedOpen = 0
    var top: [Top] = []

    static func compute(items: [TaskItem], sessions: [SessionInfo], project: (String) -> ProjectInfo) -> DiscoveryStats {
        var s = DiscoveryStats()
        let claude = items.filter { !$0.hidden && !$0.origin.isPlanned && $0.origin != .suggested }
        s.requests = claude.count
        s.sessions = Set(claude.compactMap(\.sessionID)).count
        s.projects = Set(claude.map(\.projectID)).count
        s.since = claude.map(\.createdAt).min()
        // Sessions, not tickets: one session can only wait on one question at a time.
        let waiting = claude.filter { $0.status == .needsYou }
        s.waiting = Set(waiting.map { $0.sessionID ?? $0.id }).count
        s.running = sessions.filter(\.isLive).count
        s.busy = sessions.filter(\.isBusy).count
        s.plannedOpen = items.filter { $0.origin.isPlanned && $0.status.isOpen && !$0.hidden }.count
        s.top = Dictionary(grouping: claude, by: \.projectID)
            .map { id, ts in
                let p = project(id)
                return Top(id: id, name: p.name, colorIndex: p.colorIndex, count: ts.count)
            }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(3).map { $0 }
        return s
    }
}

struct DiscoverySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = DiscoveryStats()
    @State private var revealed = false
    /// One-way: set once a refresh has finished while the sheet is up (or before it opened), so the
    /// 20-second background refresh never flips the sheet back to its loading state.
    @State private var ready = false

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return f
    }()

    private var loading: Bool { !ready }

    var body: some View {
        let stats = DiscoveryStats.compute(items: store.items, sessions: Array(store.sessions.values), project: store.project)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loading ? "Reading your Claude Code history…" : "Here's what ClaudeBoard found")
                        .font(.title2.weight(.semibold))
                    Text(loading ? "Transcripts, prompt history and running sessions, all on this Mac."
                                 : "Everything below comes from Claude Code's files on this Mac. Nothing left it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(.bottom, 22)

            if !loading && stats.requests == 0 {
                empty
            } else {
                found(stats)
            }
        }
        .padding(26)
        .frame(width: 640)
        .onAppear {
            if store.lastRefresh != nil && !store.isRefreshing { ready = true }
            reveal(stats)
        }
        .onChange(of: store.lastRefresh) { _, _ in
            ready = true
            reveal(DiscoveryStats.compute(items: store.items, sessions: Array(store.sessions.values), project: store.project))
        }
    }

    private func reveal(_ stats: DiscoveryStats) {
        guard !loading, stats.requests > 0, !revealed || stats != shown else { return }
        if reduceMotion || revealed {
            shown = stats
        } else {
            withAnimation(.easeOut(duration: 1.2)) { shown = stats }
        }
        revealed = true
    }

    @ViewBuilder
    private func found(_ stats: DiscoveryStats) -> some View {
        let n = { (v: Int) in Self.number.string(from: NSNumber(value: v)) ?? "\(v)" }
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(n(shown.requests))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(shown.requests)))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.86, green: 0.47, blue: 0.33), Color(red: 0.55, green: 0.30, blue: 0.62)],
                                                    startPoint: .leading, endPoint: .trailing))
                Text(stats.since.map { "requests you've given Claude since \(Self.day.string(from: $0))" } ?? "requests you've given Claude")
                    .font(.title3).foregroundStyle(.secondary)
            }
            .redacted(reason: loading ? .placeholder : [])

            HStack(spacing: 12) {
                tile(n(shown.sessions), "sessions")
                tile(n(shown.projects), "projects")
                tile(n(shown.running), shown.busy > 0 ? "open now, \(shown.busy) busy" : "open now")
                tile(n(shown.plannedOpen), "planned tasks")
            }
            .redacted(reason: loading ? .placeholder : [])

            if !loading && stats.waiting > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.bubble.fill").font(.title3).foregroundStyle(Palette.status(.needsYou))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(stats.waiting == 1 ? "1 session is waiting on you right now." : "\(stats.waiting) sessions are waiting on you right now.")
                            .font(.headline)
                        Text(stats.waiting == 1 ? "Claude finished its turn with a question for you."
                                                : "Claude finished its turn with a question in each of them.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Palette.status(.needsYou).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            if !loading && !stats.top.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Where most of your work went").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(stats.top, id: \.id) { t in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(Palette.project(t.colorIndex)).frame(width: 10, height: 10)
                            Text(t.name).font(.callout.weight(.medium))
                            Spacer()
                            Text("\(n(t.count)) requests").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                if stats.waiting > 0 {
                    Button { go(.inbox, .board) } label: { Text("Show me what needs me") }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button { go(.all, .board) } label: { Text("Open the board") }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
                Button { go(.all, .plan) } label: { Text("Plan my projects") }
                Spacer()
                Button("Take the tour") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.showGuide = true }
                }
                .buttonStyle(.link)
            }
            .disabled(loading)
            .padding(.top, 4)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No Claude Code sessions yet")
                .font(.title3.weight(.semibold))
            Text("Start Claude Code in any project folder (the CLI or the desktop app's Code tab). Your requests show up here within 20 seconds. Meanwhile, plan your projects' tasks or look around the demo board.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { go(.all, .plan) } label: { Text("Plan my projects") }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                if !Demo.isOn {
                    Button("Try the Demo Board") { DemoLauncher.open() }
                }
                Spacer()
                Button("Take the tour") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.showGuide = true }
                }
                .buttonStyle(.link)
            }
        }
    }

    private func go(_ scope: SidebarItem, _ mode: ViewMode) {
        store.sidebar = scope
        store.mode = mode
        store.selection = scope == .inbox ? store.items.first { $0.status == .needsYou && !$0.hidden }?.id : nil
        store.showInspector = scope == .inbox
        dismiss()
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}
