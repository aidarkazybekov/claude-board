import AppKit
import SwiftUI

/// `ClaudeBoard --render <dir>` renders every screen of the demo board to PNGs and quits.
/// Windows are drawn far off screen and the app never shows a Dock icon or takes focus,
/// so it can run while someone is working on the same Mac.
@MainActor
enum Render {
    static let size = CGSize(width: 1600, height: 1000)

    static func run(dir: String) {
        harness(dir: dir) { store in await scenes(store: store, dir: dir) }
    }

    /// Starts the demo store without a Dock icon or a visible window, runs `body`, then quits.
    static func harness(dir: String, _ body: @escaping @MainActor (Store) async -> Void) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = Store()
        store.showOnboarding = false
        store.start()
        Task { @MainActor in
            for _ in 0..<160 where store.lastRefresh == nil { try? await Task.sleep(for: .milliseconds(250)) }
            try? await Task.sleep(for: .milliseconds(800))
            await body(store)
            exit(0)
        }
        app.run()
    }

    private static func window(_ size: CGSize, dark: Bool) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.isReleasedWhenClosed = false
        return w
    }

    static func shoot<V: View>(_ view: V, store: Store, size: CGSize, dark: Bool = false, wait: Int = 1300, _ path: String) async {
        let w = window(size, dark: dark)
        w.contentView = NSHostingView(rootView: view.environment(store).frame(width: size.width, height: size.height))
        w.orderFrontRegardless()
        w.setFrameOrigin(NSPoint(x: -30000, y: -30000))
        try? await Task.sleep(for: .milliseconds(wait))
        await Marketing.capture(w, path)
        w.orderOut(nil)
    }

    static func scenes(store: Store, dir: String) async {
        store.period = .month

        let needs = store.items.first { $0.status == .needsYou && !$0.hidden }?.id
        let planned = store.items.first { $0.origin == .file && !($0.claudeLinks ?? []).isEmpty }?.id
            ?? store.items.first { $0.origin == .file }?.id

        let shots: [(String, ViewMode, SidebarItem, String?, Bool, Bool)] = [
            ("board", .board, .all, needs, true, false),
            ("board-dark", .board, .all, needs, true, true),
            ("plan", .plan, .all, planned, true, false),
            ("list", .list, .all, nil, false, false),
            ("worklog", .worklog, .all, nil, false, false),
            ("insights", .insights, .all, nil, false, false),
            ("insights-dark", .insights, .all, nil, false, true),
        ]
        for (name, mode, scope, select, inspector, dark) in shots {
            store.mode = mode
            store.sidebar = scope
            store.selection = select
            store.showInspector = inspector
            await shoot(RenderWindow(), store: store, size: size, dark: dark, wait: mode == .insights ? 3500 : 1400, "\(dir)/\(name).png")
        }
        if let first = store.items.first(where: { $0.status == .inProgress && !$0.origin.isPlanned }) {
            store.mode = .board
            store.sidebar = .project(first.projectID)
            store.selection = first.id
            store.showInspector = true
            await shoot(RenderWindow(), store: store, size: size, "\(dir)/project-board.png")
        }
        store.sidebar = .all

        let web = store.repos.first { $0.hasSuffix("/apps/web") } ?? store.repos.first
        store.newTaskProject = web
        let sheets: [(String, AnyView, CGSize)] = [
            ("new-task", AnyView(NewTaskSheet()), CGSize(width: 680, height: 760)),
            ("share-week", AnyView(ShareWeekSheet()), CGSize(width: 1000, height: 640)),
            ("discovery", AnyView(DiscoverySheet()), CGSize(width: 1100, height: 720)),
            ("onboarding", AnyView(OnboardingSheet()), CGSize(width: 760, height: 640)),
            ("guide", AnyView(GuideSheet()), CGSize(width: 900, height: 560)),
            ("settings", AnyView(SettingsView()), CGSize(width: 900, height: 1100)),
            ("menubar", AnyView(MenuBarView()), CGSize(width: 390, height: 660)),
        ]
        for (name, view, size) in sheets {
            await shoot(view.background(Studio.surface), store: store, size: size, wait: name == "discovery" ? 2400 : 1200, "\(dir)/\(name).png")
        }
        if let web, let info = store.projects[web] {
            await shoot(ProjectSettingsSheet(project: info), store: store, size: CGSize(width: 560, height: 560), "\(dir)/project-settings.png")
        }
    }
}

/// The app window's layout without the system chrome: sidebar, main area, details.
/// `chrome` adds the window buttons above the sidebar, for screenshots that should read as a Mac window.
struct RenderWindow: View {
    @Environment(Store.self) private var store
    var chrome = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if chrome { TrafficLights().frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).padding(.leading, 18) }
                }
                .frame(width: 252)
            MainArea()
            if store.showInspector {
                SelectedDetail()
                    .frame(width: 430)
                    .background(Studio.surface)
            }
        }
        .background(Studio.ground)
    }
}

/// The close, minimise and zoom buttons of a Mac window.
struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([UInt32(0xFF5F57), 0xFEBC2E, 0x28C840], id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 12, height: 12)
            }
        }
    }
}
