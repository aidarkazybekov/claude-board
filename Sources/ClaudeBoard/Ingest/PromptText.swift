import Foundation

/// Heuristics that turn raw user turns into ticket text.
enum PromptText {
    /// Slash commands that are app plumbing, never work requests.
    static let plumbingCommands: Set<String> = [
        "/clear", "/compact", "/model", "/mcp", "/login", "/logout", "/exit", "/quit", "/resume", "/config",
        "/cost", "/help", "/status", "/context", "/plugins", "/plugin", "/permissions", "/memory", "/doctor",
        "/init", "/hooks", "/agents", "/ide", "/terminal-setup", "/vim", "/theme", "/fast", "/usage",
        "/add-dir", "/bug", "/release-notes", "/upgrade", "/statusline", "/output-style", "/export", "/rewind",
    ]

    /// Normalizes a user turn. Returns nil when the turn is not something the user asked for.
    static func clean(_ raw: String) -> String? {
        var text = raw
        if text.hasPrefix("<bash-") || text.hasPrefix("<local-command") || text.hasPrefix("Caveat:")
            || text.hasPrefix("This session is being continued") || text.hasPrefix("<task-notification")
            || text.hasPrefix("<artifact-") || text.hasPrefix("<side-sessions-event") || text.hasPrefix("<ci-monitor-event")
        {
            return nil
        }
        if text.contains("<command-name>") {
            let name = between(text, "<command-name>", "</command-name>")?.trimmingCharacters(in: .whitespaces) ?? ""
            let args = between(text, "<command-args>", "</command-args>")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if args.isEmpty || plumbingCommands.contains(name) { return nil }
            text = "\(name) \(args)"
        }
        text = text.replacingOccurrences(of: "[Request interrupted by user for tool use]", with: "")
        text = text.replacingOccurrences(of: "[Request interrupted by user]", with: "")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if text.hasPrefix("!") { return nil }  // shell escape
        if text.hasPrefix("/") {
            let cmd = String(text.split(whereSeparator: { $0 == " " || $0.isNewline }).first ?? "")
            if plumbingCommands.contains(cmd.lowercased()) { return nil }
        }
        return text
    }

    private static let replyWords: Set<String> = [
        "y", "yes", "yeah", "yep", "yup", "no", "nope", "ok", "okay", "k", "sure", "go", "go ahead", "continue",
        "proceed", "do it", "start", "next", "done", "thanks", "thank you", "thx", "lgtm", "approve", "approved",
        "agree", "agreed", "fine", "good", "great", "perfect", "nice", "cool", "both", "all", "all of them",
        "keep going", "go on", "carry on", "ship it", "merge", "commit", "push", "retry", "try again", "again",
        "да", "нет", "ок", "окей", "давай", "продолжай", "продолжи", "согласен", "хорошо", "отлично", "го",
        "делай", "сделай", "запускай", "спасибо", "ага", "угу", "верно", "правильно", "вперед", "вперёд", "дальше",
        "супер", "класс", "норм", "можно", "начинай", "поехали", "оба", "все", "всё",
    ]

    private static let replyPrefixes = [
        "yes ", "yes,", "yeah ", "ok ", "ok,", "okay ", "okay,", "no ", "no,", "sure ", "go ahead", "do it",
        "let's go", "lets go", "continue ", "proceed ", "option ", "да ", "да,", "нет ", "нет,", "давай ", "давай,",
        "ок ", "ок,", "хорошо ", "хорошо,", "продолжай", "согласен", "вариант ",
    ]

    /// True when a turn answers Claude rather than asking for new work.
    static func isFollowUp(_ text: String, claudeAsked: Bool) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        if t.count <= 3 { return true }
        if replyWords.contains(t) { return true }
        if t.allSatisfy({ $0.isNumber || $0 == "," || $0 == " " || $0 == "." }) { return true }
        let firstLine = !text.contains("\n")
        // Mid-session one-liners this short are nearly always steering, not a new request.
        if firstLine && t.count < 40 { return true }
        if firstLine && t.count < 70 && replyPrefixes.contains(where: { t.hasPrefix($0) }) { return true }
        if claudeAsked && firstLine && t.count < 60 { return true }
        return false
    }

    /// Greetings and tests that should never become a ticket on their own.
    static func isTrivial(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return t.count < 3 || [
            "hi", "hello", "hey", "test", "ping", "привет", "тест", "yo", "sup", "exit", "clear", "quit", "mcp",
            "where", "help", "status", "resume", "login", "logout",
        ].contains(t)
    }

    /// Removes the desktop app's `<pasted_content>` wrappers, keeping what the user typed first.
    static func titleSource(_ text: String) -> String {
        guard text.contains("<pasted_content") else { return text }
        var outside = ""
        var inside = ""
        var depth = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("<pasted_content") { depth += 1; continue }
            if l.hasPrefix("</pasted_content") { depth = max(0, depth - 1); continue }
            if depth > 0 { if inside.isEmpty && !l.isEmpty { inside = l } } else if !l.isEmpty { outside += l + "\n" }
        }
        if !outside.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return outside }
        return inside.isEmpty ? "Pasted content" : "Pasted: " + inside
    }

    /// One-line title from a prompt.
    static func title(from raw: String, limit: Int = 96) -> String {
        let text = titleSource(raw)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        var line = lines.first(where: { l in
            !l.isEmpty && !l.hasPrefix("[Image") && !l.hasPrefix("[Pasted text") && l != "```" && !l.hasPrefix("[1 image")
                && !l.hasSuffix("images attached]")
        }) ?? (lines.first.map { $0.hasPrefix("[") ? "Screenshot / image" : $0 } ?? text)
        for ch in ["#", "*", "`", ">", "_"] where line.hasPrefix(ch) {
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*`>_ "))
        }
        line = line.replacingOccurrences(of: "**", with: "")
        line = line.replacingOccurrences(of: "\t", with: " ")
        while line.contains("  ") { line = line.replacingOccurrences(of: "  ", with: " ") }
        if line.count <= limit { return line.isEmpty ? "(empty request)" : line }
        let cut = line.prefix(limit)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    static func between(_ s: String, _ a: String, _ b: String) -> String? {
        guard let r1 = s.range(of: a), let r2 = s.range(of: b, range: r1.upperBound..<s.endIndex) else { return nil }
        return String(s[r1.upperBound..<r2.lowerBound])
    }

    static func truncate(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "…"
    }
}
