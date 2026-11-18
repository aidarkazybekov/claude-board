import Foundation

struct IngestResult {
    var startedAt = Date()
    var plannedTasks: [TaskItem] = []
    var taskFolders: [String] = []
    var repos: [String] = []
    var transcriptTasks: [TaskItem] = []
    var transcriptSessionIDs: Set<String> = []
    var historyTasks: [String: [TaskItem]] = [:]
    var sessions: [SessionInfo] = []
    var live: [String: LiveSession] = [:]
    var dataChanged = false
    var duration: TimeInterval = 0
    var bytesRead: UInt64 = 0
}

/// Owns every data-source reader and produces a fresh view of all Claude work on each pass.
/// Not thread-safe: call `run()` from one serial queue.
final class Ingestor: @unchecked Sendable {
    private var parsers: [String: TranscriptParser] = [:]
    private let history = HistoryLoader()
    private let desktop = DesktopIndex()
    private var firstRun = true
    private var runs = 0
    private var lastDiscoverySeconds: TimeInterval = 0
    private var discovered = Discovery.Result()
    private var discoveredRoots: [String] = []
    private var fileCache: [String: (mtime: Date, file: TaskFile)] = [:]
    private let codex = CodexReader()
    private let cursor = CursorReader()
    private let gemini = GeminiReader()
    private let antigravity = AntigravityReader()

    /// Agents turned off in Settings; their history isn't read.
    var disabledAgents: Set<Agent> = []

    /// Folders added or ignored in Settings; set from the main thread before a run.
    var extraFolders: [String] = []
    var ignoredFolders: [String] = []
    var forceDiscovery = false

