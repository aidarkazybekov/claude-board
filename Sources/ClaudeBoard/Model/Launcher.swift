import AppKit
import Foundation

/// Opens Terminal sessions running Claude Code. Uses a throwaway `.command` file so no
/// Automation permission is needed.
enum Launcher {
    static var claudeBinary: String {
        for p in ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", Paths.home + "/.local/bin/claude", Paths.home + "/.claude/local/claude"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "claude"
    }

    static func resumeClaude(sessionID: String, in dir: String) {
        run(script: """
        cd \(quote(dir)) || exit 1
        echo "Resuming Claude session \(sessionID)…"
        exec \(quote(claudeBinary)) --resume \(quote(sessionID))
        """)
    }

    static func startClaude(in dir: String, prompt: String) {
        let promptFile = Paths.appSupport.appendingPathComponent("launch-\(UUID().uuidString.prefix(8)).txt")
        try? prompt.write(to: promptFile, atomically: true, encoding: .utf8)
        run(script: """
        cd \(quote(dir)) || exit 1
        PROMPT="$(cat \(quote(promptFile.path)))"
        rm -f \(quote(promptFile.path))
        exec \(quote(claudeBinary)) "$PROMPT"
        """)
    }

    private static func run(script body: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claudeboard-\(UUID().uuidString.prefix(8)).command")
        let script = "#!/bin/zsh -l\nrm -f \(quote(url.path))\n" + body + "\n"
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
