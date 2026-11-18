import AppKit
import ServiceManagement

/// How Pitwall starts and where it shows up: open at login, quiet start in the menu bar, Dock icon.
enum Startup {
    static let dockKey = "showInDock"
    /// True when macOS opened Pitwall at login (or PITWALL_QUIET_START is set): menu bar only, no window.
    static var quiet = ProcessInfo.processInfo.environment["PITWALL_QUIET_START"] != nil
    /// Set once the launch window has been dealt with, so later "Open Board" clicks always show it.
    static var quietHandled = false

    /// On unless turned off. `bool(forKey:)` also reads "NO"/"0" from a `-showInDock NO` launch argument.
    static var showInDock: Bool { UserDefaults.standard.object(forKey: dockKey) == nil || UserDefaults.standard.bool(forKey: dockKey) }

    /// The demo has no menu bar item, so it always keeps its Dock icon.
    @MainActor static func applyDockPolicy() {
        let policy: NSApplication.ActivationPolicy = showInDock || Demo.isOn ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if policy == .accessory { NSApp.activate(ignoringOtherApps: true) }  // keep an open board in front
        }
    }

    // MARK: Login launch

    private static let openApplication: AEEventID = 0x6F61_7070       // 'oapp'
    private static let propData: AEKeyword = 0x7072_6474              // 'prdt' (keyAEPropData)
    private static let launchedAsLoginItem: OSType = 0x6C67_6974      // 'lgit' (keyAELaunchedAsLogInItem)

    /// Whether the launch Apple event says macOS started us as a login item. Pure, for the self-test.
    static func isLoginLaunch(eventID: AEEventID?, launchProperty: OSType?) -> Bool {
        eventID == openApplication && launchProperty == launchedAsLoginItem
    }

    static func detectLoginLaunch() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return isLoginLaunch(eventID: event.eventID, launchProperty: event.paramDescriptor(forKeyword: propData)?.enumCodeValue)
    }

    // MARK: Open at login (SMAppService, macOS 13+)

    enum LoginItem { case on, off, needsApproval, unavailable }

    /// Only a real app bundle can be a login item; never the demo or a `swift run` build.
    static var loginItem: LoginItem {
        guard Bundle.main.bundlePath.hasSuffix(".app"), Bundle.main.bundleIdentifier != nil, !Demo.isOn else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    static func setOpenAtLogin(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Sees the launch Apple event, which SwiftUI's App doesn't expose.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if Startup.detectLoginLaunch() { Startup.quiet = true }
        MainActor.assumeIsolated { Startup.applyDockPolicy() }
        Store.debugLog("startup: quiet=\(Startup.quiet) dock=\(Startup.showInDock)")
    }

    /// Pitwall lives in the menu bar: closing the board must never quit it (it would stop
    /// tracking and notifying). Quit from the menu bar window or with ⌘Q.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only a window that pops up while launching is closed; after that, "Open Board" always opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { Startup.quietHandled = true }
        guard ProcessInfo.processInfo.environment["PITWALL_LOG"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let visible = NSApp.windows.filter { $0.isVisible && $0.identifier?.rawValue.hasPrefix("main") == true }.count
            let all = NSApp.windows.map { "\($0.identifier?.rawValue ?? "-")[\(type(of: $0))]\($0.isVisible ? "+" : "")" }.joined(separator: " ")
            Store.debugLog("startup: policy=\(NSApp.activationPolicy() == .accessory ? "accessory" : "regular") mainWindowsVisible=\(visible) windows=\(all)")
        }
    }
}
