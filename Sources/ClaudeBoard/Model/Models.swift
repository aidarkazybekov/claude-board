import Foundation

// MARK: - Status / priority

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Hashable {
    case backlog, todo, inProgress, needsYou, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .needsYou: return "Needs You"
        case .done: return "Done"
        }
    }

    var symbol: String {
        switch self {
        case .backlog: return "tray"
        case .todo: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .needsYou: return "exclamationmark.bubble.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var isOpen: Bool { self != .done }
}

enum Priority: Int, Codable, CaseIterable, Identifiable, Hashable, Comparable {
    case none = 0, low, medium, high, urgent

    var id: Int { rawValue }
    static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .none: return "No priority"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "minus"
        case .low: return "arrow.down"
        case .medium: return "equal"
        case .high: return "arrow.up"
        case .urgent: return "exclamationmark.2"
        }
    }
}

/// Where a ticket came from.
enum TaskOrigin: String, Codable, Hashable {
    /// A request typed to Claude, read from a full session transcript.
    case prompt
    /// A request recovered from ~/.claude/history.jsonl (transcript already cleaned up).
    case history
    /// A follow-up Claude proposed (start_session "own_initiative").
    case suggested
    /// Created by hand in ClaudeBoard, stored on this Mac.
    case manual
    /// A task file in a backlog folder (shared through the repo).
    case file

    var title: String {
        switch self {
        case .prompt: return "Claude session"
        case .history: return "Prompt history"
        case .suggested: return "Suggested by Claude"
        case .manual: return "Your task · this Mac"
        case .file: return "Your task · backlog file"
        }
    }

    /// Tasks you planned yourself, as opposed to work Claude logged.
    var isPlanned: Bool { self == .manual || self == .file }
}

enum SubtaskState: String, Codable, Hashable {
    case pending, inProgress, completed
}

struct Subtask: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var state: SubtaskState
}

/// A follow-up message the user sent while Claude was on the same ticket.
struct Exchange: Codable, Hashable {
    var at: Date
    var text: String
}

struct WorkStats: Codable, Hashable {
    var toolCalls = 0
    var bashCalls = 0
    var edits = 0
    var agentCalls = 0
    var filesTouched: [String] = []
    var endedAt: Date?
    var replied = false
    /// Time Claude spent actively working (gaps over 5 minutes are not counted).
    var activeSeconds: Double?
}

// MARK: - Ticket

struct TaskItem: Codable, Identifiable, Hashable {
    var id: String
    var origin: TaskOrigin
    var projectID: String
    var sessionID: String?
    var title: String
    var prompt: String
    var followUps: [Exchange] = []
    var subtasks: [Subtask] = []
    /// Short recap (wrap_up) of what was done.
    var recap: String?
    /// Claude's last message on this ticket.
    var finalReply: String?
    /// A question Claude is waiting on.
    var pendingAsk: String?
    var stats = WorkStats()
    var createdAt: Date
    var updatedAt: Date
    var inferredStatus: TaskStatus
    var cwd: String?
    var branch: String?

    // Fields owned by the user (manual tasks store them directly; imported tasks get them from overrides).
    var number: Int = 0
    var status: TaskStatus = .todo
    var statusOverridden = false
    var priority: Priority = .none
    var labels: [String] = []
    var notes: String = ""
    var due: Date?
    var hidden = false
    var doneAt: Date?

    // Backlog-file tasks
    var filePath: String?
    var folder: String?
    var externalID: String?
    var area: String?
    var rawStatus: String?
    var rawPriority: String?
    var projectHint: String?
    /// Claude tickets that worked on this task (mentioned its key, or were started from it).
    var claudeLinks: [String]?
    /// For Claude tickets: the planned task they belong to.
    var plannedLink: String?

    var subtaskProgress: (done: Int, total: Int) {
        (subtasks.filter { $0.state == .completed }.count, subtasks.count)
    }

    var lastActivity: Date { max(updatedAt, stats.endedAt ?? updatedAt) }
}

/// User edits layered on top of an imported ticket.
struct TaskOverride: Codable, Hashable {
    var status: TaskStatus?
    var statusSetAt: Date?
    var priority: Priority?
    var title: String?
    var notes: String?
    var labels: [String]?
    var due: Date?
    var hidden: Bool?
    var subtaskStates: [String: SubtaskState]?

    var isEmpty: Bool {
        status == nil && priority == nil && title == nil && (notes ?? "").isEmpty && (labels ?? []).isEmpty
            && due == nil && hidden == nil && (subtaskStates ?? [:]).isEmpty
    }
}

// MARK: - Sessions / projects

struct SessionInfo: Codable, Identifiable, Hashable {
    var id: String
    var projectID: String
    var title: String
    var cwd: String
    var startedAt: Date
    var lastActivity: Date
    var transcriptPath: String?
    var desktopID: String?
    var archived = false
    var isLive = false
    var liveStatus: String?
    var summaryCategory: String?
    var summaryDetail: String?
    var needsAction: String?
    var promptCount = 0
    var entrypoint: String?

    var isBusy: Bool { isLive && liveStatus == "busy" }
}

struct ProjectInfo: Identifiable, Hashable {
    var id: String          // normalized absolute path (or special token)
    var name: String
    var workspace: String   // top-level DEV folder, or "Other"
    var relativePath: String
    var key: String
    var colorIndex: Int
}

struct ProjectSettings: Codable, Hashable {
    var name: String?
    var key: String?
    var colorIndex: Int?
    var hidden: Bool?
    /// Other names the project goes by in task titles ("fe" for frontend).
    var aliases: [String]?
    var pinned: Bool?
}

/// A manual ticket that was handed to Claude; when the matching prompt shows up in a
/// transcript, the manual ticket is folded into it (same key, same notes).
struct LaunchRecord: Codable, Hashable {
    var taskID: String
    var projectID: String
    var prompt: String
    var at: Date
}

// MARK: - Persistence envelopes

struct IngestedStore: Codable {
    var version = 1
    var tasks: [TaskItem] = []
    var sessions: [SessionInfo] = []
    var numbers: [String: Int] = [:]
    var counters: [String: Int] = [:]
    /// Project each number was issued in; a ticket that moves project gets a new number there.
    var numberProjects: [String: String]?
}

struct UserStore: Codable {
    var version = 1
    var overrides: [String: TaskOverride] = [:]
    var manual: [TaskItem] = []
    var projectSettings: [String: ProjectSettings] = [:]
    var launches: [LaunchRecord] = []
    /// Backlog folders added by hand (on top of the discovered ones).
    var extraFolders: [String]?
    var ignoredFolders: [String]?
}
