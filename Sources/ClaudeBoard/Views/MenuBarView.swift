import SwiftUI

struct MenuBarView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow

    private static let ago: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        // Claude's questions first (they can be answered right here), then your blocked tasks; newest first.
        let needs = Array(store.items.filter { $0.status == .needsYou && !$0.hidden }
            .sorted { ($0.origin.isPlanned ? 1 : 0, $1.lastActivity) < ($1.origin.isPlanned ? 1 : 0, $0.lastActivity) }.prefix(4))
        let waiting = store.count(.inbox)
        let live = store.liveSessions
        let busy = live.filter(\.isBusy)
        VStack(alignment: .leading, spacing: 0) {
            header(open: live.count, busy: busy.count)
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                if store.notificationsAllowed == false && Notifier.kinds.contains(.needsYou) {
                    notificationsOff
                }
                if needs.isEmpty {
                    allClear(open: live.count)
                } else {
                    section("Waiting on you", count: waiting, color: Palette.status(.needsYou)) {
                        ForEach(needs) { t in card(t) }
                        if waiting > needs.count {
                            Button("Show all \(waiting) in Needs You") { store.sidebar = .inbox; store.mode = .board; open(nil) }
                                .buttonStyle(.link).font(.caption)
                        }
                    }
                }
                if !busy.isEmpty {
                    section("Working now", count: busy.count, color: Palette.status(.inProgress)) {
                        ForEach(busy.prefix(4)) { s in
                            HStack(spacing: 8) {
                                LiveDot(busy: true)
                                Text(s.title).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(store.project(s.projectID).name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .font(.callout)
                        }
                    }
                }
                today
            }
            .padding(14)
            Divider()
            footer
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { store.start(); Notifier.shared.refreshAuthorization() }
    }

    // MARK: Parts

    private func header(open: Int, busy: Int) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text("ClaudeBoard").font(.headline)
                Text(open == 0 ? "No Claude session open" : "\(open) open · \(busy) busy")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isRefreshing { ProgressView().controlSize(.mini) }
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh now")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func card(_ t: TaskItem) -> some View {
        let p = store.project(t.projectID)
        let question = t.origin.isPlanned ? "Your task is marked blocked."
            : (store.session(t.sessionID)?.needsAction ?? StatusChanges.question(of: t))
        return VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    KeyLabel(text: store.key(for: t))
                    Text(p.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(Self.ago.localizedString(for: t.lastActivity, relativeTo: Date()))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(t.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(question).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if t.sessionID != nil && !t.origin.isPlanned {
                        Button { store.resume(t.id) } label: { Label("Resume", systemImage: "terminal") }
                            .buttonStyle(.borderedProminent).help("Answer in Terminal (claude --resume)")
                    }
                    Button("Open") { open(t.id) }
                }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.leading, 13)
        // The project color as a thin bar that always matches the card's height.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(Palette.project(p.colorIndex)).frame(width: 3)
        }
        .padding(10)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func allClear(open: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Palette.status(.done))
            VStack(alignment: .leading, spacing: 1) {
                Text("Nothing is waiting on you").font(.callout.weight(.medium))
                Text(open == 0 ? "Start Claude Code in any project and it shows up here."
                               : "Claude will tap you when a session needs an answer.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var notificationsOff: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash").foregroundStyle(.secondary)
            Text("Notifications are off for ClaudeBoard").font(.caption)
            Spacer()
            Button("Turn On") { Notifier.openSystemSettings() }.controlSize(.small)
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Today at a glance; opens the Worklog.
    private var today: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let asked = store.items.filter { ($0.origin == .prompt || $0.origin == .history) && !$0.hidden && $0.createdAt >= start }
        let done = asked.filter { $0.status == .done }.count
        let seconds = asked.reduce(0.0) { $0 + ($1.stats.activeSeconds ?? 0) }
        return Button {
            store.sidebar = .all
            store.mode = .worklog
            open(nil)
        } label: {
            HStack(spacing: 14) {
                stat("\(asked.count)", asked.count == 1 ? "request today" : "requests today")
                stat("\(done)", "done")
                stat(Self.duration(seconds), "Claude time")
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the Worklog")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    static func duration(_ s: Double) -> String {
        let m = Int(s / 60)
        return m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Open Board") { open(nil) }
            Button("New Task…") {
                open(nil)
                store.showNewTask = true
            }
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }.help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit ClaudeBoard")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func section<C: View>(_ title: String, count: Int, color: Color, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            c()
        }
    }

    private func open(_ id: String?) {
        Startup.quietHandled = true
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        if let id, let t = store.task(id) {
            store.sidebar = .project(t.projectID)
            store.selection = id
            store.showInspector = true
        }
    }
}

struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        let n = store.count(.inbox)
        HStack(spacing: 3) {
            Image(systemName: n > 0 ? "checklist.unchecked" : "checklist")
            if n > 0 { Text("\(n)") }
        }
        // The label is alive even with every window closed, so it reopens the board for notification clicks.
        .onChange(of: store.openMainRequest) { _, _ in
            Startup.quietHandled = true
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
