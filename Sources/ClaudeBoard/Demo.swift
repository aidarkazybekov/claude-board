import Foundation

/// `ClaudeBoard --demo` runs the app on generated sample data: a fictional company ("Acme") with
/// a few apps, Claude Code sessions in various states, and a shared backlog folder. Everything
/// lives in a temp folder; the real `~/.claude`, settings and ClaudeBoard data are never touched.
enum Demo {
    static var isOn: Bool { ProcessInfo.processInfo.environment["CLAUDEBOARD_DEMO"] == "1" }

    static var base: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBoard-Demo", isDirectory: true)
    }

    /// Points every data path at a fresh demo folder and fills it. Call before the app starts.
    static func prepare() {
        let b = base.path
        try? FileManager.default.removeItem(atPath: b)
        setenv("CLAUDEBOARD_DEMO", "1", 1)
        setenv("CLAUDEBOARD_DATA_DIR", b + "/data", 1)
        setenv("CLAUDEBOARD_CLAUDE_DIR", b + "/claude", 1)
        setenv("CLAUDEBOARD_DESKTOP_DIR", b + "/desktop", 1)
        setenv("CLAUDEBOARD_ROOTS", b + "/Projects", 1)
        // Other agents read demo folders too, so the demo never shows real data.
        setenv("CLAUDEBOARD_CODEX_DIR", b + "/codex", 1)
        setenv("CLAUDEBOARD_CURSOR_DIR", b + "/cursor", 1)
        setenv("CLAUDEBOARD_GEMINI_DIR", b + "/gemini", 1)
        setenv("CLAUDEBOARD_ANTIGRAVITY_DIR", b + "/antigravity", 1)
        DemoData(base: b).write()
    }

    /// Local ("this Mac") tasks for the personal projects; called once the store exists.
    @MainActor
    static func seed(_ store: Store) {
        guard isOn else { return }
        let projects = base.path + "/Projects"
        let bot = projects + "/recipe-bot"
        let site = projects + "/portfolio"
        store.createTask(title: "Add Spanish recipes to the catalogue", projectID: bot, notes: "Start with 30 dishes. Keep the same JSON schema.",
                         priority: .medium, status: .todo, subtasks: ["Pick 30 recipes", "Translate titles", "Add photos"], destination: .local)
        store.createTask(title: "Rate-limit /random to 5 per minute per chat", projectID: bot, notes: "", priority: .low, status: .backlog, destination: .local)
        store.createTask(title: "Move hosting to a cheaper VPS", projectID: bot, notes: "", priority: .none, status: .backlog, destination: .local)
        store.createTask(title: "Write a case study about the checkout redesign", projectID: site, notes: "Before/after screenshots and numbers from T-004.",
                         priority: .medium, status: .todo, labels: ["writing"], destination: .local)
        store.selection = nil
        store.lastQuickAddProject = projects + "/acme/apps/web"
    }
}

/// Writes the demo world: repos, a backlog folder, Claude transcripts, prompt history,
/// desktop session index entries and live-session markers.
struct DemoData {
    let base: String
    let now = Date()

    var projects: String { base + "/Projects" }
    var acme: String { projects + "/acme" }

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func write() {
        let fm = FileManager.default
        for repo in ["acme/apps/web", "acme/apps/api", "acme/apps/mobile", "acme/apps/billing", "acme/infra", "recipe-bot", "portfolio"] {
            try? fm.createDirectory(atPath: projects + "/" + repo + "/.git", withIntermediateDirectories: true)
        }
        writeBacklog()
        writeSessions()
        writeCodex()
    }

    // MARK: Codex sessions (JSONL rollouts, as the Codex CLI writes them)

