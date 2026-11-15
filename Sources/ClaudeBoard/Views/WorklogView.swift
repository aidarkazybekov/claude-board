import SwiftUI

/// Day-by-day log of what was asked and what Claude did.
struct WorklogView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let since = store.period.since
        let tasks = store.scoped.filter { since == nil || $0.lastActivity >= since! }
        let days = Dictionary(grouping: tasks) { Calendar.current.startOfDay(for: $0.createdAt) }
            .sorted { $0.key > $1.key }

        VStack(spacing: 0) {
        HStack {
            Text("What you asked and what Claude did, day by day.").font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button {
                store.showShareWeek = true
            } label: {
                Label("Share Your Week", systemImage: "square.and.arrow.up")
            }
            .help("Make a recap card of your week with Claude (⇧⌘S)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        Divider()
        if days.isEmpty {
            ContentUnavailableView("No work in this period", systemImage: "calendar.badge.clock",
                                   description: Text("Widen the period or pick another project."))
                .frame(maxHeight: .infinity)
        } else {
            List(selection: Binding(get: { store.selection }, set: { store.selection = $0; store.showInspector = true })) {
                ForEach(days, id: \.key) { day, items in
                    Section {
                        ForEach(items.sorted { $0.createdAt > $1.createdAt }) { t in
                            WorklogRow(task: t).tag(t.id)
                                .contextMenu { TaskContextMenu(task: t) }
                        }
                    } header: {
                        DayHeader(day: day, tasks: items)
                    }
                }
            }
            .listStyle(.inset)
        }
        }
    }
}

struct DayHeader: View {
    @Environment(Store.self) private var store
    let day: Date
    let tasks: [TaskItem]

    var body: some View {
        let projects = Dictionary(grouping: tasks, by: \.projectID).sorted { $0.value.count > $1.value.count }
        let minutes = tasks.reduce(0.0) { $0 + ($1.stats.activeSeconds ?? 0) }
        HStack(spacing: 10) {
            Text(Calendar.current.isDateInToday(day) ? "Today" : Calendar.current.isDateInYesterday(day) ? "Yesterday" : Fmt.dayHeader.string(from: day))
                .font(.headline)
            Text("\(tasks.count) requests").foregroundStyle(.secondary)
            if minutes > 60 {
                Text("· \(Fmt.duration(minutes)) of Claude active time").foregroundStyle(.secondary)
            }
            Spacer()
            ForEach(projects.prefix(4), id: \.key) { pid, ts in
                HStack(spacing: 3) {
                    ProjectChip(info: store.project(pid))
                    Text("\(ts.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
        .padding(.vertical, 4)
    }
}

struct WorklogRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Fmt.time.string(from: task.createdAt))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Image(systemName: task.status.symbol)
                .foregroundStyle(Palette.status(task.status))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    KeyLabel(text: store.key(for: task))
                    Text(task.title).lineLimit(2)
                }
                if let recap = task.recap ?? task.finalReply {
                    Text(Markdown.plain(recap, limit: 260)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 8) {
                    ProjectChip(info: store.project(task.projectID))
                    if task.stats.toolCalls > 0 {
                        Label("\(task.stats.toolCalls)", systemImage: "wrench.and.screwdriver").help("Tool calls")
                    }
                    if task.stats.edits > 0 {
                        Label("\(task.stats.filesTouched.count) files", systemImage: "doc.badge.ellipsis")
                    }
                    if !task.followUps.isEmpty {
                        Label("\(task.followUps.count)", systemImage: "bubble.left.and.bubble.right").help("Follow-ups")
                    }
                    let p = task.subtaskProgress
                    if p.total > 0 { Label("\(p.done)/\(p.total)", systemImage: "checklist") }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 3)
    }
}
