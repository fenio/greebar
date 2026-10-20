// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GreeBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GreeBar", path: "Sources/GreeBar")
    ]
)
