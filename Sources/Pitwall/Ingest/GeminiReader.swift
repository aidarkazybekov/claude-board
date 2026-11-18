import CryptoKit
import Foundation

/// Reads Gemini CLI sessions from `~/.gemini/tmp/<project>/chats/`: one JSON file per session
/// (`sessionId`, `startTime`, `lastUpdated`, `messages`), or JSONL in newer builds (one message per
/// line, with the session fields on a line of their own). `<project>` is the SHA-256 of the project
/// folder, so it's matched against the repos found under the project roots; files that name their
/// `directories` say it outright.
final class GeminiReader {
    private var signature = ""
    private(set) var tasks: [TaskItem] = []
    private(set) var sessions: [SessionInfo] = []

    var root: String { Paths.geminiDir + "/tmp" }

    @discardableResult
    func update() -> Bool {
        let files = chatFiles()
        guard !files.isEmpty else {
            defer { tasks = []; sessions = []; signature = "" }
            return !tasks.isEmpty || !sessions.isEmpty
        }
        var sig = files.map(CodexReader.mtimeKey).joined(separator: "|")
        if sessions.contains(where: \.isLive) { sig += "|\(Int(Date().timeIntervalSince1970 / 60))" }
        guard sig != signature else { return false }
        signature = sig
        read(files)
        return true
    }

    func chatFiles() -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for project in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let chats = "\(root)/\(project)/chats"
            for f in (try? fm.contentsOfDirectory(atPath: chats)) ?? [] where f.hasSuffix(".json") || f.hasSuffix(".jsonl") {
                out.append("\(chats)/\(f)")
            }
        }
        return out.sorted().suffix(400).map { $0 }
    }

    func read(_ files: [String], now: Date = Date()) {
        var byHash: [String: String] = [:]
        for repo in ProjectRegistry.shared.repos + Roots.all {
            byHash[Self.hash(repo)] = repo
        }
        var outTasks: [TaskItem] = []
        var outSessions: [SessionInfo] = []
        for path in files {
            guard let chat = Self.parse(path) else { continue }
            if (chat["kind"] as? String) == "subagent" { continue }
            let projectDir = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            let hash = (chat["projectHash"] as? String) ?? (projectDir as NSString).lastPathComponent
            let cwd = ((chat["directories"] as? [String])?.first)
                ?? (try? String(contentsOfFile: projectDir + "/.project_root", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? byHash[hash]
            let sid = (chat["sessionId"] as? String) ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let messages = (chat["messages"] as? [[String: Any]]) ?? []
            let started = TicketBuilder.date(chat["startTime"]) ?? TicketBuilder.date(messages.first?["timestamp"]) ?? now
            var b = TicketBuilder(agent: .gemini, sessionID: sid, cwd: cwd)
            var at = started
            var lastWasUser = false
            var running = false
            for (i, m) in messages.enumerated() {
                at = TicketBuilder.date(m["timestamp"]) ?? at
                switch m["type"] as? String {
                case "user":
                    b.user(TicketBuilder.text(m["content"]), at: at, key: (m["id"] as? String) ?? "\(i)")
                    lastWasUser = true
                    running = false
                case "gemini", "model":
                    for call in (m["toolCalls"] as? [[String: Any]]) ?? [] {
                        let when = TicketBuilder.date(call["timestamp"]) ?? at
                        b.tool((call["name"] as? String) ?? "tool", files: TicketBuilder.files(in: (call["args"] as? [String: Any]) ?? [:]), at: when)
                        if call["name"] as? String == "write_todos", let todos = (call["args"] as? [String: Any])?["todos"] as? [[String: Any]] {
                            b.plan(todos.enumerated().compactMap { j, t in
                                guard let d = (t["description"] as? String) ?? (t["content"] as? String) else { return nil }
                                return Subtask(id: "\(j)", title: d, state: TicketBuilder.stepState(t["status"] as? String))
                            })
                        }
                        running = !["success", "error", "cancelled"].contains((call["status"] as? String) ?? "success")
                    }
                    b.reply(TicketBuilder.text(m["content"]), at: at)
                    lastWasUser = false
                default:
                    break
                }
            }
            guard !b.isEmpty else { continue }
            let mtime = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? at
            let updated = max(TicketBuilder.date(chat["lastUpdated"]) ?? at, at)
            let fresh = now.timeIntervalSince(max(mtime, updated))
            let busy = fresh < 120 && (lastWasUser || running)
            let live = fresh < 600
            outSessions.append(b.session(title: chat["summary"] as? String, startedAt: started, lastActivity: updated,
                                         live: live, busy: busy, transcriptPath: path))
            outTasks.append(contentsOf: b.tickets)
        }
        tasks = outTasks
        sessions = outSessions
    }

    /// One session object, from a JSON file or a JSONL one (messages one per line, session fields merged in).
    static func parse(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else { return nil }
        if let whole = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return whole }
        var chat: [String: Any] = [:]
        var messages: [[String: Any]] = []
        for line in text.split(separator: "\n") {
            guard let obj = CodexReader.json(String(line)) else { continue }
            if obj["type"] != nil && (obj["content"] != nil || obj["toolCalls"] != nil) {
                messages.append(obj)
            } else {
                for (k, v) in obj where k != "messages" { chat[k] = v }
                if let ms = obj["messages"] as? [[String: Any]] { messages += ms }
            }
        }
        guard !messages.isEmpty else { return nil }
        chat["messages"] = messages
        return chat
    }

    /// Gemini CLI names a project's folder after the SHA-256 of its absolute path.
    static func hash(_ path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
