import Foundation

/// Turns one agent conversation into tickets, the same way for every agent: one ticket per request,
/// short replies ("yes", "go on") fold into the request before, and tool calls, edits, replies and
/// active time land on the request they belong to.
struct TicketBuilder {
    let agent: Agent
    let sessionID: String
    let projectID: String
    let cwd: String?
    private(set) var tickets: [TaskItem] = []
    private var asked = false
    private var lastEvent: Date?

    init(agent: Agent, sessionID: String, cwd: String?) {
        self.agent = agent
        self.sessionID = sessionID
        let folder = cwd.flatMap { $0.isEmpty ? nil : $0 }
        self.cwd = folder
        projectID = folder.map { ProjectResolver.projectID(for: $0) } ?? ProjectResolver.scratchID
    }

    var isEmpty: Bool { tickets.isEmpty }

    /// A message from the user. `key` keeps ticket ids stable across refreshes.
    mutating func user(_ raw: String, at: Date, key: String, images: Int = 0) {
        guard let prompt = PromptText.clean(raw) else { return }
        if !tickets.isEmpty && (PromptText.isFollowUp(prompt, claudeAsked: asked) || PromptText.isTrivial(prompt)) {
            let k = tickets.count - 1
            tickets[k].followUps.append(Exchange(at: at, text: prompt))
            tickets[k].pendingAsk = nil
            touch(at)
        } else if tickets.isEmpty && PromptText.isTrivial(prompt) {
            return
        } else {
            var shown = prompt
            if images > 0 { shown += images == 1 ? "\n[1 image attached]" : "\n[\(images) images attached]" }
            var t = TaskItem(id: "\(agent.rawValue):\(sessionID):\(key)", origin: .prompt, projectID: projectID,
                             sessionID: sessionID, title: PromptText.title(from: prompt), prompt: shown,
                             createdAt: at, updatedAt: at, inferredStatus: .todo, cwd: cwd)
            t.agent = agent
            tickets.append(t)
            lastEvent = at
        }
        asked = false
    }

    /// The agent's text reply.
    mutating func reply(_ raw: String, at: Date) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tickets.isEmpty, !text.isEmpty else { return }
        let k = tickets.count - 1
        tickets[k].finalReply = PromptText.truncate(text, 6000)
        tickets[k].stats.replied = true
        tickets[k].pendingAsk = nil
        asked = text.hasSuffix("?") || text.suffix(200).contains("?\n")
        touch(at)
    }

    /// A tool call. Shell commands and file edits are told apart by the tool's name.
    mutating func tool(_ name: String, files: [String] = [], at: Date) {
        guard !tickets.isEmpty else { return }
        let k = tickets.count - 1
        let n = name.lowercased()
        tickets[k].stats.toolCalls += 1
        if ["shell", "terminal", "command", "bash", "exec"].contains(where: n.contains) {
            tickets[k].stats.bashCalls += 1
        } else if ["edit", "write", "replace", "patch", "create_file", "delete", "apply"].contains(where: n.contains) {
            tickets[k].stats.edits += 1
            addFiles(files)
        } else if n.contains("agent") || n == "task" {
            tickets[k].stats.agentCalls += 1
        }
        touch(at)
    }

    mutating func addFiles(_ files: [String]) {
        guard !tickets.isEmpty else { return }
        let k = tickets.count - 1
        for f in files where !f.isEmpty && !tickets[k].stats.filesTouched.contains(f) {
            tickets[k].stats.filesTouched.append(f)
        }
    }

    /// The agent stopped to ask: a question, or permission to run something.
    mutating func ask(_ question: String) {
        guard !tickets.isEmpty else { return }
        tickets[tickets.count - 1].pendingAsk = question
    }

    mutating func plan(_ steps: [Subtask]) {
        guard !tickets.isEmpty, !steps.isEmpty else { return }
        tickets[tickets.count - 1].subtasks = steps
    }

    /// Active time: gaps between events on the same request, leaving out pauses over 5 minutes.
    mutating func touch(_ at: Date) {
        guard !tickets.isEmpty else { return }
        let k = tickets.count - 1
        if let prev = lastEvent {
            let gap = at.timeIntervalSince(prev)
            if gap > 0 && gap < 300 { tickets[k].stats.activeSeconds = (tickets[k].stats.activeSeconds ?? 0) + gap }
        }
        lastEvent = max(lastEvent ?? at, at)
        tickets[k].updatedAt = max(tickets[k].updatedAt, at)
        tickets[k].stats.endedAt = max(tickets[k].stats.endedAt ?? at, at)
    }

    func session(title: String?, startedAt: Date?, lastActivity: Date, live: Bool, busy: Bool, waiting: String? = nil,
                 transcriptPath: String? = nil) -> SessionInfo {
        let named = title.flatMap { $0.isEmpty ? nil : PromptText.title(from: $0) }
        var s = SessionInfo(id: sessionID, projectID: projectID, title: named ?? tickets.first?.title ?? agent.title,
                            cwd: cwd ?? "", startedAt: startedAt ?? tickets.first?.createdAt ?? lastActivity,
                            lastActivity: lastActivity, transcriptPath: transcriptPath,
                            promptCount: tickets.count + tickets.reduce(0) { $0 + $1.followUps.count })
        s.agent = agent
        s.isLive = live || busy
        s.liveStatus = busy ? "busy" : (waiting != nil ? "waiting" : (live ? "idle" : nil))
        if let waiting { s.needsAction = waiting }
        return s
    }

    // MARK: Shared parsing helpers

    /// An ISO 8601 string, or a number of seconds or milliseconds since 1970.
    static func date(_ v: Any?) -> Date? {
        switch v {
        case let s as String: return CodexReader.iso(s) ?? Double(s).flatMap(epoch)
        case let n as NSNumber: return epoch(n.doubleValue)
        default: return nil
        }
    }

    static func epoch(_ d: Double) -> Date? {
        d > 1e11 ? Date(timeIntervalSince1970: d / 1000) : (d > 0 ? Date(timeIntervalSince1970: d) : nil)
    }

    /// Text from a string, or from a list of `{text: …}` parts.
    static func text(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let parts = v as? [[String: Any]] { return parts.compactMap { $0["text"] as? String }.joined(separator: "\n") }
        return ""
    }

    /// File paths named in a tool's arguments, under the keys agents commonly use.
    static func files(in args: [String: Any]) -> [String] {
        ["file_path", "absolute_path", "target_file", "path", "relativeWorkspacePath", "filePath", "file"]
            .compactMap { args[$0] as? String }
    }

    static func stepState(_ s: String?) -> SubtaskState {
        switch (s ?? "").lowercased() {
        case "completed", "complete", "done", "cancelled": return .completed
        case "in_progress", "inprogress", "in-progress", "active": return .inProgress
        default: return .pending
        }
    }
}
