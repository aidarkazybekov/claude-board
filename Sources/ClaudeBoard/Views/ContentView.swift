import SwiftUI

struct ContentView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            MainArea()
                .inspector(isPresented: $store.showInspector) {
                    Group {
                        if let t = store.task(store.selection) {
                            TaskDetailView(task: t)
                        } else {
                            ContentUnavailableView("No ticket selected", systemImage: "square.dashed",
                                                   description: Text("Pick a card to see the request, Claude's plan and the worklog."))
                        }
                    }
                    .inspectorColumnWidth(min: 340, ideal: 420, max: 620)
                }
        }
        .searchable(text: $store.search, placement: .toolbar, prompt: "Search tickets, keys, prompts")
        .toolbar { MainToolbar() }
        .sheet(isPresented: $store.showNewTask) { NewTaskSheet() }
        .sheet(isPresented: $store.showOnboarding) { OnboardingSheet() }
        .sheet(isPresented: $store.showGuide) { GuideSheet() }
        .sheet(isPresented: $store.showShareWeek) { ShareWeekSheet() }
        .sheet(isPresented: $store.showDiscovery) { DiscoverySheet() }
        .alert("ClaudeBoard", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            store.start()
            Snapshot.runIfRequested(store: store)
            // Opened at login: stay in the menu bar, in case the window came up anyway while launching
            // (e.g. restored). Later openings (menu bar, notification) set quietHandled first.
            if Startup.quiet && !Startup.quietHandled && !Demo.isOn {
                // A restored window is still being set up in onAppear; close it on the next turn.
                DispatchQueue.main.async {
                    dismissWindow(id: "main")
                    NSApp.windows.filter { $0.identifier?.rawValue.hasPrefix("main") == true }.forEach { $0.close() }
                    Store.debugLog("startup: closed the board window (quiet start)")
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
    }
}

struct MainToolbar: ToolbarContent {
    @Environment(Store.self) private var store

    var body: some ToolbarContent {
        @Bindable var store = store
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $store.mode) {
                ForEach(ViewMode.allCases) { m in
                    Label(m.title, systemImage: m.symbol).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .help("⌘1 Plan · ⌘2 Board · ⌘3 List · ⌘4 Worklog · ⌘5 Insights")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker("Show", selection: $store.source) {
                    ForEach(SourceFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Period", selection: $store.period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Show hidden tickets", isOn: $store.showHidden)
            } label: {
                Label(store.source == .all ? store.period.title : "\(store.source.title) · \(store.period.title)",
                      systemImage: store.source == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Filter by source (your tasks or Claude sessions) and period. Open tickets always show.")

            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .help("Re-read Claude sessions (⌘R)")

            Button {
                store.newTaskProject = store.scopeProjectID
                store.showNewTask = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .help("New task (⌘N)")

            Button {
                store.showInspector.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Toggle details (⌘I)")
        }
    }
}

struct MainArea: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            ScopeHeader()
            Divider()
            Group {
                switch store.mode {
                case .plan: PlanView()
                case .board: BoardView()
                case .list: ListView()
                case .worklog: WorklogView()
                case .insights: InsightsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(store.scopeTitle)
        .navigationSubtitle(store.lastIngestInfo)
    }
}

struct ScopeHeader: View {
    @Environment(Store.self) private var store

    var body: some View {
        let tasks = store.periodScoped
        let open = tasks.filter { $0.status.isOpen }
        HStack(spacing: 14) {
            if let pid = store.scopeProjectID {
                let info = store.project(pid)
                RoundedRectangle(cornerRadius: 3).fill(Palette.project(info.colorIndex)).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.name).font(.headline)
                    Text(info.relativePath).font(.caption).foregroundStyle(.secondary)
                }
                Text(info.key).font(.system(.caption, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            } else {
                Text(store.scopeTitle).font(.headline)
            }
            Spacer()
            stat("Needs you", open.filter { $0.status == .needsYou }.count, Palette.status(.needsYou))
            stat("In progress", open.filter { $0.status == .inProgress }.count, Palette.status(.inProgress))
            stat("Backlog", open.filter { $0.status == .backlog || $0.status == .todo }.count, Palette.status(.todo))
            stat("Done · \(store.period.title.lowercased())", tasks.filter { !$0.status.isOpen }.count, Palette.status(.done))
            if store.isRefreshing { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func stat(_ label: String, _ n: Int, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Text("\(n)").font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(c)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(Store.self) private var store
    @State private var expanded: Set<String> = []
    @State private var editing: ProjectInfo?
    @AppStorage("showAllRepos") private var showAllRepos = false

    var body: some View {
        @Bindable var store = store
        List(selection: $store.sidebar) {
            Section("Overview") {
                row(.inbox, "Needs You", "exclamationmark.bubble", Palette.status(.needsYou))
                row(.active, "In Progress", "circle.lefthalf.filled", Palette.status(.inProgress))
                row(.backlog, "Backlog & To Do", "tray", Palette.status(.todo))
                row(.all, "All Projects", "square.grid.2x2", .accentColor)
            }

            if !store.liveSessions.isEmpty {
                Section("Running now") {
                    ForEach(store.liveSessions.prefix(8)) { s in
                        Button {
                            if let t = store.latestTask(inSession: s.id) {
                                store.sidebar = .project(t.projectID)
                                store.selection = t.id
                                store.showInspector = true
                            }
                        } label: {
                            HStack(spacing: 7) {
                                LiveDot(busy: s.isBusy)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(s.title).lineLimit(1)
                                    Text(store.project(s.projectID).name).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Projects") {
                ForEach(store.workspaces, id: \.name) { ws in
                    if ws.projects.count == 1, let p = ws.projects.first {
                        projectRow(p)
                    } else {
                        DisclosureGroup(isExpanded: binding(ws.name)) {
                            ForEach(ws.projects) { p in projectRow(p) }
                        } label: {
                            HStack {
                                Label(ws.name, systemImage: "folder")
                                Spacer()
                                countBadge(store.count(.workspace(ws.name)))
                            }
                            .tag(SidebarItem.workspace(ws.name))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(item: $editing) { p in ProjectSettingsSheet(project: p) }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
            if Demo.isOn {
                HStack(spacing: 6) {
                    Image(systemName: "play.rectangle.on.rectangle").foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Demo board").font(.caption.weight(.semibold))
                        Text("Sample data. Your real data is untouched.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Quit Demo") { NSApp.terminate(nil) }.controlSize(.small)
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 10)
            }
            HStack {
                Button { store.showGuide = true } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.borderless)
                    .help("ClaudeBoard Guide (⌘/)")
                if let d = store.lastRefresh {
                    Text("Synced \(Fmt.ago(d))").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Toggle(isOn: Binding(get: { showAllRepos }, set: { showAllRepos = $0; store.refresh() })) {
                    Text("All repos").font(.caption2)
                }
                .toggleStyle(.checkbox)
                .controlSize(.mini)
                .help("Also list repos with no tasks or Claude sessions yet")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            }
        }
    }

    private func binding(_ ws: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(ws) || store.sidebar == .workspace(ws) || isChildSelected(ws) },
                set: { if $0 { expanded.insert(ws) } else { expanded.remove(ws) } })
    }

    private func isChildSelected(_ ws: String) -> Bool {
        if case .project(let p) = store.sidebar { return store.project(p).workspace == ws }
        return false
    }

    private func row(_ item: SidebarItem, _ title: String, _ icon: String, _ tint: Color) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            Spacer()
            countBadge(store.count(item))
        }
        .tag(item)
    }

    private func projectRow(_ p: ProjectInfo) -> some View {
        let planned = store.plannedOpenCount(p.id)
        return HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(Palette.project(p.colorIndex)).frame(width: 9, height: 9)
            Text(p.name).lineLimit(1)
            Spacer()
            if planned > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "checklist").font(.system(size: 9))
                    Text("\(planned)")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .help("\(planned) open task(s) you planned")
            }
            countBadge(store.count(.project(p.id)) - planned)
        }
        .tag(SidebarItem.project(p.id))
        .contextMenu {
            Button("Project Settings…") { editing = p }
            Button("New Task in \(p.name)…") {
                store.newTaskProject = p.id
                store.showNewTask = true
            }
            Button("Copy Open Tasks for Claude") { store.copyPlanForClaude(p.id) }
            if store.folders(for: p.id).isEmpty && p.id.hasPrefix("/") {
                Button("Keep Tasks in the Repo (create backlog/)") { store.createBacklogFolder(for: p.id) }
            }
            if p.id.hasPrefix("/") {
                Button("Open Folder") { NSWorkspace.shared.open(URL(fileURLWithPath: p.id)) }
            }
            Divider()
            Button("Hide Project") { store.updateProject(p.id) { $0.hidden = true } }
        }
    }

    @ViewBuilder
    private func countBadge(_ n: Int) -> some View {
        if n > 0 {
            Text("\(n)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

struct ProjectSettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let project: ProjectInfo
    @State private var name = ""
    @State private var key = ""
    @State private var color = 0
    @State private var aliases = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder", value: project.relativePath)
                TextField("Display name", text: $name)
                TextField("Ticket key prefix", text: $key)
                TextField("Also called", text: $aliases, prompt: Text("e.g. fe, front end"))
                    .help("Other names used in task titles, so backlog tasks that mention them land in this project")
                Picker("Color", selection: $color) {
                    ForEach(0..<Palette.projectColors.count, id: \.self) { i in
                        HStack {
                            RoundedRectangle(cornerRadius: 3).fill(Palette.project(i)).frame(width: 14, height: 14)
                            Text("Color \(i + 1)")
                        }
                        .tag(i)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.updateProject(project.id) {
                        $0.name = name.isEmpty ? nil : name
                        $0.key = key.isEmpty ? nil : key.uppercased()
                        $0.colorIndex = color
                        let a = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        $0.aliases = a.isEmpty ? nil : a
                    }
                    dismiss()
                }
            }
        }
        .onAppear {
            let s = store.projectSettings(project.id)
            name = s.name ?? ""
            key = s.key ?? ""
            color = project.colorIndex
            aliases = (s.aliases ?? []).joined(separator: ", ")
        }
    }
}
