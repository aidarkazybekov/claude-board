import SwiftUI

/// The in-app guide: six short pages, opened from Help → ClaudeBoard Guide (⌘/),
/// after onboarding, and from the "?" button in the sidebar.
struct GuidePage: Identifiable {
    let id: Int
    let symbol: String
    let title: String
    let lead: String
    let points: [String]
    let visual: GuideVisual
}

enum GuideVisual { case twoKinds, views, columns, plan, link, stayOnTop }

enum Guide {
    static let pages: [GuidePage] = [
        GuidePage(id: 0, symbol: "square.stack.3d.up", title: "Two kinds of tickets",
                  lead: "ClaudeBoard puts the work you hand to Claude Code and the work you plan yourself on one board.",
                  points: [
                      "**Claude's work** is tracked automatically. Every request you type in Claude Code becomes a ticket in its project, with Claude's plan, outcome and the files it touched.",
                      "**Your tasks** are what each project still needs, often before Claude knows about it. You add these yourself.",
                      "Nothing to set up: ClaudeBoard reads Claude Code's local logs and refreshes every 20 seconds.",
                  ], visual: .twoKinds),
        GuidePage(id: 1, symbol: "rectangle.split.3x1", title: "Five ways to look at it",
                  lead: "Switch views in the toolbar or with ⌘1–⌘5. The sidebar picks the scope: everything, one workspace, or one project.",
                  points: [
                      "**Plan:** your tasks, grouped per project, with an add line under each.",
                      "**Board:** columns from Backlog to Done. Drag cards between them.",
                      "**List:** a sortable table of every ticket.",
                      "**Worklog:** what you asked and what Claude did, day by day.",
                      "**Insights:** requests per day, status per project, when you work.",
                  ], visual: .views),
        GuidePage(id: 2, symbol: "rectangle.3.group", title: "What the columns mean",
                  lead: "Claude tickets move by themselves, based on what happens in the session.",
                  points: [
                      "**In Progress:** Claude is working now, or its plan still has open steps.",
                      "**Needs You:** Claude finished its turn with a question, or the session is blocked on your answer.",
                      "**Done:** Claude finished and you moved on. **To Do:** you asked, but the session closed before Claude answered.",
                      "Drag a card to override it (marked with a hand). Choose \"Use status from Claude\" to undo.",
                  ], visual: .columns),
        GuidePage(id: 3, symbol: "checklist", title: "Plan your own tasks",
                  lead: "Use the Plan view's add line, a Board column's add field, or ⌘N.",
                  points: [
                      "Type a title and press Return. Add `!high`, `!urgent` or `!low` to set priority.",
                      "Without a backlog folder, tasks stay **on this Mac**.",
                      "**In a backlog folder** they're markdown files in the repo, so your team, and Claude, read the same list. Choose *Keep Tasks in the Repo* in a project's menu to create one.",
                      "Existing `backlog/` folders, including Backlog.md ones, are found and filed under the right app.",
                  ], visual: .plan),
        GuidePage(id: 4, symbol: "link", title: "Connect tasks and Claude",
                  lead: "Mention a task's key in any Claude prompt and that session links to the task.",
                  points: [
                      "Example: \"work on **T-004**\" or \"[**WEB-3**] fix the header\". The task then shows Claude's live activity and outcome.",
                      "**Start with Claude** opens Terminal in the project and hands the task over, key included.",
                      "**Resume** reopens a Claude ticket's session with `claude --resume`.",
                  ], visual: .link),
        GuidePage(id: 5, symbol: "menubar.arrow.up.rectangle", title: "Stay on top of it",
                  lead: "You don't have to keep the window open.",
                  points: [
                      "The **menu bar** icon shows how many tickets need you, and which sessions are busy.",
                      "**Needs You** in the sidebar is your inbox: every place Claude is waiting.",
                      "**Settings:** project folders, backlog folders, refresh interval.",
                      "Everything stays on your Mac. Claude Code's files are only read, never changed.",
                  ], visual: .stayOnTop),
    ]
}

struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        let p = Guide.pages[page]
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 26) {
                GuideIllustration(visual: p.visual)
                    .frame(width: 250, height: 280)
                    .background(
                        LinearGradient(colors: [Color(red: 0.86, green: 0.47, blue: 0.33).opacity(0.22),
                                                Color(red: 0.36, green: 0.30, blue: 0.70).opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                VStack(alignment: .leading, spacing: 12) {
                    Label(p.title, systemImage: p.symbol).font(.title2.weight(.semibold))
                    Text(p.lead).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(p.points, id: \.self) { point in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle().fill(Color.accentColor).frame(width: 5, height: 5).offset(y: -2)
                                Text(LocalizedStringKey(point)).font(.callout).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(26)
            .frame(height: 340, alignment: .top)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(Guide.pages) { g in
                        Circle()
                            .fill(g.id == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                            .onTapGesture { withAnimation(.snappy) { page = g.id } }
                    }
                }
                Spacer()
                if !Demo.isOn && page == Guide.pages.count - 1 {
                    Button("Try the Demo Board") { DemoLauncher.open() }
                }
                if page > 0 {
                    Button("Back") { withAnimation(.snappy) { page -= 1 } }
                }
                if page < Guide.pages.count - 1 {
                    Button("Next") { withAnimation(.snappy) { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 760)
        .onExitCommand { dismiss() }
    }
}

/// Small pictures built from the app's own components, so the guide matches the board.
struct GuideIllustration: View {
    let visual: GuideVisual

    var body: some View {
        VStack(spacing: 10) {
            switch visual {
            case .twoKinds:
                miniCard(key: "WEB-12", title: "Redesign the checkout page", icon: "sparkle", status: .inProgress, live: true)
                miniCard(key: "T-004", title: "Checkout: one column on mobile", icon: "doc.text", status: .todo, live: false)
                Text("Claude's work · your task").font(.caption2).foregroundStyle(.secondary)
            case .views:
                ForEach(ViewMode.allCases) { m in
                    HStack {
                        Image(systemName: m.symbol).frame(width: 20)
                        Text(m.title)
                        Spacer()
                        Text("⌘\((ViewMode.allCases.firstIndex(of: m) ?? 0) + 1)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            case .columns:
                ForEach(TaskStatus.allCases) { s in StatusBadge(status: s) }
                StatusBadge(status: .done, overridden: true)
            case .plan:
                VStack(alignment: .leading, spacing: 6) {
                    Text("billing").font(.headline)
                    planLine("T-002", "Stripe webhooks fail after retries", .inProgress)
                    planLine("BIL-3", "Add CSV export for invoices", .todo)
                    HStack(spacing: 6) {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        Text("Add a task for billing… !high").foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            case .link:
                Text("“work on T-004 …”").font(.callout.italic())
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                Image(systemName: "arrow.down").foregroundStyle(.secondary)
                miniCard(key: "T-004", title: "Checkout: one column on mobile", icon: "doc.text", status: .inProgress, live: true,
                         extra: "Claude working · 1")
            case .stayOnTop:
                HStack(spacing: 4) {
                    Image(systemName: "checklist.unchecked")
                    Text("2")
                }
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                StatusBadge(status: .needsYou)
                Text("“Use Redis or sticky sessions?”").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func miniCard(key: String, title: String, icon: String, status: TaskStatus, live: Bool, extra: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                KeyLabel(text: key)
                Spacer()
                if live { LiveDot(busy: true) }
                Image(systemName: icon).font(.caption2).foregroundStyle(.tertiary)
            }
            Text(title).font(.callout).lineLimit(2)
            if let extra {
                Label(extra, systemImage: "sparkle").font(.caption2).foregroundStyle(.secondary)
            }
            StatusBadge(status: status)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func planLine(_ key: String, _ title: String, _ s: TaskStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: s.symbol).foregroundStyle(Palette.status(s))
            KeyLabel(text: key)
            Text(title).lineLimit(1)
        }
        .font(.caption)
    }
}
