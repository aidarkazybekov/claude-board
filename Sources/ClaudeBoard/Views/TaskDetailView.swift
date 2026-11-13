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

    var body: some View {
        let info = store.project(task.projectID)
        let session = store.session(task.sessionID)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        KeyLabel(text: store.key(for: task))
                        ProjectChip(info: info, showWorkspace: true)
                        Spacer()
                        OriginIcon(origin: task.origin).foregroundStyle(.secondary)
                        Text(task.origin.title).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .onSubmit { store.setTitle(task.id, title) }
                    if task.hidden {
                        Label("Hidden: not counted as a task", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary)
                    }
                }

                // Fields
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Status").foregroundStyle(.secondary)
                        HStack {
                            Menu {
                                ForEach(TaskStatus.allCases) { s in
                                    Button(s.title) { store.setStatus(task.id, s) }
                                }
                            } label: {
                                StatusBadge(status: task.status, overridden: task.statusOverridden)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            if let raw = task.rawStatus, task.origin == .file {
                                Text("status: \(raw)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                            }
                            if task.statusOverridden {
                                Button("Reset to \(task.inferredStatus.title)") { store.clearStatusOverride(task.id) }
                                    .buttonStyle(.link).font(.caption)
                                    .help("Claude's transcript suggests \(task.inferredStatus.title)")
                            }
                        }
                    }
                    GridRow {
                        Text("Priority").foregroundStyle(.secondary)
                        Picker("", selection: Binding(get: { task.priority }, set: { store.setPriority(task.id, $0) })) {
                            ForEach(Priority.allCases.reversed()) { p in
                                Label(p.title, systemImage: p.symbol).tag(p)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    if task.origin.isPlanned {
                        GridRow {
                            Text("Project").foregroundStyle(.secondary)
                            ProjectMenu(selection: Binding(get: { task.projectID }, set: { if let p = $0 { store.setProject(task.id, p) } }))
                                .help(task.origin == .file ? "Writes `project:` into the task file" : "Moves the task (it gets a new key)")
                        }
                        GridRow {
                            Text("Area").foregroundStyle(.secondary)
                            TextField("e.g. Frontend, Observability", text: $area)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { store.setArea(task.id, area) }
                        }
                    }
                    GridRow {
                        Text("Labels").foregroundStyle(.secondary)
                        TextField("comma, separated", text: $labels)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { store.setLabels(task.id, labels) }
                    }
                    GridRow {
                        Text("Due").foregroundStyle(.secondary)
                        HStack {
                            if let due = task.due {
                                DatePicker("", selection: Binding(get: { due }, set: { store.setDue(task.id, $0) }), displayedComponents: .date)
                                    .labelsHidden()
                                Button { store.setDue(task.id, nil) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                            } else {
                                Button("Set due date") { store.setDue(task.id, Calendar.current.date(byAdding: .day, value: 1, to: Date())) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                    if let s = session {
                        GridRow {
                            Text("Session").foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                if s.isLive { LiveDot(busy: s.isBusy) }
                                Text(s.title).lineLimit(2).textSelection(.enabled)
                            }
                        }
                    }
                    if let path = task.filePath {
                        GridRow {
                            Text("File").foregroundStyle(.secondary)
                            Button {
                                store.revealFile(task.id)
                            } label: {
                                Text(Paths.tilde(path)).font(.system(.caption, design: .monospaced)).lineLimit(2).truncationMode(.head)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    if let link = task.plannedLink, let planned = store.task(link) {
                        GridRow {
                            Text("Task").foregroundStyle(.secondary)
                            Button {
                                store.selection = planned.id
                            } label: {
                                Text("\(store.key(for: planned)) \(planned.title)").lineLimit(2)
                            }
                            .buttonStyle(.link)
                            .help("This Claude request mentions the task's key")
                        }
                    }
                    if let b = task.branch {
                        GridRow {
                            Text("Branch").foregroundStyle(.secondary)
                            Text(b).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
                .font(.callout)

                actions(session: session)

                // Waiting on you
                if let ask = task.pendingAsk ?? (task.status == .needsYou ? session?.needsAction : nil) {
                    callout(icon: "questionmark.bubble.fill", color: Palette.status(.needsYou), title: "Claude is waiting on you", text: ask)
                }

                if task.origin == .file {
                    section("Description", icon: "doc.text") {
                        if editingBody {
                            TextEditor(text: $notes)
                                .font(.system(.callout, design: .monospaced))
                                .frame(minHeight: 220)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Button("Save to File") {
                                    store.setNotes(task.id, notes)
                                    editingBody = false
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Cancel") { notes = task.notes; editingBody = false }
                            }
                        } else {
                            ExpandableText(text: task.prompt.isEmpty ? "No description yet." : task.prompt, limit: 1400, font: .callout, markdown: true)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            HStack {
                                Button("Edit Here") { notes = task.notes; editingBody = true }.buttonStyle(.link)
                                Button("Open in Editor") { store.openFile(task.id) }.buttonStyle(.link)
                                Spacer()
                                Text("Captured \(task.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    section(task.origin == .manual ? "Task" : "Request", icon: "text.bubble") {
                        ExpandableText(text: task.prompt, limit: 900, font: .callout)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        Text(task.createdAt.formatted(date: .complete, time: .shortened))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }

                if task.origin.isPlanned {
                    claudeWork
                }

                if !task.subtasks.isEmpty || task.origin.isPlanned {
                    section("Plan · \(task.subtaskProgress.done)/\(task.subtaskProgress.total)", icon: "checklist") {
                        if task.subtaskProgress.total > 0 {
                            ProgressView(value: Double(task.subtaskProgress.done), total: Double(max(1, task.subtaskProgress.total)))
                                .tint(Palette.status(.done))
                        }
                        ForEach(task.subtasks) { sub in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Button { store.toggleSubtask(task.id, sub.id) } label: {
                                    Image(systemName: icon(sub.state))
                                        .foregroundStyle(sub.state == .completed ? Palette.status(.done) : sub.state == .inProgress ? Palette.status(.inProgress) : .secondary)
                                }
                                .buttonStyle(.borderless)
                                Text(sub.title)
                                    .font(.callout)
                                    .strikethrough(sub.state == .completed, color: .secondary)
                                    .foregroundStyle(sub.state == .completed ? .secondary : .primary)
                                    .textSelection(.enabled)
                                Spacer()
                                if task.origin.isPlanned {
                                    Button { store.removeSubtask(task.id, sub.id) } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        if task.origin.isPlanned {
                            HStack {
                                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                                TextField("Add a step", text: $newSubtask)
                                    .textFieldStyle(.plain)
                                    .onSubmit {
                                        store.addSubtask(task.id, newSubtask)
                                        newSubtask = ""
                                    }
                            }
                            .font(.callout)
                        }
                    }
                }

                if let recap = task.recap {
                    section("Outcome", icon: "flag.checkered") {
                        Text(Markdown.inline(recap)).font(.callout).textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.status(.done).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                if let reply = task.finalReply {
                    DisclosureGroup(isExpanded: $showReply) {
                        ExpandableText(text: reply, limit: 1500, font: .callout, markdown: true)
                            .padding(.top, 4)
                    } label: {
                        Label("Claude's last reply", systemImage: "sparkle").font(.subheadline.weight(.semibold))
                    }
                }

                if !task.followUps.isEmpty {
                    section("Conversation · \(task.followUps.count) follow-ups", icon: "bubble.left.and.bubble.right") {
                        ForEach(Array(task.followUps.enumerated()), id: \.offset) { _, ex in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Fmt.time.string(from: ex.at)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                    .frame(width: 58, alignment: .leading)
                                Text(PromptText.truncate(ex.text, 400)).font(.callout).textSelection(.enabled)
                            }
                        }
                    }
                }

                if !task.origin.isPlanned && task.origin != .suggested {
                    section("Worklog", icon: "hammer") {
                        worklog
                    }
                }

                if task.origin != .file {
                section("Notes", icon: "note.text") {
                    TextEditor(text: $notes)
                        .font(.callout)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
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
            .padding(16)
        }
        .onAppear(perform: sync)
        .onChange(of: task.id) { old, _ in
            flush(old)
            sync()
        }
        .onDisappear { flush(task.id) }
    }

    @State private var notesSave: Task<Void, Never>?

    /// Saves edits that were typed but not submitted before switching tickets.
    private func flush(_ id: String) {
        notesSave?.cancel()
        guard let t = store.task(id) else { return }
        // Backlog files are only written from an explicit edit, never from stale view state.
        if t.origin != .file || editingBody { if notes != t.notes { store.setNotes(id, notes) } }
        if !title.isEmpty && title != t.title { store.setTitle(id, title) }
        if t.origin.isPlanned && area != (t.area ?? "") { store.setArea(id, area) }
        let l = labels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if l != t.labels { store.setLabels(id, labels) }
    }

    private func sync() {
        title = task.title
        notes = task.notes
        labels = task.labels.joined(separator: ", ")
        newSubtask = ""
        showReply = task.recap == nil
        area = task.area ?? ""
        editingBody = false
    }

    /// Claude requests that mentioned this task's key or were started from it.
    @ViewBuilder
    private var claudeWork: some View {
        let linked = store.linkedClaudeTickets(task)
        section("Claude's work on this · \(linked.count)", icon: "sparkle") {
            if linked.isEmpty {
                Text("No Claude session has mentioned \(store.key(for: task)) yet. Start one with the button above, or mention the key in any prompt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(linked) { l in
                Button {
                    store.selection = l.id
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: l.status.symbol).foregroundStyle(Palette.status(l.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.title).lineLimit(2)
                            HStack(spacing: 6) {
                                KeyLabel(text: store.key(for: l))
                                if let s = store.session(l.sessionID) {
                                    if s.isLive { LiveDot(busy: s.isBusy) }
                                    Text(s.title).lineLimit(1)
                                }
                                Text(Fmt.ago(l.lastActivity))
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                            if let r = l.recap ?? l.pendingAsk {
                                Text(Markdown.plain(r, limit: 180)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func actions(session: SessionInfo?) -> some View {
        HStack(spacing: 8) {
            if task.origin.isPlanned || task.origin == .suggested {
                Button {
                    store.startWithClaude(task.id)
                } label: {
                    Label("Start with Claude", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Opens Terminal in the project folder and hands this ticket to Claude Code")
            }
            if task.sessionID != nil && task.origin != .suggested {
                Button {
                    store.resume(task.id)
                } label: {
                    Label("Resume", systemImage: "terminal")
                }
                .help("claude --resume in Terminal")
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
                    Button(task.hidden ? "Unhide" : "Hide from ClaudeBoard") { store.setHidden(task.id, !task.hidden) }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .fixedSize()
        }
        .controlSize(.regular)
    }

    private var worklog: some View {
        let s = task.stats
        let end = s.endedAt ?? task.updatedAt
        return VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    metric("Claude active time", Fmt.duration(s.activeSeconds ?? 0))
                    metric("Tool calls", "\(s.toolCalls)")
                    metric("Edits", "\(s.edits)")
                }
                GridRow {
                    metric("Elapsed", Fmt.duration(end.timeIntervalSince(task.createdAt)))
                    metric("Shell · subagents", "\(s.bashCalls) · \(s.agentCalls)")
                    metric("Files touched", "\(s.filesTouched.count)")
                }
            }
            if !s.filesTouched.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(s.filesTouched.prefix(25), id: \.self) { f in
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)])
                        } label: {
                            Text(shortPath(f)).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.head)
                        }
                        .buttonStyle(.link)
                    }
                    if s.filesTouched.count > 25 {
                        Text("+\(s.filesTouched.count - 25) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if task.origin == .history {
                Text("The full transcript for this session was cleaned up by Claude Code, so only your prompts remain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func shortPath(_ p: String) -> String {
        if let cwd = task.cwd, p.hasPrefix(cwd + "/") { return String(p.dropFirst(cwd.count + 1)) }
        return p.replacingOccurrences(of: Paths.home, with: "~")
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.body, design: .rounded).weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func icon(_ s: SubtaskState) -> String {
        switch s {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "circle.lefthalf.filled"
        case .pending: return "circle"
        }
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func callout(icon: String, color: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(text).font(.callout).textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
