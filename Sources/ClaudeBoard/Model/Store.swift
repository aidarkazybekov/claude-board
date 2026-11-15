import AppKit
import Foundation
import Observation

enum SidebarItem: Hashable {
    case inbox, active, backlog, all
    case workspace(String)
    case project(String)
}

enum ViewMode: String, CaseIterable, Identifiable {
    case plan, board, list, worklog, insights
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plan: return "Plan"
        case .board: return "Board"
        case .list: return "List"
        case .worklog: return "Worklog"
        case .insights: return "Insights"
        }
    }
    var symbol: String {
        switch self {
        case .plan: return "checklist"
        case .board: return "rectangle.split.3x1"
        case .list: return "list.bullet.rectangle"
        case .worklog: return "calendar.day.timeline.left"
        case .insights: return "chart.bar.xaxis"
        }
    }
}

/// Which tickets to show: everything, only what you planned, or only Claude's logged work.
enum SourceFilter: String, CaseIterable, Identifiable {
    case all, planned, claude
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "Everything"
        case .planned: return "My tasks"
        case .claude: return "Claude sessions"
        }
    }
    func accepts(_ t: TaskItem) -> Bool {
        switch self {
        case .all: return true
        case .planned: return t.origin.isPlanned
        case .claude: return !t.origin.isPlanned
        }
    }
}

enum Period: Int, CaseIterable, Identifiable {
    case day = 1, week = 7, twoWeeks = 14, month = 30, quarter = 90, all = 0
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .day: return "Today"
        case .week: return "7 days"
        case .twoWeeks: return "14 days"
        case .month: return "30 days"
        case .quarter: return "90 days"
        case .all: return "All time"
        }
    }
    var since: Date? {
        if self == .all { return nil }
        if self == .day { return Calendar.current.startOfDay(for: Date()) }
        return Date().addingTimeInterval(-Double(rawValue) * 86_400)
    }
}

/// Where a new task is saved.
enum TaskDestination: Hashable {
    case local
    case folder(String)
}

@Observable
@MainActor
final class Store {
    // Data
    private(set) var items: [TaskItem] = []
    private(set) var projects: [String: ProjectInfo] = [:]
    private(set) var sessions: [String: SessionInfo] = [:]
    private(set) var taskFolders: [String] = []
    private(set) var repos: [String] = []
    private var fileTasks: [TaskItem] = []
    private var ingested = IngestedStore()
    private var user = UserStore()
    private var mentionLinks: [String: String] = [:]   // Claude ticket id → planned task id

    // UI state
    var sidebar: SidebarItem? = .all
    var scope: SidebarItem { sidebar ?? .all }
    var mode: ViewMode = .board
    var period: Period = .month
    var source: SourceFilter = .all
    var search = ""
    var showHidden = false
    var selection: String?
    var showInspector = true
    var showNewTask = false
    var newTaskProject: String?
    var showOnboarding = false
    var lastQuickAddProject: String?
    var errorMessage: String?
    var showGuide = false
    var showShareWeek = false

    // Status
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var lastIngestInfo = ""
    private(set) var loadError: String?

    @ObservationIgnored private let ingestor = Ingestor()
    @ObservationIgnored private let queue = DispatchQueue(label: "claudeboard.ingest", qos: .utility)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var saveUserWork: DispatchWorkItem?
    @ObservationIgnored private var localWrites: [String: Date] = [:]
    @ObservationIgnored private var pendingRefresh = false

