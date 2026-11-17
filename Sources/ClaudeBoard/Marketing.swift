import AppKit
import SwiftUI
import WebKit

/// `ClaudeBoard --media <dir>` renders the demo board's shots for the README, the site and the tour
/// to PNGs and quits. Like `--render`, every window is drawn off screen and the app never takes focus;
/// `scripts/make-media.swift` turns the PNGs into the published images and videos.
@MainActor
enum Marketing {
    /// Wide enough for all five columns and the details panel, so a waiting ticket and its question show together.
    static let wide = CGSize(width: 2280, height: 1060)

    struct Scene {
        let name: String
        let mode: ViewMode
        let scope: SidebarItem
        let select: (Store) -> String?
        var inspector = true
        var dark = false
        var size = CGSize(width: 1600, height: 1000)
        var period: Period = .month
        var source: SourceFilter = .all
    }
    /// The hero: wide enough for all five columns.
    static let hero = CGSize(width: 1760, height: 1100)

    static func run(dir: String) {
        Render.harness(dir: dir) { store in await scenes(store: store, dir: dir) }
    }

    static func scenes(store: Store, dir: String) async {
        store.period = .month
        let acme = Demo.base.path + "/Projects/acme"
        let web = acme + "/apps/web"
        func agentTicket(_ cwd: String, _ status: TaskStatus, _ agent: Agent? = nil) -> String? {
            store.items.first { $0.cwd == cwd && $0.status == status && !$0.origin.isPlanned && !$0.hidden
                && (agent == nil || $0.agentKind == agent) }?.id
        }
        func file(_ key: String) -> String? { store.items.first { $0.externalID == key }?.id }

        let scenes = [
            Scene(name: "board", mode: .board, scope: .all, select: { _ in nil }, inspector: false, size: hero),
            Scene(name: "board-dark", mode: .board, scope: .all, select: { _ in nil }, inspector: false, dark: true, size: hero),
            Scene(name: "needs-you", mode: .board, scope: .all, select: { _ in agentTicket(acme + "/apps/api", .needsYou, .codex) ?? agentTicket(acme + "/apps/api", .needsYou) },
                  size: wide),
            Scene(name: "plan", mode: .plan, scope: .all, select: { _ in file("T-004") }),
            Scene(name: "plan-dark", mode: .plan, scope: .all, select: { _ in file("T-004") }, dark: true),
            Scene(name: "project", mode: .board, scope: .project(web), select: { _ in agentTicket(web, .inProgress) }),
            Scene(name: "agent", mode: .board, scope: .agent(.codex), select: { _ in nil }, inspector: false),
            // Agent work only, so the first day shown is one full of requests whatever the time of day.
            Scene(name: "worklog", mode: .worklog, scope: .all, select: { s in s.items.first { $0.title.hasPrefix("Add a /random") }?.id },
                  source: .claude),
            Scene(name: "list", mode: .list, scope: .all, select: { _ in nil }, inspector: false),
            Scene(name: "insights", mode: .insights, scope: .all, select: { _ in nil }, inspector: false, period: .week),
            Scene(name: "insights-dark", mode: .insights, scope: .all, select: { _ in nil }, inspector: false, dark: true, period: .week),
        ]
        for scene in scenes {
            store.period = scene.period
            store.source = scene.source
            store.mode = scene.mode
            store.sidebar = scene.scope
            store.showInspector = scene.inspector
            store.selection = scene.select(store)
            await Render.shoot(RenderWindow(chrome: true), store: store, size: scene.size, dark: scene.dark,
                               wait: scene.mode == .insights ? 3800 : 1500, "\(dir)/\(scene.name).png")
        }
        store.sidebar = .all
        store.mode = .board
        store.period = .month
        store.source = .all

        // Sheets and panels, each in its own window.
        store.newTaskProject = web
        for (name, view, w, h) in [
            ("discovery", AnyView(DiscoverySheet()), 1060.0, 600.0),
            ("guide", AnyView(GuideSheet()), 900.0, 520.0),
            ("new-task", AnyView(NewTaskSheet()), 640.0, 740.0),
            ("settings", AnyView(SettingsView()), 900.0, 1100.0),
            ("menubar", AnyView(MenuBarView()), 390.0, 660.0),
            ("share-sheet", AnyView(ShareWeekSheet()), 1000.0, 640.0),
        ] {
            await Render.shoot(view.background(Studio.surface), store: store, size: CGSize(width: w, height: h),
                               wait: name == "discovery" ? 2600 : 1300, "\(dir)/\(name).png")
        }
        // The share-your-week card on its own, private and with project names.
        let (ws, we) = SharePeriod.week.range()
        let summary = WeekSummary.compute(items: store.visibleItems, project: store.project, start: ws, end: we)
        for (name, names) in [("week-card", false), ("week-card-projects", true)] {
            if let png = CardRenderer.png(WeekCard(summary: summary, heading: SharePeriod.week.heading, showProjects: names)) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
    }

    /// Renders the window, then paints any web view (charts) on top from its own snapshot.
    static func capture(_ win: NSWindow, _ path: String) async {
        guard let root = win.contentView, let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
        root.cacheDisplay(in: root.bounds, to: rep)
        let image = NSImage(size: root.bounds.size)
        image.addRepresentation(rep)
        if let web = findWeb(root) {
            let rect = web.convert(web.bounds, to: root)
            if let shot = await snapshot(web) {
                let out = NSImage(size: root.bounds.size)
                out.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: root.bounds.size))
                let y = root.isFlipped ? root.bounds.height - rect.maxY : rect.minY
                shot.draw(in: NSRect(x: rect.minX, y: y, width: rect.width, height: rect.height))
                out.unlockFocus()
                write(out, scale: rep.pixelsWide, path)
                return
            }
        }
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }

    private static func write(_ image: NSImage, scale pixelsWide: Int, _ path: String) {
        let w = pixelsWide
        let h = Int(Double(w) * image.size.height / image.size.width)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    }

    private static func snapshot(_ web: WKWebView) async -> NSImage? {
        await withCheckedContinuation { c in web.takeSnapshot(with: nil) { img, _ in c.resume(returning: img) } }
    }

    private static func findWeb(_ v: NSView) -> WKWebView? {
        if let w = v as? WKWebView { return w }
        for s in v.subviews { if let w = findWeb(s) { return w } }
        return nil
    }
}