    private func writeCodex() {
        let fm = FileManager.default
        let api = acme + "/apps/api", web = acme + "/apps/web", mobile = acme + "/apps/mobile"
        let day = DateFormatter()
        day.dateFormat = "yyyy/MM/dd"
        func rollout(_ id: String, cwd: String, start: Date, _ events: [(Date, [String: Any])], open: Bool) {
            let dir = base + "/codex/sessions/" + day.string(from: start)
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var lines = [json(["timestamp": iso.string(from: start), "type": "session_meta",
                               "payload": ["id": id, "cwd": cwd, "timestamp": iso.string(from: start), "originator": "codex_cli_rs"]])]
            for (at, payload) in events { lines.append(json(["timestamp": iso.string(from: at), "type": "event_msg", "payload": payload])) }
            let path = dir + "/rollout-\(id).jsonl"
            try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            let mtime = open ? now : (events.last?.0 ?? start)
            try? fm.setAttributes([.modificationDate: mtime], ofItemAtPath: path)
        }
        func cmd(_ at: Date) -> (Date, [String: Any]) { (at, ["type": "exec_command_end", "exit_code": 0]) }
        func patch(_ at: Date, _ files: [String], in dir: String) -> (Date, [String: Any]) {
            (at, ["type": "patch_apply_end", "success": true, "changes": Dictionary(uniqueKeysWithValues: files.map { (dir + "/" + $0, ["type": "update"]) })])
        }

        // Busy right now: tests for the limiter.
        rollout("019a6b2e-api3-4c1d-9f00-codexdemo001", cwd: api, start: ago(9), [
            (ago(9), ["type": "user_message", "message": "Add 429 tests for the rate limiter: per-key limits, Retry-After header, and the reset after a minute."]),
            cmd(ago(8)), patch(ago(7), ["internal/ratelimit/bucket_test.go"], in: api), cmd(ago(6)), cmd(ago(3)),
            (ago(2), ["type": "agent_message", "message": "Running the limiter tests: 31 of 58 pass so far."]),
        ], open: true)

        // Waiting on you: a question about the shared store.
        rollout("019a6b2e-api6-4c1d-9f00-codexdemo002", cwd: api, start: ago(40), [
            (ago(40), ["type": "user_message", "message": "Look at T-006 and make the limiter work across all API pods."]),
            cmd(ago(38)), patch(ago(33), ["internal/ratelimit/shared_test.go"], in: api), cmd(ago(30)),
            (ago(23), ["type": "agent_message", "message": "Each pod keeps its own counter, so a client can make twice the allowed requests. I wrote a failing test for it."]),
            (ago(23), ["type": "request_user_input", "question": "Use Redis for the limiter, or sticky sessions on the load balancer?"]),
        ], open: true)

        // Done this morning: the flaky checkout test.
        rollout("019a6b2e-web1-4c1d-9f00-codexdemo003", cwd: web, start: ago(260), [
            (ago(260), ["type": "user_message", "message": "The Playwright checkout test fails about one run in five. Find out why and fix it."]),
            cmd(ago(255)), cmd(ago(250)), patch(ago(240), ["tests/e2e/checkout.spec.ts", "tests/e2e/helpers/payment.ts"], in: web), cmd(ago(236)),
            (ago(232), ["type": "task_complete", "last_agent_message": "The test raced the payment iframe. It now waits for the frame to load; 50 runs in a row pass."]),
        ], open: false)

        // Done yesterday: offline cart, with a short follow-up.
        rollout("019a6b2e-mob5-4c1d-9f00-codexdemo004", cwd: mobile, start: ago(26 * 60), [
            (ago(26 * 60), ["type": "user_message", "message": "Keep the cart when the phone goes offline: store it locally and sync when the connection is back."]),
            cmd(ago(26 * 60 - 5)), patch(ago(26 * 60 - 20), ["src/cart/store.ts", "src/cart/sync.ts"], in: mobile),
            (ago(26 * 60 - 25), ["type": "agent_message", "message": "The cart now lives in local storage and syncs on reconnect. Should I also show a banner while offline?"]),
            (ago(26 * 60 - 24), ["type": "user_message", "message": "yes please"]),
            patch(ago(26 * 60 - 15), ["src/components/OfflineBanner.tsx"], in: mobile),
            (ago(26 * 60 - 12), ["type": "task_complete", "last_agent_message": "Added an offline banner that disappears once the cart has synced."]),
        ], open: false)
    }

