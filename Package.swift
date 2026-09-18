// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6)
]

let package = Package(
    name: "OverlayGen",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ProjectModel", targets: ["ProjectModel"]),
        .library(name: "TelemetryKit", targets: ["TelemetryKit"]),
        .library(name: "Importers", targets: ["Importers"]),
        .library(name: "GPMFKit", targets: ["GPMFKit"]),
        .library(name: "RenderKit", targets: ["RenderKit"]),
        .library(name: "MediaKit", targets: ["MediaKit"]),
        .library(name: "Scripting", targets: ["Scripting"]),
        .executable(name: "overlaygen", targets: ["OverlayGenCLI"]),
        .executable(name: "OverlayGenApp", targets: ["OverlayGenApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        // MARK: Libraries
        .target(name: "ProjectModel", swiftSettings: strict),
        .target(name: "TelemetryKit", swiftSettings: strict),
        .target(name: "GPMFKit", dependencies: ["TelemetryKit"], swiftSettings: strict),
        .target(name: "Importers", dependencies: ["TelemetryKit", "GPMFKit"], swiftSettings: strict),
        .target(name: "RenderKit", dependencies: ["ProjectModel", "TelemetryKit"], swiftSettings: strict),
        .target(
            name: "MediaKit",
            dependencies: ["ProjectModel", "TelemetryKit", "RenderKit", "Importers", "GPMFKit"],
            swiftSettings: strict
        ),
        .target(name: "Scripting", dependencies: ["RenderKit", "TelemetryKit"], swiftSettings: strict),

        // MARK: Executables
        .executableTarget(
            name: "OverlayGenCLI",
            dependencies: [
                "ProjectModel", "TelemetryKit", "Importers", "GPMFKit", "RenderKit", "MediaKit", "Scripting",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: strict
        ),
        // The SwiftUI app. Also compiled by the XcodeGen project (project.yml) as OverlayGen.app,
        // where Sparkle is added; here it builds as a plain executable for `swift run`.
        .executableTarget(
            name: "OverlayGenApp",
            dependencies: [
                "ProjectModel", "TelemetryKit", "Importers", "GPMFKit", "RenderKit", "MediaKit", "Scripting",
            ],
            swiftSettings: strict + [.defaultIsolation(MainActor.self)]
        ),

        // MARK: Tests
        .testTarget(name: "ProjectModelTests", dependencies: ["ProjectModel"], swiftSettings: strict),
        .testTarget(name: "TelemetryKitTests", dependencies: ["TelemetryKit"], swiftSettings: strict),
        .testTarget(
            name: "ImportersTests",
            dependencies: ["Importers"],
            resources: [.copy("../Fixtures")],
            swiftSettings: strict
        ),
        .testTarget(name: "RenderKitTests", dependencies: ["RenderKit"], swiftSettings: strict),
        .testTarget(name: "GPMFKitTests", dependencies: ["GPMFKit"], swiftSettings: strict),
        .testTarget(
            name: "MediaKitTests",
            dependencies: ["MediaKit"],
            resources: [.copy("../Fixtures")],
            swiftSettings: strict
        ),
        .testTarget(name: "ScriptingTests", dependencies: ["Scripting"], swiftSettings: strict),
    ]
)
