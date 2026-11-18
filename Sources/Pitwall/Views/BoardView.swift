import SwiftUI

struct BoardView: View {
    @Environment(Store.self) private var store

    var body: some View {
        let tasks = store.periodScoped
        let grouped = Dictionary(grouping: tasks, by: \.status)
        GeometryReader { geo in
            // Columns share the width; below 230pt each the board scrolls sideways.
            // Each column is `width` plus its 6pt padding on both sides.
            let n = CGFloat(TaskStatus.allCases.count)
            let width = max(230, min(340, (geo.size.width - 46 - 14 * (n - 1) - 12 * n) / n))
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TaskStatus.allCases) { status in
                        BoardColumn(status: status, tasks: sorted(grouped[status] ?? [], status), width: width)
                    }
                }
                .padding(.leading, 26)
                .padding(.trailing, 20)
                .padding(.bottom, 8)
                .frame(height: geo.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
    }

    private func sorted(_ ts: [TaskItem], _ s: TaskStatus) -> [TaskItem] {
        switch s {
        case .backlog, .todo:
            return ts.sorted { ($0.priority, $0.createdAt) > ($1.priority, $1.createdAt) }
        case .done:
            return ts.sorted { ($0.doneAt ?? $0.lastActivity) > ($1.doneAt ?? $1.lastActivity) }
        case .needsYou:
            // Oldest question first: it has waited longest.
            return ts.sorted { ($0.priority.rawValue, $1.lastActivity) > ($1.priority.rawValue, $0.lastActivity) }
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

    private var titleColor: Color {
        switch status {
        case .needsYou: return Studio.coralInk
        case .inProgress: return Studio.blueInk
        case .done: return Studio.doneInk
        case .todo: return Studio.ink2
        case .backlog: return Studio.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(status.title).font(Studio.display(15))
                Text("\(tasks.count)").font(Studio.display(22)).monospacedDigit()
                Spacer()
                if status == .backlog || status == .todo {
                    CircleIconButton(symbol: "plus", help: "New task in \(status.title)") {
                        store.newTaskProject = store.scopeProjectID
                        store.showNewTask = true
                    }
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                }
            }
            .foregroundStyle(titleColor)
            .padding(.horizontal, 4)

            if status == .backlog || status == .todo {
                QuickAddField(status: status)
            }

            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    ForEach(tasks.prefix(limit)) { t in
                        TaskCard(task: t)
                    }
                    if tasks.count > limit {
                        Button("Show \(min(60, tasks.count - limit)) more of \(tasks.count - limit)") { limit += 60 }
                            .buttonStyle(.studio(.quiet, size: 12))
                            .padding(.vertical, 4)
                    }
                    if tasks.isEmpty {
                        Text(emptyText)
                            .font(Studio.text(12.5, .semibold))
                            .foregroundStyle(Studio.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Studio.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                }
                .padding(.bottom, 14)
                .padding(.horizontal, 2)
                .padding(.top, 2)
            }
            .scrollIndicators(.never)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(targeted ? Palette.statusFill(status) : .clear))
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
        let asks = task.status == .needsYou
        let question = asks ? (task.pendingAsk ?? session?.needsAction) : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ProjectDot(colorIndex: info.colorIndex, size: 8)
                Text("\(info.name) · \(store.key(for: task))")
                    .font(Studio.text(12, .bold))
                    .foregroundStyle(Palette.ink(info.colorIndex))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let s = session, s.isLive, store.latestTask(inSession: s.id)?.id == task.id {
                    LiveDot(busy: s.isBusy)
                }
                Text(Fmt.ago(task.lastActivity)).font(Studio.text(12, .semibold)).foregroundStyle(Studio.ink2)
            }
            Text(task.title)
                .font(Studio.text(14.5, .bold))
                .foregroundStyle(task.hidden ? Studio.muted : Studio.ink)
                .strikethrough(task.hidden)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let q = question {
                Text("“\(Markdown.plain(q, limit: 200))”")
                    .font(Studio.text(13.5, .semibold))
                    .foregroundStyle(Studio.coralInk)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if task.origin.isPlanned {
                let a = store.claudeActivity(task)
                if a.count > 0, let agent = store.agents(on: task).first {
                    HStack(spacing: 6) {
                        if a.live { LiveDot(busy: a.busy) }
                        AgentAvatar(agent: agent, size: 16)
                        Text(a.needsYou ? "\(agent.title) needs you" : a.busy ? "\(agent.title) working · \(a.count)" : "\(a.count) agent request\(a.count == 1 ? "" : "s")")
                    }
                    .font(Studio.text(12, .bold))
                    .foregroundStyle(a.needsYou ? Studio.coralInk : Studio.ink2)
                }
            } else if let link = task.plannedLink, let planned = store.task(link) {
                Label("\(store.key(for: planned)) \(planned.title)", systemImage: "arrow.turn.down.right")
                    .font(Studio.text(12, .semibold))
                    .foregroundStyle(Studio.ink2)
                    .lineLimit(1)
            }
            let p = task.subtaskProgress
            if p.total > 0 {
                HStack(spacing: 8) {
                    GeometryReader { g in
                        Capsule().fill(Studio.ink.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Palette.project(info.colorIndex))
                                    .frame(width: max(6, g.size.width * CGFloat(p.done) / CGFloat(max(p.total, 1))))
                            }
                    }
                    .frame(height: 6)
                    Text("\(p.done)/\(p.total)").font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(Studio.ink2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(p.done) of \(p.total) steps done")
            }
            chips(info: info, asks: asks)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(asks ? Studio.surface : Palette.tint(info.colorIndex))
                .shadow(color: .black.opacity(hovering ? 0.10 : 0), radius: 8, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Studio.ink : (asks ? Studio.coral : .clear), lineWidth: selected ? 2.5 : 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onTapGesture {
            store.selection = task.id
            store.showInspector = true
        }
        .draggable(task.id) {
            Text("\(store.key(for: task))  \(task.title)")
                .font(Studio.text(13, .bold))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Studio.surface))
        }
        .contextMenu { TaskContextMenu(task: task) }
    }

    @ViewBuilder
    private func chips(info: ProjectInfo, asks: Bool) -> some View {
        let hasLabels = !task.labels.isEmpty || !(task.area ?? "").isEmpty
        if task.agentKind != nil || task.priority != .none || hasLabels || !task.followUps.isEmpty || task.origin.isPlanned {
            FlowRow(spacing: 6) {
                if let agent = task.agentKind {
                    AgentChip(agent: agent, onWell: !asks)
                } else {
                    Tag(text: "Your task", fill: asks ? Studio.well : Studio.surface)
                }
                if task.priority != .none {
                    Tag(text: task.priority.title, color: Palette.priority(task.priority), fill: asks ? Studio.well : Studio.surface)
                }
                if let area = task.area, !area.isEmpty { Tag(text: area, color: Studio.ink2, fill: asks ? Studio.well : Studio.surface) }
                ForEach(task.labels.prefix(2), id: \.self) { l in Tag(text: l, color: Studio.ink2, fill: asks ? Studio.well : Studio.surface) }
                if !task.followUps.isEmpty {
                    Text("\(task.followUps.count) repl\(task.followUps.count == 1 ? "y" : "ies")")
                        .font(Studio.text(12, .semibold)).foregroundStyle(Studio.ink2)
                }
            }
        }
    }
}

/// Lays children out left to right and wraps to new lines, like text.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxW { y += line + spacing; x = 0; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
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
                Button("Use status from \((task.agentKind ?? .claudeCode).title) (\(task.inferredStatus.title))") { store.clearStatusOverride(task.id) }
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
            Button("Resume in \((task.agentKind ?? .claudeCode).runsInTerminal ? "Terminal" : (task.agentKind ?? .claudeCode).title)") { store.resume(task.id) }
        }
        if task.origin.isPlanned || task.origin == .suggested {
            Menu("Start with") {
                ForEach(Agent.allCases) { a in
                    Button(a.title) { store.start(task.id, with: a) }
                }
            }
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
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(Studio.muted)
            TextField(projectID.map { "Add to \(store.project($0).name)…" } ?? "Pick a project, then type…", text: $draft)
                .textFieldStyle(.plain)
                .font(Studio.text(13, .medium))
                .focused($focused)
                .onSubmit(add)
            if store.scopeProjectID == nil {
                ProjectMenu(selection: Binding(get: { projectID }, set: { chosen = $0 }))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Capsule().fill(Studio.surface))
        .overlay(Capsule().stroke(focused ? Studio.ink.opacity(0.5) : Studio.line, lineWidth: 1))
        .help("Type a task and press Return. !high or !low sets the priority.")
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
                HStack(spacing: 4) {
                    ProjectDot(colorIndex: info.colorIndex, size: 7)
                    Text(info.name).lineLimit(1)
                }
                .font(Studio.text(12, .bold))
                .foregroundStyle(Palette.ink(info.colorIndex))
            } else {
                Text("Project").font(Studio.text(12, .bold))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
