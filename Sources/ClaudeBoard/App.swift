import SwiftUI

struct ClaudeBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: Store

    init() {
        let s = Store()
        _store = State(initialValue: s)
        Notifier.shared.attach(s)
        Notifier.shared.refreshAuthorization()
        // Auto-refresh starts with the app, not with a view: it must keep running when the window is
        // closed or was never opened (macOS can restore it closed), and in the menu bar.
        DispatchQueue.main.async {
            s.start()
            if Snapshot.directory != nil { Snapshot.runIfRequested(store: s) }
        }
    }

    var body: some Scene {
        Window("ClaudeBoard", id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1500, height: 900)
        // Always show the main window at launch, whatever macOS saved about it at the last quit;
        // except at login, where ClaudeBoard starts quietly in the menu bar.
        .defaultLaunchBehavior(Startup.quiet ? .suppressed : .presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    store.newTaskProject = store.scopeProjectID
                    store.showNewTask = true
                }
                .keyboardShortcut("n")
            }
            CommandMenu("Board") {
                Button("Refresh") { store.refresh() }.keyboardShortcut("r")
                Divider()
                ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { i, m in
                    Button(m.title) { store.mode = m }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
                Button("Toggle Details") { store.showInspector.toggle() }.keyboardShortcut("i")
                Button("Share Your Week…") { store.showShareWeek = true }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Needs You") { store.sidebar = .inbox }.keyboardShortcut("1", modifiers: [.command, .shift])
                Button("All Projects") { store.sidebar = .all }.keyboardShortcut("0", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("ClaudeBoard Guide") { store.showGuide = true }.keyboardShortcut("/", modifiers: .command)
                Button("What ClaudeBoard Found…") { store.showDiscovery = true }
                if !Demo.isOn {
                    Button("Try the Demo Board") { DemoLauncher.open() }
                }
                Divider()
                Button("ClaudeBoard on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/aidarkazybekov/claude-board")!)
                }
                Button("Report an Issue…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/aidarkazybekov/claude-board/issues/new/choose")!)
                }
            }
        }

        // The demo runs next to the real app, so it stays out of the menu bar.
        MenuBarExtra(isInserted: .constant(!Demo.isOn)) {
            MenuBarView().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store)
        }
        .defaultSize(width: 900, height: 860)
    }
}

/// Opens a second copy of the app on sample data.
enum DemoLauncher {
    static func open() {
        let bundle = Bundle.main.bundleURL
        if bundle.pathExtension == "app" {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.arguments = ["--demo"]
            cfg.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: bundle, configuration: cfg)
        } else if let exe = Bundle.main.executableURL {
            let p = Process()
            p.executableURL = exe
            p.arguments = ["--demo"]
            try? p.run()
        }
    }
}
