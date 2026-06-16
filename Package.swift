// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlindSpot",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "BlindSpot",
            dependencies: ["Sparkle"],
            path: "Sources/BlindSpot"
        )
    ]
)
