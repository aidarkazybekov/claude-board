import SwiftUI

struct ClaudeBoardApp: App {
    @State private var store = Store()

    var body: some Scene {
        Window("ClaudeBoard", id: "main") {
            ContentView()
                .environment(store)
        }
        .defaultSize(width: 1500, height: 900)
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
                Button("Needs You") { store.sidebar = .inbox }.keyboardShortcut("1", modifiers: [.command, .shift])
                Button("All Projects") { store.sidebar = .all }.keyboardShortcut("0", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store)
        }
        .defaultSize(width: 560, height: 620)
    }
}
