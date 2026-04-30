// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlindSpot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BlindSpot",
            path: "Sources/BlindSpot"
        )
    ]
)
