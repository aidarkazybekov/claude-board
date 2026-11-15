import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @AppStorage("refreshSeconds") private var refreshSeconds = 20.0

    var body: some View {
        Form {
            RootsSection()
            FoldersSection()
            StartupSection()
            NotificationsSection()
            Section("Claude Code data (read-only)") {
                LabeledContent("Transcripts", value: Paths.tilde(Paths.projectsDir))
                LabeledContent("Prompt history", value: Paths.tilde(Paths.historyFile))
                LabeledContent("Desktop sessions", value: "~/Library/Application Support/Claude")
            }
            Section("Sync") {
                Stepper("Refresh every \(Int(refreshSeconds)) s", value: $refreshSeconds, in: 5...300, step: 5)
                Text("Takes effect on next launch. Each refresh reads only new bytes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("ClaudeBoard data") {
                LabeledContent("Stored in", value: Paths.tilde(Paths.appSupport.path))
                Button("Show in Finder") { NSWorkspace.shared.open(Paths.appSupport) }
                ForEach(store.hiddenProjects) { p in
                    HStack {
                        Text("Hidden project: \(p.name)")
                        Spacer()
                        Button("Unhide") { store.updateProject(p.id) { $0.hidden = nil } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 560)
    }
}

/// Folders that hold projects. Every git repo inside becomes a project.
struct StartupSection: View {
    @AppStorage(Startup.dockKey) private var showInDock = true
    @State private var login = Startup.loginItem
    @State private var error: String?

    var body: some View {
        Section {
            Toggle("Open ClaudeBoard at login", isOn: Binding(
                get: { login == .on || login == .needsApproval },
                set: { on in
                    do { try Startup.setOpenAtLogin(on); error = nil } catch { self.error = error.localizedDescription }
                    login = Startup.loginItem
                }))
                .disabled(login == .unavailable)
            if login == .needsApproval {
                HStack {
                    Text("macOS needs your OK in Login Items.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items") { Startup.openLoginItemsSettings() }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Toggle("Show ClaudeBoard in the Dock", isOn: $showInDock)
                .onChange(of: showInDock) { _, _ in Startup.applyDockPolicy() }
        } header: {
            Text("Menu bar and startup")
        } footer: {
            Text(login == .unavailable
                 ? "Open at login works in the installed app, not in the demo or a `swift run` build."
                 : "At login it starts quietly in the menu bar, so notifications keep coming. Without the Dock icon, open the board from the menu bar.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { login = Startup.loginItem }
    }
}

struct NotificationsSection: View {
    @Environment(Store.self) private var store
    @AppStorage(Notifier.needsYouKey) private var needsYou = true
    @AppStorage(Notifier.doneKey) private var done = false

    var body: some View {
        Section {
            Toggle("When Claude is waiting on you", isOn: $needsYou)
            Toggle("When Claude finishes a request", isOn: $done)
            if !Notifier.available {
                Text("Notifications work in the installed app, not in the demo or a `swift run` build.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if store.notificationsAllowed == false {
                HStack {
                    Text("macOS has notifications turned off for ClaudeBoard.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Notification Settings") { Notifier.openSystemSettings() }
                }
            } else {
                HStack {
                    Text(store.notificationsAllowed == nil ? "macOS asks for permission the first time one is sent."
                                                           : "Click one to open its ticket. Resume in Terminal answers right away.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Send a Test Notification") { Notifier.shared.sendTest() }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Only real changes while ClaudeBoard runs: nothing at launch, never the same question twice.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { Notifier.shared.refreshAuthorization() }
    }
}

struct RootsSection: View {
    @Environment(Store.self) private var store
    @State private var roots: [String] = Roots.all

    var body: some View {
        Section {
            ForEach(roots, id: \.self) { r in
                HStack {
                    Image(systemName: "folder")
                    Text(Paths.tilde(r))
                    Spacer()
                    Button { remove(r) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .disabled(roots.count <= 1)
                }
            }
            HStack {
                Button("Add Folder…") { pick() }
                Spacer()
                Text("\(store.repos.count) repos found").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Project roots")
        } footer: {
            Text("Every git repo inside these folders is a project. Claude sessions are filed under the repo they ran in.")
                .font(.caption).foregroundStyle(.secondary)
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

/// Backlog folders: markdown task files ClaudeBoard reads and edits.
struct FoldersSection: View {
    @Environment(Store.self) private var store

    var body: some View {
        Section {
            if store.taskFolders.isEmpty {
                Text("None found yet. Create one from a project's menu (“Keep Tasks in the Repo”), or add an existing folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.taskFolders, id: \.self) { f in
                HStack {
                    Image(systemName: "checklist")
                    VStack(alignment: .leading) {
                        Text(Paths.tilde(f)).lineLimit(1).truncationMode(.head)
                        Text("\(store.items.filter { $0.folder == f }.count) tasks").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)]) }
                        .buttonStyle(.link)
                    Button { store.ignoreFolder(f) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Stop reading this folder")
                }
            }
            Button("Add Backlog Folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Add"
                if panel.runModal() == .OK, let u = panel.url { store.addFolder(u.path) }
            }
        } header: {
            Text("Backlog folders")
        } footer: {
            Text("One markdown file per task with `id`, `title`, `status`, `priority` front matter, optionally indexed by BACKLOG.md. Found automatically as backlog/ folders inside your roots. Works with Backlog.md too.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct OnboardingSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to ClaudeBoard").font(.title2.weight(.semibold))
                    Text("A task board for your projects and everything you ask Claude Code.")
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                point("sparkle", "Claude's work, tracked for you",
                      "Every request you give Claude Code becomes a ticket, with its plan, outcome and whether Claude is waiting on you. Read from ~/.claude; nothing is changed there.")
                point("checklist", "Your own tasks per project",
                      "Plan what each app still needs, before Claude knows about it. Mention a task's key in any Claude prompt and the session links to it.")
                point("person.2", "Shared through the repo when you want",
                      "Tasks can live in a project's backlog/ folder as markdown files, so teammates and Claude read the same list.")
            }
            Form {
                RootsSection()
            }
            .formStyle(.grouped)
            .frame(height: 210)
            HStack {
                Button("Try the Demo Board First") { DemoLauncher.open() }
                    .help("Opens a second window with sample projects, so you can click around safely")
                Spacer()
                Button("Get Started") {
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    if UserDefaults.standard.stringArray(forKey: Roots.defaultsKey) == nil { Roots.all = Roots.all }
                    store.refresh(rediscover: true)
                    dismiss()
                    // The first "aha": show what ClaudeBoard found in the user's Claude history.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.showDiscovery = true }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    private func point(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
