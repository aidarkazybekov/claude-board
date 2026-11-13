import SwiftUI

/// Your own task list per app: "billing has these, web has those". Planned tasks only;
/// Claude's work on them shows as a badge on each row.
struct PlanView: View {
    @Environment(Store.self) private var store
    @AppStorage("planShowEmpty") private var showEmpty = false
    @AppStorage("planShowDone") private var showDone = false

    var body: some View {
        let planned = store.scoped.filter { $0.origin.isPlanned }
        let byProject = Dictionary(grouping: planned, by: \.projectID)
        let ids = projectIDs(byProject)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Tasks you planned, per project. Claude's work on a task shows on its row once a session mentions its key.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Show done", isOn: $showDone).toggleStyle(.checkbox)
                    if store.scopeProjectID == nil {
                        Toggle("Show projects without tasks", isOn: $showEmpty).toggleStyle(.checkbox)
                    }
                }
                .font(.caption)
                if ids.isEmpty {
                    ContentUnavailableView {
                        Label("No planned tasks yet", systemImage: "checklist")
                    } description: {
                        Text("Add tasks for each app here. They stay on this Mac, or go in a project's backlog/ folder so your team and Claude can read them too.")
                    } actions: {
                        Button("New Task…") { store.newTaskProject = store.scopeProjectID; store.showNewTask = true }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                ForEach(ids, id: \.self) { pid in
                    ProjectPlanSection(projectID: pid, tasks: byProject[pid] ?? [], showDone: showDone)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func projectIDs(_ byProject: [String: [TaskItem]]) -> [String] {
        if let p = store.scopeProjectID { return [p] }
        var ids = Set(byProject.filter { $0.value.contains { $0.status.isOpen } || showDone }.keys)
        if showEmpty {
            let scope = store.scope
            for p in store.allProjectChoices {
                if case .workspace(let w) = scope, p.workspace != w { continue }
                ids.insert(p.id)
            }
        }
        return ids.sorted { a, b in
            let ca = byProject[a]?.filter { $0.status.isOpen }.count ?? 0
            let cb = byProject[b]?.filter { $0.status.isOpen }.count ?? 0
            if ca != cb { return ca > cb }
            return store.project(a).name.lowercased() < store.project(b).name.lowercased()
        }
    }
}

struct ProjectPlanSection: View {
    @Environment(Store.self) private var store
    let projectID: String
    let tasks: [TaskItem]
    let showDone: Bool
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let info = store.project(projectID)
        let open = tasks.filter { $0.status.isOpen }.sorted(by: order)
        let done = tasks.filter { !$0.status.isOpen }.sorted { ($0.doneAt ?? $0.updatedAt) > ($1.doneAt ?? $1.updatedAt) }
        let folder = store.folders(for: projectID).first
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(Palette.project(info.colorIndex)).frame(width: 11, height: 11)
                Button {
                    store.sidebar = .project(projectID)
                } label: {
                    Text(info.name).font(.headline)
                }
                .buttonStyle(.plain)
                if info.workspace != info.name && info.workspace != "Other" {
                    Text(info.workspace).font(.caption).foregroundStyle(.secondary)
                }
                Text("\(open.count) open").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                if let folder {
                    Label(Paths.tilde(folder), systemImage: "folder")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                        .help("Tasks are saved as files in this backlog folder")
                } else {
                    Label("This Mac", systemImage: "laptopcomputer")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .help("Tasks are saved in ClaudeBoard on this Mac only")
                }
                Menu {
                    Button("New Task…") { store.newTaskProject = projectID; store.showNewTask = true }
                    Button("Copy Open Tasks for Claude") { store.copyPlanForClaude(projectID) }
                    if folder == nil && projectID.hasPrefix("/") {
                        Divider()
                        Button("Keep Tasks in the Repo (create backlog/)") { store.createBacklogFolder(for: projectID) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            VStack(spacing: 0) {
                ForEach(open) { t in PlanRow(task: t) }
                if showDone {
                    ForEach(done) { t in PlanRow(task: t) }
                }
                HStack(spacing: 8) {
                    Image(systemName: "plus").foregroundStyle(.secondary).frame(width: 16)
                    TextField("Add a task for \(info.name)…", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(add)
                    if !draft.isEmpty {
                        Text("⏎").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
    }

    private func order(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let rank: [TaskStatus: Int] = [.inProgress: 0, .needsYou: 1, .todo: 2, .backlog: 3, .done: 4]
        if rank[a.status]! != rank[b.status]! { return rank[a.status]! < rank[b.status]! }
        if a.priority != b.priority { return a.priority > b.priority }
        return a.createdAt < b.createdAt
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let (clean, priority) = QuickAdd.parse(title)
        store.createTask(title: clean, projectID: projectID, notes: "", priority: priority, status: .todo)
        draft = ""
        focused = true
    }
}

/// "Fix login !high" → title + priority. Keeps quick-add one line.
enum QuickAdd {
    static func parse(_ raw: String) -> (String, Priority) {
        var words = raw.split(separator: " ").map(String.init)
        var p: Priority = .none
        words.removeAll { w in
            switch w.lowercased() {
            case "!urgent", "!!!", "!p0": p = .urgent; return true
            case "!high", "!!", "!p1": p = .high; return true
            case "!medium", "!med", "!p2": p = .medium; return true
            case "!low", "!p3": p = .low; return true
            default: return false
            }
        }
        return (words.joined(separator: " "), p)
    }
}

struct PlanRow: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    @State private var hovering = false

    var body: some View {
        let selected = store.selection == task.id
        let activity = store.claudeActivity(task)
        HStack(spacing: 10) {
            Button {
                store.setStatus(task.id, task.status == .done ? .todo : .done)
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : task.status.symbol)
                    .foregroundStyle(Palette.status(task.status))
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(task.status == .done ? "Reopen" : "Mark done")

            KeyLabel(text: store.key(for: task)).frame(minWidth: 52, alignment: .leading)
            PriorityIcon(priority: task.priority)
            Text(task.title)
                .lineLimit(1)
                .strikethrough(task.status == .done, color: .secondary)
                .foregroundStyle(task.status == .done ? .secondary : .primary)
            if let area = task.area, !area.isEmpty {
                Text(area).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer(minLength: 8)
            if activity.count > 0 {
                HStack(spacing: 4) {
                    if activity.live { LiveDot(busy: activity.busy) }
                    Image(systemName: "sparkle")
                    Text("\(activity.count)")
                }
                .font(.caption2)
                .foregroundStyle(activity.needsYou ? Palette.status(.needsYou) : .secondary)
                .help(activity.needsYou ? "Claude is waiting on you in a session for this task" : "\(activity.count) Claude request(s) worked on this")
            }
            let p = task.subtaskProgress
            if p.total > 0 {
                Text("\(p.done)/\(p.total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            if task.status != .done && task.status != .todo {
                Text(task.status.title).font(.caption2).foregroundStyle(Palette.status(task.status))
            }
            if hovering && task.status.isOpen {
                Button {
                    store.startWithClaude(task.id)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .help("Start with Claude in Terminal")
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.14) : hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            store.selection = task.id
            store.showInspector = true
        }
        .draggable(task.id)
        .contextMenu { TaskContextMenu(task: task) }
    }
}
