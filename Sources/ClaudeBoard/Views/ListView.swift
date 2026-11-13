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
        let created: Date
        let updated: Date
        let steps: String
        let followUps: Int
        let tools: Int
        let task: TaskItem
    }

    var body: some View {
        @Bindable var store = store
        let rows = makeRows()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("Status", selection: $statusFilter) {
                    Text("Any status").tag(TaskStatus?.none)
                    ForEach(TaskStatus.allCases) { Text($0.title).tag(TaskStatus?.some($0)) }
                }
                .frame(width: 170)
                Text("\(rows.count) tickets").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Table(rows, selection: $store.selection, sortOrder: $sortOrder) {
                TableColumn("Key", value: \.number) { r in KeyLabel(text: r.key) }
                    .width(min: 60, ideal: 75, max: 110)
                TableColumn("Title", value: \.title) { r in
                    HStack(spacing: 5) {
                        OriginIcon(origin: r.task.origin).font(.caption2).foregroundStyle(.tertiary)
                        Text(r.title).lineLimit(1)
                            .foregroundStyle(r.task.hidden ? .secondary : .primary)
                    }
                }
                .width(min: 220, ideal: 420)
                TableColumn("Status", value: \.statusRank) { r in StatusBadge(status: r.status, overridden: r.task.statusOverridden) }
                    .width(min: 90, ideal: 115, max: 140)
                TableColumn("Pri", value: \.priority) { r in PriorityIcon(priority: r.task.priority) }
                    .width(min: 28, ideal: 34, max: 44)
                TableColumn("Project", value: \.project) { r in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.project(r.projectColor)).frame(width: 7, height: 7)
                        Text(r.project).lineLimit(1)
                    }
                }
                .width(min: 90, ideal: 130)
                TableColumn("Session", value: \.session) { r in Text(r.session).lineLimit(1).foregroundStyle(.secondary) }
                    .width(min: 100, ideal: 180)
                TableColumn("Steps", value: \.steps) { r in Text(r.steps).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    .width(min: 40, ideal: 50, max: 60)
                TableColumn("Tools", value: \.tools) { r in Text(r.tools == 0 ? "" : "\(r.tools)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    .width(min: 36, ideal: 44, max: 60)
                TableColumn("Created", value: \.created) { r in Text(r.created.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                    .width(min: 110, ideal: 140)
                TableColumn("Updated", value: \.updated) { r in Text(Fmt.ago(r.updated)).foregroundStyle(.secondary) }
                    .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let t = store.task(id) { TaskContextMenu(task: t) }
            } primaryAction: { ids in
                if let id = ids.first { store.selection = id; store.showInspector = true }
            }
        }
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
                projectColor: info.colorIndex, session: store.session(t.sessionID)?.title ?? "",
                created: t.createdAt, updated: t.lastActivity, steps: p.total == 0 ? "" : "\(p.done)/\(p.total)",
                followUps: t.followUps.count, tools: t.stats.toolCalls, task: t
            )
        }
        rows.sort(using: sortOrder)
        return rows
    }
}
