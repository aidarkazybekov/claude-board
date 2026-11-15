import AppKit
import UserNotifications

/// A Claude ticket that just moved to a column worth a notification.
struct StatusChange: Equatable {
    enum Kind: String { case needsYou, done }
    var id: String
    var kind: Kind
    /// Identifies this exact event, so the same question or recap is never announced twice.
    var dedupeKey: String
}

enum StatusChanges {
    /// Which Claude tickets changed status between two merges. Pure, so the self-test can cover it.
    /// - `before` is nil on the first merge after launch: nothing is announced until there is a baseline.
    /// - Only tickets read from a live transcript count, and only if they moved in the last `recent` seconds,
    ///   so adding a root or importing old history never floods the screen.
    static func detect(before: [String: TaskStatus]?, after items: [TaskItem], now: Date = Date(),
                       kinds: Set<StatusChange.Kind>, alreadySent: Set<String>, recent: TimeInterval = 15 * 60) -> [StatusChange] {
        guard let before else { return [] }
        var out: [StatusChange] = []
        for t in items where t.origin == .prompt && !t.hidden && now.timeIntervalSince(t.lastActivity) < recent {
            let kind: StatusChange.Kind
            switch t.status {
            case .needsYou: kind = .needsYou
            case .done: kind = .done
            default: continue
            }
            guard kinds.contains(kind), before[t.id] != t.status else { continue }
            let detail = kind == .needsYou ? (t.pendingAsk ?? t.finalReply ?? "") : (t.recap ?? t.finalReply ?? "")
            let key = "\(t.id)|\(kind.rawValue)|\(detail.hashValue)"
            if alreadySent.contains(key) { continue }
            out.append(StatusChange(id: t.id, kind: kind, dedupeKey: key))
        }
        return out
    }

    /// The question Claude ended on, short enough for a notification.
    static func question(of t: TaskItem) -> String {
        if let ask = t.pendingAsk?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty { return clip(ask) }
        let reply = (t.finalReply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = reply.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let q = lines.last(where: { $0.contains("?") }) { return clip(Markdown.plain(q)) }
        return clip(lines.last.map { Markdown.plain($0) } ?? t.title)
    }

    static func clip(_ s: String, _ n: Int = 180) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }
}

/// Posts macOS notifications when Claude needs you or finishes, and routes clicks back to the ticket.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let needsYouKey = "notifyNeedsYou"
    static let doneKey = "notifyDone"
    private static let category = "claude-ticket"
    private static let resumeAction = "resume"

    weak var store: Store?
    private var sent: Set<String> = []

    /// Notifications need a real app bundle; never from `swift run`, the demo or snapshot runs. Set in `attach`.
    private(set) static var available = false

    static var kinds: Set<StatusChange.Kind> {
        var k: Set<StatusChange.Kind> = []
        if UserDefaults.standard.object(forKey: needsYouKey) == nil || UserDefaults.standard.bool(forKey: needsYouKey) { k.insert(.needsYou) }
        if UserDefaults.standard.bool(forKey: doneKey) { k.insert(.done) }
        return k
    }

    @MainActor func attach(_ store: Store) {
        self.store = store
        Self.available = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
            && !Demo.isOn && Snapshot.directory == nil
        guard Self.available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let resume = UNNotificationAction(identifier: Self.resumeAction, title: "Resume in Terminal", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [resume], intentIdentifiers: [])])
    }

    /// Called after each merge with the statuses from before it.
    @MainActor func process(before: [String: TaskStatus]?, store: Store) {
        let changes = StatusChanges.detect(before: before, after: store.items, kinds: Self.kinds, alreadySent: sent)
        guard !changes.isEmpty else { return }
        changes.forEach { sent.insert($0.dedupeKey) }
        let requests: [UNNotificationRequest]
        if changes.count > 3 {
            // A burst (e.g. waking from sleep): one summary instead of a stack of banners.
            let waiting = changes.filter { $0.kind == .needsYou }.count
            let c = UNMutableNotificationContent()
            c.title = waiting > 0 ? "\(waiting) Claude sessions are waiting on you" : "Claude finished \(changes.count) requests"
            c.body = "Open ClaudeBoard to see them."
            c.sound = .default
            c.userInfo = ["scope": waiting > 0 ? "inbox" : "all"]
            requests = [UNNotificationRequest(identifier: "burst-\(Date().timeIntervalSince1970)", content: c, trigger: nil)]
        } else {
            requests = changes.compactMap { ch in
                guard let t = store.task(ch.id) else { return nil }
                let p = store.project(t.projectID)
                let c = UNMutableNotificationContent()
                c.title = ch.kind == .needsYou ? "Claude is waiting on you" : "Claude finished"
                c.subtitle = "\(store.key(for: t)) · \(p.name): \(StatusChanges.clip(t.title, 60))"
                c.body = ch.kind == .needsYou ? StatusChanges.question(of: t) : StatusChanges.clip(Markdown.plain(t.recap ?? t.finalReply ?? t.title))
                c.sound = ch.kind == .needsYou ? .default : nil
                c.threadIdentifier = t.projectID
                c.userInfo = ["ticket": t.id]
                if ch.kind == .needsYou && t.sessionID != nil { c.categoryIdentifier = Self.category }
                return UNNotificationRequest(identifier: ch.dedupeKey, content: c, trigger: nil)
            }
        }
        deliver(requests)
    }

    /// From Settings: shows what a "waiting on you" notification looks like.
    func sendTest() {
        let c = UNMutableNotificationContent()
        c.title = "Claude is waiting on you"
        c.subtitle = "WEB-12 · web: Checkout redesign"
        c.body = "This is a test. ClaudeBoard shows Claude's question here when a session stops to ask you something."
        c.sound = .default
        deliver([UNNotificationRequest(identifier: "test-\(Date().timeIntervalSince1970)", content: c, trigger: nil)])
    }

    /// Asks for permission the first time something is actually sent, never at launch.
    private func deliver(_ requests: [UNNotificationRequest]) {
        guard Self.available, !requests.isEmpty else { return }
        // CLAUDEBOARD_NOTIFY_DRYRUN=1: log what would be shown (with CLAUDEBOARD_LOG) instead of asking macOS.
        if ProcessInfo.processInfo.environment["CLAUDEBOARD_NOTIFY_DRYRUN"] != nil {
            for r in requests {
                let c = r.content
                Store.debugLog("notify: \(c.title) | \(c.subtitle) | \(c.body) | actions=\(c.categoryIdentifier.isEmpty ? "none" : "resume")")
            }
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { requests.forEach { center.add($0) } }
                    self.refreshAuthorization()
                }
            case .authorized, .provisional:
                requests.forEach { center.add($0) }
            default:
                break
            }
        }
    }

    /// Mirrors the system setting into the store, for the Settings screen.
    func refreshAuthorization() {
        guard Self.available else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed: Bool? = settings.authorizationStatus == .notDetermined ? nil
                : [.authorized, .provisional].contains(settings.authorizationStatus)
            Task { @MainActor in self.store?.notificationsAllowed = allowed }
        }
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let ticket = info["ticket"] as? String
        let scope = info["scope"] as? String
        let action = response.actionIdentifier
        Task { @MainActor in
            defer { completionHandler() }
            guard let store = self.store else { return }
            if action == Self.resumeAction, let ticket {
                store.resume(ticket)
            } else {
                store.reveal(ticket: ticket, inbox: scope == "inbox")
            }
        }
    }
}
