// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TrafficControl",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "TrafficControlCore"),
        .executableTarget(
            name: "TrafficControl",
            dependencies: [
                "TrafficControlCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            // Sparkle.framework is copied into Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "TrafficControlCoreTests",
            dependencies: ["TrafficControlCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
