// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClipWise",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ClipWise", path: "Sources/ClipWise")
    ]
)
