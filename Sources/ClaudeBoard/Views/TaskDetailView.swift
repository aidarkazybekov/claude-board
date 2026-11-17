import SwiftUI

struct TaskDetailView: View {
    @Environment(Store.self) private var store
    let task: TaskItem

    @State private var title = ""
    @State private var notes = ""
    @State private var labels = ""
    @State private var newSubtask = ""
    @State private var showReply = false
    @State private var area = ""
    @State private var editingBody = false
    @State private var notesSave: Task<Void, Never>?
    /// What the fields held when the ticket was opened. Only fields you changed are written back,
    /// so an edit made elsewhere (another app, the task file itself) is never overwritten.
    @State private var synced = (title: "", notes: "", labels: "", area: "")

    var body: some View {
        let info = store.project(task.projectID)
        let session = store.session(task.sessionID)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(info: info)
                statusRow
                actions(session: session)

                if let ask = task.pendingAsk ?? (task.status == .needsYou ? session?.needsAction : nil) {
                    waiting(ask: ask, session: session)
                }

                details

                if task.origin == .file {
                    description
                } else {
                    panel(task.origin == .manual ? "Task" : "Request", detail: task.createdAt.formatted(date: .abbreviated, time: .shortened)) {
                        ExpandableText(text: task.prompt, limit: 900, font: Studio.text(13.5))
                            .foregroundStyle(Studio.ink)
                    }
                }

                if task.origin.isPlanned { agentWork }

                if !task.subtasks.isEmpty || task.origin.isPlanned { plan }

                if let recap = task.recap {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Outcome").font(Studio.display(14)).foregroundStyle(Studio.doneInk)
                        Text(Markdown.inline(recap)).font(Studio.text(13.5)).foregroundStyle(Studio.ink).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Studio.doneBg))
                }

                if let reply = task.finalReply {
                    DisclosureGroup(isExpanded: $showReply) {
                        ExpandableText(text: reply, limit: 1500, font: Studio.text(13.5), markdown: true)
                            .padding(.top, 6)
                    } label: {
                        Text("\((task.agentKind ?? .claudeCode).title)'s last reply").font(Studio.display(14)).foregroundStyle(Studio.ink)
                    }
                }

                if !task.followUps.isEmpty {
                    panel("Conversation", detail: "\(task.followUps.count) follow-up\(task.followUps.count == 1 ? "" : "s")") {
                        ForEach(Array(task.followUps.enumerated()), id: \.offset) { _, ex in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(Fmt.time.string(from: ex.at)).font(Studio.text(12, .semibold).monospacedDigit()).foregroundStyle(Studio.muted)
                                    .frame(width: 58, alignment: .leading)
                                Text(PromptText.truncate(ex.text, 400)).font(Studio.text(13)).foregroundStyle(Studio.ink).textSelection(.enabled)
                            }
                        }
                    }
                }

                if !task.origin.isPlanned && task.origin != .suggested { worklog }

                if task.origin != .file {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes").font(Studio.display(14)).foregroundStyle(Studio.ink)
                        TextEditor(text: $notes)
                            .font(Studio.text(13))
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.well))
                            .onChange(of: notes) { _, v in
                                notesSave?.cancel()
                                let id = task.id
                                notesSave = Task {
                                    try? await Task.sleep(for: .milliseconds(700))
                                    guard !Task.isCancelled else { return }
                                    if store.task(id)?.notes != v { store.setNotes(id, v) }
                                }
                            }
                    }
                }
            }
            .padding(22)
        }
        .scrollIndicators(.automatic)
        .background(Studio.surface)
        .onAppear(perform: sync)
        .onChange(of: task.id) { old, _ in
            flush(old)
            sync()
        }
        .onDisappear { flush(task.id) }
        // Changes from outside (a refresh, the file edited elsewhere) show up unless you're editing that field.
        .onChange(of: task.title) { _, v in if title == synced.title { title = v; synced.title = v } }
        .onChange(of: task.notes) { _, v in if notes == synced.notes && !editingBody { notes = v; synced.notes = v } }
        .onChange(of: task.labels) { _, v in
            let joined = v.joined(separator: ", ")
            if labels == synced.labels { labels = joined; synced.labels = joined }
        }
        .onChange(of: task.area) { _, v in if area == synced.area { area = v ?? ""; synced.area = v ?? "" } }
    }

    // MARK: Header

    private func header(info: ProjectInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProjectChip(info: info, showWorkspace: true)
                Text(store.key(for: task)).font(Studio.text(12.5, .bold).monospacedDigit()).foregroundStyle(Studio.muted)
                    .textSelection(.enabled)
                Spacer(minLength: 6)
                Text(task.originTitle).font(Studio.text(12, .semibold)).foregroundStyle(Studio.muted).lineLimit(1)
            }
            TextField("Title", text: $title, axis: .vertical)
                .font(Studio.display(23))
                .foregroundStyle(Studio.ink)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { store.setTitle(task.id, title) }
            if task.hidden {
                Label("Hidden: not counted as a task", systemImage: "eye.slash").font(Studio.text(12, .semibold)).foregroundStyle(Studio.muted)
            }
        }
    }

    private var statusRow: some View {
        FlowRow(spacing: 8) {
            Menu {
                ForEach(TaskStatus.allCases) { s in
                    Button(s.title) { store.setStatus(task.id, s) }
                }
                if task.statusOverridden {
                    Divider()
                    Button("Use status from \((task.agentKind ?? .claudeCode).title) (\(task.inferredStatus.title))") { store.clearStatusOverride(task.id) }
                }
            } label: {
                StatusBadge(status: task.status, overridden: task.statusOverridden)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change the status")

            Menu {
                ForEach(Priority.allCases.reversed()) { p in
                    Button(p.title) { store.setPriority(task.id, p) }
                }
            } label: {
                Tag(text: task.priority == .none ? "No priority" : "\(task.priority.title) priority", color: Palette.priority(task.priority), fill: Studio.well)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Change the priority")

            if let agent = task.agentKind {
                AgentChip(agent: agent)
            }
            if let raw = task.rawStatus, task.origin == .file {
                Text("status: \(raw)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Studio.faint)
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(session: SessionInfo?) -> some View {
        HStack(spacing: 8) {
            if task.origin.isPlanned || task.origin == .suggested {
                StartWithMenu(taskID: task.id)
            }
            if task.sessionID != nil && task.origin != .suggested {
                let agent = session?.agentKind ?? task.agentKind ?? .claudeCode
                Button {
                    store.resume(task.id)
                } label: {
                    Label(agent.runsInTerminal ? "Resume in Terminal" : "Open in \(agent.title)", systemImage: agent.runsInTerminal ? "terminal" : "arrow.up.forward.app")
                }
                .buttonStyle(.studio(task.origin.isPlanned ? .secondary : .primary))
                .help(agent == .claudeCode ? "claude --resume in Terminal" : "Continue this \(agent.title) session")
            }
            Menu {
                Button("Copy Key and Title") { store.copyKey(task.id) }
                Button("Copy Prompt") { store.copyPrompt(task.id) }
                if session?.transcriptPath != nil {
                    Button("Reveal Transcript in Finder") { store.revealTranscript(task.id) }
                }
                Button("Open Project Folder") { store.openFolder(task.id) }
                if task.filePath != nil {
                    Button("Open Task File") { store.openFile(task.id) }
                    Button("Reveal Task File in Finder") { store.revealFile(task.id) }
                }
                Divider()
                if task.origin == .manual {
                    Button("Delete Task", role: .destructive) { store.deleteManual(task.id) }
                } else {
                    Button(task.hidden ? "Unhide" : "Hide from the board") { store.setHidden(task.id, !task.hidden) }
                }
            } label: {
                HeaderMenuLabel(text: "More")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func waiting(ask: String, session: SessionInfo?) -> some View {
        let agent = session?.agentKind ?? task.agentKind ?? .claudeCode
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentAvatar(agent: agent, size: 20)
                Text("\(agent.title) is waiting on you · \(Fmt.ago(task.lastActivity))")
                    .font(Studio.text(12.5, .heavy))
                    .foregroundStyle(Studio.coralInk)
            }
            Text(Markdown.inline(PromptText.truncate(ask, 900)))
                .font(Studio.text(16, .bold))
                .foregroundStyle(Studio.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if task.sessionID != nil {
                    Button(agent.runsInTerminal ? "Answer in Terminal" : "Answer in \(agent.title)") { store.resume(task.id) }
                        .buttonStyle(.studio(.primary))
                }
                Button("Copy question") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ask, forType: .string)
                }
                .buttonStyle(.studio(.white))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Studio.coralBg))
    }

    // MARK: Sections

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Description").font(Studio.display(14)).foregroundStyle(Studio.ink)
                Spacer()
                Text("Captured \(task.createdAt.formatted(date: .abbreviated, time: .omitted))").font(Studio.text(11.5, .semibold)).foregroundStyle(Studio.faint)
            }
            if editingBody {
                TextEditor(text: $notes)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.well))
                HStack {
                    Button("Save to file") {
                        store.setNotes(task.id, notes)
                        editingBody = false
                    }
                    .buttonStyle(.studio(.primary, size: 12))
                    Button("Cancel") { notes = task.notes; editingBody = false }.buttonStyle(.studio(.secondary, size: 12))
                }
            } else {
                ExpandableText(text: task.prompt.isEmpty ? "No description yet." : task.prompt, limit: 1400, font: Studio.text(13.5), markdown: true)
                    .foregroundStyle(Studio.ink)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Studio.well))
                HStack(spacing: 14) {
                    Button("Edit here") { notes = task.notes; editingBody = true }
                    Button("Open in editor") { store.openFile(task.id) }
                }
                .buttonStyle(.plain)
                .font(Studio.text(12.5, .bold))
                .foregroundStyle(Studio.blueInk)
            }
        }
    }

    /// Fields: project, area, labels, due date, session, file, linked task, branch.
    private var details: some View {
        let session = store.session(task.sessionID)
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
            if task.origin.isPlanned {
                GridRow {
                    label("Project")
                    ProjectMenu(selection: Binding(get: { task.projectID }, set: { if let p = $0 { store.setProject(task.id, p) } }))
                        .help(task.origin == .file ? "Writes `project:` into the task file" : "Moves the task (it gets a new key)")
                }
                GridRow {
                    label("Area")
                    inlineField("Frontend, Observability", text: $area) { store.setArea(task.id, area) }
                }
            }
            GridRow {
                label("Labels")
                inlineField("comma, separated", text: $labels) { store.setLabels(task.id, labels) }
            }
            GridRow {
                label("Due")
                HStack {
                    if let due = task.due {
                        DatePicker("", selection: Binding(get: { due }, set: { store.setDue(task.id, $0) }), displayedComponents: .date)
                            .labelsHidden()
                        Button { store.setDue(task.id, nil) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(Studio.faint).help("Remove the due date")
                    } else {
                        Button("Set a due date") { store.setDue(task.id, Calendar.current.date(byAdding: .day, value: 1, to: Date())) }
                            .buttonStyle(.plain).font(Studio.text(13, .bold)).foregroundStyle(Studio.blueInk)
                    }
                }
            }
            if let s = session {
                GridRow {
                    label("Session")
                    HStack(spacing: 6) {
                        if s.isLive { LiveDot(busy: s.isBusy) }
                        Text("\(s.title) · \(s.agentKind.title)").lineLimit(2).textSelection(.enabled)
                    }
                }
            }
            if let path = task.filePath {
                GridRow {
                    label("File")
                    Button { store.revealFile(task.id) } label: {
                        Text(Paths.tilde(path)).font(.system(size: 11.5, design: .monospaced)).lineLimit(2).truncationMode(.head)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Studio.blueInk)
                    .help("Show in Finder")
                }
            }
            if let link = task.plannedLink, let planned = store.task(link) {
                GridRow {
                    label("Task")
                    Button { store.selection = planned.id } label: {
                        Text("\(store.key(for: planned)) \(planned.title)").lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Studio.blueInk)
                    .help("This request mentions the task's key")
                }
            }
            if let b = task.branch {
                GridRow {
                    label("Branch")
                    Text(b).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
        .font(Studio.text(13, .medium))
        .foregroundStyle(Studio.ink)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Studio.line, lineWidth: 1))
    }

    /// Agent requests that mentioned this task's key or were started from it.
    @ViewBuilder
    private var agentWork: some View {
        let linked = store.linkedClaudeTickets(task)
        panel("Agents on this task", detail: linked.isEmpty ? nil : "\(linked.count)") {
            if linked.isEmpty {
                Text("No agent has mentioned \(store.key(for: task)) yet. Start one above, or mention the key in any prompt.")
                    .font(Studio.text(12.5, .medium)).foregroundStyle(Studio.muted)
            }
            ForEach(linked) { l in
                Button { store.selection = l.id } label: {
                    HStack(alignment: .top, spacing: 10) {
                        AgentAvatar(agent: l.agentKind ?? .claudeCode, size: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(l.title).font(Studio.text(13, .bold)).foregroundStyle(Studio.ink).lineLimit(2)
                                Spacer(minLength: 4)
                                StatusBadge(status: l.status)
                            }
                            HStack(spacing: 6) {
                                Text(store.key(for: l)).monospacedDigit()
                                if let s = store.session(l.sessionID), s.isLive { LiveDot(busy: s.isBusy) }
                                Text(Fmt.ago(l.lastActivity))
                            }
                            .font(Studio.text(11.5, .semibold)).foregroundStyle(Studio.muted)
                            if let r = l.recap ?? l.pendingAsk {
                                Text(Markdown.plain(r, limit: 180)).font(Studio.text(12.5)).foregroundStyle(Studio.ink2).lineLimit(2)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Studio.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var plan: some View {
        let p = task.subtaskProgress
        return panel("Plan", detail: p.total > 0 ? "\(p.done) of \(p.total) done" : nil) {
            if p.total > 0 {
                GeometryReader { g in
                    Capsule().fill(Studio.well)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Palette.project(store.project(task.projectID).colorIndex))
                                .frame(width: max(8, g.size.width * CGFloat(p.done) / CGFloat(max(1, p.total))))
                        }
                }
                .frame(height: 7)
                .accessibilityHidden(true)
            }
            ForEach(task.subtasks) { sub in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button { store.toggleSubtask(task.id, sub.id) } label: {
                        Image(systemName: icon(sub.state))
                            .font(.system(size: 15))
                            .foregroundStyle(sub.state == .completed ? Palette.status(.done) : sub.state == .inProgress ? Studio.blue : Studio.faint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sub.state == .completed ? "Mark not done" : "Mark done")
                    Text(sub.title)
                        .font(Studio.text(13.5, .medium))
                        .strikethrough(sub.state == .completed, color: Studio.faint)
                        .foregroundStyle(sub.state == .completed ? Studio.muted : Studio.ink)
                        .textSelection(.enabled)
                    Spacer()
                    if task.origin.isPlanned {
                        Button { store.removeSubtask(task.id, sub.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).foregroundStyle(Studio.faint).help("Remove this step")
                    }
                }
            }
            if task.origin.isPlanned {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle").foregroundStyle(Studio.muted)
                    TextField("Add a step", text: $newSubtask)
                        .textFieldStyle(.plain)
                        .font(Studio.text(13.5, .medium))
                        .onSubmit {
                            store.addSubtask(task.id, newSubtask)
                            newSubtask = ""
                        }
                }
            }
        }
    }

    private var worklog: some View {
        let s = task.stats
        let end = s.endedAt ?? task.updatedAt
        let agent = (task.agentKind ?? .claudeCode).title
        return panel("Work", detail: nil) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                metric("Active time", Fmt.duration(s.activeSeconds ?? 0))
                metric("Tool calls", "\(s.toolCalls)")
                metric("Edits", "\(s.edits)")
                metric("Elapsed", Fmt.duration(end.timeIntervalSince(task.createdAt)))
                metric("Shell · subagents", "\(s.bashCalls) · \(s.agentCalls)")
                metric("Files touched", "\(s.filesTouched.count)")
            }
            if !s.filesTouched.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(s.filesTouched.prefix(25), id: \.self) { f in
                        Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) } label: {
                            Text(shortPath(f)).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.head)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Studio.blueInk)
                    }
                    if s.filesTouched.count > 25 {
                        Text("+\(s.filesTouched.count - 25) more").font(Studio.text(12, .semibold)).foregroundStyle(Studio.muted)
                    }
                }
            }
            if task.origin == .history {
                Text("\(agent) cleaned up the full transcript for this session, so only your prompts remain.")
                    .font(Studio.text(12, .medium)).foregroundStyle(Studio.muted)
            }
        }
    }

    // MARK: Pieces

    private func panel<C: View>(_ title: String, detail: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(Studio.display(14)).foregroundStyle(Studio.ink)
                if let detail { Text(detail).font(Studio.text(12, .semibold)).foregroundStyle(Studio.muted) }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(Studio.text(12.5, .semibold)).foregroundStyle(Studio.muted).gridColumnAlignment(.leading)
    }

    private func inlineField(_ prompt: String, text: Binding<String>, submit: @escaping () -> Void) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(Studio.text(13, .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Studio.well))
            .onSubmit(submit)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Studio.display(18)).foregroundStyle(Studio.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Studio.text(11.5, .semibold)).foregroundStyle(Studio.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.well))
    }

    private func shortPath(_ p: String) -> String {
        if let cwd = task.cwd, p.hasPrefix(cwd + "/") { return String(p.dropFirst(cwd.count + 1)) }
        return p.replacingOccurrences(of: Paths.home, with: "~")
    }

    private func icon(_ s: SubtaskState) -> String {
        switch s {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "circle.lefthalf.filled"
        case .pending: return "circle"
        }
    }

    /// Saves edits that were typed but not submitted before switching tickets.
    private func flush(_ id: String) {
        notesSave?.cancel()
        guard let t = store.task(id) else { return }
        // Only what you changed in this panel is written; backlog files only from an explicit edit.
        if (t.origin != .file || editingBody) && notes != synced.notes && notes != t.notes { store.setNotes(id, notes) }
        if !title.isEmpty && title != synced.title && title != t.title { store.setTitle(id, title) }
        if t.origin.isPlanned && area != synced.area && area != (t.area ?? "") { store.setArea(id, area) }
        let l = labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if labels != synced.labels && l != t.labels { store.setLabels(id, labels) }
    }

    private func sync() {
        title = task.title
        notes = task.notes
        labels = task.labels.joined(separator: ", ")
        newSubtask = ""
        showReply = task.recap == nil
        area = task.area ?? ""
        editingBody = false
        synced = (title, notes, labels, area)
    }
}

