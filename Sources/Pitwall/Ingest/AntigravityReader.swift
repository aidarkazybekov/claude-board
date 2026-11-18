import Foundation

/// Reads Antigravity's agent conversations from `~/.gemini/antigravity/brain/<conversation>/`.
/// The conversation log itself is a binary format, but each conversation keeps readable Markdown:
/// `task.md` (the checklist the agent works through), `implementation_plan.md` and, once it's done,
/// `walkthrough.md`. That's one ticket per conversation: the plan's title and summary, the checklist
/// as its steps, the walkthrough as the outcome. The project is the repo its file links point into.
final class AntigravityReader {
    private var signature = ""
    private(set) var tasks: [TaskItem] = []
    private(set) var sessions: [SessionInfo] = []

    static let artifacts = ["task.md", "implementation_plan.md", "walkthrough.md"]

    var roots: [String] { ["antigravity", "antigravity-ide"].map { Paths.geminiDir + "/\($0)/brain" } }

    @discardableResult
    func update() -> Bool {
        let folders = conversationFolders()
        guard !folders.isEmpty else {
            defer { tasks = []; sessions = []; signature = "" }
            return !tasks.isEmpty || !sessions.isEmpty
        }
        var sig = folders.flatMap { f in Self.artifacts.map { CodexReader.mtimeKey(f + "/" + $0) } }.joined(separator: "|")
        if sessions.contains(where: \.isLive) { sig += "|\(Int(Date().timeIntervalSince1970 / 60))" }
        guard sig != signature else { return false }
        signature = sig
        read(folders)
        return true
    }

    func conversationFolders() -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !name.hasPrefix(".") {
                let dir = root + "/" + name
                if Self.artifacts.contains(where: { fm.fileExists(atPath: dir + "/" + $0) }) { out.append(dir) }
            }
        }
        return out.sorted().suffix(400).map { $0 }
    }

    func read(_ folders: [String], now: Date = Date()) {
        let fm = FileManager.default
        var outTasks: [TaskItem] = []
        var outSessions: [SessionInfo] = []
        for dir in folders {
            let id = (dir as NSString).lastPathComponent
            var docs: [String: String] = [:]
            var updated = Date.distantPast
            var earliest = Date.distantFuture
            for name in Self.artifacts {
                guard let text = try? String(contentsOfFile: dir + "/" + name, encoding: .utf8) else { continue }
                docs[name] = text
                if let m = (try? fm.attributesOfItem(atPath: dir + "/" + name))?[.modificationDate] as? Date {
                    updated = max(updated, m)
                    earliest = min(earliest, m)
                }
            }
            guard !docs.isEmpty else { continue }
            // The folder appears when the conversation starts; a copied folder is newer than its files.
            let folderDate = ((try? fm.attributesOfItem(atPath: dir))?[.creationDate] as? Date) ?? earliest
            let created = min(folderDate, earliest)

            let all = Self.artifacts.compactMap { docs[$0] }.joined(separator: "\n")
            let files = Self.fileLinks(all)
            let cwd = files.lazy.compactMap(Self.repo(containing:)).first

            let plan = docs["implementation_plan.md"], task = docs["task.md"], walk = docs["walkthrough.md"]
            let title = [plan, task, walk].compactMap { $0.flatMap(Self.heading) }.first ?? "Antigravity conversation"
            let summary = [plan, task].compactMap { $0.flatMap(Self.firstParagraph) }.first ?? title
            let steps = task.map(Self.checklist) ?? []

            var t = TaskItem(id: "antigravity:\(id)", origin: .prompt,
                             projectID: cwd.map { ProjectResolver.projectID(for: $0) } ?? ProjectResolver.scratchID,
                             sessionID: id, title: PromptText.title(from: title), prompt: summary,
                             createdAt: created, updatedAt: updated, inferredStatus: .todo, cwd: cwd)
            t.agent = .antigravity
            t.subtasks = steps
            t.stats.filesTouched = files
            t.stats.endedAt = updated
            if let walk, let outcome = Self.firstParagraph(walk) {
                t.finalReply = PromptText.truncate(outcome, 6000)
                t.stats.replied = true
            }
            let fresh = now.timeIntervalSince(updated)
            let open = steps.contains { $0.state != .completed }
            let busy = fresh < 180 && walk == nil && (open || steps.isEmpty)
            var s = SessionInfo(id: id, projectID: t.projectID, title: t.title, cwd: cwd ?? "", startedAt: created,
                                lastActivity: updated, promptCount: 1)
            s.agent = .antigravity
            s.isLive = fresh < 900
            s.liveStatus = busy ? "busy" : (s.isLive ? "idle" : nil)
            outSessions.append(s)
            outTasks.append(t)
        }
        tasks = outTasks
        sessions = outSessions
    }

    // MARK: Markdown

    static func heading(_ md: String) -> String? {
        for line in md.split(separator: "\n") where line.hasPrefix("# ") {
            let h = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            for prefix in ["Implementation Plan:", "Implementation Plan -", "Task:", "Walkthrough:"] where h.hasPrefix(prefix) {
                return String(h.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            return h.isEmpty ? nil : h
        }
        return nil
    }

    /// The first run of prose: not a heading, list, table, quote or code.
    static func firstParagraph(_ md: String) -> String? {
        var para: [String] = []
        var inCode = false
        for raw in md.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { continue }
            if line.isEmpty { if !para.isEmpty { break } else { continue } }
            if line.hasPrefix("#") || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("|") || line.hasPrefix(">")
                || line.first?.isNumber == true && line.contains(". ") && line.prefix(4).contains(".")
            {
                if !para.isEmpty { break } else { continue }
            }
            para.append(line)
        }
        let text = para.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// `- [ ] step`, `- [x] done`, `- [/] in progress`, nested or not.
    static func checklist(_ md: String) -> [Subtask] {
        var out: [Subtask] = []
        for raw in md.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count > 6, line.hasPrefix("- [") || line.hasPrefix("* ["), line.dropFirst(4).hasPrefix("] ") else { continue }
            let mark = line[line.index(line.startIndex, offsetBy: 3)]
            let title = String(line.dropFirst(6)).replacingOccurrences(of: "`", with: "")
            let state: SubtaskState = mark == "x" || mark == "X" ? .completed : (mark == "/" ? .inProgress : .pending)
            out.append(Subtask(id: "\(out.count)", title: title, state: state))
        }
        return out
    }

    /// Absolute paths from `file:///…` links, in order, without duplicates.
    static func fileLinks(_ md: String) -> [String] {
        var out: [String] = []
        var rest = Substring(md)
        while let r = rest.range(of: "file://") {
            let tail = rest[r.upperBound...]
            let end = tail.firstIndex(where: { ")] \n\"'>`#".contains($0) }) ?? tail.endIndex
            var path = String(tail[..<end])
            path = path.removingPercentEncoding ?? path
            if path.hasPrefix("/"), !out.contains(path) { out.append(path) }
            rest = tail[end...]
        }
        return out
    }

    /// The git repo a file is in: a known project, or the nearest folder above it with `.git`.
    static func repo(containing path: String) -> String? {
        if let known = ProjectRegistry.shared.repo(containing: path) { return known }
        var dir = (path as NSString).deletingLastPathComponent
        while dir.count > 1 {
            if FileManager.default.fileExists(atPath: dir + "/.git") { return dir }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }
}
