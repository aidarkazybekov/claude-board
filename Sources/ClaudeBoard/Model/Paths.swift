import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Overridable so the demo (and tests) never read the real Claude Code data.
    static var claudeDir: String { ProcessInfo.processInfo.environment["CLAUDEBOARD_CLAUDE_DIR"] ?? home + "/.claude" }
    static var projectsDir: String { claudeDir + "/projects" }
    static var historyFile: String { claudeDir + "/history.jsonl" }
    static var liveSessionsDir: String { claudeDir + "/sessions" }
    static var desktopSessionsDir: String {
        ProcessInfo.processInfo.environment["CLAUDEBOARD_DESKTOP_DIR"] ?? home + "/Library/Application Support/Claude/claude-code-sessions"
    }

    static var appSupport: URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDEBOARD_DATA_DIR"] {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func tilde(_ p: String) -> String {
        if Demo.isOn {
            // Show demo folders as if they were in the home folder: ~/Projects/acme/…
            for b in [Demo.base.path, "/private" + Demo.base.path] where p.hasPrefix(b) {
                return "~" + p.dropFirst(b.count)
            }
        }
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}

/// Where projects live. Works for anyone: roots are detected on first launch and editable in Settings.
enum Roots {
    static let defaultsKey = "projectRoots"

    /// Common places people keep code. The first launch picks the ones that exist.
    static let candidates = ["DEV", "Developer", "Projects", "projects", "code", "Code", "src", "dev", "workspace",
                             "Workspace", "repos", "git", "GitHub", "Documents/GitHub", "Documents/Projects", "Sites"]

    static var all: [String] {
        get {
            if let env = ProcessInfo.processInfo.environment["CLAUDEBOARD_ROOTS"] {
                return env.split(separator: ":").map(String.init)
            }
            if let saved = UserDefaults.standard.stringArray(forKey: defaultsKey), !saved.isEmpty {
                return saved.map { ($0 as NSString).expandingTildeInPath }
            }
            return detect()
        }
        set {
            guard !Demo.isOn else { return }  // the demo must never change the real settings
            UserDefaults.standard.set(newValue.map(Paths.tilde), forKey: defaultsKey)
        }
    }

    static var primary: String { all.first ?? Paths.home }

    /// Existing common folders, plus folders Claude sessions ran in that sit under none of them.
    static func detect() -> [String] {
        var found: [String] = []
        if let legacy = UserDefaults.standard.string(forKey: "devRoot"), !legacy.isEmpty {
            found.append((legacy as NSString).expandingTildeInPath)
        }
        var isDir: ObjCBool = false
        for c in candidates {
            let p = Paths.home + "/" + c
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue,
               !found.contains(where: { $0.lowercased() == p.lowercased() })
            {
                found.append(p)
            }
        }
        return found
    }

    /// The root containing a path, if any.
    static func root(containing path: String) -> String? {
        all.filter { path == $0 || path.hasPrefix($0 + "/") }.max { $0.count < $1.count }
    }
}

/// Snapshot of discovered git repos, shared between the ingest queue and the UI.
final class ProjectRegistry: @unchecked Sendable {
    static let shared = ProjectRegistry()
    private let lock = NSLock()
    private var _repos: [String] = []

    var repos: [String] {
        lock.lock(); defer { lock.unlock() }
        return _repos
    }

    func set(repos: [String]) {
        lock.lock(); _repos = repos.sorted { $0.count > $1.count }; lock.unlock()
    }

    /// Deepest known repo containing the path.
    func repo(containing path: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return _repos.first { path == $0 || path.hasPrefix($0 + "/") }
    }
}

enum ProjectResolver {
    static let scratchID = "@scratch"
    static let otherID = "@other"

