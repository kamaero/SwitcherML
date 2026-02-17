// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwitcherLM",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SwitcherLM",
            path: "Sources/SwitcherLM",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
