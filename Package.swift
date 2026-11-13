// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeBoard",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "ClaudeBoard", targets: ["ClaudeBoard"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeBoard",
            path: "Sources/ClaudeBoard",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