    /// Maps a session cwd to the project it belongs to (an absolute path, or a special token).
    static func projectID(for rawCwd: String?) -> String {
        guard var cwd = rawCwd, !cwd.isEmpty else { return otherID }
        cwd = (cwd as NSString).standardizingPath

        // Worktrees belong to their parent repo.
        for marker in ["/.claude/worktrees/", "/.worktrees/", "/.claude-worktrees/"] {
            if let r = cwd.range(of: marker) { cwd = String(cwd[..<r.lowerBound]) }
        }
        if cwd.contains("/Application Support/Claude/scratch-workspaces") { return scratchID }

        // Inside a known repo: that repo is the project.
        if let repo = ProjectRegistry.shared.repo(containing: cwd) { return repo }

        if let root = Roots.root(containing: cwd) {
            if cwd == root { return root }
            let rel = cwd.dropFirst(root.count + 1).split(separator: "/").map(String.init)
            // Cap depth: workspace/group/app is as deep as a project goes.
            let depth = rel.first == "legacy_projects" ? 2 : 3
            return root + "/" + rel.prefix(depth).joined(separator: "/")
        }
        return cwd
    }

    static func info(for id: String, settings: ProjectSettings?) -> ProjectInfo {
        var name: String
        var workspace: String
        var rel: String
        switch id {
        case scratchID:
            name = "Scratch"; workspace = "Other"; rel = "scratch"
        case otherID:
            name = "Unknown folder"; workspace = "Other"; rel = "?"
        default:
            if let root = Roots.root(containing: id) {
                let rootName = (root as NSString).lastPathComponent
                if id == root {
                    rel = "."
                    workspace = rootName
                    name = "\(rootName) (root)"
                } else {
                    rel = String(id.dropFirst(root.count + 1))
                    let parts = rel.split(separator: "/").map(String.init)
                    workspace = parts.first ?? rootName
                    name = parts.last ?? rel
                }
            } else {
                rel = Paths.tilde(id)
                workspace = "Other"
                name = (id as NSString).lastPathComponent
            }
        }
        if let custom = settings?.name, !custom.isEmpty { name = custom }
        let key = settings?.key.flatMap { $0.isEmpty ? nil : $0.uppercased() } ?? defaultKey(for: id, name: name)
        let color = settings?.colorIndex ?? stableColorIndex(id)
        return ProjectInfo(id: id, name: name, workspace: workspace, relativePath: rel, key: key, colorIndex: color)
    }

    static func defaultKey(for id: String, name: String) -> String {
        if id == scratchID { return "SCR" }
        if id == otherID { return "OTH" }
        let base = (id as NSString).lastPathComponent
        let words = base.split(whereSeparator: { "-_ .".contains($0) }).map(String.init).filter { !$0.isEmpty }
        let letters: String
        if words.count >= 2 {
            letters = words.prefix(4).compactMap { $0.first.map(String.init) }.joined()
        } else {
            letters = String(base.filter { $0.isLetter || $0.isNumber }.prefix(3))
        }
        let k = letters.uppercased()
        return k.isEmpty ? "TSK" : k
    }

    static func stableColorIndex(_ s: String) -> Int {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(h % 10)
    }
}

/// Walks the project roots for git repos and backlog folders.
enum Discovery {
    static let skip: Set<String> = [
        "node_modules", ".git", ".build", "build", "dist", "target", "vendor", ".next", ".nuxt", "Pods", "DerivedData",
        ".venv", "venv", "__pycache__", ".terraform", "coverage", ".cache", ".idea", ".vscode", "Library", ".Trash",
    ]
    static let backlogNames: Set<String> = ["backlog", ".backlog", "tasks", "Backlog"]

    struct Result {
        var repos: [String] = []
        var taskFolders: [String] = []
    }

    static func scan(roots: [String], maxDepth: Int = 5) -> Result {
        var out = Result()
        let fm = FileManager.default
        func walk(_ dir: String, _ depth: Int, insideRepo: Bool) {
            guard depth <= maxDepth, let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            let isRepo = names.contains(".git")
            if isRepo { out.repos.append(dir) }
            for n in names {
                let p = dir + "/" + n
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
                if backlogNames.contains(n) {
                    if TaskFolder.isTaskFolder(p) { out.taskFolders.append(p) }
                    continue
                }
                if skip.contains(n) || (n.hasPrefix(".") && n != ".claude") { continue }
                // Inside a repo only look one level for a backlog folder (handled above); don't walk the source tree.
                if isRepo || insideRepo { continue }
                walk(p, depth + 1, insideRepo: false)
            }
        }
        for r in roots { walk(r, 0, insideRepo: false) }
        out.taskFolders = Array(Set(out.taskFolders)).sorted()
        return out
    }
}
