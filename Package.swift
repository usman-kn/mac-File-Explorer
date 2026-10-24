// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Explorer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Explorer", path: "Sources/Explorer")
    ]
)
