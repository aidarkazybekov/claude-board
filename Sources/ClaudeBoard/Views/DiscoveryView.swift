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
        HStack(alignment: .center, spacing: 32) {
            VStack(alignment: .leading, spacing: 20) {
                Text(loading ? "Reading your agents' history…" : stats.requests == 0 ? "Nothing to show yet." : "Your agents are already here.")
                    .font(Studio.display(40)).foregroundStyle(Studio.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(loading ? "Sessions, prompts and running work from the coding agents on this Mac."
                     : "We read the history your coding agents keep on this Mac and put every task on one board, project by project. Nothing was changed, and nothing left your Mac.")
                    .font(Studio.text(15, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
                if !loading && stats.requests == 0 {
                    empty
                } else {
                    found(stats)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            agentsCard(stats)
                .frame(width: 400)
        }
        .padding(34)
        .frame(width: 1060)
        .background(Studio.ground)
        .onAppear {
            if store.lastRefresh != nil && !store.isRefreshing { ready = true }
            reveal(stats)
        }
        .onChange(of: store.lastRefresh) { _, _ in
            ready = true
            reveal(DiscoveryStats.compute(items: store.items, sessions: Array(store.sessions.values), project: store.project))
        }
    }

    private func agentsCard(_ stats: DiscoveryStats) -> some View {
        let n = { (v: Int) in Self.number.string(from: NSNumber(value: v)) ?? "\(v)" }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Found on this Mac").font(Studio.display(17)).foregroundStyle(Studio.ink)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            ForEach(Agent.allCases) { a in
                let st = store.agentStats(a)
                let present = FileManager.default.fileExists(atPath: Paths.data(for: a))
                HStack(spacing: 12) {
                    AgentAvatar(agent: a, size: 30).opacity(present ? 1 : 0.35)
                    Text(a.title).font(Studio.text(14, .heavy)).foregroundStyle(present ? Studio.ink : Studio.muted)
                    Spacer()
                    Text(!present ? "Not installed" : st.sessions > 0 ? "\(n(st.sessions)) session\(st.sessions == 1 ? "" : "s")" : (a == .claudeCode || a == .codex) ? "No sessions yet" : "Found")
                        .font(Studio.text(13, .bold)).foregroundStyle(present ? Studio.ink2 : Studio.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.well))
            }
            HStack(spacing: 10) {
                miniTile(n(shown.projects), "projects", tint: Studio.blueBg)
                miniTile(n(shown.plannedOpen), "planned tasks", tint: Studio.doneBg)
            }
            if !loading && !stats.top.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Where most of your work went").font(Studio.text(13, .heavy)).foregroundStyle(Studio.ink)
                    ForEach(stats.top, id: \.id) { t in
                        HStack(spacing: 8) {
                            ProjectDot(colorIndex: t.colorIndex, size: 10)
                            Text(t.name).font(Studio.text(13, .bold)).foregroundStyle(Studio.ink)
                            Spacer()
                            Text("\(n(t.count)) requests").font(Studio.text(13, .semibold).monospacedDigit()).foregroundStyle(Studio.ink2)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .studioCard(radius: 26, padding: 20)
    }

    private func miniTile(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Studio.display(24)).foregroundStyle(Studio.ink).contentTransition(.numericText())
            Text(label).font(Studio.text(12, .bold)).foregroundStyle(Studio.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint))
        .redacted(reason: loading ? .placeholder : [])
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
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(n(shown.requests))
                        .font(Studio.display(58))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown.requests)))
                    Text(stats.since.map { "requests since \(Self.day.string(from: $0))" } ?? "requests")
                        .font(Studio.text(13.5, .bold)).foregroundStyle(Studio.onInk.opacity(0.75))
                }
                .foregroundStyle(Studio.onInk)
                .frame(minWidth: 190, alignment: .leading)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Studio.ink))
                .redacted(reason: loading ? .placeholder : [])

                if !loading && stats.waiting > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stats.waiting == 1 ? "1 agent is waiting on you" : "\(stats.waiting) agents are waiting on you")
                            .font(Studio.display(20)).foregroundStyle(Studio.coralInk)
                        Text("They finished their turn with a question. They're first on the board.")
                            .font(Studio.text(13, .semibold)).foregroundStyle(Studio.coralInk.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Studio.coralBg))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(n(shown.sessions)) sessions, \(n(shown.running)) open now").font(Studio.display(20)).foregroundStyle(Studio.ink)
                        Text(shown.busy > 0 ? "\(shown.busy) busy right now." : "Nothing is waiting on you.").font(Studio.text(13, .semibold)).foregroundStyle(Studio.ink2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Studio.surface))
                    .redacted(reason: loading ? .placeholder : [])
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if stats.waiting > 0 {
                    Button("Show me what needs me") { go(.inbox, .board) }
                        .buttonStyle(.studio(.primary, size: 14)).keyboardShortcut(.defaultAction)
                } else {
                    Button("Open the board") { go(.all, .board) }
                        .buttonStyle(.studio(.primary, size: 14)).keyboardShortcut(.defaultAction)
                }
                Button("Plan my projects") { go(.all, .plan) }.buttonStyle(.studio(.white, size: 14))
                Button("Take the tour") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.showGuide = true }
                }
                .buttonStyle(.studio(.quiet, size: 14))
            }
            .disabled(loading)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Start Claude Code, Codex or another agent in any project folder. Its requests show up here within a few seconds. Meanwhile, plan your projects' tasks or look around the demo.")
                .font(Studio.text(14, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Plan my projects") { go(.all, .plan) }
                    .buttonStyle(.studio(.primary, size: 14)).keyboardShortcut(.defaultAction)
                if !Demo.isOn {
                    Button("Try the demo") { DemoLauncher.open() }.buttonStyle(.studio(.white, size: 14))
                }
                Button("Take the tour") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.showGuide = true }
                }
                .buttonStyle(.studio(.quiet, size: 14))
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
}
