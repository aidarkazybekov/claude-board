import SwiftUI

/// Day-by-day log of what you asked and what your agents did.
struct WorklogView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let since = store.period.since
        let tasks = store.scoped.filter { since == nil || $0.createdAt >= since! }
        let days = Dictionary(grouping: tasks) { Calendar.current.startOfDay(for: $0.createdAt) }
            .sorted { $0.key > $1.key }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("What you asked and what your agents did, day by day.")
                        .font(Studio.text(13.5, .semibold)).foregroundStyle(Studio.ink2)
                    Spacer()
                    Button {
                        store.showShareWeek = true
                    } label: {
                        Label("Share your week", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.studio(.primary, size: 12.5))
                    .help("Make a picture of your week with your agents (⇧⌘S)")
                }
                if days.isEmpty {
                    VStack(spacing: 8) {
                        Text("No work in this period").font(Studio.display(20)).foregroundStyle(Studio.ink)
                        Text("Pick a longer period, or another project.").font(Studio.text(13.5, .medium)).foregroundStyle(Studio.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .studioCard(radius: Studio.radiusPanel)
                }
                ForEach(days, id: \.key) { day, items in
                    VStack(alignment: .leading, spacing: 10) {
                        DayHeader(day: day, tasks: items)
                        VStack(spacing: 0) {
                            let sorted = items.sorted { $0.createdAt > $1.createdAt }
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, t in
                                if i > 0 { Rectangle().fill(Studio.line).frame(height: 1).padding(.horizontal, 14) }
                                WorklogRow(task: t)
                                    .contextMenu { TaskContextMenu(task: t) }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous).fill(Studio.surface))
                    }
                }
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
    }
}

struct DayHeader: View {
    @Environment(Store.self) private var store
    let day: Date
    let tasks: [TaskItem]

    var body: some View {
        let projects = Dictionary(grouping: tasks, by: \.projectID).sorted { $0.value.count > $1.value.count }
        let seconds = tasks.reduce(0.0) { $0 + ($1.stats.activeSeconds ?? 0) }
        let requests = tasks.filter { $0.agentKind != nil && $0.origin != .suggested }.count
        let cal = Calendar.current
        FlowRow(spacing: 12) {
            Text(cal.isDateInToday(day) ? "Today" : cal.isDateInYesterday(day) ? "Yesterday" : Fmt.dayHeader.string(from: day))
                .font(Studio.display(22)).foregroundStyle(Studio.ink)
            if cal.isDateInToday(day) || cal.isDateInYesterday(day) {
                Text(Fmt.dayHeader.string(from: day)).font(Studio.text(13, .bold)).foregroundStyle(Studio.ink2)
            }
            Text("\(requests) request\(requests == 1 ? "" : "s")").font(Studio.text(13, .bold)).foregroundStyle(Studio.ink)
            if seconds > 60 {
                Text("\(Fmt.duration(seconds)) of agent time").font(Studio.text(13, .semibold)).foregroundStyle(Studio.ink2)
            }
            ForEach(projects.prefix(4), id: \.key) { pid, ts in
                let info = store.project(pid)
                HStack(spacing: 5) {
                    ProjectDot(colorIndex: info.colorIndex, size: 8)
                    Text("\(info.name) \(ts.count)")
                }
                .font(Studio.text(12, .bold))
                .foregroundStyle(Palette.ink(info.colorIndex))
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(Capsule().fill(Palette.tint(info.colorIndex)))
            }
        }
        .padding(.horizontal, 6)
    }
}

struct WorklogRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    var body: some View {
        let selected = store.selection == task.id
        let info = store.project(task.projectID)
        HStack(alignment: .top, spacing: 14) {
            Text(Fmt.time.string(from: task.createdAt))
                .font(Studio.text(12.5, .bold).monospacedDigit())
                .foregroundStyle(Studio.muted)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(Palette.status(task.status)).frame(width: 9, height: 9).help(task.status.title)
                    Text(store.key(for: task)).font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(Studio.muted)
                    Text(task.title).font(Studio.text(14, .bold)).foregroundStyle(Studio.ink).lineLimit(2)
                }
                if let recap = task.recap ?? task.finalReply ?? task.pendingAsk {
                    Text(Markdown.plain(recap, limit: 260)).font(Studio.text(13)).foregroundStyle(Studio.ink2).lineLimit(2)
                }
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    ProjectChip(info: info)
                    if let a = task.agentKind { AgentChip(agent: a) } else { Tag(text: "Your task", fill: Studio.well) }
                }
                let parts = [task.stats.toolCalls > 0 ? "\(task.stats.toolCalls) tool calls" : nil,
                             task.stats.filesTouched.isEmpty ? nil : "\(task.stats.filesTouched.count) file\(task.stats.filesTouched.count == 1 ? "" : "s")",
                             task.followUps.isEmpty ? nil : "\(task.followUps.count) repl\(task.followUps.count == 1 ? "y" : "ies")",
                             task.subtaskProgress.total > 0 ? "\(task.subtaskProgress.done)/\(task.subtaskProgress.total) steps" : nil].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · ")).font(Studio.text(12, .semibold)).foregroundStyle(Studio.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? Studio.well : .clear).padding(4))
        .contentShape(Rectangle())
        .onTapGesture {
            store.selection = task.id
            store.showInspector = true
        }
    }
}
