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
        // Agents' questions first (they can be answered right away), then your blocked tasks; oldest first.
        let all = store.waitingOnYou
        let needs = Array(all.sorted { ($0.origin.isPlanned ? 1 : 0, $0.lastActivity) < ($1.origin.isPlanned ? 1 : 0, $1.lastActivity) }.prefix(4))
        let live = store.liveSessions
        let busy = live.filter(\.isBusy)
        VStack(alignment: .leading, spacing: 0) {
            header(waiting: all.count)
            VStack(alignment: .leading, spacing: 12) {
                if store.notificationsAllowed == false && Notifier.kinds.contains(.needsYou) {
                    notificationsOff
                }
                if needs.isEmpty {
                    allClear(open: live.count)
                } else {
                    ForEach(needs) { t in card(t) }
                    if all.count > needs.count {
                        Button("Show all \(all.count) in Needs you") { store.sidebar = .inbox; store.mode = .board; open(nil) }
                            .buttonStyle(.studio(.quiet, size: 12))
                    }
                }
                if !busy.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Working now · \(busy.count)").font(Studio.text(13.5, .heavy)).foregroundStyle(Studio.ink)
                        ForEach(busy.prefix(4)) { s in
                            HStack(spacing: 8) {
                                LiveDot(busy: true)
                                Text(s.title).font(Studio.text(13, .semibold)).foregroundStyle(Studio.ink).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(s.agentKind.title).font(Studio.text(12, .bold)).foregroundStyle(Studio.ink2).lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            footer
        }
        .frame(width: 390)
        .fixedSize(horizontal: false, vertical: true)
        .background(Studio.surface)
        .onAppear { store.start(); Notifier.shared.refreshAuthorization() }
    }

    // MARK: Parts

    private func header(waiting: Int) -> some View {
        HStack(spacing: 8) {
            Text(waiting > 0 ? "Your turn" : "All clear").font(Studio.display(18)).foregroundStyle(waiting > 0 ? Studio.coralInk : Studio.ink)
            if waiting > 0 {
                Text("\(waiting)").font(Studio.text(13, .heavy).monospacedDigit()).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 1)
                    .background(Capsule().fill(Studio.coral))
            }
            Spacer()
            if store.isRefreshing { ProgressView().controlSize(.mini) }
            Button("Open the board") { open(nil) }
                .buttonStyle(.plain)
                .font(Studio.text(12.5, .heavy))
                .foregroundStyle(Studio.ink)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func card(_ t: TaskItem) -> some View {
        let p = store.project(t.projectID)
        let agent = store.session(t.sessionID)?.agentKind ?? t.agentKind
        let question = t.origin.isPlanned ? "Your task is marked blocked."
            : (store.session(t.sessionID)?.needsAction ?? StatusChanges.question(of: t))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if let agent { AgentAvatar(agent: agent, size: 18) }
                Text([agent?.title, p.name, store.key(for: t)].compactMap { $0 }.joined(separator: " · "))
                    .font(Studio.text(12, .bold)).foregroundStyle(Studio.ink2).lineLimit(1)
                Spacer(minLength: 6)
                Text(Self.ago.localizedString(for: t.lastActivity, relativeTo: Date()))
                    .font(Studio.text(12, .bold)).foregroundStyle(Studio.coralInk)
            }
            Text(Markdown.plain(question, limit: 160)).font(Studio.text(14, .bold)).foregroundStyle(Studio.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if t.sessionID != nil && !t.origin.isPlanned {
                    let a = agent ?? .claudeCode
                    Button(a.runsInTerminal ? "Answer in Terminal" : "Open \(a.title)") { store.resume(t.id) }
                        .buttonStyle(.studio(.primary, size: 12))
                }
                Button("Show on the board") { open(t.id) }.buttonStyle(.studio(.white, size: 12))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.tint(p.colorIndex)))
    }

    private func allClear(open: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Nothing is waiting on you").font(Studio.text(14, .heavy)).foregroundStyle(Studio.doneInk)
            Text(open == 0 ? "Start an agent in any project and its work shows up here."
                           : "You'll get a nudge when an agent needs an answer.")
                .font(Studio.text(12.5, .medium)).foregroundStyle(Studio.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Studio.doneBg))
    }

    private var notificationsOff: some View {
        HStack(spacing: 8) {
            Text("Notifications are off for this app").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink)
            Spacer()
            Button("Turn on") { Notifier.openSystemSettings() }.buttonStyle(.studio(.white, size: 11.5))
        }
        .studioWell(radius: 14, padding: 10)
    }

    /// Today at a glance; opens the Worklog.
    private var today: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let asked = store.items.filter { ($0.origin == .prompt || $0.origin == .history) && !$0.hidden && $0.createdAt >= start }
        let done = asked.filter { $0.status == .done }.count
        return Button {
            store.sidebar = .all
            store.mode = .worklog
            open(nil)
        } label: {
            Text("Today: \(asked.count) request\(asked.count == 1 ? "" : "s"), \(done) done")
                .font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
        }
        .buttonStyle(.plain)
        .help("Open the Worklog")
    }

    static func duration(_ s: Double) -> String {
        let m = Int(s / 60)
        return m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
    }

    private var footer: some View {
        HStack(spacing: 8) {
            today
            Spacer()
            CircleIconButton(symbol: "plus", help: "New task") {
                open(nil)
                store.showNewTask = true
            }
            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Studio.surface))
                    .overlay(Circle().stroke(Studio.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Settings")
            CircleIconButton(symbol: "power", help: "Quit") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Studio.well)
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
        let n = store.waitingOnYou.count
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
