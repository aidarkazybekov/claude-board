import AppKit

/// Reads Cursor's agent chats (Agent, Composer) from its global state database:
/// `User/globalStorage/state.vscdb`, table `cursorDiskKV`. Each chat is `composerData:<id>`, its
/// messages are `bubbleId:<chat>:<message>` (older builds keep them inline under `conversation`), and
/// `composerHeaders` (newer builds) says which folder a chat belongs to and whether it's archived.
final class CursorReader {
    static let bundleID = "com.todesktop.230313mzl4w4u92"
    private var signature = ""
    private(set) var tasks: [TaskItem] = []
    private(set) var sessions: [SessionInfo] = []

    var database: String { Paths.cursorDir + "/User/globalStorage/state.vscdb" }

    /// Re-reads when the database changed (and once a minute while a chat is live). True when the data changed.
    @discardableResult
    func update() -> Bool {
        let db = database
        guard FileManager.default.fileExists(atPath: db) else {
            defer { tasks = []; sessions = []; signature = "" }
            return !tasks.isEmpty || !sessions.isEmpty
        }
        let running = !Demo.isOn && !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
        var sig = [db, db + "-wal"].map(CodexReader.mtimeKey).joined(separator: "|") + "|\(running)"
        if sessions.contains(where: \.isLive) { sig += "|\(Int(Date().timeIntervalSince1970 / 60))" }
        guard sig != signature else { return false }
        signature = sig
        read(db, running: running)
        return true
    }

