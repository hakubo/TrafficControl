// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TrafficControl",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TrafficControlCore"),
        .executableTarget(
            name: "TrafficControl",
            dependencies: ["TrafficControlCore"]
        ),
        .testTarget(
            name: "TrafficControlCoreTests",
            dependencies: ["TrafficControlCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
