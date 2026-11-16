// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Proledo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Proledo",
            path: "Sources/Proledo"
        )
    ]
)
