import Foundation

// MARK: - ~/.claude/history.jsonl

/// Prompt history covers sessions whose transcripts Claude Code has already cleaned up.
final class HistoryLoader {
    struct Entry {
        var text: String
        var at: Date
        var project: String
        var sessionID: String
    }

    private var lastSize: UInt64 = 0
    private var lastMtime: Date?
    private(set) var bySession: [String: [Entry]] = [:]

    /// Returns true when the file changed.
    func update() -> Bool {
        let path = Paths.historyFile
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let mtime = attrs[.modificationDate] as? Date
        if size == lastSize && mtime == lastMtime { return false }
        lastSize = size; lastMtime = mtime
        guard let data = FileManager.default.contents(atPath: path),
              let content = String(data: data, encoding: .utf8)
        else { return false }

        var map: [String: [Entry]] = [:]
        content.enumerateLines { line, _ in
            guard let d = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  var text = obj["display"] as? String
            else { return }
            let ms = (obj["timestamp"] as? NSNumber)?.doubleValue ?? 0
            let project = (obj["project"] as? String) ?? ""
            let at = Date(timeIntervalSince1970: ms / 1000)
            let sid = (obj["sessionId"] as? String) ?? "history:\(project):\(Int(ms / 86_400_000))"
            // Inline pasted text when history kept it.
            if let pastes = obj["pastedContents"] as? [String: Any] {
                for (_, v) in pastes {
                    guard let p = v as? [String: Any], let id = p["id"] as? Int, let body = p["content"] as? String else { continue }
                    let marker = "[Pasted text #\(id)"
                    if let r = text.range(of: marker), let close = text.range(of: "]", range: r.upperBound..<text.endIndex) {
                        text.replaceSubrange(r.lowerBound..<close.upperBound, with: body)
                    }
                }
            }
            map[sid, default: []].append(Entry(text: text, at: at, project: project, sessionID: sid))
        }
        bySession = map
        return true
    }

    /// Builds tickets for one session from its prompt history.
    func tasks(for sessionID: String) -> [TaskItem] {
        guard let entries = bySession[sessionID]?.sorted(by: { $0.at < $1.at }) else { return [] }
        var out: [TaskItem] = []
        for e in entries {
            guard let text = PromptText.clean(e.text) else { continue }
            if !out.isEmpty && (PromptText.isFollowUp(text, claudeAsked: false) || PromptText.isTrivial(text)) {
                out[out.count - 1].followUps.append(Exchange(at: e.at, text: text))
                out[out.count - 1].updatedAt = e.at
                continue
            }
            if out.isEmpty && PromptText.isTrivial(text) { continue }
            let ms = Int(e.at.timeIntervalSince1970 * 1000)
            out.append(TaskItem(
                id: "\(sessionID):h\(ms)",
                origin: .history,
                projectID: ProjectResolver.projectID(for: e.project),
                sessionID: sessionID,
                title: PromptText.title(from: text),
                prompt: text,
                createdAt: e.at,
                updatedAt: e.at,
                inferredStatus: .done,
                cwd: e.project
            ))
        }
        return out
    }
}

// MARK: - Claude desktop app session index

struct DesktopSession {
    var localID: String
    var cliSessionID: String
    var cwd: String
    var title: String?
    var archived: Bool
    var createdAt: Date?
    var lastActivityAt: Date?
    var summaryCategory: String?
    var summaryDetail: String?
    var needsAction: String?
}

final class DesktopIndex {
    private var cache: [String: (mtime: Date, value: DesktopSession?)] = [:]
    private(set) var byCLI: [String: DesktopSession] = [:]

    func update() -> Bool {
        let fm = FileManager.default
        let root = Paths.desktopSessionsDir
        var files: [String] = []
        for a in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            for b in (try? fm.contentsOfDirectory(atPath: root + "/" + a)) ?? [] {
                let dir = "\(root)/\(a)/\(b)"
                for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where f.hasPrefix("local_") && f.hasSuffix(".json") {
                    files.append(dir + "/" + f)
                }
            }
        }
        var changed = false
        var seen = Set<String>()
        for path in files {
            seen.insert(path)
            let mtime = ((try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
            if let c = cache[path], c.mtime == mtime { continue }
            changed = true
            cache[path] = (mtime, parse(path))
        }
        for k in cache.keys where !seen.contains(k) { cache[k] = nil; changed = true }
        if changed {
            var map: [String: DesktopSession] = [:]
            for (_, v) in cache { if let s = v.value { map[s.cliSessionID] = s } }
            byCLI = map
        }
        return changed
    }

    private func parse(_ path: String) -> DesktopSession? {
        guard let data = FileManager.default.contents(atPath: path),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cli = o["cliSessionId"] as? String
        else { return nil }
        func ms(_ k: String) -> Date? { (o[k] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } }
        let summary = o["postTurnSummary"] as? [String: Any]
        let needs = (summary?["needs_action"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return DesktopSession(
            localID: (o["sessionId"] as? String) ?? "",
            cliSessionID: cli,
            cwd: (o["cwd"] as? String) ?? "",
            title: o["title"] as? String,
            archived: (o["isArchived"] as? Bool) ?? false,
            createdAt: ms("createdAt"),
            lastActivityAt: ms("lastActivityAt"),
            summaryCategory: summary?["status_category"] as? String,
            summaryDetail: summary?["status_detail"] as? String,
            needsAction: needs
        )
    }
}

// MARK: - Running sessions (~/.claude/sessions/<pid>.json)

struct LiveSession {
    var pid: Int32
    var sessionID: String
    var cwd: String
    var status: String
    var name: String?
    var entrypoint: String?
}

enum LiveSessions {
    private static let ctime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return f
    }()

    /// Whether the running process `pid` started at `recorded` (ctime format, UTC). Unparseable → trusted.
    static func sameStart(pid: Int32, recorded: String) -> Bool {
        let normalized = recorded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let want = ctime.date(from: normalized), let started = processStart(pid) else { return true }
        return abs(started.timeIntervalSince(want)) < 3
    }

    static func processStart(_ pid: Int32) -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        guard tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
    }

    static func load() -> [String: LiveSession] {
        let dir = Paths.liveSessionsDir
        var out: [String: LiveSession] = [:]
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".json") {
            guard let data = FileManager.default.contents(atPath: dir + "/" + f),
                  let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let pid = (o["pid"] as? NSNumber)?.int32Value,
                  let sid = o["sessionId"] as? String
            else { continue }
            // kill(pid, 0) == 0 or EPERM means the process exists. The pid may have been reused by
            // another program since, so its start time must match the one Claude Code wrote down.
            guard kill(pid, 0) == 0 || errno == EPERM else { continue }
            if let recorded = o["procStart"] as? String, !Self.sameStart(pid: pid, recorded: recorded) { continue }
            out[sid] = LiveSession(
                pid: pid, sessionID: sid, cwd: (o["cwd"] as? String) ?? "",
                status: (o["status"] as? String) ?? "idle", name: o["name"] as? String,
                entrypoint: o["entrypoint"] as? String
            )
        }
        return out
    }
}
