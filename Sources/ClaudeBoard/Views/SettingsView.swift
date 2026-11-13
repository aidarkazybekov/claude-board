import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @AppStorage("refreshSeconds") private var refreshSeconds = 20.0

    var body: some View {
        Form {
            RootsSection()
            FoldersSection()
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
                Spacer()
                Button("Get Started") {
                    UserDefaults.standard.set(true, forKey: "onboarded")
                    if UserDefaults.standard.stringArray(forKey: Roots.defaultsKey) == nil { Roots.all = Roots.all }
                    store.refresh(rediscover: true)
                    dismiss()
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
