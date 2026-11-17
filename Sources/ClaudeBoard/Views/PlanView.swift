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
        let openCount = planned.filter { $0.status.isOpen }.count
        let withAgent = planned.filter { $0.status.isOpen && store.claudeActivity($0).live }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Text(withAgent > 0 ? "\(openCount) planned tasks. \(withAgent) with an agent right now." : "\(openCount) planned task\(openCount == 1 ? "" : "s"). Start one with any agent.")
                        .font(Studio.text(13.5, .semibold)).foregroundStyle(Studio.ink2)
                    Spacer()
                    Toggle("Show done", isOn: $showDone).toggleStyle(.checkbox)
                    if store.scopeProjectID == nil {
                        Toggle("Show projects without tasks", isOn: $showEmpty).toggleStyle(.checkbox)
                    }
                }
                .font(Studio.text(12.5, .semibold))
                .foregroundStyle(Studio.ink2)
                if ids.isEmpty {
                    VStack(spacing: 10) {
                        Text("No planned tasks yet").font(Studio.display(22)).foregroundStyle(Studio.ink)
                        Text("Add tasks for each project here. They stay on this Mac, or go in the project's backlog/ folder so your team and your agents can read them too.")
                            .font(Studio.text(13.5, .medium)).foregroundStyle(Studio.ink2).multilineTextAlignment(.center).frame(maxWidth: 460)
                        Button("New task") { store.newTaskProject = store.scopeProjectID; store.showNewTask = true }
                            .buttonStyle(.studio(.primary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .studioCard(radius: Studio.radiusPanel, padding: 20)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 520), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(ids, id: \.self) { pid in
                        ProjectPlanSection(projectID: pid, tasks: byProject[pid] ?? [], showDone: showDone)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 26)
        }
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
            HStack(spacing: 10) {
                ProjectDot(colorIndex: info.colorIndex, size: 14)
                Button { store.sidebar = .project(projectID) } label: {
                    Text(info.name).font(Studio.display(19)).foregroundStyle(Studio.ink)
                }
                .buttonStyle(.plain)
                .help("Show only \(info.name)")
                Text("\(open.count) open").font(Studio.text(13, .bold)).foregroundStyle(Palette.ink(info.colorIndex))
                Text(folder.map { "Saved in \(($0 as NSString).lastPathComponent)/" } ?? "Saved on this Mac")
                    .font(Studio.text(12, .semibold)).foregroundStyle(Studio.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(Capsule().fill(Studio.surface.opacity(0.75)))
                    .help(folder.map { "Tasks are saved as files in \(Paths.tilde($0))" } ?? "Tasks are saved in the app on this Mac only")
                Spacer(minLength: 6)
                Button("Copy for an agent") { store.copyPlanForClaude(projectID) }
                    .buttonStyle(.studio(.white, size: 12))
                    .help("Copies the open tasks as a Markdown list to paste into any agent")
                Menu {
                    Button("New Task…") { store.newTaskProject = projectID; store.showNewTask = true }
                    Button("Copy Open Tasks for an Agent") { store.copyPlanForClaude(projectID) }
                    if folder == nil && projectID.hasPrefix("/") {
                        Divider()
                        Button("Keep Tasks in the Repo (create backlog/)") { store.createBacklogFolder(for: projectID) }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .heavy)).frame(width: 28, height: 28)
                        .background(Circle().fill(Studio.surface))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More for \(info.name)")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Palette.tint(info.colorIndex))

            VStack(spacing: 2) {
                ForEach(open) { t in PlanRow(task: t) }
                if showDone {
                    ForEach(done) { t in PlanRow(task: t) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(Studio.muted)
                TextField("Add a task for \(info.name)…  !high sets priority", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Studio.text(13, .medium))
                    .focused($focused)
                    .onSubmit(add)
                if !draft.isEmpty { Text("⏎").font(Studio.text(12, .bold)).foregroundStyle(Studio.faint) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Studio.well))
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Studio.surface)
        .clipShape(RoundedRectangle(cornerRadius: Studio.radiusPanel, style: .continuous))
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
        let agent = store.agents(on: task).first
        HStack(spacing: 10) {
            Button {
                store.setStatus(task.id, task.status == .done ? .todo : .done)
            } label: {
                StatusRing(status: task.status)
            }
            .buttonStyle(.plain)
            .help(task.status == .done ? "Reopen" : "Mark done")
            .accessibilityLabel(task.status == .done ? "Reopen \(task.title)" : "Mark \(task.title) done")

            Text(store.key(for: task)).font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(Studio.muted)
                .frame(minWidth: 54, alignment: .leading)
            Text(task.title)
                .font(Studio.text(13.5, .bold))
                .lineLimit(1)
                .strikethrough(task.status == .done, color: Studio.faint)
                .foregroundStyle(task.status == .done ? Studio.muted : Studio.ink)
            if task.priority >= .medium {
                Text(task.priority.title).font(Studio.text(12, .bold)).foregroundStyle(Palette.priority(task.priority))
            }
            if let area = task.area, !area.isEmpty { Tag(text: area, color: Studio.ink2, fill: Studio.well) }
            Spacer(minLength: 8)
            if activity.count > 0, let agent {
                AgentChip(agent: agent, text: activity.needsYou ? "\(agent.title) needs you" : activity.busy ? "\(agent.title) working" : "\(activity.count) request\(activity.count == 1 ? "" : "s")",
                          coral: activity.needsYou)
                    .overlay(alignment: .topTrailing) { if activity.live { LiveDot(busy: activity.busy).offset(x: 3, y: -3) } }
            }
            let p = task.subtaskProgress
            if p.total > 0 {
                Text("\(p.done)/\(p.total)").font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(Studio.muted)
            }
            if hovering && task.status.isOpen {
                StartWithMenu(taskID: task.id, size: 11.5)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(selected ? Studio.well : hovering ? Studio.well.opacity(0.6) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Studio.ink : .clear, lineWidth: 1.5))
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

/// Round status marker: open ring, half-filled while in progress, coral when it needs you, filled when done.
struct StatusRing: View {
    let status: TaskStatus
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            switch status {
            case .done:
                Circle().fill(Palette.status(.done))
                Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .heavy)).foregroundStyle(.white)
            case .needsYou:
                Circle().fill(Studio.coral)
                Text("!").font(.system(size: size * 0.6, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            case .inProgress:
                Circle().strokeBorder(Studio.blue, lineWidth: 2)
                Circle().trim(from: 0, to: 0.5).fill(Studio.blue).rotationEffect(.degrees(-90)).padding(4)
            case .todo:
                Circle().strokeBorder(Studio.ink2, lineWidth: 2)
            case .backlog:
                Circle().strokeBorder(Palette.status(.backlog), style: StrokeStyle(lineWidth: 2, dash: [3, 2.5]))
            }
        }
        .frame(width: size, height: size)
    }
}
