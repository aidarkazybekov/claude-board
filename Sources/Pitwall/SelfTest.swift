import Foundation

/// `Pitwall --selftest` checks parsing and merge rules on synthetic data.
/// Run with PITWALL_DATA_DIR pointing at a temp folder so real data is untouched.
@MainActor
enum SelfTest {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        print((ok ? "  ✓ " : "  ✗ ") + what)
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IONBF, 0)
        guard ProcessInfo.processInfo.environment["PITWALL_DATA_DIR"] != nil else {
            print("set PITWALL_DATA_DIR to a temp folder first"); return 2
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cb-selftest-\(UUID().uuidString.prefix(6))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let cwd = Roots.primary + "/demo-shop"
        var n = 0
        func ts(_ s: Int) -> String {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: Date(timeIntervalSince1970: 1_790_000_000 + Double(s)))
        }
        func user(_ text: String, _ t: Int) -> String {
            n += 1
            let o: [String: Any] = ["type": "user", "uuid": "u\(n)", "timestamp": ts(t), "cwd": cwd, "gitBranch": "main",
                                    "origin": ["kind": "human"], "message": ["role": "user", "content": text]]
            return String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
        }
        func asst(_ parts: [[String: Any]], _ t: Int) -> String {
            let o: [String: Any] = ["type": "assistant", "timestamp": ts(t), "cwd": cwd, "message": ["role": "assistant", "content": parts]]
            return String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
        }
        func tool(_ name: String, _ input: [String: Any]) -> [String: Any] { ["type": "tool_use", "id": UUID().uuidString, "name": name, "input": input] }
        let toolResult = #"{"type":"user","timestamp":"\#(ts(9))","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"ok"}]}}"#

        let lines = [
            user("Build the login page with OAuth for the shop", 0),
            asst([tool("mcp__ccd_turn__update_plan", ["items": [["content": "A", "status": "in_progress"], ["content": "B", "status": "pending"], ["content": "C", "status": "pending"]]])], 10),
            asst([tool("mcp__ccd_turn__update_plan", ["advance": true])], 20),
            toolResult,
            asst([["type": "text", "text": "Done with A. Want me to continue?"]], 30),
            user("yes", 40),
            asst([tool("Edit", ["file_path": cwd + "/app/login.tsx"])], 50),
            asst([tool("mcp__ccd_turn__wrap_up", ["recap": "Login page built", "ask": "Ship it?"])], 60),
            user("<command-name>/model</command-name>\n<command-args></command-args>", 70),
            user("Now fix the flaky checkout test in CI please, it fails on main every other run", 1000),
            asst([tool("TaskCreate", ["subject": "Repro"]), tool("TaskUpdate", ["taskId": "1", "status": "completed"])], 1010),
            asst([tool("mcp__ccd_session__start_session", ["initiation": "own_initiative", "title": "Refactor auth module", "prompt": "brief"])], 1020),
        ]
        let file = tmp.appendingPathComponent("11111111-2222-3333-4444-555555555555.jsonl")
        try! (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)

        print("TranscriptParser")
        let p = TranscriptParser(url: file)
        p.update()
        check(p.tasks.count == 2, "two tickets (got \(p.tasks.count))")
        check(p.suggestions.count == 1, "one suggested follow-up")
        if p.tasks.count == 2 {
            let a = p.tasks[0], b = p.tasks[1]
            check(a.followUps.count == 1 && a.followUps[0].text == "yes", "short reply folded as follow-up")
            check(a.subtasks.map(\.state) == [.completed, .completed, .completed], "plan advanced and checked off by wrap_up")
            check(a.recap == "Login page built" && a.pendingAsk == "Ship it?", "recap and pending ask captured")
            check(a.stats.edits == 1 && a.stats.filesTouched.count == 1, "edit counted")
            check((a.stats.activeSeconds ?? 0) > 0, "active time measured")
            check(b.subtasks.first?.state == .completed, "TaskCreate/TaskUpdate tracked")
            check(a.projectID == cwd, "project from cwd")
            var ts = p.tasks + p.suggestions
            Ingestor.inferStatuses(&ts, session: nil)
            check(ts[0].inferredStatus == .done, "older ticket done")
            check(ts[1].inferredStatus == .todo, "unanswered latest ticket stays To Do")
            check(ts[2].inferredStatus == .backlog, "suggestion lands in Backlog")
        }
        // Incremental append
        let more = user("Also add Apple sign-in to the login page, same flow as Google please", 2000) + "\n"
        let h = try! FileHandle(forWritingTo: file); h.seekToEndOfFile(); h.write(more.data(using: .utf8)!); try? h.close()
        check(p.update() && p.tasks.count == 3, "appended prompt picked up incrementally")

        print("PromptText")
        check(PromptText.clean("<command-name>/design</command-name><command-args>landing page</command-args>") == "/design landing page", "skill command with args kept")
        check(PromptText.clean("!ls -la") == nil, "shell escapes dropped")
        check(PromptText.isFollowUp("давай", claudeAsked: false), "Russian reply folded")
        check(!PromptText.isFollowUp("Please refactor the payment service so it retries failed webhooks", claudeAsked: false), "real request kept")
        check(PromptText.title(from: "<pasted_content id=\"a\">\nstack trace here\n</pasted_content>") == "Pasted: stack trace here", "pasted-only title")

        print("Store: links between planned tasks and Claude tickets")
        guard p.tasks.count == 3 else { print("  (skipped: parser checks failed)"); return 1 }
        let store = Store()
        guard let manual = store.createTask(title: "Add Apple sign-in to the login page", projectID: cwd, notes: "", priority: .high,
                                            status: .todo, labels: ["auth"], destination: .local) else { check(false, "create local task"); return 1 }
        let manualKey = store.key(for: manual)
        var r = IngestResult()
        var imported = p.tasks
        imported[2].prompt = "[\(manualKey)] Add Apple sign-in to the login page"
        imported[1].prompt = "Now fix the flaky checkout test; it blocks \(manualKey) as well"
        r.transcriptTasks = imported + p.suggestions
        r.transcriptSessionIDs = [p.sessionID]
        r.sessions = [SessionInfo(id: p.sessionID, projectID: cwd, title: "Synthetic", cwd: cwd, startedAt: Date(), lastActivity: Date())]
        store.merge(r)
        let planned = store.task(manual.id)
        check(planned != nil && store.key(for: planned!) == manualKey, "planned task keeps key \(manualKey)")
        check(Set(planned?.claudeLinks ?? []) == Set([imported[2].id, imported[1].id]), "both Claude tickets linked to it")
        check(store.task(imported[2].id)?.folded == true && store.scoped.allSatisfy { $0.id != imported[2].id }, "ticket launched from the task is folded into it")
        check(store.task(imported[1].id)?.hidden == false && store.task(imported[1].id)?.plannedLink == manual.id, "ticket that only mentions the key stays visible, linked")
        if let f = store.task(imported[0].id) {
            store.setStatus(f.id, f.inferredStatus == .done ? .todo : .done)
            check(store.task(f.id)?.statusOverridden == true, "manual status override")
            store.setStatus(f.id, f.inferredStatus)
            check(store.task(f.id)?.statusOverridden == false, "moving back to inferred status clears override")
        }
        let keysBefore = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, store.key(for: $0)) })
        store.merge(IngestResult())
        check(store.items.filter { $0.sessionID == p.sessionID && !$0.origin.isPlanned }.count == 4, "tickets kept after transcript disappears")
        check(store.items.allSatisfy { keysBefore[$0.id] == nil || keysBefore[$0.id] == store.key(for: $0) }, "keys stable across merges")

        print("Backlog folders")
        let ws = tmp.appendingPathComponent("ws").path
        let fm = FileManager.default
        for d in ["backlog/tasks", "apps/billing/.git", "apps/web/.git", "apps/api/.git"] {
            try? fm.createDirectory(atPath: ws + "/" + d, withIntermediateDirectories: true)
        }
        let index = """
        # Backlog index

        | ID | Title | Area | Priority | Status |
        | --- | --- | --- | --- | --- |
        | [T-001](tasks/T-001-web-deploy.md) | Web deploy script — one page never ships | Apps | P1 | backlog |
        | [T-002](tasks/T-002-invoices.md) | Invoice export is off by one day | Apps | P2 | investigating |
        | [T-003](tasks/T-003-flags.md) | Decide whether we need a feature-flag service | Platform | P3 | backlog |

        ## Areas
        """
        try! index.write(toFile: ws + "/backlog/BACKLOG.md", atomically: true, encoding: .utf8)
        func taskFile(_ id: String, _ slug: String, _ title: String, _ pr: String, _ st: String, _ extra: String = "") {
            let body = "---\nid: \(id)\ntitle: \(title)\narea: Apps\npriority: \(pr)\nstatus: \(st)\ncaptured: 2026-08-27\n\(extra)---\n\n# \(id) — \(title)\n\nSome words.\n\n- [ ] first step\n- [x] second step\n"
            try! body.write(toFile: ws + "/backlog/tasks/\(id)-\(slug).md", atomically: true, encoding: .utf8)
        }
        taskFile("T-001", "web-deploy", "Web deploy script — one page never ships", "P1", "backlog")
        taskFile("T-002", "invoices", "Invoice export is off by one day", "P2", "investigating", "owner-session: billing\n")
        taskFile("T-003", "flags", "Decide whether we need a feature-flag service", "P3", "backlog")
        setenv("PITWALL_ROOTS", tmp.path, 1)
        let disc = Discovery.scan(roots: [tmp.path])
        check(disc.taskFolders == [ws + "/backlog"], "backlog folder discovered")
        check(Set(disc.repos) == Set([ws + "/apps/billing", ws + "/apps/web", ws + "/apps/api"]), "repos discovered")
        ProjectRegistry.shared.set(repos: disc.repos)
        let files = TaskFolder.taskFiles(in: ws + "/backlog").compactMap { TaskFolder.parse($0, folder: ws + "/backlog") }
        check(files.map(\.id) == ["T-001", "T-002", "T-003"], "task files parsed")
        check(TaskFolder.column(for: "investigating") == .todo && TaskFolder.column(for: "In Progress") == .inProgress, "status vocabulary mapped")
        var fr = IngestResult()
        fr.repos = disc.repos
        fr.taskFolders = disc.taskFolders
        fr.plannedTasks = files.map(Ingestor.item(from:))
        fr.startedAt = Date()
        store.merge(fr)
        let t1 = "file:\(ws)/backlog#T-001", t2 = "file:\(ws)/backlog#T-002", t3 = "file:\(ws)/backlog#T-003"
        check(store.task(t1)?.projectID == ws + "/apps/web", "T-001 filed under web (named in title)")
        check(store.task(t2)?.projectID == ws + "/apps/billing", "T-002 filed under billing (owner-session)")
        check(store.task(t3)?.projectID == ws, "T-003 stays with the workspace")
        check(store.task(t1)?.priority == .high && store.task(t2)?.status == .todo, "priority and status read")
        check(store.key(for: store.task(t1)!) == "T-001", "file id is the key")

        store.setStatus(t1, .inProgress)
        let f1 = try! String(contentsOfFile: ws + "/backlog/tasks/T-001-web-deploy.md", encoding: .utf8)
        check(f1.contains("status: in-progress") && f1.contains("captured: 2026-08-27") && f1.contains("Some words."), "status written, rest of file intact")
        store.setPriority(t2, .urgent)
        let f2 = try! String(contentsOfFile: ws + "/backlog/tasks/T-002-invoices.md", encoding: .utf8)
        check(f2.contains("priority: P0") && f2.contains("status: investigating"), "priority written in P-style, status untouched")
        let idx = try! String(contentsOfFile: ws + "/backlog/BACKLOG.md", encoding: .utf8)
        check(idx.contains("| P1 | in-progress |") && idx.contains("| P0 | investigating |") && idx.contains("## Areas"), "index rows updated in place")
        store.setStatus(t2, .todo)
        check((try! String(contentsOfFile: ws + "/backlog/tasks/T-002-invoices.md", encoding: .utf8)).contains("status: investigating"), "same column keeps the original word")

        if let sub = store.task(t1)?.subtasks.first {
            store.toggleSubtask(t1, sub.id)
            let f = try! String(contentsOfFile: ws + "/backlog/tasks/T-001-web-deploy.md", encoding: .utf8)
            check(f.contains("- [x] first step") && f.contains("- [x] second step"), "checklist item ticked in file")
        }
        let created = store.createTask(title: "Add CSV export: invoices", projectID: ws + "/apps/billing", notes: "Finance asked.", priority: .medium,
                                       status: .backlog, subtasks: ["Export button"], area: "Apps")
        check(created?.externalID == "T-004", "new task gets next id T-004")
        check(created?.projectID == ws + "/apps/billing", "new task filed under billing")
        if let p4 = created?.filePath {
            let f = try! String(contentsOfFile: p4, encoding: .utf8)
            check(f.contains("project: apps/billing") && f.contains("title: \"Add CSV export: invoices\"") && f.contains("- [ ] Export button"), "task file written with quoted title, project, checklist")
            let idx2 = try! String(contentsOfFile: ws + "/backlog/BACKLOG.md", encoding: .utf8)
            check(idx2.contains("| [T-004](tasks/T-004-add-csv-export-invoices.md) | Add CSV export: invoices | Apps | P2 | backlog |"), "index row appended")
            let reparsed = TaskFolder.parse(p4, folder: ws + "/backlog")
            check(reparsed?.title == "Add CSV export: invoices", "quoted title round-trips")
        }
        // A Claude ticket in billing mentioning T-002 links to it
        var lr = fr
        var mention = p.tasks[0]
        mention.id = "synthetic:mention"
        mention.prompt = "can you look at T-002 for billing please"
        mention.projectID = ws + "/apps/billing"
        mention.cwd = ws + "/apps/billing"
        lr.transcriptTasks = [mention]
        lr.transcriptSessionIDs = [p.sessionID]
        lr.plannedTasks = TaskFolder.taskFiles(in: ws + "/backlog").compactMap { TaskFolder.parse($0, folder: ws + "/backlog") }.map(Ingestor.item(from:))
        lr.startedAt = Date()
        store.merge(lr)
        check(store.task(t2)?.claudeLinks == ["synthetic:mention"], "Claude prompt mentioning T-002 links to it")

        print("Scaffold")
        let proj = ws + "/apps/api"
        _ = store.createTask(title: "Local one", projectID: proj, notes: "", priority: .none, status: .todo, subtasks: ["a", "b"], destination: .local)
        store.createBacklogFolder(for: proj)
        let made = TaskFolder.taskFiles(in: proj + "/backlog")
        check(made.count == 1 && fm.fileExists(atPath: proj + "/backlog/README.md") && fm.fileExists(atPath: proj + "/backlog/BACKLOG.md"), "backlog/ created and local task moved into it")
        check(!store.items.contains { $0.origin == .manual && $0.projectID == proj }, "local copy removed after move")

        print("Wrap-up without closing text")
        let wf = tmp.appendingPathComponent("aaaaaaaa-0000-0000-0000-000000000001.jsonl")
        try! ([user("Summarise this week's changes for the team update, five bullets", 5000),
               asst([tool("mcp__ccd_turn__wrap_up", ["recap": "Five bullets written."])], 5010)].joined(separator: "\n") + "\n")
            .write(to: wf, atomically: true, encoding: .utf8)
        let wp = TranscriptParser(url: wf)
        wp.update()
        var wt = wp.tasks
        Ingestor.inferStatuses(&wt, session: nil)
        check(wt.first?.inferredStatus == .done, "a turn that ends in a wrap-up summary counts as answered")

        print("Share your week")
        do {
            let now = Date()
            // Anchor at 23:00 yesterday so "2h ago" and "3h ago" share a day whatever the clock says.
            let base = Calendar.current.startOfDay(for: now).addingTimeInterval(-3600)
            func mk(_ id: String, _ proj: String, _ hoursAgo: Double, origin: TaskOrigin = .prompt, status: TaskStatus = .done,
                    tools: Int = 3, files: [String] = [], active: Double = 60) -> TaskItem {
                var t = TaskItem(id: id, origin: origin, projectID: proj, sessionID: "s", title: id, prompt: id,
                                 createdAt: base.addingTimeInterval(-hoursAgo * 3600), updatedAt: now, inferredStatus: status)
                t.status = status
                t.stats.toolCalls = tools
                t.stats.filesTouched = files
                t.stats.activeSeconds = active
                return t
            }
            let items = [
                mk("a", "/p/web", 2, files: ["/x/a.swift", "/x/b.swift"]),
                mk("b", "/p/web", 3, status: .needsYou, files: ["/x/a.swift"]),
                mk("c", "/p/api", 30),
                mk("d", "/p/api", 24 * 10),                       // outside the 7-day window
                mk("e", "/p/web", 1, origin: .manual),             // planned task: not a request
                mk("f", "/p/web", 1, origin: .suggested),          // suggestion: not a request
            ]
            let (start, end) = SharePeriod.week.range(now: now)
            let w = WeekSummary.compute(items: items, project: { ProjectResolver.info(for: $0, settings: nil) }, start: start, end: end)
            check(w.requests == 3, "week counts only Claude requests in range (got \(w.requests))")
            check(w.files == 2 && w.toolCalls == 9 && w.done == 2 && w.activeSeconds == 180, "files are unique; tools, done and active time add up")
            check(w.projects.first?.name == "web" && w.projects.first?.count == 2 && w.projects.count == 2, "projects ranked by requests")
            check(w.busiestCount == 2, "busiest day found")

            let d = DiscoveryStats.compute(items: items, sessions: [], project: { ProjectResolver.info(for: $0, settings: nil) })
            check(d.requests == 4 && d.projects == 2 && d.plannedOpen == 0, "discovery counts all Claude requests, not planned or suggested (got \(d.requests))")
            check(d.waiting == 1 && d.top.map(\.name) == ["api", "web"] && d.top.allSatisfy { $0.count == 2 },
                  "discovery finds the waiting session and ranks projects (ties by name)")
            check(d.since.map { abs($0.timeIntervalSince(base.addingTimeInterval(-24 * 10 * 3600))) < 1 } == true, "discovery dates the first request")
        }

        print("Notifications")
        do {
            let now = Date()
            func tk(_ id: String, _ status: TaskStatus, minutesAgo: Double = 1, origin: TaskOrigin = .prompt,
                    ask: String? = "Redis or sticky sessions?", hidden: Bool = false) -> TaskItem {
                var t = TaskItem(id: id, origin: origin, projectID: "/p/api", sessionID: "s-\(id)", title: id, prompt: id,
                                 createdAt: now.addingTimeInterval(-minutesAgo * 60), updatedAt: now.addingTimeInterval(-minutesAgo * 60),
                                 inferredStatus: status)
                t.status = status
                t.finalReply = ask
                t.recap = "Shipped."
                t.hidden = hidden
                return t
            }
            let both: Set<StatusChange.Kind> = [.needsYou, .done]
            let after = [tk("a", .needsYou), tk("b", .done), tk("c", .inProgress), tk("d", .needsYou), tk("e", .needsYou, minutesAgo: 120),
                         tk("f", .needsYou, origin: .manual), tk("g", .needsYou, hidden: true), tk("h", .needsYou, origin: .history)]
            let before: [String: TaskStatus] = ["a": .inProgress, "b": .inProgress, "c": .todo, "d": .needsYou, "e": .inProgress, "f": .todo, "g": .todo, "h": .todo]
            check(StatusChanges.detect(before: nil, after: after, now: now, kinds: both, alreadySent: []).isEmpty,
                  "no notifications on the first merge after launch")
            let ch = StatusChanges.detect(before: before, after: after, now: now, kinds: both, alreadySent: [])
            check(ch.map(\.id) == ["a", "b"] && ch.map(\.kind) == [.needsYou, .done],
                  "only Claude tickets that just moved to Needs You or Done (got \(ch.map(\.id)))")
            check(StatusChanges.detect(before: before, after: after, now: now, kinds: [.needsYou], alreadySent: []).map(\.id) == ["a"],
                  "Done notifications follow their setting")
            check(StatusChanges.detect(before: before, after: after, now: now, kinds: both, alreadySent: Set(ch.map(\.dedupeKey))).isEmpty,
                  "the same question or recap is never announced twice")
            let fresh = StatusChanges.detect(before: [:], after: [tk("n", .needsYou)], now: now, kinds: both, alreadySent: [])
            check(fresh.map(\.id) == ["n"], "a new request that ends on a question right away counts")
            var asked = tk("q", .needsYou, ask: "Done with the audit.\n\nShould I also update the **Playwright** tests?\nI can start now.")
            check(StatusChanges.question(of: asked) == "Should I also update the Playwright tests?", "the notification shows Claude's question")
            asked.pendingAsk = "Pick a database"
            check(StatusChanges.question(of: asked) == "Pick a database", "a pending ask wins over the reply text")
        }

        print("Startup")
        check(Startup.isLoginLaunch(eventID: 0x6F61_7070, launchProperty: 0x6C67_6974), "an 'oapp' event marked as login item is a login launch")
        check(!Startup.isLoginLaunch(eventID: 0x6F61_7070, launchProperty: nil), "opening the app by hand is not a login launch")
        check(!Startup.isLoginLaunch(eventID: nil, launchProperty: nil), "no launch event is not a login launch")

        print("Refresh picks up changes")
        let rr = tmp.appendingPathComponent("refresh-root").path
        let emptyClaude = tmp.appendingPathComponent("empty-claude").path
        try? fm.createDirectory(atPath: rr + "/ws/backlog/tasks", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: emptyClaude, withIntermediateDirectories: true)
        setenv("PITWALL_ROOTS", rr, 1)
        setenv("PITWALL_CLAUDE_DIR", emptyClaude, 1)
        setenv("PITWALL_DESKTOP_DIR", emptyClaude + "/desktop", 1)
        setenv("PITWALL_CODEX_DIR", emptyClaude + "/codex", 1)
        func task(_ path: String, _ id: String) {
            try! "---\nid: \(id)\ntitle: Task \(id)\nstatus: todo\n---\n".write(toFile: path, atomically: true, encoding: .utf8)
        }
        task(rr + "/ws/backlog/tasks/T-001-a.md", "T-001")
        let ing = Ingestor()
        check(ing.run().plannedTasks.count == 1, "first refresh reads the backlog")
        task(rr + "/ws/backlog/tasks/T-002-b.md", "T-002")
        check(ing.run().plannedTasks.count == 2, "a task file added later appears on the next refresh")
        try? fm.createDirectory(atPath: rr + "/side/backlog/tasks", withIntermediateDirectories: true)
        task(rr + "/side/backlog/tasks/T-001-c.md", "T-001")
        let r3 = ing.run()
        check(r3.taskFolders.contains(rr + "/side/backlog") && r3.plannedTasks.count == 3, "a new backlog folder appears on the next refresh")

        auditChecks(tmp)
        renameChecks(tmp)
        agentReaderChecks(tmp)

        print("Demo world")
        Demo.prepare()
        let demoStore = Store()
        demoStore.merge(Ingestor().run())
        let demoItems = demoStore.items
        check(demoItems.filter { $0.origin == .file }.count == 10, "demo backlog has 10 tasks")
        check(demoItems.filter { $0.origin == .manual }.count == 4, "demo has 4 local tasks")
        check(demoItems.contains { $0.status == .needsYou && !$0.origin.isPlanned }, "a Claude ticket waits on you")
        check(demoStore.liveSessions.contains { $0.isBusy }, "a session is busy")
        check(demoItems.filter { !($0.claudeLinks ?? []).isEmpty }.count >= 4, "backlog tasks linked to Claude sessions")
        check(!demoItems.contains { !$0.origin.isPlanned && $0.origin != .suggested && $0.status == .todo && $0.recap != nil },
              "no finished ticket left in To Do")
        check(Paths.tilde(Demo.base.path + "/Projects/acme") == "~/Projects/acme", "demo paths shown as ~/Projects")
        check(Set(demoItems.compactMap(\.agentKind)) == Set(Agent.allCases), "every agent has work on the demo board")

        try? FileManager.default.removeItem(at: tmp)
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Cursor, Gemini CLI, Antigravity

    static func agentReaderChecks(_ tmp: URL) {
        print("Other agents")
        let fm = FileManager.default
        func json(_ o: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)! }
        let now = Date()
        let ms = Int(now.timeIntervalSince1970 * 1000) - 60_000

        // Cursor: an older build with the conversation inline, plus an archived chat.
        let cdb = tmp.appendingPathComponent("cursor-state.vscdb").path
        if let db = SQLiteWriter(path: cdb) {
            db.exec("CREATE TABLE cursorDiskKV (key TEXT, value TEXT)")
            db.exec("CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, workspaceId TEXT, createdAt INTEGER, lastUpdatedAt INTEGER, isArchived INTEGER, isSubagent INTEGER, recency INTEGER, checkpointAt INTEGER, value TEXT)")
            let open: [String: Any] = ["composerId": "c1", "createdAt": ms, "lastUpdatedAt": ms, "conversation": [
                ["type": 1, "bubbleId": "u1", "text": "Rename the settings screen to Preferences"],
                ["type": 2, "bubbleId": "a1", "text": "", "toolFormerData": ["name": "run_terminal_cmd", "status": "pending", "params": json(["command": "npm test"])]],
            ]]
            let archived: [String: Any] = ["composerId": "c2", "createdAt": ms, "conversation": [["type": 1, "bubbleId": "u2", "text": "Old chat about the logo colours"]]]
            db.exec("INSERT INTO cursorDiskKV VALUES (?, ?)", ["composerData:c1", json(open)])
            db.exec("INSERT INTO cursorDiskKV VALUES (?, ?)", ["composerData:c2", json(archived)])
            db.exec("INSERT INTO composerHeaders VALUES ('c1', 'w1', 0, 0, 0, 0, 0, 0, ?)", [json(["workspaceIdentifier": ["id": "w1", "uri": ["fsPath": "/tmp/shop"]]])])
            db.exec("INSERT INTO composerHeaders VALUES ('c2', 'w1', 0, 0, 1, 0, 0, 0, '{}')")
        }
        let cursor = CursorReader()
        cursor.read(cdb, running: false)
        check(cursor.tasks.count == 1 && cursor.tasks.first?.agent == .cursor && cursor.tasks.first?.cwd == "/tmp/shop",
              "Cursor: inline conversations are read, archived chats skipped, the folder comes from the header")
        check(cursor.tasks.first?.pendingAsk == "Allow running `npm test`?" && cursor.tasks.first?.stats.bashCalls == 1,
              "Cursor: a command waiting for approval is a question for you")

        // Gemini CLI: the JSONL layout, and project folders matched by hash.
        check(GeminiReader.hash("/Users/me/code/app") == "9564acb42d7416f38450ddfd48b9786ea1d7bb286c1e278a09cb877b757e4b82",
              "Gemini CLI: project folders are matched by the SHA-256 of their path")
        let gdir = tmp.appendingPathComponent("gemini/tmp/abc/chats")
        try? fm.createDirectory(at: gdir, withIntermediateDirectories: true)
        let gfile = gdir.appendingPathComponent("session-1.jsonl").path
        let iso = ISO8601DateFormatter()
        let lines = [
            json(["sessionId": "g1", "projectHash": "abc", "startTime": iso.string(from: now.addingTimeInterval(-3600)), "directories": ["/tmp/shop"]]),
            json(["id": "m1", "timestamp": iso.string(from: now.addingTimeInterval(-3600)), "type": "user", "content": [["text": "Add a dark mode toggle to the header"]]]),
            json(["id": "m2", "timestamp": iso.string(from: now.addingTimeInterval(-3500)), "type": "gemini", "content": "Added the toggle; it follows the system setting by default.",
                  "toolCalls": [["id": "t1", "name": "write_file", "args": ["file_path": "/tmp/shop/src/Header.tsx"], "status": "success",
                                 "timestamp": iso.string(from: now.addingTimeInterval(-3550))]]]),
        ]
        try? lines.joined(separator: "\n").write(toFile: gfile, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.modificationDate: now.addingTimeInterval(-3500)], ofItemAtPath: gfile)
        let gemini = GeminiReader()
        gemini.read([gfile])
        let g = gemini.tasks.first
        check(gemini.tasks.count == 1 && g?.stats.edits == 1 && g?.stats.filesTouched == ["/tmp/shop/src/Header.tsx"] && g?.stats.replied == true,
              "Gemini CLI: a JSONL session gives a ticket with its edits and reply")
        check(gemini.sessions.first?.isLive == false && gemini.sessions.first?.agent == .gemini, "Gemini CLI: an hour-old session isn't live")

        // Antigravity: Markdown artifacts.
        check(AntigravityReader.checklist("- [x] read\n  - [/] build\n- [ ] test\n- not a step").map(\.state) == [.completed, .inProgress, .pending],
              "Antigravity: the task.md checklist becomes the plan")
        check(AntigravityReader.heading("Intro\n# Implementation Plan: Faster search\n") == "Faster search", "Antigravity: the plan's title names the ticket")
        check(AntigravityReader.fileLinks("[a](file:///x/y%20z.ts) and <file:///x/w.ts>, again file:///x/w.ts") == ["/x/y z.ts", "/x/w.ts"],
              "Antigravity: file links point at the project")
        check(AntigravityReader.firstParagraph("# T\n\n```\ncode\n```\nFirst line\nsecond line\n\nNext") == "First line second line",
              "Antigravity: the summary skips headings and code")
    }

    // MARK: - ClaudeBoard → Pitwall

    static func renameChecks(_ tmp: URL) {
        print("Rename from ClaudeBoard")
        let fm = FileManager.default
        let old = tmp.appendingPathComponent("rename/ClaudeBoard"), new = tmp.appendingPathComponent("rename/Pitwall")
        try? fm.createDirectory(at: old.appendingPathComponent("cache"), withIntermediateDirectories: true)
        try? "{\"items\":[]}".write(to: old.appendingPathComponent("user.json"), atomically: true, encoding: .utf8)
        try? "x".write(to: old.appendingPathComponent("cache/big.sqlite"), atomically: true, encoding: .utf8)
        Rename.copyData(from: old, to: new)
        check(fm.fileExists(atPath: new.appendingPathComponent("user.json").path), "the old data folder is copied")
        check(!fm.fileExists(atPath: new.appendingPathComponent("cache").path), "the cache is left behind")
        check(fm.fileExists(atPath: old.appendingPathComponent("user.json").path), "the old folder stays intact")
        try? "{\"items\":[1]}".write(to: new.appendingPathComponent("user.json"), atomically: true, encoding: .utf8)
        Rename.copyData(from: old, to: new)
        check((try? String(contentsOf: new.appendingPathComponent("user.json"), encoding: .utf8)) == "{\"items\":[1]}",
              "an existing Pitwall folder is never overwritten")
        let suite = "pitwall-selftest-\(UUID().uuidString.prefix(6))"
        let d = UserDefaults(suiteName: suite)!
        d.set(false, forKey: "showInDock")
        Rename.copySettings(["showInDock": true, "projectRoots": ["~/Code"]], into: d)
        check(d.bool(forKey: "showInDock") == false && (d.stringArray(forKey: "projectRoots") ?? []) == ["~/Code"],
              "old settings fill gaps but never replace new ones")
        d.removePersistentDomain(forName: suite)
    }

    // MARK: - Fixes from the data audit (2026-11-16), one check each

    static func auditChecks(_ tmp: URL) {
        let fm = FileManager.default
        func line(_ o: [String: Any]) -> String { String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)! }
        func at(_ s: Double) -> String {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.string(from: Date().addingTimeInterval(s))
        }
        func transcript(_ name: String, _ lines: [String]) -> TranscriptParser {
            let url = tmp.appendingPathComponent(name + ".jsonl")
            try! (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            let p = TranscriptParser(url: url)
            p.update()
            return p
        }
        let cwd = Roots.primary + "/audit-app"
        func user(_ content: Any, _ t: Double, uuid: String = UUID().uuidString) -> String {
            line(["type": "user", "uuid": uuid, "timestamp": at(t), "cwd": cwd, "origin": ["kind": "human"], "message": ["role": "user", "content": content]])
        }
        func asst(_ parts: [[String: Any]], _ t: Double) -> String {
            line(["type": "assistant", "timestamp": at(t), "cwd": cwd, "message": ["role": "assistant", "content": parts]])
        }
        func result(_ id: String, _ text: String, _ t: Double) -> String {
            line(["type": "user", "timestamp": at(t), "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "content": text]]]])
        }

        print("Audit fixes")
        // 2. An answered question (or approved plan) no longer waits on you.
        let asked = transcript("audit-ask", [
            user("Set up the deploy pipeline for staging", -600),
            asst([["type": "tool_use", "id": "ask-1", "name": "AskUserQuestion", "input": ["questions": [["question": "Which cloud?"]]]]], -590),
            result("ask-1", "AWS", -580),
            asst([["type": "text", "text": "Using AWS. Pipeline added."]], -570),
        ])
        check(asked.tasks.first?.pendingAsk == nil, "an answered question is cleared")
        let open = transcript("audit-ask-open", [
            user("Set up the deploy pipeline for production", -600),
            asst([["type": "tool_use", "id": "ask-2", "name": "AskUserQuestion", "input": ["questions": [["question": "Which region?"]]]]], -590),
        ])
        check(open.tasks.first?.pendingAsk == "Which region?", "an unanswered question still waits")

        // 5. A screenshot with a short reply is a follow-up, not a new ticket.
        let image = transcript("audit-image", [
            user("Make the header sticky on the product page", -500),
            asst([["type": "text", "text": "Done. Should I also shrink it on scroll?"]], -490),
            user([["type": "image", "source": [:]], ["type": "text", "text": "yes"]], -480),
        ])
        check(image.tasks.count == 1 && image.tasks.first?.followUps.first?.text.contains("image") == true,
              "image + short reply folds into the request")

        // Withdrawn suggestions leave the backlog.
        let dismissed = transcript("audit-dismiss", [
            user("Clean up the auth module and its tests", -400),
            asst([["type": "tool_use", "id": "ss-1", "name": "mcp__ccd_session__start_session",
                   "input": ["initiation": "own_initiative", "title": "Rotate the signing keys", "prompt": "brief"]]], -390),
            result("ss-1", "Proposed as task_ab12cd34", -389),
            asst([["type": "tool_use", "id": "dt-1", "name": "mcp__ccd_session__dismiss_task", "input": ["task_id": "task_ab12cd34"]]], -380),
        ])
        check(dismissed.suggestions.first?.hidden == true, "a withdrawn suggestion is hidden")

        // 6 and 7. Status rules: open steps only count while the session is open; old questions expire.
        func ticket(_ replied: Bool, ask: String? = nil, reply: String? = nil, steps: Bool = false, age: Double = 60) -> TaskItem {
            var t = TaskItem(id: "x:\(UUID().uuidString)", origin: .prompt, projectID: cwd, sessionID: "s", title: "t", prompt: "p",
                             createdAt: Date().addingTimeInterval(-age), updatedAt: Date().addingTimeInterval(-age), inferredStatus: .todo)
            t.stats.replied = replied
            t.pendingAsk = ask
            t.finalReply = reply
            if steps { t.subtasks = [Subtask(id: "plan-0", title: "a", state: .pending)] }
            return t
        }
        func session(live: Bool, archived: Bool = false, age: Double = 60) -> SessionInfo {
            var s = SessionInfo(id: "s", projectID: cwd, title: "s", cwd: cwd, startedAt: Date().addingTimeInterval(-age), lastActivity: Date().addingTimeInterval(-age))
            s.isLive = live
            s.liveStatus = live ? "idle" : nil
            s.archived = archived
            return s
        }
        func status(_ t: TaskItem, _ s: SessionInfo) -> TaskStatus {
            var ts = [t]
            Ingestor.inferStatuses(&ts, session: s)
            return ts[0].inferredStatus
        }
        check(status(ticket(true, steps: true, age: 7200), session(live: false, age: 7200)) == .done, "closed session with open steps is done")
        check(status(ticket(true, steps: true), session(live: true)) == .inProgress, "open session with open steps is in progress")
        check(status(ticket(true, reply: "Should I go on?", steps: true), session(live: true)) == .needsYou, "a closing question beats open steps")
        check(status(ticket(true, ask: "Ship it?", age: 3 * 86_400), session(live: false, age: 3 * 86_400)) == .done, "a question from days ago expires")
        check(status(ticket(true, ask: "Ship it?"), session(live: false, archived: true)) == .done, "an archived session's question doesn't wait")
        check(status(ticket(true, ask: "Ship it?"), session(live: false)) == .needsYou, "a recent question waits, CLI or desktop alike")

        // Store-level fixes.
        let root = Roots.primary
        let a = root + "/audit-a", b = root + "/audit-b"
        func req(_ id: String, project: String, prompt: String, session sid: String, age: Double, replied: Bool = true, live: Bool = false) -> TaskItem {
            var t = TaskItem(id: id, origin: .prompt, projectID: project, sessionID: sid, title: prompt, prompt: prompt,
                             createdAt: Date().addingTimeInterval(-age), updatedAt: Date().addingTimeInterval(-age), inferredStatus: .todo, cwd: project)
            t.stats.replied = replied
            return t
        }
        func sess(_ id: String, _ project: String, age: Double, live: Bool = false) -> SessionInfo {
            var s = SessionInfo(id: id, projectID: project, title: id, cwd: project, startedAt: Date().addingTimeInterval(-age), lastActivity: Date().addingTimeInterval(-age))
            s.isLive = live
            return s
        }
        var plannedFile = TaskItem(id: "file:\(a)/backlog#T-1", origin: .file, projectID: "", sessionID: nil, title: "Rotate keys", prompt: "",
                                   createdAt: Date(), updatedAt: Date(), inferredStatus: .todo)
        plannedFile.folder = a + "/backlog"
        plannedFile.externalID = "T-1"
        plannedFile.filePath = a + "/backlog/T-1.md"
        var r = IngestResult()
        r.repos = [a, b]
        ProjectRegistry.shared.set(repos: [a, b])
        r.plannedTasks = [plannedFile]
        r.transcriptTasks = [
            req("sOld:m1", project: a, prompt: "Add billing export", session: "sOld", age: 9000),
            req("sNew:m1", project: a, prompt: "Add billing export", session: "sNew", age: 8000),
            req("sNew:m2", project: b, prompt: "work on T-1 please", session: "sNew", age: 7000),
            req("sNew:m3", project: a, prompt: "[T-1] Rotate keys", session: "sNew", age: 6000),
            req("sOld:m4", project: a, prompt: "Old cleanup", session: "sOld", age: 40 * 86_400, replied: false),
        ]
        r.transcriptSessionIDs = ["sOld", "sNew"]
        r.sessions = [sess("sOld", a, age: 9000), sess("sNew", a, age: 6000)]
        let st = Store()
        st.merge(r)
        check(st.items.filter { $0.title == "Add billing export" }.count == 1, "a resumed session's copied message is one ticket")
        check(st.task("sNew:m2")?.plannedLink == nil, "a key from another project doesn't link")
        check(st.task("sNew:m3")?.plannedLink == "file:\(a)/backlog#T-1", "a key in the same project links")
        check(st.task("sNew:m3")?.folded == true && st.task("sNew:m3")?.hidden == false, "a ticket started from a task is folded, not hidden")

        // 4. A status you set holds until the agent does something new.
        st.setStatus("sNew:m2", .inProgress)
        check(st.task("sNew:m2")?.status == .inProgress, "your status holds")
        var r2 = r
        r2.transcriptTasks = r.transcriptTasks.map { t in
            var t = t
            if t.id == "sNew:m2" { t.updatedAt = Date().addingTimeInterval(60) }
            return t
        }
        st.merge(r2)
        check(st.task("sNew:m2")?.status == .done && st.task("sNew:m2")?.statusOverridden == false, "new agent activity replaces your status")

        // 12. An old ticket you mark done stays in this week's view.
        st.period = .week
        st.setStatus("sOld:m4", .done)
        check(st.periodScoped.contains { $0.id == "sOld:m4" }, "an old ticket moved to Done stays visible")

        // 8. Project keys never move.
        let keyA = st.project(a).key
        var r3 = r2
        let a2 = root + "/zz/audit-a"
        r3.repos = [a, b, a2]
        r3.transcriptTasks.append(req("sNew:m5", project: a2, prompt: "Same initials", session: "sNew", age: 100))
        st.merge(r3)
        check(st.project(a).key == keyA && st.project(a2).key != keyA, "a same-named project doesn't take an existing key (\(keyA), \(st.project(a2).key))")

        // 9. Hidden projects stay out of the menu bar.
        var r4 = r3
        r4.transcriptTasks.append({ var t = req("sNew:m6", project: b, prompt: "Pick a region", session: "sNew", age: 30); t.pendingAsk = "EU or US?"; return t }())
        st.merge(r4)
        let before = st.waitingOnYou.count
        st.updateProject(b) { $0.hidden = true }
        check(before > 0 && st.waitingOnYou.allSatisfy { $0.projectID != b }, "a hidden project's question leaves the menu bar")
        st.updateProject(b) { $0.hidden = nil }

        // 10. "7 days" is the same seven calendar days everywhere.
        let today = Calendar.current.startOfDay(for: Date())
        check(Period.week.since == Calendar.current.date(byAdding: .day, value: -6, to: today), "a week is today and the six days before")

        // 14. Worktrees land in their repo.
        check(!ProjectResolver.projectID(for: a + "/.conductor-worktrees/fix-1").contains("worktree"), "a hidden worktree folder belongs to its repo")
        check(Store.genericNames.contains("app"), "generic folder names don't pick a project")

        // 15. Backlog files with Windows line ends.
        let crlfDir = tmp.appendingPathComponent("crlf/backlog").path
        try? fm.createDirectory(atPath: crlfDir, withIntermediateDirectories: true)
        let crlfFile = crlfDir + "/T-9.md"
        try! "---\r\nid: T-9\r\ntitle: Windows task\r\nstatus: todo\r\n---\r\nBody\r\n".write(toFile: crlfFile, atomically: true, encoding: .utf8)
        check(TaskFolder.parse(crlfFile, folder: crlfDir)?.fields["title"] == "Windows task", "CRLF front matter is read")
        try? TaskFolder.updateFields(crlfFile, [("status", "done")])
        let after = (try? String(contentsOfFile: crlfFile, encoding: .utf8)) ?? ""
        check(after.contains("status: done\r\n") && !after.contains("\r\r"), "a CRLF file keeps its line ends when edited")
        let crlfIndex = crlfDir + "/BACKLOG.md"
        try! "# Backlog\r\n\r\n| ID | Title | Status |\r\n|---|---|---|\r\n| [T-9](tasks/T-9.md) | Windows task | todo |\r\n".write(toFile: crlfIndex, atomically: true, encoding: .utf8)
        TaskFolder.appendIndexRow(folder: crlfDir, id: "T-10", relPath: "tasks/T-10.md", title: "Next", area: "", priority: "", status: "todo")
        let index = (try? String(contentsOfFile: crlfIndex, encoding: .utf8)) ?? ""
        check(index.contains("T-10") && !index.replacingOccurrences(of: "\r\n", with: "").contains("\n"),
              "a new row in a CRLF index keeps CRLF line ends")

        // Live sessions: a reused process id isn't a live session.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        if let mine = LiveSessions.processStart(getpid()) {
            check(LiveSessions.sameStart(pid: getpid(), recorded: f.string(from: mine)), "this process matches its own start time")
            check(!LiveSessions.sameStart(pid: getpid(), recorded: f.string(from: mine.addingTimeInterval(-3600))), "a different start time is a reused pid")
        }

        print("Codex")
        let codexDir = tmp.appendingPathComponent("codex").path
        setenv("PITWALL_CODEX_DIR", codexDir, 1)
        try? fm.createDirectory(atPath: codexDir + "/sessions/2026/11/17", withIntermediateDirectories: true)
        let events: [[String: Any]] = [
            ["timestamp": at(-300), "type": "session_meta", "payload": ["id": "cx-1", "cwd": cwd, "timestamp": at(-300)]],
            ["timestamp": at(-299), "type": "event_msg", "payload": ["type": "user_message", "message": "Add a health check endpoint to the API"]],
            ["timestamp": at(-290), "type": "event_msg", "payload": ["type": "exec_command_end", "exit_code": 0]],
            ["timestamp": at(-280), "type": "event_msg", "payload": ["type": "patch_apply_end", "changes": [cwd + "/health.go": ["type": "add"]]]],
            ["timestamp": at(-270), "type": "event_msg", "payload": ["type": "agent_message", "message": "Added /health. Want readiness checks too?"]],
            ["timestamp": at(-269), "type": "event_msg", "payload": ["type": "request_user_input", "question": "Add readiness checks too?"]],
        ]
        try! (events.map(line).joined(separator: "\n") + "\n").write(toFile: codexDir + "/sessions/2026/11/17/rollout-cx-1.jsonl", atomically: true, encoding: .utf8)
        let codex = CodexReader()
        codex.update()
        let ct = codex.tasks.first
        check(codex.tasks.count == 1 && ct?.agent == .codex, "a Codex rollout becomes one Codex ticket")
        check(ct?.stats.bashCalls == 1 && ct?.stats.filesTouched == [cwd + "/health.go"], "Codex commands and edits are counted (\(ct?.stats.bashCalls ?? -1), \(ct?.stats.filesTouched ?? []))")
        check(ct?.pendingAsk == "Add readiness checks too?" && codex.sessions.first?.isLive == true, "a Codex question waits on you")
        check(ProjectResolver.projectID(for: Paths.home + "/Documents/Codex/2026-09-01/new-chat") == ProjectResolver.scratchID,
              "Codex chats without a project go to Scratch")
    }
}
