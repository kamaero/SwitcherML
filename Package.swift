// swift-tools-version: 6.0
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
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("CreateML"),
            ]
        ),
        .testTarget(
            name: "SwitcherLMTests",
            dependencies: ["SwitcherLM"],
            path: "Tests/SwitcherLMTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
