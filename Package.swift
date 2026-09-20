// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacZ",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacZ", targets: ["MacZ"])],
    targets: [
        .target(name: "MacZCore"),
        .executableTarget(name: "MacZ", dependencies: ["MacZCore"], resources: [.copy("Resources/AppIcon.icns")]),
        .testTarget(name: "MacZCoreTests", dependencies: ["MacZCore"]),
        .testTarget(name: "MacZTests", dependencies: ["MacZ"])
    ]
)
