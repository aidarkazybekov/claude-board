import SwiftUI

struct BoardView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let tasks = store.periodScoped
        let grouped = Dictionary(grouping: tasks, by: \.status)
        GeometryReader { geo in
            // Columns share the width; below 220pt each the board scrolls sideways.
            let n = CGFloat(TaskStatus.allCases.count)
            let width = max(220, min(340, (geo.size.width - 24 - 10 * (n - 1)) / n))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(TaskStatus.allCases) { status in
                        BoardColumn(status: status, tasks: sorted(grouped[status] ?? [], status), width: width)
                    }
                }
                .padding(12)
                .frame(height: geo.size.height, alignment: .top)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sorted(_ ts: [TaskItem], _ s: TaskStatus) -> [TaskItem] {
        switch s {
        case .backlog, .todo:
            return ts.sorted { ($0.priority, $0.createdAt) > ($1.priority, $1.createdAt) }
        case .done:
            return ts.sorted { ($0.doneAt ?? $0.lastActivity) > ($1.doneAt ?? $1.lastActivity) }
        default:
            return ts.sorted { ($0.priority.rawValue, $0.lastActivity) > ($1.priority.rawValue, $1.lastActivity) }
        }
    }
}

struct BoardColumn: View {
    @Environment(Store.self) private var store
    let status: TaskStatus
    let tasks: [TaskItem]
    var width: CGFloat = 280
    @State private var targeted = false
    @State private var limit = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: status.symbol).foregroundStyle(Palette.status(status))
                Text(status.title).font(.subheadline.weight(.semibold))
                Text("\(tasks.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer()
                if status == .backlog || status == .todo {
                    Button {
                        store.newTaskProject = store.scopeProjectID
                        store.showNewTask = true
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("New ticket")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if status == .backlog || status == .todo {
                QuickAddField(status: status)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }

            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(tasks.prefix(limit)) { t in
                        TaskCard(task: t)
                    }
                    if tasks.count > limit {
                        Button("Show \(min(60, tasks.count - limit)) more of \(tasks.count - limit)") { limit += 60 }
                            .buttonStyle(.link)
                            .font(.caption)
                            .padding(.vertical, 6)
                    }
                    if tasks.isEmpty {
                        Text(emptyText)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(targeted ? Palette.status(status) : Color.primary.opacity(0.06), lineWidth: targeted ? 2 : 1)
        )
        .dropDestination(for: String.self) { ids, _ in
            for id in ids { store.setStatus(id, status) }
            return !ids.isEmpty
        } isTargeted: { targeted = $0 }
    }

    private var emptyText: String {
        switch status {
        case .backlog: return "Drop ideas here or press ⌘N"
        case .todo: return "Nothing queued"
        case .inProgress: return "No work in flight"
        case .needsYou: return "Nothing waiting on you"
        case .done: return "Nothing finished in this period"
        }
    }
}

struct TaskCard: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    @State private var hovering = false

    var body: some View {
        let selected = store.selection == task.id
        let session = store.session(task.sessionID)
        let info = store.project(task.projectID)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                KeyLabel(text: store.key(for: task))
                PriorityIcon(priority: task.priority)
                Spacer(minLength: 4)
                if let s = session, s.isLive, store.latestTask(inSession: s.id)?.id == task.id {
                    LiveDot(busy: s.isBusy)
                }
                OriginIcon(origin: task.origin).font(.caption2).foregroundStyle(.tertiary)
            }
            Text(task.title)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(task.hidden ? .secondary : .primary)
                .strikethrough(task.hidden)
            if let ask = task.pendingAsk, task.status == .needsYou {
                Label(ask, systemImage: "questionmark.bubble")
                    .font(.caption)
                    .foregroundStyle(Palette.status(.needsYou))
                    .lineLimit(2)
            } else if task.status == .needsYou, let need = session?.needsAction {
                Label(need, systemImage: "questionmark.bubble")
                    .font(.caption)
                    .foregroundStyle(Palette.status(.needsYou))
                    .lineLimit(2)
            }
            if task.origin.isPlanned {
                let a = store.claudeActivity(task)
                if a.count > 0 {
                    HStack(spacing: 4) {
                        if a.live { LiveDot(busy: a.busy) }
                        Image(systemName: "sparkle")
                        Text(a.needsYou ? "Claude needs you · \(a.count)" : a.busy ? "Claude working · \(a.count)" : "\(a.count) Claude request\(a.count == 1 ? "" : "s")")
                    }
                    .font(.caption2)
                    .foregroundStyle(a.needsYou ? Palette.status(.needsYou) : .secondary)
                }
            } else if let link = task.plannedLink, let planned = store.task(link) {
                Label("\(store.key(for: planned)) \(planned.title)", systemImage: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !task.labels.isEmpty || task.area != nil {
                HStack(spacing: 4) {
                    if let area = task.area, !area.isEmpty {
                        Text(area).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Palette.project(store.project(task.projectID).colorIndex).opacity(0.12), in: Capsule())
                    }
                    ForEach(task.labels.prefix(3), id: \.self) { l in
                        Text(l).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            HStack(spacing: 6) {
                ProjectChip(info: info)
                Spacer(minLength: 2)
                let p = task.subtaskProgress
                if p.total > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: p.done == p.total ? "checklist.checked" : "checklist")
                        Text("\(p.done)/\(p.total)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(p.done == p.total ? Palette.status(.done) : .secondary)
                }
                if !task.followUps.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "bubble.left.and.bubble.right")
                        Text("\(task.followUps.count)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Text(Fmt.ago(task.lastActivity)).font(.caption2).foregroundStyle(.tertiary)
            }
            if let s = session {
                Text(s.title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 4 : 1.5, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : Color.primary.opacity(0.07), lineWidth: selected ? 2 : 1)
        )
        .overlay(alignment: .leading) {
            if task.priority >= .high {
                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                    .fill(Palette.priority(task.priority))
                    .frame(width: 3)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            store.selection = task.id
            store.showInspector = true
        }
        .draggable(task.id) {
            Text("\(store.key(for: task))  \(task.title)")
                .font(.callout)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .contextMenu { TaskContextMenu(task: task) }
    }
}

struct TaskContextMenu: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    var body: some View {
        Menu("Status") {
            ForEach(TaskStatus.allCases) { s in
                Button {
                    store.setStatus(task.id, s)
                } label: {
                    if task.status == s { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                }
            }
            if task.statusOverridden {
                Divider()
                Button("Use status from Claude (\(task.inferredStatus.title))") { store.clearStatusOverride(task.id) }
            }
        }
        Menu("Priority") {
            ForEach(Priority.allCases.reversed()) { p in
                Button {
                    store.setPriority(task.id, p)
                } label: {
                    if task.priority == p { Label(p.title, systemImage: "checkmark") } else { Text(p.title) }
                }
            }
        }
        Divider()
        if task.sessionID != nil && task.origin != .suggested {
            Button("Resume Session in Terminal") { store.resume(task.id) }
        }
        if task.origin.isPlanned || task.origin == .suggested {
            Button("Start with Claude in Terminal") { store.startWithClaude(task.id) }
        }
        if task.filePath != nil {
            Button("Open Task File") { store.openFile(task.id) }
        }
        Button("Copy Key and Title") { store.copyKey(task.id) }
        Button("Copy Prompt") { store.copyPrompt(task.id) }
        Divider()
        if task.origin == .manual {
            Button("Delete Ticket", role: .destructive) { store.deleteManual(task.id) }
        } else {
            Button(task.hidden ? "Unhide" : "Hide (not a real task)") { store.setHidden(task.id, !task.hidden) }
        }
    }
}

/// One-line "add a task" field at the top of the Backlog and To Do columns.
struct QuickAddField: View {
    @Environment(Store.self) private var store
    let status: TaskStatus
    @State private var draft = ""
    @State private var chosen: String?
    @FocusState private var focused: Bool

    private var projectID: String? { store.scopeProjectID ?? chosen ?? store.lastQuickAddProject }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").foregroundStyle(.secondary).font(.caption)
            TextField(projectID.map { "Add to \(store.project($0).name)…" } ?? "Pick a project, then type…", text: $draft)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused($focused)
                .onSubmit(add)
            if store.scopeProjectID == nil {
                ProjectMenu(selection: Binding(get: { projectID }, set: { chosen = $0 }))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(focused ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(focused ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06)))
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let pid = projectID else { NSSound.beep(); return }
        let (title, p) = QuickAdd.parse(text)
        store.createTask(title: title, projectID: pid, notes: "", priority: p, status: status)
        draft = ""
        focused = true
    }
}

/// Compact project picker grouped by workspace.
struct ProjectMenu: View {
    @Environment(Store.self) private var store
    @Binding var selection: String?

    var body: some View {
        let choices = Dictionary(grouping: store.allProjectChoices, by: \.workspace).sorted { $0.key < $1.key }
        Menu {
            ForEach(choices, id: \.key) { ws, ps in
                if ps.count == 1, let p = ps.first {
                    Button(p.name) { selection = p.id }
                } else {
                    Menu(ws) {
                        ForEach(ps) { p in Button(p.name) { selection = p.id } }
                    }
                }
            }
        } label: {
            if let s = selection {
                let info = store.project(s)
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.project(info.colorIndex)).frame(width: 7, height: 7)
                    Text(info.name).lineLimit(1)
                }
            } else {
                Text("Project")
            }
        }
        .menuStyle(.borderlessButton)
        .font(.caption)
        .fixedSize()
    }
}
