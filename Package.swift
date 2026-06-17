// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BlindSpot",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BlindSpot",
            dependencies: ["Sparkle"],
            path: "Sources/BlindSpot",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
