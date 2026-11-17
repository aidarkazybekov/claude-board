import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @AppStorage("refreshSeconds") private var refreshSeconds = 20.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(Studio.display(24)).foregroundStyle(Studio.ink)
                AgentsSection()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 18, alignment: .top)], alignment: .leading, spacing: 18) {
                    RootsSection()
                    FoldersSection()
                    NotificationsSection()
                    StartupSection()
                }
                SettingsCard("Your data") {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Your own tasks, statuses and notes stay on this Mac in \(Paths.tilde(Paths.appSupport.path)). Agent history is only read, never changed or uploaded.")
                            .font(Studio.text(13, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.open(Paths.appSupport) }.buttonStyle(.studio(.secondary, size: 12))
                    }
                    HStack(spacing: 12) {
                        Text("Check for new work every").font(Studio.text(13, .bold)).foregroundStyle(Studio.ink)
                        Stepper("\(Int(refreshSeconds)) seconds", value: $refreshSeconds, in: 5...300, step: 5)
                            .font(Studio.text(13, .semibold))
                        Text("Takes effect on next launch. Each check reads only what's new.").font(Studio.text(12, .medium)).foregroundStyle(Studio.muted)
                    }
                    if !store.hiddenProjects.isEmpty {
                        FlowRow(spacing: 8) {
                            Text("Hidden projects").font(Studio.text(13, .bold)).foregroundStyle(Studio.ink)
                            ForEach(store.hiddenProjects) { p in
                                HStack(spacing: 8) {
                                    Text(p.name).font(Studio.text(12.5, .bold))
                                    Button("Unhide") { store.updateProject(p.id) { $0.hidden = nil } }.buttonStyle(.studio(.white, size: 11.5))
                                }
                                .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 3)
                                .background(Capsule().fill(Studio.well))
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(Studio.ground)
        .frame(minWidth: 820, minHeight: 640)
    }
}

/// A titled white card used across Settings.
struct SettingsCard<Content: View>: View {
    let title: String
    var detail: String?
    let content: Content

    init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Studio.display(17)).foregroundStyle(Studio.ink)
                if let detail { Text(detail).font(Studio.text(12.5, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true) }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioCard(radius: Studio.radiusPanel, padding: 20)
    }
}

/// Which coding agents are on this Mac, and which of them show on the board.
struct AgentsSection: View {
    @Environment(Store.self) private var store

    var body: some View {
        SettingsCard("Agents on this Mac", detail: "Their history is read, never changed. Turn one off and its work leaves the board.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 10)], spacing: 10) {
                ForEach(Agent.allCases) { a in AgentRow(agent: a) }
            }
        }
    }
}

struct AgentRow: View {
    @Environment(Store.self) private var store
    let agent: Agent

