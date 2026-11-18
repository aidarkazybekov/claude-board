// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pitwall",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Pitwall", targets: ["Pitwall"])
    ],
    targets: [
        .executableTarget(
            name: "Pitwall",
            path: "Sources/Pitwall",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
