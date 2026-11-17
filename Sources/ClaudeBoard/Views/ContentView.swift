import SwiftUI

struct ContentView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 252, max: 340)
        } detail: {
            MainArea()
                .inspector(isPresented: $store.showInspector) {
                    SelectedDetail()
                        .inspectorColumnWidth(min: 360, ideal: 430, max: 640)
                }
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
        .frame(minWidth: 1000, minHeight: 620)
    }
}

// MARK: - Main area

struct MainArea: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            StudioHeader()
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
        .background(Studio.ground)
    }
}

/// Title, a one-line summary, search and New task; then the view tabs and filters.
struct StudioHeader: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                titleBlock
                Spacer(minLength: 12)
                if store.isRefreshing {
                    ProgressView().controlSize(.small).help("Reading agent sessions…")
                }
                StudioSearchField(text: $store.search)
                    .frame(minWidth: 180, idealWidth: 260, maxWidth: 300)
                Button {
                    store.newTaskProject = store.scopeProjectID
                    store.showNewTask = true
                } label: {
                    Label("New task", systemImage: "plus")
                }
                .buttonStyle(.studio(.primary))
                .help("New task (⌘N)")
            }
            HStack(spacing: 10) {
                PillTabs(selection: $store.mode, items: ViewMode.allCases.map { ($0, $0.title) })
                    .help("⌘1 Plan · ⌘2 Board · ⌘3 List · ⌘4 Worklog · ⌘5 Insights")
                Spacer(minLength: 8)
                sourceMenu
                periodMenu
                CircleIconButton(symbol: "arrow.clockwise", help: "Refresh (⌘R)") { store.refresh() }
                CircleIconButton(symbol: "sidebar.trailing", help: store.showInspector ? "Hide details (⌘I)" : "Show details (⌘I)",
                                 filled: store.showInspector) { store.showInspector.toggle() }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    @ViewBuilder private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                if let pid = store.scopeProjectID {
                    let info = store.project(pid)
                    ProjectDot(colorIndex: info.colorIndex, size: 16)
                    Text(info.name).font(Studio.display(28)).foregroundStyle(Studio.ink).lineLimit(1)
                    Tag(text: info.key, color: Palette.ink(info.colorIndex), fill: Palette.tint(info.colorIndex))
                } else if case .agent(let a) = store.scope {
                    AgentAvatar(agent: a, size: 26)
                    Text(a.title).font(Studio.display(28)).foregroundStyle(Studio.ink).lineLimit(1)
                } else {
                    Text(store.scopeTitle).font(Studio.display(28)).foregroundStyle(Studio.ink).lineLimit(1)
                }
            }
            summary
                .font(Studio.text(14, .medium))
                .foregroundStyle(Studio.ink2)
                .lineLimit(1)
        }
    }

    private var summary: Text {
        let open = store.periodScoped.filter { $0.status.isOpen }
        let needs = open.filter { $0.status == .needsYou }.count
        let running = open.filter { $0.status == .inProgress }.count
        let queued = open.filter { $0.status == .backlog || $0.status == .todo }.count
        var rest: [String] = []
        if running > 0 { rest.append("\(running) running") }
        if queued > 0 { rest.append("\(queued) waiting to start") }
        let tail = rest.isEmpty ? (needs == 0 ? "Nothing open right now." : "") : rest.joined(separator: ", ") + "."
        if needs > 0 {
            return Text("\(needs) need\(needs == 1 ? "s" : "") you. ").foregroundStyle(Studio.coralInk).fontWeight(.bold) + Text(tail)
        }
        if let pid = store.scopeProjectID {
            return Text(store.project(pid).relativePath + " · ") + Text(tail)
        }
        return Text(tail)
    }

    private var sourceMenu: some View {
        @Bindable var store = store
        return Menu {
            Picker("Show", selection: $store.source) {
                ForEach(SourceFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Show hidden tickets", isOn: $store.showHidden)
        } label: {
            HeaderMenuLabel(text: store.source.title, active: store.source != .all || store.showHidden)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Your tasks, agent work, or both. Open tickets always show.")
    }

    private var periodMenu: some View {
        @Bindable var store = store
        return Menu {
            Picker("Period", selection: $store.period) {
                ForEach(Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HeaderMenuLabel(text: store.period == .all ? "All time" : store.period == .day ? "Today" : "Last \(store.period.title)", active: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Finished work from this period. Open tickets always show.")
    }
}

struct HeaderMenuLabel: View {
    let text: String
    var active = false
    var body: some View {
        HStack(spacing: 5) {
            Text(text)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .font(Studio.text(12.5, .semibold))
        .foregroundStyle(active ? Studio.onInk : Studio.ink)
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .background(Capsule().fill(active ? Studio.ink : Studio.surface))
        .overlay(Capsule().stroke(Studio.line, lineWidth: active ? 0 : 1))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(Store.self) private var store
    @State private var collapsed: Set<String> = []
    @State private var editing: ProjectInfo?
    @AppStorage("showAllRepos") private var showAllRepos = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 3) {
                    row(.inbox, "Needs you", coral: true)
                    row(.active, "In progress")
                    row(.backlog, "Backlog & to do")
                    row(.all, "All projects")
                }

                if !store.liveSessions.isEmpty {
                    section("Running now") {
                        ForEach(store.liveSessions.prefix(8)) { s in
                            Button {
                                if let t = store.latestTask(inSession: s.id) {
                                    store.sidebar = .project(t.projectID)
                                    store.selection = t.id
                                    store.showInspector = true
                                }
                            } label: {
                                HStack(spacing: 9) {
                                    LiveDot(busy: s.isBusy).padding(.horizontal, 3)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(s.title).font(Studio.text(13, .semibold)).foregroundStyle(Studio.ink).lineLimit(1)
                                        Text("\(store.project(s.projectID).name) · \(s.agentKind.title)")
                                            .font(Studio.text(11.5, .medium)).foregroundStyle(Studio.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                let agents = store.agentsOnBoard
                if !agents.isEmpty {
                    section("Agents") {
                        ForEach(agents, id: \.agent) { a in
                            sidebarButton(.agent(a.agent)) { on in
                                HStack(spacing: 10) {
                                    AgentAvatar(agent: a.agent, size: 22)
                                    Text(a.agent.title).font(Studio.text(13, .semibold)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    if a.live {
                                        Text("running").font(Studio.text(11, .bold))
                                            .foregroundStyle(on ? Studio.onInk : Studio.live)
                                    }
                                    if a.open > 0 { Text("\(a.open)").font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(on ? Studio.onInk : Studio.muted) }
                                }
                            }
                        }
                    }
                }

                section("Projects") {
                    let wss = store.workspaces
                    ForEach(wss, id: \.name) { ws in
                        if wss.count > 1 && ws.projects.count > 1 {
                            workspaceHeader(ws.name)
                            if !collapsed.contains(ws.name) {
                                ForEach(ws.projects) { p in projectRow(p, indent: true) }
                            }
                        } else {
                            ForEach(ws.projects) { p in projectRow(p, indent: false) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
        .background(Studio.surface)
        .sheet(item: $editing) { p in ProjectSettingsSheet(project: p) }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if Demo.isOn {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Demo board").font(Studio.text(12, .bold)).foregroundStyle(Studio.ink)
                        Text("Sample data. Your real data is untouched.").font(Studio.text(11, .medium)).foregroundStyle(Studio.muted)
                    }
                    Spacer()
                    Button("Quit Demo") { NSApp.terminate(nil) }.buttonStyle(.studio(.primary, size: 11.5))
                }
                .studioWell(radius: 14, padding: 10)
            }
            HStack(spacing: 8) {
                Button("Guide") { store.showGuide = true }
                    .buttonStyle(.studio(.secondary, size: 11.5))
                    .help("Guide (⌘/)")
                if let d = store.lastRefresh {
                    Text("Synced \(Fmt.ago(d))").font(Studio.text(11, .medium)).foregroundStyle(Studio.faint).lineLimit(1)
                }
                Spacer(minLength: 4)
                Toggle(isOn: Binding(get: { showAllRepos }, set: { showAllRepos = $0; store.refresh() })) {
                    Text("All repos").font(Studio.text(11, .semibold)).foregroundStyle(Studio.muted)
                }
                .toggleStyle(.checkbox)
                .controlSize(.mini)
                .help("Also list repos with no tasks or agent sessions yet")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Studio.surface)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Studio.text(12, .bold)).foregroundStyle(Studio.muted).padding(.horizontal, 10).padding(.bottom, 4)
            content()
        }
    }

    private func row(_ item: SidebarItem, _ title: String, coral: Bool = false) -> some View {
        let n = store.count(item)
        let on = store.sidebar == item
        return Button { store.sidebar = item } label: {
            HStack(spacing: 10) {
                Text(title).font(Studio.text(13.5, coral && n > 0 ? .bold : .semibold))
                Spacer(minLength: 4)
                if n > 0 {
                    if coral {
                        Text("\(n)").font(Studio.text(12, .heavy).monospacedDigit())
                            .foregroundStyle(on ? Studio.ink : .white)
                            .padding(.horizontal, 8).padding(.vertical, 1)
                            .background(Capsule().fill(on ? Studio.onInk : Studio.coral))
                    } else {
                        Text("\(n)").font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(on ? Studio.onInk.opacity(0.8) : Studio.muted)
                    }
                }
            }
            .foregroundStyle(on ? Studio.onInk : (coral && n > 0 ? Studio.coralInk : Studio.ink))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(on ? Studio.ink : (coral && n > 0 ? Studio.coralBg : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarButton<L: View>(_ item: SidebarItem, @ViewBuilder label: (Bool) -> L) -> some View {
        let on = store.sidebar == item
        return Button { store.sidebar = item } label: {
            label(on)
                .foregroundStyle(on ? Studio.onInk : Studio.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Studio.ink : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func workspaceHeader(_ name: String) -> some View {
        let open = !collapsed.contains(name)
        return HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if open { collapsed.insert(name) } else { collapsed.remove(name) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .heavy))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Studio.muted)
            .accessibilityLabel(open ? "Collapse \(name)" : "Expand \(name)")
            Button { store.sidebar = .workspace(name) } label: {
                HStack {
                    Text(name).font(Studio.text(12.5, .bold))
                    Spacer()
                    let n = store.count(.workspace(name))
                    if n > 0 { Text("\(n)").font(Studio.text(12, .bold).monospacedDigit()).foregroundStyle(Studio.muted) }
                }
                .foregroundStyle(store.sidebar == .workspace(name) ? Studio.ink : Studio.ink2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .padding(.top, 4)
    }

    private func projectRow(_ p: ProjectInfo, indent: Bool) -> some View {
        let planned = store.plannedOpenCount(p.id)
        let on = store.sidebar == .project(p.id)
        let other = store.count(.project(p.id)) - planned
        return Button { store.sidebar = .project(p.id) } label: {
            HStack(spacing: 9) {
                ProjectDot(colorIndex: p.colorIndex, size: 10)
                Text(p.name).font(Studio.text(13, on ? .bold : .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if planned > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "checklist").font(.system(size: 9, weight: .bold))
                        Text("\(planned)")
                    }
                    .font(Studio.text(11.5, .bold).monospacedDigit())
                    .foregroundStyle(on ? Palette.ink(p.colorIndex) : Studio.muted)
                    .help("\(planned) open task\(planned == 1 ? "" : "s") you planned")
                }
                if other > 0 {
                    Text("\(other)").font(Studio.text(12, .bold).monospacedDigit())
                        .foregroundStyle(on ? Palette.ink(p.colorIndex) : Studio.muted)
                        .help("\(other) open agent ticket\(other == 1 ? "" : "s")")
                }
            }
            .foregroundStyle(on ? Palette.ink(p.colorIndex) : Studio.ink)
            .padding(.leading, indent ? 22 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Palette.tint(p.colorIndex) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Project Settings…") { editing = p }
            Button("New Task in \(p.name)…") {
                store.newTaskProject = p.id
                store.showNewTask = true
            }
            Button("Copy Open Tasks for an Agent") { store.copyPlanForClaude(p.id) }
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
}

// MARK: - Project settings

struct ProjectSettingsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let project: ProjectInfo
    @State private var name = ""
    @State private var key = ""
    @State private var color = 0
    @State private var aliases = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.project(color)).frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name.isEmpty ? project.name : name).font(Studio.display(22)).foregroundStyle(Studio.ink)
                    Text("\(Paths.tilde(project.id)) · read-only").font(Studio.text(12.5, .medium)).foregroundStyle(Studio.muted).lineLimit(1)
                }
            }
            HStack(spacing: 12) {
                WellField(title: "Display name", text: $name, prompt: project.name)
                WellField(title: "Key prefix", text: $key, prompt: project.key)
            }
            VStack(alignment: .leading, spacing: 6) {
                WellField(title: "Also called", text: $aliases, prompt: "storefront, shop")
                Text("When a prompt or task mentions one of these names, the work lands in \(name.isEmpty ? project.name : name).")
                    .font(Studio.text(12, .medium)).foregroundStyle(Studio.muted)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(Studio.text(12.5, .bold)).foregroundStyle(Studio.ink2)
                HStack(spacing: 10) {
                    ForEach(0..<Palette.projectBase.count, id: \.self) { i in
                        Button { color = i } label: {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Palette.project(i))
                                .frame(width: 30, height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(color == i ? Studio.ink : .clear, lineWidth: 2).padding(-4))
                        }
                        .buttonStyle(.plain)
                        .help(Palette.projectNames[i])
                        .accessibilityLabel(Palette.projectNames[i])
                        .accessibilityAddTraits(color == i ? .isSelected : [])
                    }
                }
                .padding(.leading, 4)
            }
            if let folder = store.folders(for: project.id).first {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Planned tasks are saved in \(Paths.tilde(folder))").font(Studio.text(13, .bold)).foregroundStyle(Studio.ink)
                        Text("Markdown files, shared with everyone who clones the repo").font(Studio.text(12, .medium)).foregroundStyle(Studio.muted)
                    }
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)]) }
                        .buttonStyle(.studio(.white, size: 12))
                }
                .studioWell(radius: 16, padding: 12)
            }
            HStack(spacing: 10) {
                Button("Hide project") {
                    store.updateProject(project.id) { $0.hidden = true }
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(Studio.text(13, .bold))
                .foregroundStyle(Studio.coralInk)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.studio(.secondary)).keyboardShortcut(.cancelAction)
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
                .buttonStyle(.studio(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 560)
        .background(Studio.surface)
        .onAppear {
            let s = store.projectSettings(project.id)
            name = s.name ?? ""
            key = s.key ?? ""
            color = project.colorIndex
            aliases = (s.aliases ?? []).joined(separator: ", ")
        }
    }
}
