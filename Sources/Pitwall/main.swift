import Foundation

let args = CommandLine.arguments
Rename.migrateIfNeeded()
if args.contains("--demo") {
    Demo.prepare()
}
if let i = args.firstIndex(of: "--dump") {
    let n = args.count > i + 1 ? Int(args[i + 1]) ?? 25 : 25
    Dump.run(limit: n)
    exit(0)
}
if let i = args.firstIndex(of: "--render"), args.count > i + 1 {
    Demo.prepare()
    MainActor.assumeIsolated { Render.run(dir: args[i + 1]) }
}
if let i = args.firstIndex(of: "--media"), args.count > i + 1 {
    Demo.prepare()
    MainActor.assumeIsolated { Marketing.run(dir: args[i + 1]) }
}
if args.contains("--selftest") {
    let code = MainActor.assumeIsolated { SelfTest.run() }
    exit(code)
}
PitwallApp.main()
