import Foundation

/// `ClaudeBoard --selftest` checks parsing and merge rules on synthetic data.
/// Run with CLAUDEBOARD_DATA_DIR pointing at a temp folder so real data is untouched.
@MainActor
enum SelfTest {
    static var failures = 0

    static func check(_ ok: Bool, _ what: String) {
        print((ok ? "  ✓ " : "  ✗ ") + what)
        if !ok { failures += 1 }
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IONBF, 0)
        guard ProcessInfo.processInfo.environment["CLAUDEBOARD_DATA_DIR"] != nil else {
            print("set CLAUDEBOARD_DATA_DIR to a temp folder first"); return 2
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
        check(store.task(imported[2].id)?.hidden == true, "ticket launched from the task is folded (hidden)")
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
        setenv("CLAUDEBOARD_ROOTS", tmp.path, 1)
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

        try? FileManager.default.removeItem(at: tmp)
        print(failures == 0 ? "\nall checks passed" : "\n\(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }
}
