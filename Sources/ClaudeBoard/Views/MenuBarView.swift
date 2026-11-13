import SwiftUI

struct MenuBarView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let needs = store.items.filter { $0.status == .needsYou && !$0.hidden }.prefix(6)
        let running = store.liveSessions.filter(\.isBusy)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ClaudeBoard").font(.headline)
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.mini) }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
            }

            group("Needs you", count: store.count(.inbox), color: Palette.status(.needsYou)) {
                if needs.isEmpty {
                    Text("Nothing waiting on you").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(needs)) { t in row(t) }
            }

            group("Claude working now", count: running.count, color: Palette.status(.inProgress)) {
                if running.isEmpty {
                    Text("No session is busy").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(running) { s in
                    HStack(spacing: 6) {
                        LiveDot(busy: true)
                        Text(s.title).lineLimit(1)
                        Spacer()
                        Text(store.project(s.projectID).name).font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }

            Divider()
            HStack {
                Button("Open Board") { open(nil) }
                Button("New Task…") {
                    open(nil)
                    store.showNewTask = true
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { store.start() }
    }

    private func row(_ t: TaskItem) -> some View {
        Button { open(t.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    KeyLabel(text: store.key(for: t))
                    Text(t.title).lineLimit(1)
                }
                if let ask = t.pendingAsk ?? store.session(t.sessionID)?.needsAction {
                    Text(ask).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
    }

    private func group<C: View>(_ title: String, count: Int, color: Color, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            c()
        }
    }

    private func open(_ id: String?) {
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
    var body: some View {
        let n = store.count(.inbox)
        HStack(spacing: 3) {
            Image(systemName: n > 0 ? "checklist.unchecked" : "checklist")
            if n > 0 { Text("\(n)") }
        }
    }
}
