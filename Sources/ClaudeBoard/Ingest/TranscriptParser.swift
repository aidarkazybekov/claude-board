import Foundation

/// Reads one Claude Code session transcript (JSONL) incrementally and turns it into tickets.
///
/// Transcripts are append-only, so the parser remembers its byte offset and only reads
/// what was added since the last pass. A shrunk file resets the parser.
final class TranscriptParser {
    let url: URL
    let sessionID: String

    private(set) var offset: UInt64 = 0
    private var lastSize: UInt64 = 0

    // Session-level state
    private(set) var customTitle: String?
    private(set) var aiTitle: String?
    private(set) var cwd: String?
    private(set) var branch: String?
    private(set) var firstAt: Date?
    private(set) var lastAt: Date?
    private(set) var entrypoint: String?
    private(set) var promptCount = 0

    // Tickets
    private(set) var tasks: [TaskItem] = []
    private(set) var suggestions: [TaskItem] = []
    private var planOwner: Int?
    private var nativeOwner: [String: Int] = [:]
    private var nextNativeID = 1
    private var claudeAsked = false
    private var lastEventAt: Date?

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init(url: URL) {
        self.url = url
        self.sessionID = url.deletingPathExtension().lastPathComponent
    }

    var title: String? { customTitle ?? aiTitle }

    private func reset() {
        offset = 0; lastSize = 0
        customTitle = nil; aiTitle = nil; cwd = nil; branch = nil; firstAt = nil; lastAt = nil
        entrypoint = nil; promptCount = 0
        tasks = []; suggestions = []; planOwner = nil; nativeOwner = [:]; nextNativeID = 1; claudeAsked = false
        lastEventAt = nil
    }