    func run() -> IngestResult {
        let started = Date()
        var result = IngestResult()
        result.startedAt = started
        let fm = FileManager.default

        // 0. Repos and backlog folders under the project roots. A scan is usually a few ms, so it runs on
        //    every refresh and new folders show up right away; very large roots fall back to every ~5 minutes.
        let roots = Roots.all
        let cheap = lastDiscoverySeconds < 0.25
        if firstRun || forceDiscovery || roots != discoveredRoots || cheap || runs % 15 == 0 {
            let t = Date()
            discovered = Discovery.scan(roots: roots)
            lastDiscoverySeconds = Date().timeIntervalSince(t)
            discoveredRoots = roots
            forceDiscovery = false
            ProjectRegistry.shared.set(repos: discovered.repos)
            result.dataChanged = true
        }
        runs += 1
        result.repos = discovered.repos
        let folders = Array(Set(discovered.taskFolders + extraFolders.filter { fm.fileExists(atPath: $0) }))
            .filter { !ignoredFolders.contains($0) }.sorted()
        result.taskFolders = folders
        var seenFiles = Set<String>()
        for folder in folders {
            for path in TaskFolder.taskFiles(in: folder) {
                seenFiles.insert(path)
                let mtime = ((try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
                let file: TaskFile
                if let c = fileCache[path], c.mtime == mtime {
                    file = c.file
                } else {
                    guard let f = TaskFolder.parse(path, folder: folder) else { continue }
                    fileCache[path] = (mtime, f)
                    file = f
                    result.dataChanged = true
                }
                result.plannedTasks.append(Self.item(from: file))
            }
        }
        for k in fileCache.keys where !seenFiles.contains(k) { fileCache[k] = nil; result.dataChanged = true }

        // 1. Transcripts: only top-level <session>.jsonl files; subagent logs live in subfolders.
        var present = Set<String>()
        var bytesBefore: UInt64 = 0
        var bytesAfter: UInt64 = 0
        for dir in (try? fm.contentsOfDirectory(atPath: Paths.projectsDir)) ?? [] {
            let full = Paths.projectsDir + "/" + dir
            for f in (try? fm.contentsOfDirectory(atPath: full)) ?? [] where f.hasSuffix(".jsonl") {
                let path = full + "/" + f
                present.insert(path)
                let parser = parsers[path] ?? TranscriptParser(url: URL(fileURLWithPath: path))
                parsers[path] = parser
                bytesBefore += parser.offset
                if parser.update() { result.dataChanged = true }
                bytesAfter += parser.offset
            }
        }
        for k in parsers.keys where !present.contains(k) {
            parsers[k] = nil
            result.dataChanged = true
        }
        result.bytesRead = bytesAfter &- bytesBefore

        if history.update() { result.dataChanged = true }
        if desktop.update() { result.dataChanged = true }
        let live = LiveSessions.load()
        result.live = live
        if firstRun { result.dataChanged = true; firstRun = false }

        // 2. Sessions with transcripts.
        for parser in parsers.values {
            let sid = parser.sessionID
            let tasks = parser.tasks
            guard !tasks.isEmpty || parser.promptCount > 0 else { continue }
            result.transcriptSessionIDs.insert(sid)
            result.transcriptTasks.append(contentsOf: tasks)
            result.transcriptTasks.append(contentsOf: parser.suggestions)

            let d = desktop.byCLI[sid]
            let cwd = parser.cwd ?? d?.cwd ?? ""
            var s = SessionInfo(
                id: sid,
                projectID: ProjectResolver.projectID(for: cwd),
                title: d?.title ?? parser.title ?? tasks.first?.title ?? "Untitled session",
                cwd: cwd,
                startedAt: parser.firstAt ?? d?.createdAt ?? Date(),
                lastActivity: parser.lastAt ?? d?.lastActivityAt ?? Date(),
                transcriptPath: parser.url.path,
                desktopID: d?.localID,
                archived: d?.archived ?? false,
                promptCount: parser.promptCount,
                entrypoint: parser.entrypoint
            )
            apply(desktop: d, live: live[sid], to: &s)
            result.sessions.append(s)
        }

        // 3. Sessions only known from prompt history.
        for sid in history.bySession.keys where !result.transcriptSessionIDs.contains(sid) {
            let tasks = history.tasks(for: sid)
            guard let first = tasks.first else { continue }
            result.historyTasks[sid] = tasks
            let d = desktop.byCLI[sid]
            let entries = history.bySession[sid] ?? []
            var s = SessionInfo(
                id: sid,
                projectID: first.projectID,
                title: d?.title ?? first.title,
                cwd: first.cwd ?? "",
                startedAt: entries.map(\.at).min() ?? first.createdAt,
                lastActivity: entries.map(\.at).max() ?? first.updatedAt,
                desktopID: d?.localID,
                archived: d?.archived ?? false,
                promptCount: entries.count
            )
            apply(desktop: d, live: live[sid], to: &s)
            result.sessions.append(s)
        }

        // 4. Other agents, each from its own history on this Mac.
        let readers: [(Agent, () -> Bool, () -> ([TaskItem], [SessionInfo]))] = [
            (.codex, { self.codex.update() }, { (self.codex.tasks, self.codex.sessions) }),
            (.cursor, { self.cursor.update() }, { (self.cursor.tasks, self.cursor.sessions) }),
            (.gemini, { self.gemini.update() }, { (self.gemini.tasks, self.gemini.sessions) }),
            (.antigravity, { self.antigravity.update() }, { (self.antigravity.tasks, self.antigravity.sessions) }),
        ]
        for (agent, update, output) in readers where !disabledAgents.contains(agent) {
            if update() { result.dataChanged = true }
            let (tasks, sessions) = output()
            result.transcriptTasks.append(contentsOf: tasks)
            result.transcriptSessionIDs.formUnion(sessions.map(\.id))
            result.sessions.append(contentsOf: sessions)
        }

        result.duration = Date().timeIntervalSince(started)
        return result
    }

    static func item(from f: TaskFile) -> TaskItem {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let created = (f.fields["captured"] ?? f.fields["created"] ?? f.fields["created_date"] ?? f.fields["date"])
            .flatMap { df.date(from: String($0.prefix(10))) } ?? f.created
        let status = TaskFolder.column(for: f.fields["status"])
        var t = TaskItem(
            id: "file:\(f.folder)#\(f.id)",
            origin: .file,
            projectID: "",
            sessionID: nil,
            title: f.title,
            prompt: f.body.trimmingCharacters(in: .whitespacesAndNewlines),
            subtasks: TaskFolder.checklist(f.body),
            createdAt: created,
            updatedAt: f.mtime,
            inferredStatus: status,
            cwd: nil
        )
        t.status = status
        t.priority = TaskFolder.priority(f.fields["priority"])
        t.labels = f.labels
        t.due = (f.fields["due"] ?? f.fields["due_date"]).flatMap { df.date(from: String($0.prefix(10))) }
        t.filePath = f.path
        t.folder = f.folder
        t.externalID = f.id
        t.area = f.fields["area"]
        t.rawStatus = f.fields["status"]
        t.rawPriority = f.fields["priority"]
        t.projectHint = [f.fields["project"], f.fields["app"], f.fields["owner-session"], f.fields["component"]]
            .compactMap { $0 }.first
        t.notes = f.body
        t.doneAt = status == .done ? f.mtime : nil
        return t
    }

    private func apply(desktop d: DesktopSession?, live: LiveSession?, to s: inout SessionInfo) {
        if let d {
            s.summaryCategory = d.summaryCategory
            s.summaryDetail = d.summaryDetail
            s.needsAction = d.needsAction
        }
        if let live {
            s.isLive = true
            s.liveStatus = live.status
            if s.entrypoint == nil { s.entrypoint = live.entrypoint }
        }
    }

    // MARK: - Status inference

    /// Decides each ticket's column from what the transcript shows.
    static func inferStatuses(_ tasks: inout [TaskItem], session: SessionInfo?) {
        let order = tasks.indices.sorted { tasks[$0].createdAt < tasks[$1].createdAt }
        let requestIdx = order.filter { tasks[$0].origin == .prompt || tasks[$0].origin == .history }
        let latest = requestIdx.last
        for i in order {
            switch tasks[i].origin {
            case .suggested:
                tasks[i].inferredStatus = .backlog
                continue
            case .manual, .file:
                continue
            case .prompt, .history:
                break
            }
            guard i == latest else {
                tasks[i].inferredStatus = .done
                continue
            }
            let t = tasks[i]
            let unfinished = t.subtasks.contains { $0.state != .completed }
            let live = session?.isLive ?? false
            // A question only counts while it can still be answered: the session is open, or it was
            // active in the last day and isn't archived. Same rule for the CLI and the desktop app.
            let lastSeen = max(session?.lastActivity ?? t.lastActivity, t.lastActivity)
            let canAnswer = live || (Date().timeIntervalSince(lastSeen) < 86_400 && !(session?.archived ?? false))
            if let s = session, s.isBusy {
                tasks[i].inferredStatus = .inProgress
            } else if t.pendingAsk != nil && canAnswer {
                tasks[i].inferredStatus = .needsYou
            } else if let s = session, s.summaryCategory == "blocked" || s.needsAction != nil, canAnswer {
                tasks[i].inferredStatus = .needsYou
            } else if t.origin == .history {
                tasks[i].inferredStatus = live ? .inProgress : .done
            } else if !t.stats.replied {
                tasks[i].inferredStatus = live ? .inProgress : .todo
            } else if live, let reply = t.finalReply, reply.hasSuffix("?") {
                // A closing question beats unchecked plan steps: the agent is waiting on you either way.
                tasks[i].inferredStatus = .needsYou
            } else if unfinished && live {
                // Open steps only mean "in progress" while the session is still open.
                tasks[i].inferredStatus = .inProgress
            } else {
                tasks[i].inferredStatus = .done
            }
        }
    }
}
