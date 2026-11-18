import SwiftUI

/// The in-app guide: six short pages, opened from Help → Guide (⌘/), after onboarding,
/// and from the Guide button in the sidebar.
struct GuidePage: Identifiable {
    let id: Int
    let title: String
    let lead: String
    let points: [String]
    let visual: GuideVisual
}

enum GuideVisual { case twoKinds, views, columns, plan, link, stayOnTop }

enum Guide {
    static let pages: [GuidePage] = [
        GuidePage(id: 0, title: "Two kinds of tasks, one board",
                  lead: "Your own plans and everything you hand to coding agents, side by side.",
                  points: [
                      "**Your agents' work** is found on its own. Every request you give Claude Code, Codex, Cursor, Gemini CLI or Antigravity becomes a ticket in its project, with the plan, the outcome and the files touched.",
                      "**Your tasks** are what each project still needs, often before any agent knows about it. You add these yourself.",
                      "Nothing to set up: the app reads the agents' history on this Mac and checks for new work every 20 seconds.",
                  ], visual: .twoKinds),
        GuidePage(id: 1, title: "Five ways to look at it",
                  lead: "Switch views with the tabs or ⌘1 to ⌘5. The sidebar picks the scope: everything, one project, or one agent.",
                  points: [
                      "**Plan:** your tasks, project by project, with an add line under each.",
                      "**Board:** columns from Backlog to Done. Drag cards between them.",
                      "**List:** a sortable table of every ticket.",
                      "**Worklog:** what you asked and what your agents did, day by day.",
                      "**Insights:** requests per day, what's still open, which agent did the work, and when you work.",
                  ], visual: .views),
        GuidePage(id: 2, title: "What the columns mean",
                  lead: "Agent tickets move on their own, based on what happens in the session.",
                  points: [
                      "**In progress:** the agent is working now, or its plan still has open steps.",
                      "**Needs you:** the agent stopped with a question, or is waiting for your permission.",
                      "**Done:** the agent finished and you moved on. **To do:** you asked, but the session closed before an answer.",
                      "Drag a card to set its column yourself (marked with a hand). \"Use status from the agent\" undoes it.",
                  ], visual: .columns),
        GuidePage(id: 3, title: "Plan your own tasks",
                  lead: "Use the Plan view's add line, a column's add field, or ⌘N.",
                  points: [
                      "Type a title and press Return. Add `!high`, `!urgent` or `!low` to set the priority.",
                      "Without a backlog folder, tasks stay **on this Mac**.",
                      "**In a backlog folder** they're Markdown files in the repo, so your team and your agents read the same list. Choose *Keep Tasks in the Repo* in a project's menu to create one.",
                      "Existing `backlog/` folders, Backlog.md ones included, are found and filed under the right project.",
                  ], visual: .plan),
        GuidePage(id: 4, title: "Hand a task to any agent",
                  lead: "Start with picks the agent; the task goes along as its first message.",
                  points: [
                      "**Claude Code, Codex and Gemini CLI** open in Terminal, in the project folder. **Cursor and Antigravity** open the project, with the task on your clipboard.",
                      "Mention a task's key in any prompt, like \"work on **T-004**\", and that session links to the task, whichever agent ran it.",
                      "**Resume** reopens an agent's session right where it stopped.",
                  ], visual: .link),
        GuidePage(id: 5, title: "Stay on top of it",
                  lead: "You don't have to keep the window open.",
                  points: [
                      "The **menu bar** shows what's waiting on you, with the agent's question, plus what's running and today's numbers.",
                      "**Needs you** in the sidebar is your inbox: every place an agent is waiting.",
                      "A **notification** tells you when an agent stops to ask you something. Click it to open the ticket.",
                      "**Settings:** which agents to show, project folders, backlog folders, notifications.",
                      "Everything stays on your Mac. The agents' files are only read, never changed.",
                  ], visual: .stayOnTop),
    ]
}

struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    var body: some View {
        let p = Guide.pages[page]
        HStack(spacing: 0) {
            GuideIllustration(visual: p.visual)
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .background(Studio.blueBg)
            VStack(alignment: .leading, spacing: 14) {
                Text("\(page + 1) of \(Guide.pages.count)").font(Studio.text(12.5, .heavy)).foregroundStyle(Studio.muted)
                Text(p.title).font(Studio.display(28)).foregroundStyle(Studio.ink).fixedSize(horizontal: false, vertical: true)
                Text(p.lead).font(Studio.text(15, .semibold)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(p.points, id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle().fill(Studio.ink).frame(width: 5, height: 5).offset(y: -2)
                            Text(LocalizedStringKey(point)).font(Studio.text(13.5)).foregroundStyle(Studio.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(Guide.pages) { g in
                            Button { withAnimation(.snappy) { page = g.id } } label: {
                                Capsule().fill(g.id == page ? Studio.ink : Studio.line).frame(width: g.id == page ? 18 : 7, height: 7)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Page \(g.id + 1): \(g.title)")
                        }
                    }
                    Spacer()
                    if !Demo.isOn && page == Guide.pages.count - 1 {
                        Button("Try the demo") { DemoLauncher.open() }.buttonStyle(.studio(.secondary))
                    }
                    if page > 0 {
                        Button("Back") { withAnimation(.snappy) { page -= 1 } }.buttonStyle(.studio(.quiet))
                    } else {
                        Button("Skip") { dismiss() }.buttonStyle(.studio(.quiet))
                    }
                    if page < Guide.pages.count - 1 {
                        Button("Next") { withAnimation(.snappy) { page += 1 } }
                            .buttonStyle(.studio(.primary))
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Done") { dismiss() }.buttonStyle(.studio(.primary)).keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 900, height: 520)
        .background(Studio.surface)
        .onExitCommand { dismiss() }
    }
}

/// Small pictures built from the app's own components, so the guide matches the board.
struct GuideIllustration: View {
    let visual: GuideVisual

    var body: some View {
        VStack(spacing: 14) {
            switch visual {
            case .twoKinds:
                miniCard(project: "web", key: "WEB-10", title: "Faster product images", color: 0, chip: nil, ask: nil)
                    .rotationEffect(.degrees(-2))
                miniCard(project: "api", key: "API-6", title: "Shared rate-limit store", color: 1, chip: .codex, ask: "Redis, or sticky sessions?")
                    .rotationEffect(.degrees(1.5))
                    .padding(.leading, 30)
            case .views:
                VStack(spacing: 8) {
                    ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { i, m in
                        HStack {
                            Text(m.title).font(Studio.text(14, .bold))
                            Spacer()
                            Text("⌘\(i + 1)").font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(Studio.muted)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(m == .board ? Studio.ink : Studio.surface))
                        .foregroundStyle(m == .board ? Studio.onInk : Studio.ink)
                    }
                }
            case .columns:
                VStack(spacing: 10) {
                    ForEach(TaskStatus.allCases) { s in StatusBadge(status: s) }
                    StatusBadge(status: .done, overridden: true)
                }
            case .plan:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProjectDot(colorIndex: 2, size: 12)
                        Text("billing").font(Studio.display(17))
                    }
                    planLine("T-002", "Stripe webhooks fail after retries", .inProgress)
                    planLine("BIL-3", "CSV export for invoices", .todo)
                    Text("Add a task for billing…  !high")
                        .font(Studio.text(12, .medium)).foregroundStyle(Studio.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Studio.well))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Studio.surface))
            case .link:
                Text("“work on T-004 …”").font(Studio.text(14, .semibold).italic())
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Capsule().fill(Studio.surface))
                Image(systemName: "arrow.down").font(.system(size: 14, weight: .heavy)).foregroundStyle(Studio.muted)
                miniCard(project: "web", key: "T-004", title: "Checkout: one column on mobile", color: 0, chip: .claudeCode, ask: nil, working: true)
            case .stayOnTop:
                HStack(spacing: 6) {
                    Image(systemName: "checklist")
                    Text("3")
                }
                .font(Studio.display(18))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(Studio.surface))
                miniCard(project: "api", key: "API-6", title: "Shared rate-limit store", color: 1, chip: .codex, ask: "Redis, or sticky sessions?")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func miniCard(project: String, key: String, title: String, color: Int, chip: Agent?, ask: String?, working: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                ProjectDot(colorIndex: color, size: 8)
                Text("\(project) · \(key)").font(Studio.text(12, .bold)).foregroundStyle(Palette.ink(color))
                Spacer()
                if working { LiveDot(busy: true) }
            }
            Text(title).font(Studio.text(15, .bold)).foregroundStyle(Studio.ink)
            if let ask { Text("“\(ask)”").font(Studio.text(13.5, .semibold)).foregroundStyle(Studio.coralInk) }
            if let chip { AgentChip(agent: chip, text: working ? "\(chip.title) working" : nil, onWell: ask == nil) } else { Tag(text: "Your task") }
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ask == nil ? Palette.tint(color) : Studio.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(ask == nil ? .clear : Studio.coral, lineWidth: 2))
    }

    private func planLine(_ key: String, _ title: String, _ s: TaskStatus) -> some View {
        HStack(spacing: 8) {
            StatusRing(status: s, size: 16)
            Text(key).font(Studio.text(11.5, .bold).monospacedDigit()).foregroundStyle(Studio.muted)
            Text(title).font(Studio.text(13, .bold)).lineLimit(1)
        }
    }
}