    /// Reads new bytes. Returns true when anything changed.
    @discardableResult
    func update() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value
        else { return false }
        if size < lastSize { reset() }
        lastSize = size
        guard size > offset else { return false }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        do { try fh.seek(toOffset: offset) } catch { return false }
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return false }

        var consumed = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let count = raw.count
            var start = 0
            while start < count {
                guard let nl = memchr(base + start, 0x0A, count - start) else { break }
                let end = base.distance(to: UnsafeRawPointer(nl))
                if end > start { handleLine(base + start, end - start) }
                start = end + 1
                consumed = start
            }
        }
        offset += UInt64(consumed)
        return consumed > 0
    }

    // MARK: - Line handling

    private static let kUser = Array(#""type":"user""#.utf8)
    private static let kAssistant = Array(#""type":"assistant""#.utf8)
    private static let kCustomTitle = Array(#""type":"custom-title""#.utf8)
    private static let kAITitle = Array(#""type":"ai-title""#.utf8)
    private static let kToolResult = Array(#""tool_use_id""#.utf8)
    private static let kSidechain = Array(#""isSidechain":true"#.utf8)

    private func contains(_ p: UnsafeRawPointer, _ n: Int, _ needle: [UInt8]) -> Bool {
        needle.withUnsafeBytes { nb in memmem(p, n, nb.baseAddress, nb.count) != nil }
    }

    private func handleLine(_ p: UnsafeRawPointer, _ n: Int) {
        let isUser = contains(p, n, Self.kUser)
        let isAssistant = contains(p, n, Self.kAssistant)
        let isTitle = contains(p, n, Self.kCustomTitle) || contains(p, n, Self.kAITitle)
        guard isUser || isAssistant || isTitle else { return }
        if contains(p, n, Self.kSidechain) { return }
        // Tool results are the bulk of transcript bytes and never carry a request.
        if isUser && !isAssistant && !isTitle && contains(p, n, Self.kToolResult) { return }

        let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: p), count: n, deallocator: .none)
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String
        else { return }

        switch type {
        case "custom-title":
            if let t = obj["customTitle"] as? String, !t.isEmpty { customTitle = t }
        case "ai-title":
            if let t = obj["aiTitle"] as? String, !t.isEmpty { aiTitle = t }
        case "user":
            handleUser(obj)
        case "assistant":
            handleAssistant(obj)
        default:
            break
        }
    }

    private func date(_ obj: [String: Any]) -> Date? {
        guard let s = obj["timestamp"] as? String else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }

    private func touchSession(_ obj: [String: Any], _ ts: Date?) {
        if let c = obj["cwd"] as? String, !c.isEmpty { cwd = c }
        if let b = obj["gitBranch"] as? String, !b.isEmpty { branch = b }
        if let e = obj["entrypoint"] as? String { entrypoint = e }
        if let ts {
            if firstAt == nil { firstAt = ts }
            lastAt = ts
        }
    }

    private func handleUser(_ obj: [String: Any]) {
        if obj["isMeta"] as? Bool == true || obj["isCompactSummary"] as? Bool == true { return }
        let origin = (obj["origin"] as? [String: Any])?["kind"] as? String
        guard let msg = obj["message"] as? [String: Any] else { return }

        var raw = ""
        var images = 0
        if let s = msg["content"] as? String {
            if origin == nil && s.hasPrefix("<") { return }
            raw = s
        } else if let parts = msg["content"] as? [[String: Any]] {
            for part in parts {
                switch part["type"] as? String {
                case "text": raw += (raw.isEmpty ? "" : "\n") + ((part["text"] as? String) ?? "")
                case "image": images += 1
                case "tool_result": return
                default: break
                }
            }
        }
        if let origin, origin != "human" { return }

        let ts = date(obj) ?? lastAt ?? Date()
        touchSession(obj, ts)
        guard var text = PromptText.clean(raw) else { return }
        if images > 0 { text += images == 1 ? "\n[1 image attached]" : "\n[\(images) images attached]" }
        promptCount += 1
        lastEventAt = ts

        let hasCurrent = !tasks.isEmpty
        if hasCurrent && (PromptText.isFollowUp(text, claudeAsked: claudeAsked) || PromptText.isTrivial(text)) {
            tasks[tasks.count - 1].followUps.append(Exchange(at: ts, text: text))
            tasks[tasks.count - 1].updatedAt = ts
            tasks[tasks.count - 1].pendingAsk = nil
            claudeAsked = false
            return
        }
        if !hasCurrent && PromptText.isTrivial(text) { return }

        let uuid = (obj["uuid"] as? String) ?? "\(Int(ts.timeIntervalSince1970 * 1000))"
        let projectID = ProjectResolver.projectID(for: (obj["cwd"] as? String) ?? cwd)
        let t = TaskItem(
            id: "\(sessionID):\(uuid)",
            origin: .prompt,
            projectID: projectID,
            sessionID: sessionID,
            title: PromptText.title(from: text),
            prompt: text,
            createdAt: ts,
            updatedAt: ts,
            inferredStatus: .todo,
            cwd: (obj["cwd"] as? String) ?? cwd,
            branch: (obj["gitBranch"] as? String) ?? branch
        )
        tasks.append(t)
        claudeAsked = false
    }

    private func handleAssistant(_ obj: [String: Any]) {
        let ts = date(obj)
        touchSession(obj, ts)
        guard !tasks.isEmpty,
              let msg = obj["message"] as? [String: Any],
              let parts = msg["content"] as? [[String: Any]]
        else { return }
        let i = tasks.count - 1
        if let ts {
            tasks[i].updatedAt = max(tasks[i].updatedAt, ts)
            tasks[i].stats.endedAt = ts
            if let prev = lastEventAt {
                let gap = ts.timeIntervalSince(prev)
                if gap > 0 && gap < 300 { tasks[i].stats.activeSeconds = (tasks[i].stats.activeSeconds ?? 0) + gap }
            }
            lastEventAt = ts
        }

        for part in parts {
            switch part["type"] as? String {
            case "text":
                let text = ((part["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                tasks[i].finalReply = PromptText.truncate(text, 6000)
                tasks[i].stats.replied = true
                claudeAsked = text.hasSuffix("?") || text.suffix(200).contains("?\n")
            case "tool_use":
                let name = (part["name"] as? String) ?? ""
                let input = (part["input"] as? [String: Any]) ?? [:]
                handleTool(name, input, taskIndex: i, ts: ts)
            default:
                break
            }
        }
    }

    private func handleTool(_ name: String, _ input: [String: Any], taskIndex i: Int, ts: Date?) {
        tasks[i].stats.toolCalls += 1
        switch name {
        case "Bash":
            tasks[i].stats.bashCalls += 1
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            tasks[i].stats.edits += 1
            if let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String),
               !tasks[i].stats.filesTouched.contains(path)
            {
                tasks[i].stats.filesTouched.append(path)
            }
        case "Agent", "Task":
            tasks[i].stats.agentCalls += 1

        case "mcp__ccd_turn__update_plan":
            applyPlan(input, taskIndex: i)

        case "mcp__ccd_turn__wrap_up":
            if let recap = input["recap"] as? String, !recap.isEmpty {
                tasks[i].recap = recap
                tasks[i].stats.replied = true  // a wrap-up summary is an answer, even without closing text
            }
            if let ask = input["ask"] as? String, !ask.isEmpty {
                tasks[i].pendingAsk = ask
                claudeAsked = true
            } else {
                tasks[i].pendingAsk = nil
            }
            // wrap_up checks off the session's task list.
            if let owner = planOwner {
                for k in tasks[owner].subtasks.indices where tasks[owner].subtasks[k].id.hasPrefix("plan-") {
                    tasks[owner].subtasks[k].state = .completed
                }
            }

        case "TodoWrite":
            if let todos = input["todos"] as? [[String: Any]] {
                tasks[i].subtasks.removeAll { $0.id.hasPrefix("todo-") }
                for (k, t) in todos.enumerated() {
                    let title = (t["content"] as? String) ?? (t["subject"] as? String) ?? "Step \(k + 1)"
                    tasks[i].subtasks.append(Subtask(id: "todo-\(k)", title: title, state: state(t["status"] as? String)))
                }
            }

        case "TaskCreate":
            let id = String(nextNativeID)
            nextNativeID += 1
            let title = (input["subject"] as? String) ?? (input["description"] as? String) ?? "Task \(id)"
            tasks[i].subtasks.append(Subtask(id: "task-\(id)", title: title, state: .pending))
            nativeOwner[id] = i

        case "TaskUpdate":
            guard let id = (input["taskId"] as? String) ?? (input["taskId"] as? Int).map(String.init),
                  let owner = nativeOwner[id],
                  let k = tasks[owner].subtasks.firstIndex(where: { $0.id == "task-\(id)" })
            else { break }
            if let status = input["status"] as? String {
                if status == "deleted" { tasks[owner].subtasks.remove(at: k) } else { tasks[owner].subtasks[k].state = state(status) }
            }
            if let subject = input["subject"] as? String, !subject.isEmpty, tasks[owner].subtasks.indices.contains(k) {
                tasks[owner].subtasks[k].title = subject
            }

        case "AskUserQuestion":
            if let qs = input["questions"] as? [[String: Any]], let q = qs.first?["question"] as? String {
                tasks[i].pendingAsk = q
            }
            claudeAsked = true

        case "ExitPlanMode":
            tasks[i].pendingAsk = "Approve the plan"
            claudeAsked = true

        case "mcp__ccd_session__start_session":
            guard (input["initiation"] as? String) == "own_initiative",
                  let title = input["title"] as? String, !title.isEmpty
            else { break }
            let brief = (input["prompt"] as? String) ?? (input["brief"] as? String) ?? ""
            let at = ts ?? tasks[i].updatedAt
            let id = "\(sessionID):suggest:\(suggestions.count)"
            var s = TaskItem(
                id: id, origin: .suggested, projectID: tasks[i].projectID, sessionID: sessionID,
                title: title, prompt: brief.isEmpty ? title : brief,
                createdAt: at, updatedAt: at, inferredStatus: .backlog, cwd: tasks[i].cwd, branch: tasks[i].branch
            )
            s.recap = "Proposed while working on: \(tasks[i].title)"
            suggestions.append(s)

        default:
            break
        }
    }

    private func applyPlan(_ input: [String: Any], taskIndex i: Int) {
        if let items = input["items"] as? [[String: Any]] {
            tasks[i].subtasks.removeAll { $0.id.hasPrefix("plan-") }
            for (k, item) in items.enumerated() {
                let title = (item["content"] as? String) ?? "Step \(k + 1)"
                tasks[i].subtasks.append(Subtask(id: "plan-\(k)", title: title, state: state(item["status"] as? String)))
            }
            planOwner = i
            return
        }
        guard let owner = planOwner else { return }
        var plan = tasks[owner].subtasks.enumerated().filter { $0.element.id.hasPrefix("plan-") }.map(\.offset)
        if plan.isEmpty { return }
        if input["advance"] as? Bool == true {
            if let cur = plan.first(where: { tasks[owner].subtasks[$0].state == .inProgress }) {
                tasks[owner].subtasks[cur].state = .completed
            }
            if let next = plan.first(where: { tasks[owner].subtasks[$0].state == .pending }) {
                tasks[owner].subtasks[next].state = .inProgress
            }
        }
        if let done = input["done"] as? [Int] {
            for d in done where d >= 1 && d <= plan.count { tasks[owner].subtasks[plan[d - 1]].state = .completed }
        }
        if let start = input["start"] as? Int, start >= 1, start <= plan.count {
            tasks[owner].subtasks[plan[start - 1]].state = .inProgress
        }
        plan.removeAll()
    }

    private func state(_ s: String?) -> SubtaskState {
        switch s {
        case "completed", "done": return .completed
        case "in_progress", "inProgress", "active": return .inProgress
        default: return .pending
        }
    }
}
