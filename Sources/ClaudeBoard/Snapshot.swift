import AppKit
import SwiftUI
import WebKit

/// `ClaudeBoard --snapshot <dir>` renders each screen of the running app to PNGs and quits.
/// Used to check the UI without Screen Recording permission.
@MainActor
enum Snapshot {
    static var directory: String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--snapshot"), a.count > i + 1 else { return nil }
        return a[i + 1]
    }

    private static var started = false

    static func runIfRequested(store: Store) {
        guard let dir = directory, !started else { return }
        started = true
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            // Wait for the first ingest.
            for _ in 0..<120 where store.lastRefresh == nil { try? await Task.sleep(for: .milliseconds(250)) }
            store.period = .week
            // Where each planned task landed, for checking project inference.
            let planned = store.items.filter { $0.origin.isPlanned }
                .map { "\(store.key(for: $0))\t\(store.project($0.projectID).name)\t\($0.status.title)\t\($0.title)\t\(($0.claudeLinks ?? []).count) linked" }
                .sorted()
            try? (["roots: \(Roots.all)", "folders: \(store.taskFolders)", "repos: \(store.repos.count)"] + planned)
                .joined(separator: "\n").write(toFile: "\(dir)/planned.txt", atomically: true, encoding: .utf8)
            let pick = store.items.first { $0.status == .needsYou && !$0.hidden }
                ?? store.items.first { $0.status == .inProgress && !$0.subtasks.isEmpty }
                ?? store.items.first
            store.selection = pick?.id
            store.showInspector = true

            for mode in ViewMode.allCases {
                store.mode = mode
                try? await Task.sleep(for: .milliseconds(mode == .insights ? 3500 : 1200))
                capture("\(dir)/\(mode.rawValue).png")
                if mode == .insights { await captureWeb("\(dir)/insights-web.png") }
            }

            // Glass panels (sidebar, inspector) don't draw through cacheDisplay, so also render a flat
            // composition of the same views in an offscreen window.
            if pick != nil {
                let flat = HStack(spacing: 0) {
                    SidebarView().frame(width: 270)
                    Divider()
                    VStack(spacing: 0) { MainArea() }
                    Divider()
                    SelectedDetail().frame(width: 440)
                }
                .environment(store)
                .frame(width: 1760, height: 1050)
                .background(Color(nsColor: .windowBackgroundColor))
                store.mode = .board
                let win = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 1760, height: 1050),
                                   styleMask: [.borderless], backing: .buffered, defer: false)
                win.contentView = NSHostingView(rootView: flat)
                win.orderFrontRegardless()
                try? await Task.sleep(for: .milliseconds(1500))
                capture(window: win, "\(dir)/flat-board.png")
                store.mode = .list
                try? await Task.sleep(for: .milliseconds(1200))
                capture(window: win, "\(dir)/flat-list.png")
                store.mode = .plan
                store.sidebar = .all
                if let t = store.items.first(where: { $0.origin == .file && !($0.claudeLinks ?? []).isEmpty }) ?? store.items.first(where: { $0.origin == .file }) {
                    store.selection = t.id
                }
                try? await Task.sleep(for: .milliseconds(1500))
                capture(window: win, "\(dir)/flat-plan.png")
                win.orderOut(nil)
            }
            if let p = pick {
                store.mode = .board
                store.sidebar = .project(p.projectID)
                try? await Task.sleep(for: .milliseconds(1200))
                capture("\(dir)/project-board.png")
            }
            store.sidebar = .all
            store.mode = .board
            store.showNewTask = true
            try? await Task.sleep(for: .milliseconds(1000))
            if let sheet = NSApp.windows.first(where: { $0.isSheet && $0.isVisible }) {
                capture(window: sheet, "\(dir)/new-ticket.png")
            }
            store.showNewTask = false
            try? await Task.sleep(for: .milliseconds(600))
            store.showOnboarding = true
            try? await Task.sleep(for: .milliseconds(1000))
            if let sheet = NSApp.windows.first(where: { $0.isSheet && $0.isVisible }) {
                capture(window: sheet, "\(dir)/onboarding.png")
            }
            store.showOnboarding = false
            try? await Task.sleep(for: .milliseconds(400))
            NSApp.terminate(nil)
        }
    }

    private static func captureWeb(_ path: String) async {
        guard let w = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet && $0.frame.width > 600 }),
              let root = w.contentView,
              let web = findWeb(root)
        else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            web.takeSnapshot(with: nil) { img, _ in
                if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:])
                {
                    try? png.write(to: URL(fileURLWithPath: path))
                }
                c.resume()
            }
        }
    }

    private static func findWeb(_ v: NSView) -> WKWebView? {
        if let w = v as? WKWebView { return w }
        for s in v.subviews { if let w = findWeb(s) { return w } }
        return nil
    }

    private static func capture(_ path: String) {
        guard let w = NSApp.windows.first(where: { $0.isVisible && !$0.isSheet && $0.frame.width > 600 }) else { return }
        capture(window: w, path)
    }

    private static func capture(window w: NSWindow, _ path: String) {
        guard let view = w.contentView?.superview ?? w.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

/// Inspector content that follows the store's selection (used by the flat snapshot layout).
struct SelectedDetail: View {
    @Environment(Store.self) private var store
    var body: some View {
        if let t = store.task(store.selection) { TaskDetailView(task: t) } else { Color.clear }
    }
}
