import Foundation

/// The app was called ClaudeBoard until 0.4. On the first launch as Pitwall, bring over the old
/// app's settings and data folder so nothing is lost. It copies rather than moves, so the old app
/// keeps working if someone opens it again. Runs only in the real app bundle, never for the demo,
/// the self-test or a render.
enum Rename {
    static let oldBundleID = "io.github.aidarkazybekov.claudeboard"
    static let oldFolder = "ClaudeBoard"
    static let doneKey = "migratedFromClaudeBoard"

    static func migrateIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        let devFlags = ["--demo", "--render", "--media", "--selftest", "--dump", "--snapshot"]
        guard Bundle.main.bundleIdentifier == "io.github.aidarkazybekov.pitwall",
              env["PITWALL_DATA_DIR"] == nil,
              !CommandLine.arguments.contains(where: devFlags.contains)
        else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        copyData(from: support.appendingPathComponent(oldFolder, isDirectory: true),
                 to: support.appendingPathComponent("Pitwall", isDirectory: true))
        if let old = defaults.persistentDomain(forName: oldBundleID) {
            copySettings(old, into: defaults)
        }
        defaults.set(true, forKey: doneKey)
    }

    /// Copies everything but the cache (it's rebuilt from the agents' own files). A file Pitwall
    /// already has is never replaced, but one it's missing is copied even if the folder exists.
    static func copyData(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: old.path) else { return }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        for name in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] where name != "cache" {
            let dest = new.appendingPathComponent(name)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try? fm.copyItem(at: old.appendingPathComponent(name), to: dest)
        }
    }

    /// Settings the user already changed in Pitwall win over the old ones.
    static func copySettings(_ old: [String: Any], into defaults: UserDefaults) {
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
