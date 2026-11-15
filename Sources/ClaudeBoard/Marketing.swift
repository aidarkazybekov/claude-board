import AppKit
import SwiftUI
import WebKit

/// `ClaudeBoard --demo --snapshot <dir>` renders curated scenes of the demo board for the README,
/// release notes and social posts. Real-window glass panels don't draw through `cacheDisplay`,
/// so scenes are composed in a plain window that mirrors the app's layout and toolbar.
@MainActor
enum Marketing {
    static let size = CGSize(width: 1600, height: 1000)

    struct Scene {
        let name: String
        let mode: ViewMode
        let scope: SidebarItem
        let select: (Store) -> String?
        var inspector = true
        var dark = true
    }

    static func run(store: Store, dir: String) async {
        for _ in 0..<160 where store.lastRefresh == nil { try? await Task.sleep(for: .milliseconds(250)) }
        try? await Task.sleep(for: .milliseconds(800))
        store.period = .week

        let acme = Demo.base.path + "/Projects/acme"
        let web = acme + "/apps/web"
        func ticket(_ cwd: String, _ status: TaskStatus) -> String? {
            store.items.first { $0.cwd == cwd && $0.status == status && !$0.origin.isPlanned }?.id
        }
        func file(_ key: String) -> String? { store.items.first { $0.externalID == key }?.id }

        let scenes = [
            Scene(name: "board", mode: .board, scope: .all, select: { _ in nil }, inspector: false),
            Scene(name: "plan", mode: .plan, scope: .all, select: { _ in file("T-004") }),
            Scene(name: "needs-you", mode: .board, scope: .all, select: { _ in ticket(acme + "/apps/api", .needsYou) }),
            Scene(name: "project", mode: .board, scope: .project(web), select: { _ in ticket(web, .inProgress) }),
            Scene(name: "worklog", mode: .worklog, scope: .all, select: { s in s.items.first { $0.title.hasPrefix("Add a /random") }?.id }),
            Scene(name: "list", mode: .list, scope: .all, select: { _ in nil }, inspector: false),
            Scene(name: "insights", mode: .insights, scope: .all, select: { _ in nil }, inspector: false),
            Scene(name: "plan-light", mode: .plan, scope: .all, select: { _ in file("T-004") }, dark: false),
            Scene(name: "board-light", mode: .board, scope: .all, select: { _ in nil }, inspector: false, dark: false),
        ]

        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = NSHostingView(rootView: MarketingWindow().environment(store))
        if let screen = NSScreen.main {
            win.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX, y: screen.visibleFrame.maxY - size.height))
        }
        win.orderFrontRegardless()

        for scene in scenes {
            win.appearance = NSAppearance(named: scene.dark ? .darkAqua : .aqua)
            store.mode = scene.mode
            store.sidebar = scene.scope
            store.showInspector = scene.inspector
            store.selection = scene.select(store)
            try? await Task.sleep(for: .milliseconds(scene.mode == .insights ? 4000 : 1600))
            await capture(win, "\(dir)/\(scene.name).png")
        }
        win.orderOut(nil)

        // Sheets: guide and new task.
        for (name, view, w, h) in [
            ("guide", AnyView(GuideSheet()), 760.0, 410.0),
            ("new-task", AnyView(NewTaskSheet()), 580.0, 660.0),
        ] {
            store.newTaskProject = web
            let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
            sheet.appearance = NSAppearance(named: .darkAqua)
            sheet.contentView = NSHostingView(rootView: view.environment(store).frame(width: w, height: h)
                .background(Color(nsColor: .windowBackgroundColor)))
            sheet.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(1200))
            await capture(sheet, "\(dir)/\(name).png")
            sheet.orderOut(nil)
        }
        // Share-your-week card, private and with project names, plus the share sheet.
        let (ws, we) = SharePeriod.week.range()
        let summary = WeekSummary.compute(items: store.items.filter { !$0.hidden }, project: store.project, start: ws, end: we)
        for (name, names) in [("week-card", false), ("week-card-projects", true)] {
            if let png = CardRenderer.png(WeekCard(summary: summary, heading: SharePeriod.week.heading, showProjects: names)) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
        let share = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        share.appearance = NSAppearance(named: .darkAqua)
        share.contentView = NSHostingView(rootView: ShareWeekSheet().environment(store).frame(width: 680, height: 520)
            .background(Color(nsColor: .windowBackgroundColor)))
        share.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(1200))
        await capture(share, "\(dir)/share-sheet.png")
        share.orderOut(nil)
        NSApp.terminate(nil)
    }

    /// Renders the window, then paints any web view (charts) on top from its own snapshot.
    private static func capture(_ win: NSWindow, _ path: String) async {
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

/// The app's layout without glass: title bar, toolbar, sidebar, main area, inspector.
struct MarketingWindow: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            MarketingToolbar()
            Divider()
            HStack(spacing: 0) {
                SidebarView().frame(width: 262)
                Divider()
                MainArea()
                if store.showInspector {
                    Divider()
                    SelectedDetail().frame(width: 430)
                }
            }
        }
        .frame(width: Marketing.size.width, height: Marketing.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MarketingToolbar: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
            }
            .padding(.leading, 6)
            Image(systemName: "sidebar.left").foregroundStyle(.secondary).padding(.leading, 150)
            VStack(alignment: .leading, spacing: 0) {
                Text(store.scopeTitle).font(.headline)
                Text(store.lastIngestInfo.components(separatedBy: " · ").prefix(3).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 290, alignment: .leading)
            Spacer()
            Picker("View", selection: $store.mode) {
                ForEach(ViewMode.allCases) { m in Label(m.title, systemImage: m.symbol).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.titleAndIcon)
            .fixedSize()
            Spacer()
            HStack(spacing: 16) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Image(systemName: "arrow.clockwise")
                Image(systemName: "plus")
                Image(systemName: "sidebar.trailing")
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                Text("Search tickets, keys, prompts")
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .frame(width: 230, height: 28)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
