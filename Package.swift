// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppClean",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AppClean", path: "Sources/AppClean")
    ]
)
