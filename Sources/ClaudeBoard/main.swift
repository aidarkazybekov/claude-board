import Foundation

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--dump") {
    let n = args.count > i + 1 ? Int(args[i + 1]) ?? 25 : 25
    Dump.run(limit: n)
    exit(0)
}
if args.contains("--selftest") {
    let code = MainActor.assumeIsolated { SelfTest.run() }
    exit(code)
}
ClaudeBoardApp.main()
