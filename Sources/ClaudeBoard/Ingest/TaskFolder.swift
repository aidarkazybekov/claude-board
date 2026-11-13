import Foundation

/// A backlog folder: one markdown file per task with YAML front matter, optionally indexed by a
/// BACKLOG.md table. Compatible with hand-written backlogs (`id/title/area/priority/status`)
/// and with the Backlog.md CLI layout (`backlog/tasks/task-1 - Title.md`).
///
/// Writes are surgical: only the front-matter lines, checklist lines or index cells that
/// change are rewritten, so the rest of a file stays byte-for-byte as the author left it.
struct TaskFile {
    var path: String
    var folder: String
    var fields: [String: String]      // lowercased keys
    var body: String
    var mtime: Date
    var created: Date

    var id: String {
        if let v = fields["id"], !v.isEmpty { return v }
        // T-015-slug.md → T-015 ; task-12 - Title.md → task-12
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if let r = name.range(of: #"^[A-Za-z]+-\d+"#, options: .regularExpression) { return String(name[r]) }
        return name
    }

    var title: String {
        if let t = fields["title"], !t.isEmpty { return t }
        for line in body.split(separator: "\n") where line.hasPrefix("# ") {
            var t = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if t.hasPrefix(id) { t = t.dropFirst(id.count).trimmingCharacters(in: CharacterSet(charactersIn: " —–-:")) }
            return t
        }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    var labels: [String] {
        let raw = fields["labels"] ?? fields["tags"] ?? ""
        return TaskFolder.list(raw)
    }
}

enum TaskFolder {
    static let indexNames = ["BACKLOG.md", "INDEX.md", "Backlog.md"]
    static let nonTaskFiles: Set<String> = ["readme.md", "backlog.md", "index.md", "changelog.md", "config.md", "template.md"]

    // MARK: Discovery

    static func tasksDir(_ folder: String) -> String {
        var isDir: ObjCBool = false
        let sub = folder + "/tasks"
        if FileManager.default.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue { return sub }
        return folder
    }

    static func taskFiles(in folder: String) -> [String] {
        let dir = tasksDir(folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { $0.lowercased().hasSuffix(".md") && !nonTaskFiles.contains($0.lowercased()) && !$0.hasPrefix(".") }
            .sorted().map { dir + "/" + $0 }
    }

    /// A folder counts when it holds at least one markdown file with `title:`/`status:` front matter.
    static func isTaskFolder(_ folder: String) -> Bool {
        let fm = FileManager.default
        if indexNames.contains(where: { fm.fileExists(atPath: folder + "/" + $0) }) { return true }
        for f in taskFiles(in: folder).prefix(8) {
            guard let h = try? FileHandle(forReadingFrom: URL(fileURLWithPath: f)) else { continue }
            let head = String(data: h.readData(ofLength: 600), encoding: .utf8) ?? ""
            try? h.close()
            if head.hasPrefix("---") && head.contains("\nstatus:") && (head.contains("\ntitle:") || head.contains("\nid:")) { return true }
        }
        return false
    }

    // MARK: Parsing

    static func parse(_ path: String, folder: String) -> TaskFile? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let mtime = attrs?[.modificationDate] as? Date ?? Date()
        let created = attrs?[.creationDate] as? Date ?? mtime
        let (fm, body) = splitFrontMatter(text)
        var fields: [String: String] = [:]
        var lastKey: String?
        for line in fm {
            if line.hasPrefix("  - ") || line.hasPrefix("- "), let k = lastKey {
                // YAML block list → comma list
                let item = line.trimmingCharacters(in: .whitespaces).dropFirst(2).trimmingCharacters(in: .whitespaces)
                fields[k] = (fields[k].map { $0.isEmpty ? "" : $0 + ", " } ?? "") + unquote(item)
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !key.contains(" ") else { continue }
            fields[key] = unquote(value)
            lastKey = key
        }
        return TaskFile(path: path, folder: folder, fields: fields, body: body, mtime: mtime, created: created)
    }

    static func splitFrontMatter(_ text: String) -> (fm: [String], body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return ([], text) }
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            return (Array(lines[1..<i]), lines[(i + 1)...].joined(separator: "\n"))
        }
        return ([], text)
    }

    static func unquote(_ v: String) -> String {
        var s = v
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            s = String(s.dropFirst().dropLast())
            s = s.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "''", with: "'")
        }
        return s
    }

    static func quoteIfNeeded(_ v: String) -> String {
        let special = v.contains(": ") || v.contains(" #") || v.hasSuffix(":")
            || ["[", "{", "\"", "'", "&", "*", "!", "|", ">", "%", "@", "`", "#", "-", "?"].contains(where: { v.hasPrefix($0) })
        guard special else { return v }
        return "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func list(_ raw: String) -> [String] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("[") && s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        return s.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    /// `- [ ]` / `- [x]` lines in the body.
    static func checklist(_ body: String) -> [Subtask] {
        var out: [Subtask] = []
        for (i, line) in body.components(separatedBy: "\n").enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- [") || t.hasPrefix("* ["), t.count >= 5 else { continue }
            let mark = t[t.index(t.startIndex, offsetBy: 3)]
            guard t[t.index(t.startIndex, offsetBy: 4)] == "]" else { continue }
            let text = t.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let state: SubtaskState = (mark == "x" || mark == "X") ? .completed : (mark == "~" || mark == "/") ? .inProgress : .pending
            out.append(Subtask(id: "cl-\(i)", title: text, state: state))
        }
        return out
    }

    // MARK: Status / priority vocabulary

    static func column(for raw: String?) -> TaskStatus {
        let s = (raw ?? "").lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
        switch s {
        case "", "backlog", "icebox", "someday", "idea", "ideas", "draft", "new", "open": return .backlog
        case "todo", "to-do", "ready", "next", "planned", "investigating", "triage", "selected": return .todo
        case "in-progress", "inprogress", "doing", "active", "wip", "started", "working", "in-review", "review": return .inProgress
        case "blocked", "waiting", "on-hold", "needs-you", "needs-input", "paused": return .needsYou
        case "done", "closed", "complete", "completed", "shipped", "resolved", "cancelled", "canceled", "wontfix": return .done
        default: return .todo
        }
    }

    /// Status text to write. Keeps the current word when it already maps to the target column,
    /// and matches the folder's style (kebab-case `in-progress` vs Backlog.md's `In Progress`).
    static func raw(for status: TaskStatus, current: String?, titleCase: Bool) -> String {
        if let current, !current.isEmpty, column(for: current) == status { return current }
        let kebab: String
        switch status {
        case .backlog: kebab = "backlog"
        case .todo: kebab = "todo"
        case .inProgress: kebab = "in-progress"
        case .needsYou: kebab = "blocked"
        case .done: kebab = "done"
        }
        guard titleCase else { return kebab }
        switch status {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .needsYou: return "Blocked"
        case .done: return "Done"
        }
    }

    static func priority(_ raw: String?) -> Priority {
        switch (raw ?? "").lowercased().trimmingCharacters(in: .whitespaces) {
        case "p0", "urgent", "critical", "highest", "blocker": return .urgent
        case "p1", "high": return .high
        case "p2", "medium", "normal", "med": return .medium
        case "p3", "p4", "low", "lowest", "minor": return .low
        default: return .none
        }
    }

    static func raw(for p: Priority, pStyle: Bool) -> String? {
        if pStyle {
            switch p {
            case .none: return nil
            case .urgent: return "P0"
            case .high: return "P1"
            case .medium: return "P2"
            case .low: return "P3"
            }
        }
        switch p {
        case .none: return nil
        case .urgent: return "urgent"
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        }
    }

    // MARK: Writing

    /// Sets (or removes, with nil) front-matter keys, keeping every other line as it was.
    static func updateFields(_ path: String, _ changes: [(String, String?)]) throws {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        var end = -1
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" { end = i; break }
        }
        if end < 0 {
            lines.insert(contentsOf: ["---", "---"], at: 0)
            end = 1
        }
        for (key, value) in changes {
            let k = key.lowercased()
            var found = -1
            for i in 1..<end {
                let l = lines[i]
                if let c = l.firstIndex(of: ":"), l[..<c].trimmingCharacters(in: .whitespaces).lowercased() == k, !l.hasPrefix(" ") {
                    found = i; break
                }
            }
            if let value {
                let line = "\(key): \(quoteIfNeeded(value))"
                if found >= 0 {
                    // drop a following YAML block list that belonged to this key
                    var j = found + 1
                    while j < end, lines[j].hasPrefix("  - ") || lines[j].hasPrefix("- ") { j += 1 }
                    lines.replaceSubrange(found..<j, with: [line])
                    end -= (j - found - 1)
                } else {
                    lines.insert(line, at: end)
                    end += 1
                }
            } else if found >= 0 {
                var j = found + 1
                while j < end, lines[j].hasPrefix("  - ") || lines[j].hasPrefix("- ") { j += 1 }
                lines.removeSubrange(found..<j)
                end -= (j - found)
            }
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func setBody(_ path: String, _ body: String) throws {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        var head: [String] = []
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                head = Array(lines[0...i]); break
            }
        }
        let out = head.isEmpty ? body : head.joined(separator: "\n") + "\n" + body
        try out.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Flips one checklist line (by its index in the body).
    static func setChecklist(_ path: String, bodyLine: Int, done: Bool) throws {
        guard let f = parse(path, folder: "") else { return }
        var lines = f.body.components(separatedBy: "\n")
        guard lines.indices.contains(bodyLine) else { return }
        var l = lines[bodyLine]
        if let r = l.range(of: #"[-*] \[[ xX~/]\]"#, options: .regularExpression) {
            let bullet = l[r].first!
            l.replaceSubrange(r, with: "\(bullet) [\(done ? "x" : " ")]")
            lines[bodyLine] = l
            try setBody(path, lines.joined(separator: "\n"))
        }
    }

    /// Next id in the folder's pattern (T-018 → T-019, task-7 → task-8). Returns id and padding.
    static func nextID(in folder: String) -> String {
        var prefix = "T-"
        var width = 3
        var maxN = 0
        for f in taskFiles(in: folder) {
            guard let t = parse(f, folder: folder) else { continue }
            let id = t.id
            if let r = id.range(of: #"\d+$"#, options: .regularExpression) {
                let n = Int(id[r]) ?? 0
                if n >= maxN {
                    maxN = n
                    prefix = String(id[..<r.lowerBound])
                    width = id[r].count
                }
            }
        }
        // Index rows count too (a task file may have been archived elsewhere).
        if let index = indexPath(folder), let text = try? String(contentsOfFile: index, encoding: .utf8) {
            let esc = NSRegularExpression.escapedPattern(for: prefix)
            if let re = try? NSRegularExpression(pattern: "\\b\(esc)(\\d+)\\b") {
                for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let r = Range(m.range(at: 1), in: text) { maxN = max(maxN, Int(text[r]) ?? 0) }
                }
            }
        }
        return prefix + String(format: "%0\(width)d", maxN + 1)
    }

    static func slug(_ s: String) -> String {
        let latin = s.applyingTransform(.toLatin, reverse: false)?.applyingTransform(.stripDiacritics, reverse: false) ?? s
        var out = ""
        for ch in latin.lowercased() {
            if ch.isLetter || ch.isNumber { out.append(ch) } else if !out.hasSuffix("-") { out.append("-") }
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if out.count > 48, let cut = out.prefix(48).lastIndex(of: "-") { out = String(out[..<cut]) }
        return out.isEmpty ? "task" : out
    }

    /// Writes a new task file and appends it to the index. Returns the file path.
    @discardableResult
    static func create(in folder: String, title: String, status: TaskStatus, priority: Priority, area: String?,
                       project: String?, labels: [String], notes: String, checklist: [String]) throws -> String
    {
        let existing = taskFiles(in: folder).compactMap { parse($0, folder: folder) }
        let titleCase = existing.contains { ($0.fields["status"] ?? "").contains(" ") || ($0.fields["status"] ?? "").first?.isUppercase == true }
        let pStyle = existing.isEmpty || existing.contains { ($0.fields["priority"] ?? "").uppercased().hasPrefix("P") }
        let id = nextID(in: folder)
        let dir = tasksDir(folder)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/\(id)-\(slug(title)).md"

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var fm = ["---", "id: \(id)", "title: \(quoteIfNeeded(title))"]
        if let area, !area.isEmpty { fm.append("area: \(quoteIfNeeded(area))") }
        if let project, !project.isEmpty { fm.append("project: \(quoteIfNeeded(project))") }
        if let p = raw(for: priority, pStyle: pStyle) { fm.append("priority: \(p)") }
        fm.append("status: \(raw(for: status, current: nil, titleCase: titleCase))")
        if !labels.isEmpty { fm.append("labels: [\(labels.map(quoteIfNeeded).joined(separator: ", "))]") }
        fm.append("captured: \(df.string(from: Date()))")
        fm.append("---")
        var body = ["", "# \(id) — \(title)", ""]
        if !notes.isEmpty { body.append(contentsOf: [notes, ""]) }
        if !checklist.isEmpty {
            body.append("## Done when")
            body.append("")
            body.append(contentsOf: checklist.map { "- [ ] \($0)" })
            body.append("")
        }
        try (fm + body).joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)

        appendIndexRow(folder: folder, id: id, relPath: String(path.dropFirst(folder.count + 1)), title: title,
                       area: area ?? "", priority: raw(for: priority, pStyle: pStyle) ?? "", status: raw(for: status, current: nil, titleCase: titleCase))
        return path
    }

    // MARK: Index (BACKLOG.md table)

    static func indexPath(_ folder: String) -> String? {
        indexNames.map { folder + "/" + $0 }.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func cells(_ line: String) -> [String] {
        var parts = line.components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func row(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }

    /// Header columns of the first table that has an ID column.
    private static func table(_ lines: [String]) -> (header: Int, cols: [String: Int], lastRow: Int)? {
        for (i, l) in lines.enumerated() where l.hasPrefix("|") {
            let c = cells(l).map { $0.lowercased() }
            guard let idCol = c.firstIndex(where: { $0 == "id" || $0 == "key" || $0 == "#" }) else { continue }
            var cols: [String: Int] = ["id": idCol]
            for (k, name) in c.enumerated() {
                switch name {
                case "title", "task", "name": cols["title"] = k
                case "status", "state": cols["status"] = k
                case "priority", "prio", "pri": cols["priority"] = k
                case "area": cols["area"] = k
                case "project", "app": cols["project"] = k
                default: break
                }
            }
            var last = i
            var j = i + 1
            while j < lines.count, lines[j].hasPrefix("|") { last = j; j += 1 }
            return (i, cols, last)
        }
        return nil
    }

    static func updateIndexRow(folder: String, id: String, title: String? = nil, status: String? = nil, priority: String? = nil) {
        guard let path = indexPath(folder), let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        guard let t = table(lines), let idCol = t.cols["id"] else { return }
        let idRe = try? NSRegularExpression(pattern: "(^|[^A-Za-z0-9-])" + NSRegularExpression.escapedPattern(for: id) + "([^0-9]|$)")
        for i in (t.header + 2)...max(t.header + 2, t.lastRow) where i <= t.lastRow {
            var c = cells(lines[i])
            guard idCol < c.count, let idRe, idRe.firstMatch(in: c[idCol], range: NSRange(c[idCol].startIndex..., in: c[idCol])) != nil else { continue }
            if let title, let k = t.cols["title"], k < c.count { c[k] = title.replacingOccurrences(of: "|", with: "/") }
            if let status, let k = t.cols["status"], k < c.count { c[k] = status }
            if let priority, let k = t.cols["priority"], k < c.count { c[k] = priority }
            let new = row(c)
            if new != lines[i] {
                lines[i] = new
                try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
            return
        }
    }

    static func appendIndexRow(folder: String, id: String, relPath: String, title: String, area: String, priority: String, status: String) {
        guard let path = indexPath(folder), let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var lines = text.components(separatedBy: "\n")
        guard let t = table(lines) else { return }
        let width = cells(lines[t.header]).count
        var c = Array(repeating: "", count: width)
        func set(_ k: String, _ v: String) { if let i = t.cols[k], i < width { c[i] = v } }
        set("id", "[\(id)](\(relPath))")
        set("title", title.replacingOccurrences(of: "|", with: "/"))
        set("area", area)
        set("priority", priority)
        set("status", status)
        lines.insert(row(c), at: t.lastRow + 1)
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Creates `<dir>/backlog/` with a README explaining the format and an empty index.
    static func scaffold(in dir: String, projectName: String) throws -> String {
        let folder = dir + "/backlog"
        try FileManager.default.createDirectory(atPath: folder + "/tasks", withIntermediateDirectories: true)
        let readme = """
        # \(projectName) backlog

        Tasks for this project, one markdown file per task in `tasks/`, indexed in `BACKLOG.md`.
        Plain text, so it works in git, in any editor, for teammates, and for Claude Code
        ("read backlog/tasks/T-003-….md and do it"). ClaudeBoard reads and edits these files.

        ## Task file

        ```markdown
        ---
        id: T-001
        title: Short imperative title
        area: Frontend
        priority: P1        # P0 drop everything · P1 this sprint · P2 soon · P3 someday
        status: backlog     # backlog · todo · in-progress · blocked · done
        captured: 2026-01-31
        ---

        # T-001 — Short imperative title

        What it is, why it matters, what is unknown.

        ## Done when

        - [ ] a checkable outcome
        ```

        IDs are stable and never reused. Renaming a file is fine; changing an ID is not.
        """
        let index = """
        # Backlog index

        | ID | Title | Area | Priority | Status |
        | --- | --- | --- | --- | --- |
        """
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder + "/README.md") { try readme.write(toFile: folder + "/README.md", atomically: true, encoding: .utf8) }
        if !fm.fileExists(atPath: folder + "/BACKLOG.md") { try (index + "\n").write(toFile: folder + "/BACKLOG.md", atomically: true, encoding: .utf8) }
        return folder
    }
}
