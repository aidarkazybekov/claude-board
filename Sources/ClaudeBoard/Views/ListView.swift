import SwiftUI

struct ListView: View {
    @Environment(Store.self) private var store
    @State private var sortOrder = [KeyPathComparator(\Row.updated, order: .reverse)]
    @State private var statusFilter: TaskStatus?

    struct Row: Identifiable {
        let id: String
        let key: String
        let number: Int
        let title: String
        let status: TaskStatus
        let statusRank: Int
        let priority: Int
        let project: String
        let projectColor: Int
        let session: String
        let agent: String
        let created: Date
        let updated: Date
        let steps: String
        let followUps: Int
        let tools: Int
        let task: TaskItem
    }

    static let statusItems: [(TaskStatus?, String)] = [(nil, "Any status")] + TaskStatus.allCases.map { (Optional($0), $0.title) }

    var body: some View {
        @Bindable var store = store
        let rows = makeRows()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(rows.count) ticket\(rows.count == 1 ? "" : "s"), newest activity first")
                    .font(Studio.text(13.5, .semibold)).foregroundStyle(Studio.ink2)
                Spacer()
                PillTabs(selection: $statusFilter, items: Self.statusItems, size: 12)
            }
            Table(rows, selection: $store.selection, sortOrder: $sortOrder) {
                Group {
                    TableColumn("Key", value: \Row.number) { (r: Row) in ListCell.key(r.key) }
                        .width(min: 60, ideal: 76, max: 110)
                    TableColumn("Title", value: \Row.title) { (r: Row) in ListCell.title(r.title, hidden: r.task.hidden) }
                        .width(min: 220, ideal: 420)
                    TableColumn("Status", value: \Row.statusRank) { (r: Row) in StatusBadge(status: r.status, overridden: r.task.statusOverridden) }
                        .width(min: 96, ideal: 118, max: 140)
                    TableColumn("Priority", value: \Row.priority) { (r: Row) in ListCell.priority(r.task.priority) }
                        .width(min: 56, ideal: 70, max: 90)
                    TableColumn("Project", value: \Row.project) { (r: Row) in ListCell.project(r.project, color: r.projectColor) }
                        .width(min: 90, ideal: 130)
                }
                Group {
                    TableColumn("Agent", value: \Row.agent) { (r: Row) in ListCell.agent(r.task.agentKind) }
                        .width(min: 80, ideal: 120)
                    TableColumn("Session", value: \Row.session) { (r: Row) in ListCell.muted(r.session) }
                        .width(min: 100, ideal: 170)
                    TableColumn("Steps", value: \Row.steps) { (r: Row) in ListCell.muted(r.steps) }
                        .width(min: 40, ideal: 50, max: 60)
                    TableColumn("Tool calls", value: \Row.tools) { (r: Row) in ListCell.muted(r.tools == 0 ? "" : "\(r.tools)") }
                        .width(min: 50, ideal: 66, max: 80)
                    TableColumn("Created", value: \Row.created) { (r: Row) in ListCell.muted(r.created.formatted(date: .abbreviated, time: .shortened)) }
                        .width(min: 110, ideal: 140)
                    TableColumn("Updated", value: \Row.updated) { (r: Row) in ListCell.muted(Fmt.ago(r.updated)) }
                        .width(min: 60, ideal: 84)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous).fill(Studio.surface))
            .clipShape(RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous))
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let t = store.task(id) { TaskContextMenu(task: t) }
            } primaryAction: { ids in
                if let id = ids.first { store.selection = id; store.showInspector = true }
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 22)
    }

    private func makeRows() -> [Row] {
        let order = Dictionary(uniqueKeysWithValues: TaskStatus.allCases.enumerated().map { ($1, $0) })
        var rows = store.periodScoped.compactMap { t -> Row? in
            if let f = statusFilter, t.status != f { return nil }
            let info = store.project(t.projectID)
            let p = t.subtaskProgress
            return Row(
                id: t.id, key: store.key(for: t), number: t.number, title: t.title, status: t.status,
                statusRank: order[t.status] ?? 0, priority: t.priority.rawValue, project: info.name,
                projectColor: info.colorIndex, session: store.session(t.sessionID)?.title ?? "", agent: t.agentKind?.title ?? "",
                created: t.createdAt, updated: t.lastActivity, steps: p.total == 0 ? "" : "\(p.done)/\(p.total)",
                followUps: t.followUps.count, tools: t.stats.toolCalls, task: t
            )
        }
        rows.sort(using: sortOrder)
        return rows
    }
}

/// Cells for the list table, kept out of the table builder so it type-checks quickly.
enum ListCell {
    static func key(_ k: String) -> some View {
        Text(k).font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(Studio.muted)
    }

    static func title(_ t: String, hidden: Bool) -> some View {
        Text(t).font(Studio.text(13, .bold)).lineLimit(1).foregroundStyle(hidden ? Studio.muted : Studio.ink)
    }

    static func priority(_ p: Priority) -> some View {
        Text(p == .none ? "—" : p.title).font(Studio.text(12.5, .bold)).foregroundStyle(Palette.priority(p))
    }

    static func project(_ name: String, color: Int) -> some View {
        HStack(spacing: 6) {
            ProjectDot(colorIndex: color, size: 8)
            Text(name).font(Studio.text(12.5, .bold)).lineLimit(1)
        }
    }

    @ViewBuilder
    static func agent(_ a: Agent?) -> some View {
        if let a {
            HStack(spacing: 6) {
                AgentAvatar(agent: a, size: 17)
                Text(a.title).font(Studio.text(12.5, .semibold)).lineLimit(1)
            }
        } else {
            Text("You").font(Studio.text(12.5, .semibold)).foregroundStyle(Studio.muted)
        }
    }

    static func muted(_ s: String) -> some View {
        Text(s).font(Studio.text(12.5).monospacedDigit()).lineLimit(1).foregroundStyle(Studio.ink2)
    }
}
