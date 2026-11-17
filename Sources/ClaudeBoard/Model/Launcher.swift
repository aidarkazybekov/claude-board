import AppKit
import Foundation

/// Starts and resumes agent sessions. Terminal agents run in a new Terminal tab through a throwaway
/// `.command` file (no Automation permission needed); editor agents open the project in their app.
enum Launcher {
    private static func binary(_ name: String) -> String {
        for p in ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", Paths.home + "/.local/bin/\(name)", Paths.home + "/.claude/local/\(name)",
                  Paths.home + "/.npm-global/bin/\(name)", Paths.home + "/.bun/bin/\(name)"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return name
    }

    static var claudeBinary: String { binary("claude") }

    /// Bundle ids and names of the editor agents' apps.
    private static func app(for agent: Agent) -> (bundle: String, name: String)? {
        switch agent {
        case .cursor: return ("com.todesktop.230313mzl4w4u92", "Cursor")
        case .antigravity: return ("com.google.antigravity", "Antigravity")
        case .codex: return ("com.openai.codex", "Codex")
        default: return nil
        }
    }

    static func resume(agent: Agent, sessionID: String, in dir: String) {
        switch agent {
        case .claudeCode:
            run(script: """
            cd \(quote(dir)) || exit 1
            echo "Resuming Claude Code session \(sessionID)…"
            exec \(quote(claudeBinary)) --resume \(quote(sessionID))
            """)
        case .codex:
            let cli = binary("codex")
            if cli.hasPrefix("/") || !openApp(.codex, folder: nil) {
                run(script: """
                cd \(quote(dir)) || exit 1
                echo "Resuming Codex session \(sessionID)…"
                exec \(quote(cli)) resume \(quote(sessionID))
                """)
            }
        case .gemini:
            run(script: """
            cd \(quote(dir)) || exit 1
            exec \(quote(binary("gemini")))
            """)
        case .cursor, .antigravity:
            _ = openApp(agent, folder: dir)
        }
    }

    static func startClaude(in dir: String, prompt: String) { start(.claudeCode, in: dir, prompt: prompt) }

    /// Opens the agent on a task. Terminal agents get the prompt as their first message; editor
    /// agents open the folder with the prompt on the clipboard, ready to paste into a new chat.
    static func start(_ agent: Agent, in dir: String, prompt: String) {
        guard agent.runsInTerminal else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            _ = openApp(agent, folder: dir)
            return
        }
        let promptFile = Paths.appSupport.appendingPathComponent("launch-\(UUID().uuidString.prefix(8)).txt")
        try? prompt.write(to: promptFile, atomically: true, encoding: .utf8)
        let command: String
        switch agent {
        case .codex: command = "exec \(quote(binary("codex"))) \"$PROMPT\""
        case .gemini: command = "exec \(quote(binary("gemini"))) -i \"$PROMPT\""
        default: command = "exec \(quote(claudeBinary)) \"$PROMPT\""
        }
        run(script: """
        cd \(quote(dir)) || exit 1
        PROMPT="$(cat \(quote(promptFile.path)))"
        rm -f \(quote(promptFile.path))
        \(command)
        """)
    }

    /// Opens an agent's app (on a folder, when given). Returns false when the app isn't installed.
    @discardableResult
    static func openApp(_ agent: Agent, folder: String?) -> Bool {
        guard let a = app(for: agent) else { return false }
        if Demo.isOn {
            demoAlert("This opens \(a.name)" + (folder.map { " on \(Paths.tilde($0))" } ?? "") + ".")
            return true
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundle) else { return false }
        let cfg = NSWorkspace.OpenConfiguration()
        if let folder {
            NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: url, configuration: cfg)
        } else {
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        }
        return true
    }

    static func isInstalled(_ agent: Agent) -> Bool {
        if let a = app(for: agent), NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.bundle) != nil { return true }
        switch agent {
        case .claudeCode: return claudeBinary.hasPrefix("/")
        case .codex: return binary("codex").hasPrefix("/")
        case .gemini: return binary("gemini").hasPrefix("/")
        default: return false
        }
    }

    private static func demoAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "Demo board"
        alert.informativeText = "With your real projects, " + text.prefix(1).lowercased() + text.dropFirst()
        alert.runModal()
    }

    private static func run(script body: String) {
        if Demo.isOn {
            // Demo projects are fake folders; show what would happen instead of starting an agent.
            demoAlert("This opens Terminal and runs:\n\n"
                + body.split(separator: "\n").filter { $0.contains("exec ") || $0.hasPrefix("cd ") }.joined(separator: "\n"))
            return
        }
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