    init() {
        load()
        rebuild()
        if Demo.isOn { Demo.seed(self) }
        if !UserDefaults.standard.bool(forKey: "onboarded") && ProcessInfo.processInfo.environment["CLAUDEBOARD_DATA_DIR"] == nil
            && !CommandLine.arguments.contains("--snapshot")
        {
            showOnboarding = true
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        refresh()
        let interval = max(5, UserDefaults.standard.double(forKey: "refreshSeconds").nonZero ?? 20)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(rediscover: Bool = false) {
        Self.debugLog("refresh requested (busy=\(isRefreshing))")
        if isRefreshing { pendingRefresh = true; return }
        isRefreshing = true
        let ingestor = self.ingestor
        ingestor.extraFolders = user.extraFolders ?? []
        ingestor.ignoredFolders = user.ignoredFolders ?? []
        if rediscover { ingestor.forceDiscovery = true }
        queue.async {
            let result = ingestor.run()
            DispatchQueue.main.async {
                self.merge(result)
                self.isRefreshing = false
                self.lastRefresh = Date()
                if self.pendingRefresh {
                    self.pendingRefresh = false
                    self.refresh()
                }
            }
        }
    }

    // MARK: - Persistence

    private var ingestedURL: URL { Paths.appSupport.appendingPathComponent("ingested.json") }
    private var userURL: URL { Paths.appSupport.appendingPathComponent("user.json") }

    private func load() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        if let d = try? Data(contentsOf: ingestedURL) {
            do { ingested = try dec.decode(IngestedStore.self, from: d) } catch { loadError = "ingested.json: \(error)" }
        }
        if let d = try? Data(contentsOf: userURL) {
            do { user = try dec.decode(UserStore.self, from: d) } catch {
                loadError = "user.json could not be read; a backup was kept."
                try? d.write(to: Paths.appSupport.appendingPathComponent("user.backup-\(Int(Date().timeIntervalSince1970)).json"))
            }
        }
    }

    private func saveIngested() {
        let snapshot = ingested
        let url = ingestedURL
        queue.async {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .secondsSince1970
            if let d = try? enc.encode(snapshot) { try? d.write(to: url, options: .atomic) }
        }
    }

    private func saveUser() {
        saveUserWork?.cancel()
        let snapshot = user
        let url = userURL
        let work = DispatchWorkItem {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .secondsSince1970
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let d = try? enc.encode(snapshot) { try? d.write(to: url, options: .atomic) }
        }
        saveUserWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: - Merge

    func merge(_ r: IngestResult) {
        var tasks = Dictionary(uniqueKeysWithValues: ingested.tasks.map { ($0.id, $0) })

        // Sessions whose transcript exists are fully re-derived from it.
        tasks = tasks.filter { !r.transcriptSessionIDs.contains($0.value.sessionID ?? "") }
        for t in r.transcriptTasks { tasks[t.id] = t }

        // Sessions only in prompt history; skip ones we captured from a transcript before it was cleaned up.
        let captured = Set(tasks.values.filter { $0.origin == .prompt }.compactMap(\.sessionID))
        for (sid, hts) in r.historyTasks where !captured.contains(sid) {
            tasks = tasks.filter { !($0.value.sessionID == sid && $0.value.origin == .history) }
            for t in hts { tasks[t.id] = t }
        }

        // Sessions
        var sess = Dictionary(uniqueKeysWithValues: ingested.sessions.map { ($0.id, $0) })
        for k in sess.keys {
            sess[k]?.isLive = false
            sess[k]?.liveStatus = nil
        }
        for s in r.sessions { sess[s.id] = s }
        for (sid, live) in r.live where sess[sid] != nil {
            sess[sid]?.isLive = true
            sess[sid]?.liveStatus = live.status
        }

        // Re-resolve projects now that repos are known (cwd inside a repo → that repo).
        if !r.repos.isEmpty {
            for (k, t) in tasks where t.cwd != nil {
                let p = ProjectResolver.projectID(for: t.cwd)
                if p != t.projectID { tasks[k]?.projectID = p }
            }
            for (k, s) in sess where !s.cwd.isEmpty {
                sess[k]?.projectID = ProjectResolver.projectID(for: s.cwd)
            }
        }

        // Status inference per session
        var bySession = Dictionary(grouping: tasks.values, by: { $0.sessionID ?? "" })
        for (sid, var group) in bySession {
            Ingestor.inferStatuses(&group, session: sess[sid])
            bySession[sid] = group
        }
        var merged = bySession.values.flatMap { $0 }

        // Stable ticket numbers per project; a ticket that changes project gets a fresh number there.
        merged.sort { $0.createdAt < $1.createdAt }
        var numberProjects = ingested.numberProjects ?? [:]
        for i in merged.indices {
            let id = merged[i].id
            if let n = ingested.numbers[id], (numberProjects[id] ?? merged[i].projectID) == merged[i].projectID {
                merged[i].number = n
                numberProjects[id] = merged[i].projectID
            } else {
                let n = nextNumber(merged[i].projectID)
                ingested.numbers[id] = n
                numberProjects[id] = merged[i].projectID
                merged[i].number = n
            }
        }
        ingested.numberProjects = numberProjects
        ingested.tasks = merged
        ingested.sessions = Array(sess.values)
        sessions = sess
        repos = r.repos.isEmpty ? repos : r.repos
        if !r.taskFolders.isEmpty || r.dataChanged { taskFolders = r.taskFolders }

        // Backlog files: keep the in-memory copy of files this app wrote after the run started.
        let fresh = r.plannedTasks.filter { t in
            guard let p = t.filePath, let w = localWrites[p] else { return true }
            return w < r.startedAt
        }
        let keptLocal = fileTasks.filter { t in
            guard let p = t.filePath, let w = localWrites[p] else { return false }
            return w >= r.startedAt
        }
        fileTasks = fresh + keptLocal.filter { k in !fresh.contains { $0.id == k.id } }
        localWrites = localWrites.filter { $0.value >= r.startedAt }

        lastIngestInfo = (Demo.isOn ? "Demo data · " : "")
            + String(format: "%d tickets · %d sessions · %d backlog tasks · %.1fs", merged.count, sess.count, fileTasks.count, r.duration)
        rebuild()
        if r.dataChanged { saveIngested() }
        Self.debugLog("merge: planned=\(r.plannedTasks.count) fileTasks=\(fileTasks.count) items=\(items.count) folders=\(taskFolders.count) changed=\(r.dataChanged) took=\(String(format: "%.2f", r.duration))s")
    }

    /// Diagnostics, only when CLAUDEBOARD_LOG points at a file.
    static func debugLog(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["CLAUDEBOARD_LOG"] else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { FileManager.default.createFile(atPath: path, contents: data) }
    }

    private func nextNumber(_ projectID: String) -> Int {
        let n = (ingested.counters[projectID] ?? 0) + 1
        ingested.counters[projectID] = n
        return n
    }

    // MARK: - Derived data

    private func rebuild() {
        var out: [TaskItem] = []
        out.reserveCapacity(ingested.tasks.count + user.manual.count + fileTasks.count)
        for var t in ingested.tasks {
            let o = user.overrides[t.id]
            t.status = o?.status ?? t.inferredStatus
            t.statusOverridden = o?.status != nil
            t.priority = o?.priority ?? .none
            if let title = o?.title, !title.isEmpty { t.title = title }
            t.notes = o?.notes ?? ""
            t.labels = o?.labels ?? []
            t.due = o?.due
            t.hidden = o?.hidden ?? false
            if let states = o?.subtaskStates {
                for k in t.subtasks.indices { if let s = states[t.subtasks[k].id] { t.subtasks[k].state = s } }
            }
            t.doneAt = t.status == .done ? (o?.statusSetAt ?? t.lastActivity) : nil
            out.append(t)
        }
        for var m in user.manual {
            m.inferredStatus = m.status
            m.doneAt = m.status == .done ? (m.doneAt ?? m.updatedAt) : nil
            out.append(m)
        }
        let knownProjects = Set(out.map(\.projectID)).union(repos)
        for var f in fileTasks {
            f.projectID = projectForFileTask(f, known: knownProjects)
            f.hidden = user.overrides[f.id]?.hidden ?? false
            out.append(f)
        }

        // Links between planned tasks and the Claude tickets that worked on them.
        linkPlanned(&out)

        // Projects (unique keys)
        var ids = Set(out.map(\.projectID))
        for (id, s) in user.projectSettings where s.hidden != true && s.pinned == true { ids.insert(id) }
        if UserDefaults.standard.bool(forKey: "showAllRepos") { ids.formUnion(repos) }
        var infos: [String: ProjectInfo] = [:]
        var usedKeys: [String: Int] = [:]
        for id in ids.sorted() {
            var info = ProjectResolver.info(for: id, settings: user.projectSettings[id])
            let base = info.key
            let n = usedKeys[base, default: 0]
            usedKeys[base] = n + 1
            if n > 0 && user.projectSettings[id]?.key == nil { info.key = base + String(n + 1) }
            infos[id] = info
        }
        projects = infos
        items = out.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Which project a backlog file belongs to: explicit `project:` field, else the first app
    /// named in owner-session/title/area, else the folder's own project.
    private func projectForFileTask(_ t: TaskItem, known: Set<String>) -> String {
        guard let folder = t.folder else { return ProjectResolver.otherID }
        let parent = (folder as NSString).deletingLastPathComponent
        let home = ProjectResolver.projectID(for: parent)
        let candidates = known.filter { $0.hasPrefix(parent + "/") && $0 != folder }

        if let hint = t.projectHint?.trimmingCharacters(in: .whitespaces), !hint.isEmpty {
            let asPath = (parent + "/" + hint as NSString).standardizingPath
            if candidates.contains(asPath) || known.contains(asPath) { return asPath }
        }
        func names(_ id: String) -> [String] {
            var n = [(id as NSString).lastPathComponent.lowercased()]
            if let custom = user.projectSettings[id]?.name { n.append(custom.lowercased()) }
            n.append(contentsOf: (user.projectSettings[id]?.aliases ?? []).map { $0.lowercased() })
            return n.filter { $0.count >= 2 }
        }
        let texts = [t.projectHint, t.title, t.area].compactMap { $0?.lowercased() }
        for text in texts {
            var best: (pos: Int, len: Int, id: String)?
            for id in candidates {
                for name in names(id) {
                    guard let pos = Self.wordPosition(of: name, in: text) else { continue }
                    if best == nil || pos < best!.pos || (pos == best!.pos && name.count > best!.len) {
                        best = (pos, name.count, id)
                    }
                }
            }
            if let best { return best.id }
        }
        if let repo = ProjectRegistry.shared.repo(containing: folder) { return repo }
        return home
    }

    /// Position of `word` in `text` when it stands alone (not part of `my-data-prod` or `database`).
    static func wordPosition(of word: String, in text: String) -> Int? {
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: word, range: search) {
            func wordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "-" || c == "_" }
            let before: Character = r.lowerBound == text.startIndex ? " " : text[text.index(before: r.lowerBound)]
            let after: Character = r.upperBound == text.endIndex ? " " : text[r.upperBound]
            // "billing." at a sentence end counts; "deploy.sh" style suffixes do not.
            var afterOK = !wordChar(after) && after != "."
            if after == "." {
                let next = text.index(after: r.upperBound)
                afterOK = next == text.endIndex || !(text[next].isLetter || text[next].isNumber)
            }
            if !wordChar(before) && before != "." && afterOK { return text.distance(from: text.startIndex, to: r.lowerBound) }
            search = r.upperBound..<text.endIndex
        }
        return nil
    }

    private static let keyRegex = try! NSRegularExpression(pattern: #"\b[A-Za-z][A-Za-z0-9]{0,9}-\d{1,5}\b"#)

    /// Connects Claude tickets to planned tasks whose key they mention ("do T-015", "[HR-3] …").
    /// A ticket whose prompt starts with the key was launched from ClaudeBoard and is folded
    /// into the planned task instead of showing twice.
    private func linkPlanned(_ out: inout [TaskItem]) {
        var byKey: [String: [Int]] = [:]
        for (i, t) in out.enumerated() where t.origin.isPlanned {
            byKey[plannedKey(t).uppercased(), default: []].append(i)
        }
        guard !byKey.isEmpty else { return }
        var links: [Int: [String]] = [:]
        for i in out.indices where !out[i].origin.isPlanned && out[i].origin != .suggested {
            let t = out[i]
            let text = ([t.prompt] + t.followUps.map(\.text)).joined(separator: "\n")
            let ns = text as NSString
            var target: Int?
            for m in Self.keyRegex.matches(in: text, range: NSRange(location: 0, length: min(ns.length, 4000))) {
                let key = ns.substring(with: m.range).uppercased()
                guard let cands = byKey[key] else { continue }
                if cands.count == 1 {
                    target = cands[0]
                } else {
                    target = cands.first { c in
                        let folderParent = out[c].folder.map { ($0 as NSString).deletingLastPathComponent } ?? out[c].projectID
                        return t.projectID == out[c].projectID || t.projectID.hasPrefix(folderParent)
                    }
                }
                if target != nil { break }
            }
            guard let target else { continue }
            out[i].plannedLink = out[target].id
            links[target, default: []].append(out[i].id)
            let head = t.prompt.prefix(80).uppercased()
            let key = plannedKey(out[target]).uppercased()
            if head.hasPrefix("[\(key)]") || head.hasPrefix("WORK ON \(key)") { out[i].hidden = true }
        }
        for (i, ids) in links { out[i].claudeLinks = ids }
    }

    private func plannedKey(_ t: TaskItem) -> String {
        if let e = t.externalID { return e }
        return "\(project(t.projectID).key)-\(t.number)"
    }

    // MARK: - Queries

    func project(_ id: String) -> ProjectInfo {
        projects[id] ?? ProjectResolver.info(for: id, settings: user.projectSettings[id])
    }

    func key(for t: TaskItem) -> String {
        if let e = t.externalID { return e }
        return "\(project(t.projectID).key)-\(t.number)"
    }

    func task(_ id: String?) -> TaskItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    func session(_ id: String?) -> SessionInfo? {
        guard let id else { return nil }
        return sessions[id]
    }

    func linkedClaudeTickets(_ t: TaskItem) -> [TaskItem] {
        let ids = Set(t.claudeLinks ?? [])
        return items.filter { ids.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Live state of the Claude work attached to a planned task.
    func claudeActivity(_ t: TaskItem) -> (busy: Bool, live: Bool, needsYou: Bool, count: Int) {
        let linked = linkedClaudeTickets(t)
        var busy = false, live = false, needs = false
        for l in linked {
            if let s = sessions[l.sessionID ?? ""], s.isLive, latestTask(inSession: s.id)?.id == l.id {
                live = true
                if s.isBusy { busy = true }
            }
            if l.status == .needsYou { needs = true }
        }
        return (busy, live, needs, linked.count)
    }

    var workspaces: [(name: String, projects: [ProjectInfo])] {
        let visible = projects.values.filter { user.projectSettings[$0.id]?.hidden != true }
        let grouped = Dictionary(grouping: visible, by: \.workspace)
        let activity = workspaceActivity()
        return grouped.map { (name: $0.key, projects: $0.value.sorted { a, b in
            if a.relativePath.count != b.relativePath.count { return a.relativePath.count < b.relativePath.count }
            return a.name < b.name
        }) }
        .sorted { a, b in
            if a.name == "Other" { return false }
            if b.name == "Other" { return true }
            return (activity[a.name] ?? .distantPast) > (activity[b.name] ?? .distantPast)
        }
    }

    private func workspaceActivity() -> [String: Date] {
        var out: [String: Date] = [:]
        for t in items {
            let w = project(t.projectID).workspace
            if out[w] == nil { out[w] = t.lastActivity }
        }
        return out
    }

    private func inScope(_ t: TaskItem, _ item: SidebarItem) -> Bool {
        switch item {
        case .inbox: return t.status == .needsYou
        case .active: return t.status == .inProgress
        case .backlog: return t.status == .backlog || t.status == .todo
        case .all: return true
        case .workspace(let w): return project(t.projectID).workspace == w
        case .project(let p): return t.projectID == p
        }
    }

    /// Tickets in the current sidebar scope, after source, search and hidden filters (period not applied).
    var scoped: [TaskItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { t in
            if t.hidden && !showHidden { return false }
            if user.projectSettings[t.projectID]?.hidden == true { return false }
            if !source.accepts(t) { return false }
            if !inScope(t, scope) { return false }
            if q.isEmpty { return true }
            if t.title.lowercased().contains(q) { return true }
            if key(for: t).lowercased().hasPrefix(q) { return true }
            if t.labels.contains(where: { $0.lowercased().contains(q) }) { return true }
            if (t.area ?? "").lowercased().contains(q) { return true }
            if t.notes.lowercased().contains(q) { return true }
            if t.prompt.lowercased().contains(q) { return true }
            if let s = sessions[t.sessionID ?? ""], s.title.lowercased().contains(q) { return true }
            return false
        }
    }

    /// Scoped tickets inside the selected period. Open tickets always stay visible.
    var periodScoped: [TaskItem] {
        guard let since = period.since else { return scoped }
        return scoped.filter { $0.status.isOpen || $0.lastActivity >= since }
    }

    func count(_ item: SidebarItem) -> Int {
        items.lazy.filter { t in
            guard !t.hidden, self.user.projectSettings[t.projectID]?.hidden != true, self.source.accepts(t) else { return false }
            switch item {
            case .inbox, .active, .backlog: return self.inScope(t, item)
            default: return t.status.isOpen && self.inScope(t, item)
            }
        }.count
    }

    /// Open tasks you planned for a project (what the sidebar shows next to it).
    func plannedOpenCount(_ projectID: String) -> Int {
        items.lazy.filter { $0.projectID == projectID && $0.origin.isPlanned && $0.status.isOpen && !$0.hidden }.count
    }

    var liveSessions: [SessionInfo] {
        sessions.values.filter(\.isLive).sorted { $0.lastActivity > $1.lastActivity }
    }

    func latestTask(inSession sid: String) -> TaskItem? {
        items.first { $0.sessionID == sid && $0.origin != .suggested && !$0.origin.isPlanned }
    }

    var scopeTitle: String {
        switch scope {
        case .inbox: return "Needs You"
        case .active: return "In Progress"
        case .backlog: return "Backlog"
        case .all: return "All Projects"
        case .workspace(let w): return w
        case .project(let p): return project(p).name
        }
    }

    var scopeProjectID: String? {
        if case .project(let p) = sidebar { return p }
        return nil
    }

    /// Every project a task can be filed under: known ones plus every discovered repo.
    var allProjectChoices: [ProjectInfo] {
        let ids = Set(projects.keys).union(repos).subtracting([ProjectResolver.otherID, ProjectResolver.scratchID])
        return ids.map { projects[$0] ?? ProjectResolver.info(for: $0, settings: user.projectSettings[$0]) }
            .filter { user.projectSettings[$0.id]?.hidden != true }
            .sorted { ($0.workspace, $0.relativePath) < ($1.workspace, $1.relativePath) }
    }

    /// Backlog folders that serve a project: a folder inside it, or one in an ancestor folder.
    func folders(for projectID: String) -> [String] {
        taskFolders.filter { f in
            let parent = (f as NSString).deletingLastPathComponent
            return f.hasPrefix(projectID + "/") || projectID == parent || projectID.hasPrefix(parent + "/")
        }
        .sorted { $0.count > $1.count }
    }

    func defaultDestination(for projectID: String) -> TaskDestination {
        if let f = folders(for: projectID).first { return .folder(f) }
        return .local
    }

    /// Project path relative to a folder's parent, for the `project:` field.
    private func projectField(for projectID: String, folder: String) -> String? {
        let parent = (folder as NSString).deletingLastPathComponent
        if projectID == parent { return nil }
        if projectID.hasPrefix(parent + "/") { return String(projectID.dropFirst(parent.count + 1)) }
        return (projectID as NSString).lastPathComponent
    }

    // MARK: - Edits

    private func isManual(_ id: String) -> Int? { user.manual.firstIndex { $0.id == id } }
    private func fileIndex(_ id: String) -> Int? { fileTasks.firstIndex { $0.id == id } }

    private func folderUsesPStyle(_ folder: String?) -> Bool {
        guard let folder else { return true }
        let ps = fileTasks.filter { $0.folder == folder }.compactMap { $0.rawPriority }
        return ps.isEmpty || ps.contains { $0.uppercased().hasPrefix("P") }
    }

    private func folderUsesTitleCase(_ folder: String?) -> Bool {
        fileTasks.filter { $0.folder == folder }.contains { ($0.rawStatus ?? "").contains(" ") || ($0.rawStatus ?? "").first?.isUppercase == true }
    }

    /// Applies an edit to a backlog file, then re-reads it so the board matches the file exactly.
    private func editFile(_ id: String, _ write: (TaskItem) throws -> Void) {
        guard let i = fileIndex(id), let path = fileTasks[i].filePath, let folder = fileTasks[i].folder else { return }
        do {
            try write(fileTasks[i])
            localWrites[path] = Date()
            if let f = TaskFolder.parse(path, folder: folder) {
                fileTasks[i] = Ingestor.item(from: f)
            }
        } catch {
            errorMessage = "Could not write \(Paths.tilde(path)): \(error.localizedDescription)"
        }
        rebuild()
    }

    private func edit(_ id: String, manual: (inout TaskItem) -> Void, override: (inout TaskOverride) -> Void) {
        if let i = isManual(id) {
            manual(&user.manual[i])
            user.manual[i].updatedAt = Date()
        } else {
            var o = user.overrides[id] ?? TaskOverride()
            override(&o)
            user.overrides[id] = o.isEmpty ? nil : o
        }
        rebuild()
        saveUser()
    }

    func setStatus(_ id: String, _ status: TaskStatus) {
        if fileIndex(id) != nil {
            editFile(id) { t in
                let raw = TaskFolder.raw(for: status, current: t.rawStatus, titleCase: folderUsesTitleCase(t.folder))
                try TaskFolder.updateFields(t.filePath!, [("status", raw)])
                TaskFolder.updateIndexRow(folder: t.folder!, id: t.externalID!, status: raw)
            }
            return
        }
        let inferred = items.first { $0.id == id }?.inferredStatus
        edit(id, manual: {
            $0.status = status
            $0.doneAt = status == .done ? Date() : nil
        }, override: {
            // Moving a ticket back to what the transcript says clears the override.
            if status == inferred { $0.status = nil; $0.statusSetAt = nil } else { $0.status = status; $0.statusSetAt = Date() }
        })
    }

    func clearStatusOverride(_ id: String) {
        edit(id, manual: { _ in }, override: { $0.status = nil; $0.statusSetAt = nil })
    }

    func setPriority(_ id: String, _ p: Priority) {
        if fileIndex(id) != nil {
            editFile(id) { t in
                let raw = TaskFolder.raw(for: p, pStyle: folderUsesPStyle(t.folder))
                try TaskFolder.updateFields(t.filePath!, [("priority", raw)])
                TaskFolder.updateIndexRow(folder: t.folder!, id: t.externalID!, priority: raw ?? "")
            }
            return
        }
        edit(id, manual: { $0.priority = p }, override: { $0.priority = p == .none ? nil : p })
    }

    func setTitle(_ id: String, _ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if fileIndex(id) != nil {
            guard !trimmed.isEmpty else { return }
            editFile(id) { t in
                try TaskFolder.updateFields(t.filePath!, [("title", trimmed)])
                TaskFolder.updateIndexRow(folder: t.folder!, id: t.externalID!, title: trimmed)
            }
            return
        }
        edit(id, manual: { if !trimmed.isEmpty { $0.title = trimmed } }, override: { $0.title = trimmed.isEmpty ? nil : trimmed })
    }

    func setNotes(_ id: String, _ notes: String) {
        if fileIndex(id) != nil {
            editFile(id) { t in try TaskFolder.setBody(t.filePath!, notes) }
            return
        }
        edit(id, manual: { $0.notes = notes }, override: { $0.notes = notes.isEmpty ? nil : notes })
    }

    func setLabels(_ id: String, _ raw: String) {
        let labels = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if fileIndex(id) != nil {
            editFile(id) { t in
                try TaskFolder.updateFields(t.filePath!, [("labels", labels.isEmpty ? nil : "[" + labels.joined(separator: ", ") + "]")])
            }
            return
        }
        edit(id, manual: { $0.labels = labels }, override: { $0.labels = labels.isEmpty ? nil : labels })
    }

    func setArea(_ id: String, _ area: String) {
        let a = area.trimmingCharacters(in: .whitespaces)
        if fileIndex(id) != nil {
            editFile(id) { t in try TaskFolder.updateFields(t.filePath!, [("area", a.isEmpty ? nil : a)]) }
        } else if let i = isManual(id) {
            user.manual[i].area = a.isEmpty ? nil : a
            rebuild(); saveUser()
        }
    }

    func setDue(_ id: String, _ due: Date?) {
        if fileIndex(id) != nil {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            editFile(id) { t in try TaskFolder.updateFields(t.filePath!, [("due", due.map(df.string(from:)))]) }
            return
        }
        edit(id, manual: { $0.due = due }, override: { $0.due = due })
    }

    func setProject(_ id: String, _ projectID: String) {
        if fileIndex(id) != nil {
            editFile(id) { t in
                try TaskFolder.updateFields(t.filePath!, [("project", projectField(for: projectID, folder: t.folder!))])
            }
            return
        }
        guard let i = isManual(id), user.manual[i].projectID != projectID else { return }
        user.manual[i].projectID = projectID
        user.manual[i].number = nextNumber(projectID)
        user.manual[i].cwd = projectID.hasPrefix("/") ? projectID : nil
        rebuild(); saveUser(); saveIngested()
    }

    func setHidden(_ id: String, _ hidden: Bool) {
        if fileIndex(id) != nil {
            var o = user.overrides[id] ?? TaskOverride()
            o.hidden = hidden ? true : nil
            user.overrides[id] = o.isEmpty ? nil : o
            rebuild(); saveUser()
        } else {
            edit(id, manual: { $0.hidden = hidden }, override: { $0.hidden = hidden ? true : nil })
        }
        if hidden && !showHidden && selection == id { selection = nil }
    }

    func toggleSubtask(_ id: String, _ subID: String) {
        guard let t = task(id), let sub = t.subtasks.first(where: { $0.id == subID }) else { return }
        let next: SubtaskState = sub.state == .completed ? .pending : .completed
        if fileIndex(id) != nil, subID.hasPrefix("cl-"), let line = Int(subID.dropFirst(3)) {
            editFile(id) { t in try TaskFolder.setChecklist(t.filePath!, bodyLine: line, done: next == .completed) }
            return
        }
        edit(id, manual: { m in
            if let k = m.subtasks.firstIndex(where: { $0.id == subID }) { m.subtasks[k].state = next }
        }, override: { o in
            var s = o.subtaskStates ?? [:]
            s[subID] = next
            o.subtaskStates = s
        })
    }

    func addSubtask(_ id: String, _ title: String) {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let fi = fileIndex(id) {
            let body = fileTasks[fi].notes
            var lines = body.components(separatedBy: "\n")
            let lastCheck = lines.lastIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- [") }
            if let lastCheck {
                lines.insert("- [ ] \(text)", at: lastCheck + 1)
            } else {
                while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
                lines.append(contentsOf: ["", "## Done when", "", "- [ ] \(text)", ""])
            }
            editFile(id) { t in try TaskFolder.setBody(t.filePath!, lines.joined(separator: "\n")) }
            return
        }
        guard let i = isManual(id) else { return }
        user.manual[i].subtasks.append(Subtask(id: "m-\(UUID().uuidString.prefix(8))", title: text, state: .pending))
        rebuild()
        saveUser()
    }

    func removeSubtask(_ id: String, _ subID: String) {
        if fileIndex(id) != nil, subID.hasPrefix("cl-"), let line = Int(subID.dropFirst(3)), let t = task(id) {
            var lines = t.notes.components(separatedBy: "\n")
            guard lines.indices.contains(line) else { return }
            lines.remove(at: line)
            editFile(id) { t in try TaskFolder.setBody(t.filePath!, lines.joined(separator: "\n")) }
            return
        }
        guard let i = isManual(id) else { return }
        user.manual[i].subtasks.removeAll { $0.id == subID }
        rebuild()
        saveUser()
    }

    @discardableResult
    func createTask(title: String, projectID: String, notes: String, priority: Priority, status: TaskStatus,
                    labels: [String] = [], subtasks: [String] = [], area: String? = nil,
                    destination: TaskDestination? = nil) -> TaskItem?
    {
        let dest = destination ?? defaultDestination(for: projectID)
        lastQuickAddProject = projectID
        if case .folder(let folder) = dest {
            do {
                let path = try TaskFolder.create(in: folder, title: title, status: status, priority: priority, area: area,
                                                 project: projectField(for: projectID, folder: folder),
                                                 labels: labels, notes: notes, checklist: subtasks)
                localWrites[path] = Date()
                if let f = TaskFolder.parse(path, folder: folder) {
                    let item = Ingestor.item(from: f)
                    fileTasks.append(item)
                    rebuild()
                    selection = item.id
                    return task(item.id)
                }
            } catch {
                errorMessage = "Could not create the task file in \(Paths.tilde(folder)): \(error.localizedDescription)"
            }
            return nil
        }
        let now = Date()
        var t = TaskItem(
            id: "manual:\(UUID().uuidString)", origin: .manual, projectID: projectID, sessionID: nil,
            title: title, prompt: notes.isEmpty ? title : "\(title)\n\n\(notes)",
            createdAt: now, updatedAt: now, inferredStatus: status, cwd: projectID.hasPrefix("/") ? projectID : nil
        )
        t.number = nextNumber(projectID)
        t.status = status
        t.priority = priority
        t.notes = notes
        t.labels = labels
        t.area = area
        t.subtasks = subtasks.enumerated().map { Subtask(id: "m-\($0.offset)", title: $0.element, state: .pending) }
        user.manual.append(t)
        rebuild()
        saveUser()
        saveIngested()
        selection = t.id
        return t
    }

    func deleteManual(_ id: String) {
        user.manual.removeAll { $0.id == id }
        if selection == id { selection = nil }
        rebuild()
        saveUser()
    }

    /// Creates `<project>/backlog/` and moves the project's local tasks into it as files.
    func createBacklogFolder(for projectID: String) {
        guard projectID.hasPrefix("/") else { return }
        do {
            let folder = try TaskFolder.scaffold(in: projectID, projectName: project(projectID).name)
            let locals = user.manual.filter { $0.projectID == projectID }
            for m in locals {
                let path = try TaskFolder.create(in: folder, title: m.title, status: m.status, priority: m.priority,
                                                 area: m.area, project: nil, labels: m.labels, notes: m.notes,
                                                 checklist: m.subtasks.map(\.title))
                // keep checked steps checked
                if let f = TaskFolder.parse(path, folder: folder) {
                    for (k, s) in TaskFolder.checklist(f.body).enumerated() where k < m.subtasks.count && m.subtasks[k].state == .completed {
                        try? TaskFolder.setChecklist(path, bodyLine: Int(s.id.dropFirst(3))!, done: true)
                    }
                }
                localWrites[path] = Date()
                if let f = TaskFolder.parse(path, folder: folder) { fileTasks.append(Ingestor.item(from: f)) }
            }
            user.manual.removeAll { $0.projectID == projectID }
            var extra = user.extraFolders ?? []
            if !extra.contains(folder) { extra.append(folder) }
            user.extraFolders = extra
            saveUser()
            taskFolders = Array(Set(taskFolders + [folder])).sorted()
            rebuild()
            refresh(rediscover: true)
        } catch {
            errorMessage = "Could not create the backlog folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Folders & roots

    func addFolder(_ path: String) {
        var extra = user.extraFolders ?? []
        if !extra.contains(path) { extra.append(path) }
        user.extraFolders = extra
        user.ignoredFolders?.removeAll { $0 == path }
        saveUser()
        refresh(rediscover: true)
    }

    func ignoreFolder(_ path: String) {
        user.extraFolders?.removeAll { $0 == path }
        var ign = user.ignoredFolders ?? []
        if !ign.contains(path) { ign.append(path) }
        user.ignoredFolders = ign
        fileTasks.removeAll { $0.folder == path }
        taskFolders.removeAll { $0 == path }
        saveUser()
        rebuild()
    }

    func setRoots(_ roots: [String]) {
        Roots.all = roots
        refresh(rediscover: true)
    }

    // MARK: - Project settings

    func projectSettings(_ id: String) -> ProjectSettings { user.projectSettings[id] ?? ProjectSettings() }

    func updateProject(_ id: String, _ change: (inout ProjectSettings) -> Void) {
        var s = user.projectSettings[id] ?? ProjectSettings()
        change(&s)
        user.projectSettings[id] = s
        rebuild()
        saveUser()
    }

    var hiddenProjects: [ProjectInfo] {
        user.projectSettings.filter { $0.value.hidden == true }.map { project($0.key) }
    }

    // MARK: - Actions

    func startWithClaude(_ id: String) {
        guard let t = task(id) else { return }
        let dir: String = {
            if t.projectID.hasPrefix("/"), FileManager.default.fileExists(atPath: t.projectID) { return t.projectID }
            if let f = t.folder { return (f as NSString).deletingLastPathComponent }
            return t.cwd ?? Roots.primary
        }()
        let key = key(for: t)
        var prompt: String
        if let path = t.filePath {
            let rel = path.hasPrefix(dir + "/") ? String(path.dropFirst(dir.count + 1)) : path
            prompt = "Work on \(key): \(t.title)\n\nThe task is written up in \(rel). Read it first. "
                + "When you finish, update its `status:` front matter (and its row in the backlog index if there is one)."
        } else {
            prompt = "[\(key)] \(t.title)"
            if !t.notes.isEmpty { prompt += "\n\n" + t.notes }
            let open = t.subtasks.filter { $0.state != .completed }.map { "- " + $0.title }
            if !open.isEmpty { prompt += "\n\nChecklist:\n" + open.joined(separator: "\n") }
        }
        Launcher.startClaude(in: dir, prompt: prompt)
        if t.origin.isPlanned && t.status != .inProgress { setStatus(id, .inProgress) }
    }

    func resume(_ id: String) {
        guard let t = task(id), let sid = t.sessionID else { return }
        let dir = sessions[sid]?.cwd ?? t.cwd ?? Roots.primary
        Launcher.resumeClaude(sessionID: sid, in: dir)
    }

    func revealTranscript(_ id: String) {
        guard let t = task(id), let path = sessions[t.sessionID ?? ""]?.transcriptPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFile(_ id: String) {
        guard let p = task(id)?.filePath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    }

    func revealFile(_ id: String) {
        guard let p = task(id)?.filePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
    }

    func openFolder(_ id: String) {
        guard let t = task(id) else { return }
        let dir = t.cwd ?? t.projectID
        if FileManager.default.fileExists(atPath: dir) { NSWorkspace.shared.open(URL(fileURLWithPath: dir)) }
    }

    func copyPrompt(_ id: String) {
        guard let t = task(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(t.prompt, forType: .string)
    }

    func copyKey(_ id: String) {
        guard let t = task(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(key(for: t)) \(t.title)", forType: .string)
    }

    /// Markdown list of a project's open planned tasks, ready to paste into a Claude session.
    func copyPlanForClaude(_ projectID: String) {
        let open = items.filter { $0.projectID == projectID && $0.origin.isPlanned && $0.status.isOpen && !$0.hidden }
            .sorted { ($0.priority.rawValue, $1.createdAt) > ($1.priority.rawValue, $0.createdAt) }
        var lines = ["Open tasks for \(project(projectID).name):", ""]
        for t in open {
            var l = "- [\(key(for: t))] \(t.title) (\(t.status.title.lowercased())"
            if t.priority != .none { l += ", \(t.priority.title.lowercased()) priority" }
            l += ")"
            if let p = t.filePath { l += " — \(Paths.tilde(p))" }
            lines.append(l)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