    private func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    // MARK: Backlog folder

    private func writeBacklog() {
        let folder = acme + "/backlog"
        try? FileManager.default.createDirectory(atPath: folder + "/tasks", withIntermediateDirectories: true)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        func day(_ d: Double) -> String { df.string(from: now.addingTimeInterval(-d * 86_400)) }

        struct T { let id, slug, title, area, prio, status: String; let captured: Double; let owner: String?; let body: String }
        let tasks: [T] = [
            T(id: "T-001", slug: "unified-sign-in", title: "Unify the sign-in page across all apps", area: "Platform", prio: "P2", status: "backlog", captured: 20, owner: nil,
              body: "Every app has its own sign-in screen with different copy and layout. Build one shared page in the design system and use it everywhere.\n\n## Done when\n\n- [ ] Shared component in the design system\n- [ ] Web and mobile use it\n- [ ] Old screens removed"),
            T(id: "T-002", slug: "stripe-webhooks", title: "Billing: Stripe webhooks fail after retries", area: "Billing", prio: "P1", status: "in-progress", captured: 6, owner: "billing",
              body: "Since last weekend about 3% of `invoice.paid` webhooks fail after Stripe's retries, so some customers stay \"unpaid\" in our admin.\n\n## Done when\n\n- [x] Reproduce with the Stripe CLI\n- [ ] Make the handler idempotent\n- [ ] Backfill the affected invoices"),
            T(id: "T-003", slug: "storefront-dark-mode", title: "Dark mode for the web storefront", area: "Web", prio: "P3", status: "backlog", captured: 15, owner: nil,
              body: "Respect `prefers-color-scheme`, with a toggle in the footer. Product photos need a subtle border on dark."),
            T(id: "T-004", slug: "checkout-redesign", title: "Web checkout redesign: one column on mobile", area: "Web", prio: "P1", status: "in-progress", captured: 9, owner: nil,
              body: "Conversion on mobile checkout is 40% below desktop. One column on phones, order summary in a sidebar on desktop.\n\n## Done when\n\n- [x] Audit current components\n- [x] Responsive layout\n- [ ] Order summary sidebar\n- [ ] Playwright tests updated"),
            T(id: "T-005", slug: "offline-cart", title: "Mobile: keep the cart when offline", area: "Mobile", prio: "P2", status: "todo", captured: 11, owner: nil,
              body: "Cart items disappear when the app starts without a connection. Persist the cart locally and sync on reconnect."),
            T(id: "T-006", slug: "shared-rate-limit-store", title: "API: shared rate-limit store across instances", area: "API", prio: "P1", status: "blocked", captured: 2, owner: nil,
              body: "The new in-memory limiter only works per instance. Waiting on a decision: Redis, or sticky sessions at the load balancer."),
            T(id: "T-007", slug: "staging-costs", title: "Infra: cut staging costs by half", area: "Infra", prio: "P2", status: "done", captured: 12, owner: nil,
              body: "Staging doubled in cost last month.\n\n## Done when\n\n- [x] Find the cause\n- [x] Scale idle nodes to zero at night\n- [x] Verify next invoice"),
            T(id: "T-008", slug: "error-tracking", title: "Decide on an error-tracking tool", area: "Platform", prio: "P3", status: "investigating", captured: 18, owner: nil,
              body: "Compare the hosted options against self-hosting. Budget, privacy and SDK support for web, API and mobile."),
            T(id: "T-010", slug: "faster-product-images", title: "Web: faster product images (AVIF, lazy loading)", area: "Web", prio: "P2", status: "todo", captured: 3, owner: nil,
              body: "Product pages load 2.4 MB of images on mobile. Serve AVIF with a fallback and lazy-load below the fold.\n\n## Done when\n\n- [ ] AVIF pipeline in the image CDN\n- [ ] Lazy loading below the fold\n- [ ] LCP under 2 s on a mid-range phone"),
            T(id: "T-009", slug: "checkout-a11y", title: "Accessibility audit of the web checkout", area: "Web", prio: "P2", status: "backlog", captured: 4, owner: nil,
              body: "Screen reader pass, focus order, colour contrast. Do it after T-004 lands."),
        ]
        var index = """
        # Acme backlog

        One file per task in `tasks/`. IDs are stable and never reused.

        | ID | Title | Area | Priority | Status |
        | --- | --- | --- | --- | --- |

        """
        for t in tasks {
            var fm = "---\nid: \(t.id)\ntitle: \(TaskFolder.quoteIfNeeded(t.title))\narea: \(t.area)\npriority: \(t.prio)\nstatus: \(t.status)\ncaptured: \(day(t.captured))\n"
            if let o = t.owner { fm += "owner-session: \(o)\n" }
            fm += "---\n\n# \(t.id) — \(t.title)\n\n\(t.body)\n"
            try? fm.write(toFile: "\(folder)/tasks/\(t.id)-\(t.slug).md", atomically: true, encoding: .utf8)
            index += "| [\(t.id)](tasks/\(t.id)-\(t.slug).md) | \(t.title) | \(t.area) | \(t.prio) | \(t.status) |\n"
        }
        try? index.write(toFile: folder + "/BACKLOG.md", atomically: true, encoding: .utf8)
        try? "# Acme backlog\n\nShared task list for all Acme apps. Edited by hand, in ClaudeBoard, or by Claude.\n"
            .write(toFile: folder + "/README.md", atomically: true, encoding: .utf8)
    }

