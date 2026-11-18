import Foundation

/// Reads Codex work (the desktop app and the CLI) from ~/.codex.
///
/// Current builds keep an index of threads in `state_N.sqlite` (table `threads`) and the parsed
/// conversation in `thread_history_N.sqlite` (`thread_turns`, `thread_items`). Builds without those
/// databases only write JSONL rollouts under `sessions/YYYY/MM/DD/`; those are read as a fallback.
/// One ticket per request, like Claude Code: short replies ("yes", "go on") fold into the request before.
final class CodexReader {
    private var signature = ""
    private(set) var tasks: [TaskItem] = []
    private(set) var sessions: [SessionInfo] = []

    /// Re-reads when a source file changed (or a minute passed, for liveness). True when the data changed.
    @discardableResult
    func update() -> Bool {
        let dir = Paths.codexDir
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir) else {
            defer { tasks = []; sessions = []; signature = "" }
            return !tasks.isEmpty || !sessions.isEmpty
        }
        let state = Self.newest(in: dir, prefix: "state_")
        let history = Self.newest(in: dir, prefix: "thread_history_")
        let appOpen = fm.fileExists(atPath: dir + "/ipc/ipc.sock")
        var sig = [state, history].compactMap { $0 }.flatMap { [$0, $0 + "-wal"] }.map(Self.mtimeKey).joined(separator: "|")
        if state == nil || history == nil { sig += "|" + rolloutFiles(dir).map(Self.mtimeKey).joined(separator: "|") }
        sig += "|\(appOpen)|\(Int(Date().timeIntervalSince1970 / 60))"
        guard sig != signature else { return false }
        signature = sig
        if let state, let history, readDatabases(state: state, history: history, appOpen: appOpen) { return true }
        readRollouts(dir)
        return true
    }

    // MARK: - Databases

    private func readDatabases(state: String, history: String, appOpen: Bool) -> Bool {
        guard let st = SQLiteSnapshot(path: state, cacheName: "codex-state.sqlite"),
              let hist = SQLiteSnapshot(path: history, cacheName: "codex-history.sqlite"),
              st.hasTable("threads"), hist.hasTable("thread_turns"), hist.hasTable("thread_items")
        else { return false }

        let threads = st.rows("SELECT * FROM threads WHERE IFNULL(archived, 0) = 0")
        var turnsByThread: [String: [[String: Any]]] = [:]
        for t in hist.rows("SELECT thread_id, turn_id, status, started_at, completed_at, duration_ms FROM thread_turns ORDER BY started_at") {
            if let id = t.str("thread_id") { turnsByThread[id, default: []].append(t) }
        }
        var itemsByTurn: [String: [[String: Any]]] = [:]
        for i in hist.rows("""
            SELECT thread_id, turn_id, item_type, created_at_ms, item_json FROM thread_items
            WHERE item_type IN ('userMessage','agentMessage','commandExecution','fileChange','mcpToolCall','webSearch','imageView')
            ORDER BY created_at_ms
            """) {
            if let tid = i.str("thread_id"), let turn = i.str("turn_id") { itemsByTurn[tid + "/" + turn, default: []].append(i) }
        }

        var outTasks: [TaskItem] = []
        var outSessions: [SessionInfo] = []
        let now = Date()
        for th in threads {
            guard let tid = th.str("id") else { continue }
            let cwd = th.str("cwd") ?? ""
            let branch = th.str("git_branch")
            var built: [TaskItem] = []
            var asked = false
            var busy = false
            for turn in turnsByThread[tid] ?? [] {
                guard let turnID = turn.str("turn_id") else { continue }
                let items = itemsByTurn[tid + "/" + turnID] ?? []
                let started = Self.date(seconds: turn.int("started_at")) ?? Self.date(ms: items.first?.int("created_at_ms")) ?? now
                let completed = Self.date(seconds: turn.int("completed_at"))
                let status = turn.str("status") ?? ""
                if completed == nil && !["completed", "failed", "interrupted", "cancelled"].contains(status) { busy = true }

                // The request: the turn's user message.
                var text: String?
                var images = 0
                if let u = items.first(where: { $0.str("item_type") == "userMessage" }), let json = Self.json(u.str("item_json")) {
                    var raw = ""
                    for part in (json["content"] as? [[String: Any]]) ?? [] {
                        switch part["type"] as? String {
                        case "text": raw += (raw.isEmpty ? "" : "\n") + ((part["text"] as? String) ?? "")
                        case "image", "local_image", "localImage": images += 1
                        default: break
                        }
                    }
                    text = PromptText.clean(raw)
                }
                guard let prompt = text else { continue }

                let k: Int
                if !built.isEmpty && (PromptText.isFollowUp(prompt, claudeAsked: asked) || PromptText.isTrivial(prompt)) {
                    k = built.count - 1
                    built[k].followUps.append(Exchange(at: started, text: prompt))
                    built[k].pendingAsk = nil
                } else if built.isEmpty && PromptText.isTrivial(prompt) {
                    continue
                } else {
                    var shown = prompt
                    if images > 0 { shown += images == 1 ? "\n[1 image attached]" : "\n[\(images) images attached]" }
                    var t = TaskItem(id: "codex:\(tid):\(turnID)", origin: .prompt, projectID: ProjectResolver.projectID(for: cwd),
                                     sessionID: tid, title: PromptText.title(from: prompt), prompt: shown,
                                     createdAt: started, updatedAt: completed ?? started, inferredStatus: .todo,
                                     cwd: cwd.isEmpty ? nil : cwd, branch: branch)
                    t.agent = .codex
                    built.append(t)
                    k = built.count - 1
                }
                asked = false
                built[k].updatedAt = max(built[k].updatedAt, completed ?? started)
                if let completed { built[k].stats.endedAt = completed }
                if let ms = turn.int("duration_ms"), ms > 0 {
                    built[k].stats.activeSeconds = (built[k].stats.activeSeconds ?? 0) + Double(ms) / 1000
                }
                for item in items {
                    let kind = item.str("item_type") ?? ""
                    let json = Self.json(item.str("item_json")) ?? [:]
                    switch kind {
                    case "agentMessage":
                        let reply = ((json["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !reply.isEmpty else { continue }
                        built[k].finalReply = PromptText.truncate(reply, 6000)
                        built[k].stats.replied = true
                        asked = reply.hasSuffix("?") || reply.suffix(200).contains("?\n")
                    case "commandExecution":
                        built[k].stats.toolCalls += 1
                        built[k].stats.bashCalls += 1
                    case "fileChange":
                        built[k].stats.toolCalls += 1
                        built[k].stats.edits += 1
                        for change in (json["changes"] as? [[String: Any]]) ?? [] {
                            if let p = change["path"] as? String, !built[k].stats.filesTouched.contains(p) { built[k].stats.filesTouched.append(p) }
                        }
                        if let map = json["changes"] as? [String: Any] {
                            for p in map.keys where !built[k].stats.filesTouched.contains(p) { built[k].stats.filesTouched.append(p) }
                        }
                    case "mcpToolCall", "webSearch", "imageView":
                        built[k].stats.toolCalls += 1
                    default:
                        break
                    }
                }
            }
            guard !built.isEmpty else { continue }
            let updated = Self.date(ms: th.int("updated_at_ms")) ?? Self.date(seconds: th.int("updated_at")) ?? built.last!.updatedAt
            let created = Self.date(ms: th.int("created_at_ms")) ?? Self.date(seconds: th.int("created_at")) ?? built.first!.createdAt
            // An open Codex window keeps recent threads alive; a running turn is busy.
            let live = busy || (appOpen && now.timeIntervalSince(updated) < 6 * 3600)
            var s = SessionInfo(id: tid, projectID: ProjectResolver.projectID(for: cwd),
                                title: (th.str("title") ?? th.str("name")).flatMap { $0.isEmpty ? nil : PromptText.title(from: $0) } ?? built[0].title,
                                cwd: cwd, startedAt: created, lastActivity: updated, promptCount: built.count + built.reduce(0) { $0 + $1.followUps.count })
            s.agent = .codex
            s.isLive = live
            s.liveStatus = live ? (busy ? "busy" : "idle") : nil
            outSessions.append(s)
            outTasks.append(contentsOf: built)
        }
        tasks = outTasks
        sessions = outSessions
        return true
    }

    // MARK: - JSONL rollouts (older CLI builds)

    private func rolloutFiles(_ dir: String) -> [String] {
        let root = dir + "/sessions"
        guard let e = FileManager.default.enumerator(atPath: root) else { return [] }
        var files: [String] = []
        for case let rel as String in e where rel.hasSuffix(".jsonl") && (rel as NSString).lastPathComponent.hasPrefix("rollout-") {
            files.append(root + "/" + rel)
        }
        return files.sorted().suffix(400).map { $0 }
    }

    private func readRollouts(_ dir: String) {
        var outTasks: [TaskItem] = []
        var outSessions: [SessionInfo] = []
        let now = Date()
        for path in rolloutFiles(dir) {
            guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { continue }
            var sid = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            var cwd = ""
            var started: Date?
            var built: [TaskItem] = []
            var asked = false
            var lastPrompt: (String, Date)?
            var finished = true
            var waiting: String?
            var last: Date?
            for line in text.split(separator: "\n") {
                guard let obj = Self.json(String(line)) else { continue }
                let ts = (obj["timestamp"] as? String).flatMap(Self.iso)
                if let ts { last = ts }
                let payload = obj["payload"] as? [String: Any] ?? [:]
                switch obj["type"] as? String {
                case "session_meta":
                    sid = (payload["id"] as? String) ?? sid
                    cwd = (payload["cwd"] as? String) ?? cwd
                    started = (payload["timestamp"] as? String).flatMap(Self.iso) ?? ts
                case "turn_context":
                    cwd = (payload["cwd"] as? String) ?? cwd
                case "event_msg":
                    let kind = payload["type"] as? String ?? ""
                    var prompt: String?
                    if kind == "user_message" { prompt = payload["message"] as? String }
                    if kind == "item_completed", let item = payload["item"] as? [String: Any], (item["type"] as? String) == "UserMessage" {
                        prompt = ((item["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
                    }
                    if prompt != nil { waiting = nil }
                    if let raw = prompt, let clean = PromptText.clean(raw) {
                        let at = ts ?? started ?? now
                        if let lp = lastPrompt, lp.0 == clean, abs(lp.1.timeIntervalSince(at)) < 10 { break }
                        lastPrompt = (clean, at)
                        finished = false
                        if !built.isEmpty && (PromptText.isFollowUp(clean, claudeAsked: asked) || PromptText.isTrivial(clean)) {
                            built[built.count - 1].followUps.append(Exchange(at: at, text: clean))
                        } else if !(built.isEmpty && PromptText.isTrivial(clean)) {
                            var t = TaskItem(id: "codex:\(sid):\(built.count)", origin: .prompt, projectID: ProjectResolver.projectID(for: cwd),
                                             sessionID: sid, title: PromptText.title(from: clean), prompt: clean, createdAt: at, updatedAt: at,
                                             inferredStatus: .todo, cwd: cwd.isEmpty ? nil : cwd)
                            t.agent = .codex
                            built.append(t)
                        }
                        asked = false
                    }
                    guard !built.isEmpty else { break }
                    let k = built.count - 1
                    if let ts {
                        // Active time: gaps between events, leaving out pauses over 5 minutes.
                        if let prev = built[k].stats.endedAt ?? Optional(built[k].createdAt) {
                            let gap = ts.timeIntervalSince(prev)
                            if gap > 0 && gap < 300 { built[k].stats.activeSeconds = (built[k].stats.activeSeconds ?? 0) + gap }
                        }
                        built[k].updatedAt = max(built[k].updatedAt, ts)
                        built[k].stats.endedAt = ts
                    }
                    switch kind {
                    case "agent_message", "task_complete":
                        let reply = ((payload["message"] as? String) ?? (payload["last_agent_message"] as? String) ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !reply.isEmpty {
                            built[k].finalReply = PromptText.truncate(reply, 6000)
                            built[k].stats.replied = true
                            asked = reply.hasSuffix("?")
                        }
                        if kind == "task_complete" { finished = true }
                    case "turn_aborted":
                        finished = true
                    case "request_user_input", "exec_approval_request", "apply_patch_approval_request":
                        // Codex stopped to ask: a question, or permission to run a command or apply a patch.
                        let q = (payload["question"] as? String) ?? (payload["reason"] as? String)
                            ?? ((payload["command"] as? [String]).map { "Allow running `\($0.joined(separator: " "))`?" })
                            ?? (kind == "apply_patch_approval_request" ? "Allow applying these file changes?" : "Codex is waiting for your answer.")
                        waiting = q
                        built[k].pendingAsk = q
                    case "exec_command_begin":
                        // Running a command means any pending approval was given.
                        waiting = nil
                        built[k].pendingAsk = nil
                    case "exec_command_end":
                        waiting = nil
                        built[k].pendingAsk = nil
                        built[k].stats.toolCalls += 1
                        built[k].stats.bashCalls += 1
                    case "patch_apply_end":
                        waiting = nil
                        built[k].pendingAsk = nil
                        built[k].stats.toolCalls += 1
                        built[k].stats.edits += 1
                        for p in ((payload["changes"] as? [String: Any]) ?? [:]).keys where !built[k].stats.filesTouched.contains(p) {
                            built[k].stats.filesTouched.append(p)
                        }
                    default:
                        break
                    }
                default:
                    break
                }
            }
            guard !built.isEmpty else { continue }
            let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? last ?? now
            let busy = !finished && waiting == nil && now.timeIntervalSince(mtime) < 600
            let asking = waiting != nil && now.timeIntervalSince(mtime) < 86_400
            var s = SessionInfo(id: sid, projectID: ProjectResolver.projectID(for: cwd), title: built[0].title, cwd: cwd,
                                startedAt: started ?? built[0].createdAt, lastActivity: last ?? mtime,
                                transcriptPath: path, promptCount: built.count)
            s.agent = .codex
            s.isLive = busy || asking
            s.liveStatus = busy ? "busy" : (asking ? "waiting" : nil)
            if asking { s.needsAction = waiting }
            outSessions.append(s)
            outTasks.append(contentsOf: built)
        }
        tasks = outTasks
        sessions = outSessions
    }

    // MARK: - Helpers

    /// `prefix` + highest version number + ".sqlite" (state_5.sqlite beats state_4.sqlite).
    static func newest(in dir: String, prefix: String) -> String? {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let versions = files.compactMap { f -> (Int, String)? in
            guard f.hasPrefix(prefix), f.hasSuffix(".sqlite"), let n = Int(f.dropFirst(prefix.count).dropLast(7)) else { return nil }
            return (n, dir + "/" + f)
        }
        return versions.max { $0.0 < $1.0 }?.1
    }

    static func mtimeKey(_ path: String) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        let m = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let s = (a?[.size] as? NSNumber)?.intValue ?? 0
        return "\(Int(m * 1000)):\(s)"
    }

    static func json(_ s: String?) -> [String: Any]? {
        guard let s, let d = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func date(seconds: Int64?) -> Date? { seconds.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil } }
    static func date(ms: Int64?) -> Date? { ms.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0) / 1000) : nil } }

    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    static func iso(_ s: String) -> Date? { isoFrac.date(from: s) ?? isoPlain.date(from: s) }
}