    func read(_ db: String, running: Bool, now: Date = Date()) {
        guard let s = SQLiteSnapshot(path: db, cacheName: "cursor-state.sqlite"), s.hasTable("cursorDiskKV") else {
            tasks = []; sessions = []; return
        }
        var headers: [String: [String: Any]] = [:]
        if s.hasTable("composerHeaders") {
            for r in s.rows("SELECT composerId, createdAt, lastUpdatedAt, IFNULL(isArchived, 0) AS archived, IFNULL(isSubagent, 0) AS sub, value FROM composerHeaders") {
                guard let id = r.str("composerId") else { continue }
                var h = CodexReader.json(r.str("value")) ?? [:]
                h["_archived"] = r.int("archived") ?? 0
                h["_sub"] = r.int("sub") ?? 0
                h["_created"] = r.int("createdAt")
                h["_updated"] = r.int("lastUpdatedAt")
                headers[id] = h
            }
        }
        var bubbles: [String: [String: [String: Any]]] = [:]
        for r in s.rows("SELECT key, value FROM cursorDiskKV WHERE key LIKE 'bubbleId:%'") {
            let parts = (r.str("key") ?? "").split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3, let json = CodexReader.json(r.str("value")) else { continue }
            bubbles[parts[1], default: [:]][parts[2]] = json
        }
        let folders = Self.workspaceFolders(Paths.cursorDir + "/User/workspaceStorage")

        var outTasks: [TaskItem] = []
        var outSessions: [SessionInfo] = []
        for r in s.rows("SELECT key, value FROM cursorDiskKV WHERE key LIKE 'composerData:%'") {
            let cid = String((r.str("key") ?? "").dropFirst("composerData:".count))
            guard !cid.isEmpty, let data = CodexReader.json(r.str("value")) else { continue }
            let h = headers[cid] ?? [:]
            if (h["_archived"] as? Int64 ?? 0) != 0 || (h["_sub"] as? Int64 ?? 0) != 0 || (data["isArchived"] as? Bool) == true { continue }

            let ws = h["workspaceIdentifier"] as? [String: Any]
            var cwd = (ws?["uri"] as? [String: Any])?["fsPath"] as? String
            if cwd == nil, let wid = ws?["id"] as? String { cwd = folders[wid] }

            var conversation: [[String: Any]] = []
            if let heads = data["fullConversationHeadersOnly"] as? [[String: Any]], !heads.isEmpty {
                conversation = heads.compactMap { ($0["bubbleId"] as? String).flatMap { bubbles[cid]?[$0] } }
            } else if let inline = data["conversation"] as? [[String: Any]] {
                conversation = inline
            }
            guard !conversation.isEmpty else { continue }

            let created = TicketBuilder.date(data["createdAt"]) ?? TicketBuilder.date(h["_created"]) ?? now
            var b = TicketBuilder(agent: .cursor, sessionID: cid, cwd: cwd)
            var at = created
            var pendingTool: String?
            for (i, bubble) in conversation.enumerated() {
                at = TicketBuilder.date(bubble["createdAt"])
                    ?? TicketBuilder.date((bubble["timingInfo"] as? [String: Any])?["clientStartTime"]) ?? at
                let text = (bubble["text"] as? String) ?? ""
                switch (bubble["type"] as? NSNumber)?.intValue {
                case 1:
                    let images = (bubble["images"] as? [Any])?.count ?? 0
                    b.user(text, at: at, key: (bubble["bubbleId"] as? String) ?? "\(i)", images: images)
                    pendingTool = nil
                case 2:
                    if let tool = bubble["toolFormerData"] as? [String: Any] {
                        let name = (tool["name"] as? String) ?? "tool"
                        let args = Self.args(tool)
                        b.tool(name, files: TicketBuilder.files(in: args), at: at)
                        if name.contains("todo"), let todos = args["todos"] as? [[String: Any]] {
                            b.plan(Self.steps(todos))
                        }
                        // A tool still waiting for the user's go-ahead (Cursor asks before some commands).
                        let status = (tool["status"] as? String) ?? ""
                        if ["pending", "awaiting_approval"].contains(status) && tool["userDecision"] == nil {
                            pendingTool = (args["command"] as? String).map { "Allow running `\($0)`?" } ?? "Cursor is waiting for your go-ahead on \(name)."
                        } else {
                            pendingTool = nil
                        }
                    }
                    if !text.isEmpty { b.reply(text, at: at) }
                default:
                    break
                }
            }
            guard !b.isEmpty else { continue }
            if let todos = data["todos"] as? [[String: Any]], !todos.isEmpty { b.plan(Self.steps(todos)) }
            var touched: [String] = (data["originalFileStates"] as? [String: Any]).map { Array($0.keys) } ?? []
            touched += ((data["newlyCreatedFiles"] as? [[String: Any]]) ?? []).compactMap { ($0["uri"] as? [String: Any])?["fsPath"] as? String }
            b.addFiles(touched.map { $0.hasPrefix("file://") ? (URL(string: $0)?.path ?? $0) : $0 }.sorted())

            let updated = max(TicketBuilder.date(data["lastUpdatedAt"]) ?? TicketBuilder.date(h["_updated"]) ?? at, at)
            let busy = !((data["generatingBubbleIds"] as? [Any]) ?? []).isEmpty || (data["status"] as? String) == "generating"
            var waiting = pendingTool
            if waiting == nil, (h["hasBlockingPendingActions"] as? Bool) == true { waiting = "Cursor is waiting for your approval." }
            if let waiting { b.ask(waiting) }
            let live = busy || (running && now.timeIntervalSince(updated) < 6 * 3600)
            let title = (data["name"] as? String) ?? (h["name"] as? String)
            outSessions.append(b.session(title: title, startedAt: created, lastActivity: updated, live: live, busy: busy && waiting == nil,
                                         waiting: waiting))
            outTasks.append(contentsOf: b.tickets)
        }
        tasks = outTasks
        sessions = outSessions
    }

    /// A tool's arguments: `params` or `rawArgs`, either a JSON string or an object.
    static func args(_ tool: [String: Any]) -> [String: Any] {
        for key in ["params", "rawArgs", "args"] {
            if let d = tool[key] as? [String: Any] { return d }
            if let s = tool[key] as? String, let d = CodexReader.json(s) { return d }
        }
        return [:]
    }

    static func steps(_ todos: [[String: Any]]) -> [Subtask] {
        todos.enumerated().compactMap { i, t in
            guard let title = (t["content"] as? String) ?? (t["title"] as? String), !title.isEmpty else { return nil }
            return Subtask(id: (t["id"] as? String) ?? "\(i)", title: title, state: TicketBuilder.stepState(t["status"] as? String))
        }
    }

    /// workspaceStorage/<id>/workspace.json → the folder that workspace opened.
    static func workspaceFolders(_ dir: String) -> [String: String] {
        var out: [String: String] = [:]
        for id in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
            guard let d = FileManager.default.contents(atPath: "\(dir)/\(id)/workspace.json"),
                  let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let uri = json["folder"] as? String, let url = URL(string: uri), url.isFileURL
            else { continue }
            out[id] = url.path
        }
        return out
    }
}