/// "Start with Claude Code ▾": starts the default agent on a click, or pick another from the menu.
struct StartWithMenu: View {
    @Environment(Store.self) private var store
    let taskID: String
    var size: CGFloat = 13

    var body: some View {
        let agent = store.defaultAgent
        HStack(spacing: 0) {
            Button {
                store.start(taskID, with: agent)
            } label: {
                Label("Start with \(agent.title)", systemImage: "play.fill")
                    .font(Studio.text(size, .bold))
                    .padding(.leading, size * 1.1)
                    .padding(.trailing, 8)
                    .padding(.vertical, size * 0.55)
            }
            .buttonStyle(.plain)
            .help(agent.runsInTerminal ? "Opens Terminal in the project folder and hands this task to \(agent.title)"
                  : "Opens the project in \(agent.title) with the task on the clipboard")
            Rectangle().fill(Studio.onInk.opacity(0.25)).frame(width: 1, height: size * 1.4)
            Menu {
                ForEach(Agent.allCases) { a in
                    Button(a.title) { store.start(taskID, with: a) }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: size * 0.7, weight: .heavy))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 6)
            .padding(.trailing, size * 0.9)
            .help("Start with another agent")
        }
        .foregroundStyle(Studio.onInk)
        .tint(Studio.onInk)
        .background(Capsule().fill(Studio.ink))
    }
}