    var body: some View {
        let found = FileManager.default.fileExists(atPath: Paths.data(for: agent))
        let readable = agent == .claudeCode || agent == .codex
        let stats = store.agentStats(agent)
        let on = !store.disabledAgents.contains(agent)
        HStack(spacing: 12) {
            AgentAvatar(agent: agent, size: 34).opacity(found ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.title).font(Studio.text(14, .heavy)).foregroundStyle(Studio.ink)
                Text(detail(found: found, readable: readable, stats: stats))
                    .font(Studio.text(12, .semibold)).foregroundStyle(Studio.ink2).lineLimit(2)
            }
            Spacer(minLength: 6)
            if found && readable {
                Toggle("Show \(agent.title)", isOn: Binding(get: { on }, set: { store.setAgent(agent, enabled: $0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Studio.ink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Studio.well))
    }

    private func detail(found: Bool, readable: Bool, stats: (sessions: Int, requests: Int, projects: Int, last: Date?)) -> String {
        guard found else { return "Not found on this Mac" }
        guard readable else { return "Found. Reading its chats isn't supported yet." }
        if stats.sessions == 0 { return "Found · no sessions yet · \(Paths.tilde(Paths.data(for: agent)))" }
        let last = stats.last.map { " · last \(Fmt.ago($0))" } ?? ""
        return "\(stats.sessions) session\(stats.sessions == 1 ? "" : "s") in \(stats.projects) project\(stats.projects == 1 ? "" : "s")\(last)"
    }
}

/// Folders that hold projects. Every git repo inside becomes a project.
struct StartupSection: View {
    @AppStorage(Startup.dockKey) private var showInDock = true
    @State private var login = Startup.loginItem
    @State private var error: String?

    var body: some View {
        SettingsCard("Startup and menu bar") {
            switchRow("Open at login", detail: login == .unavailable ? "Works in the installed app, not the demo or a `swift run` build." : "Starts quietly in the menu bar, so alerts keep coming.",
                      isOn: Binding(get: { login == .on || login == .needsApproval },
                                    set: { on in
                                        do { try Startup.setOpenAtLogin(on); error = nil } catch { self.error = error.localizedDescription }
                                        login = Startup.loginItem
                                    }))
                .disabled(login == .unavailable)
            if login == .needsApproval {
                HStack {
                    Text("macOS needs your OK in Login Items.").font(Studio.text(12.5, .semibold)).foregroundStyle(Studio.coralInk)
                    Spacer()
                    Button("Open Login Items") { Startup.openLoginItemsSettings() }.buttonStyle(.studio(.secondary, size: 12))
                }
            }
            if let error { Text(error).font(Studio.text(12, .semibold)).foregroundStyle(Studio.coralInk) }
            switchRow("Show in the Dock", detail: "Off keeps it in the menu bar only.", isOn: $showInDock)
                .onChange(of: showInDock) { _, _ in Startup.applyDockPolicy() }
        }
        .onAppear { login = Startup.loginItem }
    }
}

/// A row with a title, one line of detail and a black switch.
func switchRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
    HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Studio.text(13.5, .bold)).foregroundStyle(Studio.ink)
            Text(detail).font(Studio.text(12, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        Toggle(title, isOn: isOn).toggleStyle(.switch).labelsHidden().tint(Studio.ink)
    }
}

struct NotificationsSection: View {
    @Environment(Store.self) private var store
    @AppStorage(Notifier.needsYouKey) private var needsYou = true
    @AppStorage(Notifier.doneKey) private var done = false

    var body: some View {
        SettingsCard("Notifications", detail: "Only real changes while the app runs: nothing at launch, never the same question twice.") {
            switchRow("When an agent is waiting on you", detail: "A question, a permission, or a plan to approve.", isOn: $needsYou)
            switchRow("When an agent finishes", detail: "Grouped when several finish at once.", isOn: $done)
            if !Notifier.available {
                Text("Notifications work in the installed app, not in the demo or a `swift run` build.")
                    .font(Studio.text(12, .medium)).foregroundStyle(Studio.muted)
            } else if store.notificationsAllowed == false {
                HStack {
                    Text("macOS has notifications turned off for this app.").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.coralInk)
                    Spacer()
                    Button("Open Settings") { Notifier.openSystemSettings() }.buttonStyle(.studio(.secondary, size: 12))
                }
                .studioWell(radius: 14, padding: 10)
            } else {
                HStack {
                    Text(store.notificationsAllowed == nil ? "macOS asks for permission the first time one is sent." : "Allowed in System Settings")
                        .font(Studio.text(12.5, .bold))
                        .foregroundStyle(store.notificationsAllowed == nil ? Studio.ink2 : Studio.doneInk)
                    Spacer()
                    Button("Send a test") { Notifier.shared.sendTest() }.buttonStyle(.studio(.white, size: 12))
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(store.notificationsAllowed == nil ? Studio.well : Studio.doneBg))
            }
        }
        .onAppear { Notifier.shared.refreshAuthorization() }
    }
}

struct RootsSection: View {
    @Environment(Store.self) private var store
    @State private var roots: [String] = Roots.all