    // MARK: Claude sessions

    private final class Session {
        let id = UUID().uuidString.lowercased()
        let cwd: String
        let title: String
        var lines: [String] = []
        var n = 0
        init(cwd: String, title: String) { self.cwd = cwd; self.title = title }
    }

    private func json(_ o: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: o), encoding: .utf8)!
    }

    private func user(_ s: Session, _ text: String, _ at: Date) {
        s.n += 1
        s.lines.append(json(["type": "user", "uuid": "\(s.id)-u\(s.n)", "timestamp": iso.string(from: at), "cwd": s.cwd,
                             "gitBranch": "main", "sessionId": s.id, "origin": ["kind": "human"],
                             "message": ["role": "user", "content": text]]))
    }

    private func say(_ s: Session, _ text: String, _ at: Date) {
        s.lines.append(json(["type": "assistant", "timestamp": iso.string(from: at), "cwd": s.cwd, "sessionId": s.id,
                             "message": ["role": "assistant", "content": [["type": "text", "text": text]]]]))
    }

    private func tool(_ s: Session, _ name: String, _ input: [String: Any], _ at: Date) {
        s.lines.append(json(["type": "assistant", "timestamp": iso.string(from: at), "cwd": s.cwd, "sessionId": s.id,
                             "message": ["role": "assistant", "content": [["type": "tool_use", "id": UUID().uuidString, "name": name, "input": input]]]]))
    }

    private func plan(_ s: Session, _ steps: [(String, String)], _ at: Date) {
        tool(s, "mcp__ccd_turn__update_plan", ["items": steps.map { ["content": $0.0, "status": $0.1] }], at)
    }

    /// A burst of tool work: reads, shell runs and edits spread over `minutes`.
    private func work(_ s: Session, files: [String], from start: Date, minutes: Double) {
        let steps = max(4, files.count * 3)
        for k in 0..<steps {
            let at = start.addingTimeInterval(Double(k) / Double(steps) * minutes * 60)
            switch k % 3 {
            case 0: tool(s, "Read", ["file_path": s.cwd + "/" + files[(k / 3) % files.count]], at)
            case 1: tool(s, "Bash", ["command": "npm test"], at)
            default: tool(s, "Edit", ["file_path": s.cwd + "/" + files[(k / 3) % files.count]], at)
            }
        }
    }

    private func wrap(_ s: Session, _ recap: String, ask: String? = nil, _ at: Date) {
        var input: [String: Any] = ["recap": recap]
        if let ask { input["ask"] = ask }
        tool(s, "mcp__ccd_turn__wrap_up", input, at)
    }

    private func writeSessions() {
        var sessions: [Session] = []
        let web = acme + "/apps/web", api = acme + "/apps/api", mobile = acme + "/apps/mobile"
        let billing = acme + "/apps/billing", infra = acme + "/infra"

        // 1. Live and busy: checkout redesign, linked to T-004.
        let s1 = Session(cwd: web, title: "Checkout redesign")
        user(s1, "Work on T-004: redesign the checkout. One column on mobile, order summary in a sidebar on desktop. Keep the existing payment form.", ago(95))
        plan(s1, [("Audit current checkout components", "in_progress"), ("Build the responsive layout", "pending"),
                  ("Move order summary to a sidebar", "pending"), ("Update Playwright tests", "pending")], ago(94))
        work(s1, files: ["src/app/checkout/page.tsx", "src/components/OrderSummary.tsx", "src/components/CheckoutForm.tsx"], from: ago(93), minutes: 30)
        tool(s1, "mcp__ccd_turn__update_plan", ["advance": true], ago(62))
        work(s1, files: ["src/app/checkout/layout.tsx", "src/styles/checkout.css"], from: ago(61), minutes: 25)
        tool(s1, "mcp__ccd_turn__update_plan", ["advance": true], ago(35))
        say(s1, "Layout is responsive now. Moving the order summary into a sticky sidebar for screens wider than 1024px.", ago(34))
        work(s1, files: ["src/components/OrderSummary.tsx"], from: ago(33), minutes: 30)
        sessions.append(s1)

        // 2. Waiting on you: rate limiting, links T-006.
        let s2 = Session(cwd: api, title: "Rate limiting for the public API")
        user(s2, "Add rate limiting to the public API: 100 requests per minute per API key, answer 429 with a Retry-After header.", ago(26 * 60))
        plan(s2, [("Token-bucket limiter middleware", "in_progress"), ("429 response with Retry-After", "pending"), ("Tests", "pending")], ago(26 * 60 - 1))
        work(s2, files: ["internal/ratelimit/bucket.go", "internal/http/middleware.go", "internal/ratelimit/bucket_test.go"], from: ago(26 * 60 - 2), minutes: 35)
        wrap(s2, "Added a token-bucket limiter as HTTP middleware: 100 req/min per key, 429 with `Retry-After`. 14 new tests pass.", ago(25 * 60 - 20))
        user(s2, "The limiter state lives in memory, so it breaks with 3 instances behind the load balancer. Look at T-006 and propose a fix.", ago(24 * 60))
        work(s2, files: ["internal/ratelimit/bucket.go", "deploy/api.yaml"], from: ago(24 * 60 - 1), minutes: 12)
        say(s2, "Two options: a Redis-backed bucket (exact limits, one more dependency) or sticky sessions on the load balancer (no new infra, limits become per-instance). I'd go with Redis. Which one should I build?", ago(24 * 60 - 14))
        wrap(s2, "Compared a Redis-backed limiter with sticky sessions for T-006. Nothing changed in code yet.",
             ask: "Use Redis for the limiter, or sticky sessions?", ago(24 * 60 - 14))
        sessions.append(s2)

        // 3. Mobile: done, with a folded follow-up and a suggested next task.
        let s3 = Session(cwd: mobile, title: "Push notification opt-in")
        user(s3, "Add a push-notification opt-in screen that shows after the first order. iOS only for now.", ago(3 * 1440 + 300))
        plan(s3, [("Opt-in screen UI", "in_progress"), ("Ask permission after first order", "pending"), ("Analytics events", "pending")], ago(3 * 1440 + 299))
        work(s3, files: ["ios/Acme/Onboarding/PushOptInView.swift", "ios/Acme/Orders/OrderFlow.swift"], from: ago(3 * 1440 + 298), minutes: 40)
        say(s3, "The opt-in screen is in place and only appears after the first successful order. Should I also track the decision in analytics?", ago(3 * 1440 + 255))
        user(s3, "yes", ago(3 * 1440 + 250))
        work(s3, files: ["ios/Acme/Analytics/Events.swift"], from: ago(3 * 1440 + 249), minutes: 10)
        wrap(s3, "Opt-in screen after the first order, plus `push_optin_shown/accepted/declined` events.", ago(3 * 1440 + 238))
        tool(s3, "mcp__ccd_session__start_session", ["initiation": "own_initiative", "title": "Notification settings screen in the app",
                                                     "prompt": "Let users change their push preferences later from Settings."], ago(3 * 1440 + 237))
        user(s3, "Now localise the opt-in screen to German and Spanish.", ago(3 * 1440 + 200))
        work(s3, files: ["ios/Acme/de.lproj/Localizable.strings", "ios/Acme/es.lproj/Localizable.strings"], from: ago(3 * 1440 + 199), minutes: 12)
        wrap(s3, "Added German and Spanish strings for the opt-in screen; screenshots checked on small and large phones.", ago(3 * 1440 + 186))
        sessions.append(s3)

        // 4. Infra: done, linked to T-007.
        let s4 = Session(cwd: infra, title: "Staging costs")
        user(s4, "Staging costs doubled last month. Find out why and cut it (T-007).", ago(5 * 1440 + 120))
        plan(s4, [("Break down last month's bill", "in_progress"), ("Find idle resources", "pending"), ("Scale down at night", "pending")], ago(5 * 1440 + 119))
        work(s4, files: ["terraform/staging/nodes.tf", "terraform/staging/schedule.tf"], from: ago(5 * 1440 + 118), minutes: 45)
        wrap(s4, "Two GPU nodes were left running after a load test. Removed them and added a night-time scale-to-zero schedule: about 55% lower staging cost.", ago(5 * 1440 + 70))
        sessions.append(s4)

        // 5. Billing: asked, never answered (session closed), linked to T-002.
        let s5 = Session(cwd: billing, title: "Stripe webhook failures")
        user(s5, "Investigate the failed Stripe webhooks from last weekend (T-002). Start by reproducing with the Stripe CLI.", ago(20 * 60))
        work(s5, files: ["src/webhooks/stripe.ts", "src/webhooks/stripe.test.ts"], from: ago(20 * 60 - 1), minutes: 6)
        sessions.append(s5)

        // 6. Personal project: done.
        let s6 = Session(cwd: projects + "/recipe-bot", title: "Recipe bot commands")
        user(s6, "Add a /random command to the Telegram recipe bot and send a recipe of the day at 9:00.", ago(2 * 1440 + 600))
        plan(s6, [("/random command", "in_progress"), ("Daily scheduler at 9:00", "pending"), ("Tests", "pending")], ago(2 * 1440 + 599))
        work(s6, files: ["bot/commands.py", "bot/scheduler.py", "tests/test_commands.py"], from: ago(2 * 1440 + 598), minutes: 25)
        wrap(s6, "Added `/random` and a 9:00 daily recipe (per-chat time zone). 9 tests pass.", ago(2 * 1440 + 570))
        user(s6, "Make the daily message include the recipe photo and cooking time.", ago(2 * 1440 + 540))
        work(s6, files: ["bot/scheduler.py", "bot/render.py"], from: ago(2 * 1440 + 539), minutes: 10)
        wrap(s6, "Daily message now sends the photo with a caption: title, cooking time and a link.", ago(2 * 1440 + 527))
        sessions.append(s6)

        // 7. Portfolio: done, a week ago.
        let s7 = Session(cwd: projects + "/portfolio", title: "About page copy")
        user(s7, "Rewrite the About page copy: shorter, friendlier, no buzzwords.", ago(7 * 1440 + 200))
        work(s7, files: ["src/pages/about.mdx"], from: ago(7 * 1440 + 199), minutes: 8)
        wrap(s7, "About page cut from 410 to 160 words, rewritten in first person.", ago(7 * 1440 + 190))
        sessions.append(s7)

        // 8. Web: done, flaky test.
        let s8 = Session(cwd: web, title: "Flaky cart test")
        user(s8, "The cart e2e test fails on CI about once in five runs. Find the cause and fix it properly, no retries.", ago(4 * 1440 + 400))
        plan(s8, [("Reproduce locally", "in_progress"), ("Fix the race", "pending")], ago(4 * 1440 + 399))
        work(s8, files: ["e2e/cart.spec.ts", "src/lib/cart.ts"], from: ago(4 * 1440 + 398), minutes: 30)
        wrap(s8, "The test clicked before the cart hydrated. Added a ready signal and waited on it; 50 CI runs green.", ago(4 * 1440 + 365))
        sessions.append(s8)

        // 9. Workspace: weekly summary, done today.
        let s9 = Session(cwd: acme, title: "Weekly update")
        user(s9, "Summarise what we shipped this week for the team update. Keep it to five bullets.", ago(70))
        work(s9, files: ["backlog/BACKLOG.md"], from: ago(69), minutes: 4)
        wrap(s9, "Five-bullet update: checkout redesign in progress, rate limiter shipped, push opt-in live in DE/ES, staging cost down 55%, flaky cart test fixed.", ago(64))
        sessions.append(s9)

        let fm = FileManager.default
        let claude = base + "/claude"
        for s in sessions {
            let dir = claude + "/projects/" + s.cwd.replacingOccurrences(of: "/", with: "-")
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var lines = s.lines
            lines.append(json(["type": "ai-title", "aiTitle": s.title, "sessionId": s.id]))
            try? (lines.joined(separator: "\n") + "\n").write(toFile: "\(dir)/\(s.id).jsonl", atomically: true, encoding: .utf8)
        }

        // Prompt history for an older session whose transcript was already cleaned up.
        let old = UUID().uuidString.lowercased()
        let hist = [
            ["display": "Set up the monorepo with shared lint and TypeScript config for all apps", "timestamp": ago(13 * 1440).timeIntervalSince1970 * 1000, "project": acme, "sessionId": old],
            ["display": "ok, also add a pre-commit hook", "timestamp": ago(13 * 1440 - 30).timeIntervalSince1970 * 1000, "project": acme, "sessionId": old],
        ].map(json)
        try? (hist.joined(separator: "\n") + "\n").write(toFile: claude + "/history.jsonl", atomically: true, encoding: .utf8)

        // Live sessions: this process stands in for the running Claude Code processes.
        let pid = Int(getpid())
        try? fm.createDirectory(atPath: claude + "/sessions", withIntermediateDirectories: true)
        for (i, (s, status)) in [(s1, "busy"), (s2, "idle")].enumerated() {
            let marker: [String: Any] = ["pid": pid, "sessionId": s.id, "cwd": s.cwd, "status": status, "kind": "interactive", "entrypoint": "cli"]
            try? json(marker).write(toFile: "\(claude)/sessions/\(pid + i).json", atomically: true, encoding: .utf8)
        }

        // Desktop app index: titles and a "needs your action" summary.
        let desk = base + "/desktop/demo/demo"
        try? fm.createDirectory(atPath: desk, withIntermediateDirectories: true)
        for (s, needs) in [(s1, nil as String?), (s2, "Choose Redis or sticky sessions for the rate limiter")] {
            var o: [String: Any] = ["sessionId": "local_\(s.id)", "cliSessionId": s.id, "cwd": s.cwd, "title": s.title, "isArchived": false]
            if let needs { o["postTurnSummary"] = ["status_category": "blocked", "status_detail": needs, "needs_action": needs] }
            try? json(o).write(toFile: "\(desk)/local_\(s.id).json", atomically: true, encoding: .utf8)
        }
    }
}