    var body: some View {
        SettingsCard("Project folders", detail: "Every git repo inside these folders is a project. Agent sessions are filed under the repo they ran in.") {
            VStack(spacing: 8) {
                ForEach(roots, id: \.self) { r in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").foregroundStyle(Studio.muted)
                        Text(Paths.tilde(r)).font(Studio.text(13, .bold)).foregroundStyle(Studio.ink).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button { remove(r) } label: { Image(systemName: "minus").font(.system(size: 11, weight: .heavy)).frame(width: 24, height: 24).background(Circle().fill(Studio.surface)) }
                            .buttonStyle(.plain)
                            .disabled(roots.count <= 1)
                            .help("Stop looking in this folder")
                            .accessibilityLabel("Remove \(Paths.tilde(r))")
                    }
                    .studioWell(radius: 14, padding: 10)
                }
            }
            HStack {
                Button("Add folder…") { pick() }.buttonStyle(.studio(.primary, size: 12.5))
                Spacer()
                Text("\(store.repos.count) repos found").font(Studio.text(12.5, .semibold)).foregroundStyle(Studio.muted)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for u in panel.urls where !roots.contains(u.path) { roots.append(u.path) }
        store.setRoots(roots)
    }

    private func remove(_ r: String) {
        roots.removeAll { $0 == r }
        store.setRoots(roots)
    }
}

/// Backlog folders: Markdown task files the app reads and edits.
struct FoldersSection: View {
    @Environment(Store.self) private var store

    var body: some View {
        SettingsCard("Backlog folders", detail: "Planned tasks kept in the repo, one Markdown file per task, so your team and your agents see the same list. Found automatically as backlog/ folders. Works with Backlog.md too.") {
            if store.taskFolders.isEmpty {
                Text("None yet. Create one from a project's menu (Keep Tasks in the Repo), or add an existing folder.")
                    .font(Studio.text(12.5, .medium)).foregroundStyle(Studio.muted)
            }
            VStack(spacing: 8) {
                ForEach(store.taskFolders, id: \.self) { f in
                    HStack(spacing: 10) {
                        Image(systemName: "checklist").foregroundStyle(Studio.muted)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Paths.tilde(f)).font(Studio.text(13, .bold)).foregroundStyle(Studio.ink).lineLimit(1).truncationMode(.head)
                            Text("\(store.items.filter { $0.folder == f }.count) tasks").font(Studio.text(12, .semibold)).foregroundStyle(Studio.muted)
                        }
                        Spacer()
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) }
                            .buttonStyle(.studio(.white, size: 11.5))
                        Button { store.ignoreFolder(f) } label: { Image(systemName: "minus").font(.system(size: 11, weight: .heavy)).frame(width: 24, height: 24).background(Circle().fill(Studio.surface)) }
                            .buttonStyle(.plain)
                            .help("Stop reading this folder")
                            .accessibilityLabel("Stop reading \(Paths.tilde(f))")
                    }
                    .studioWell(radius: 14, padding: 10)
                }
            }
            Button("Add backlog folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Add"
                if panel.runModal() == .OK, let u = panel.url { store.addFolder(u.path) }
            }
            .buttonStyle(.studio(.secondary, size: 12.5))
        }
    }
}

struct OnboardingSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("One board for every coding agent").font(Studio.display(30)).foregroundStyle(Studio.ink)
                Text("Every task you give Claude Code, Codex and other agents, plus the tasks you plan yourself, on one board per project.")
                    .font(Studio.text(15, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 12) {
                point("Agents' work, found for you", "Each request becomes a ticket with its plan, outcome, and whether the agent is waiting on you. Read-only.", tint: Studio.blueBg)
                point("Your own tasks per project", "Plan what each project still needs. Hand any task to any agent in one click.", tint: Palette.tint(1))
                point("Shared through the repo", "Keep tasks as Markdown files in backlog/, so your team and your agents read the same list.", tint: Studio.doneBg)
            }
            RootsSection()
            HStack {
                Button("Try the demo first") { DemoLauncher.open() }
                    .buttonStyle(.studio(.secondary))
                    .help("Opens a second copy with sample projects, so you can click around safely")
                Spacer()
                Button("Get started") {
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    if UserDefaults.standard.stringArray(forKey: Roots.defaultsKey) == nil { Roots.all = Roots.all }
                    store.refresh(rediscover: true)
                    dismiss()
                    // The first "aha": what the app found in the agents' history.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.showDiscovery = true }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.studio(.primary, size: 14))
            }
        }
        .padding(28)
        .frame(width: 760)
        .background(Studio.ground)
    }

    private func point(_ title: String, _ text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Studio.text(14, .heavy)).foregroundStyle(Studio.ink)
            Text(text).font(Studio.text(12.5, .medium)).foregroundStyle(Studio.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint))
    }
}
