// swift-tools-version: 6.2
// MacEMUI: the window shell, controls and Metal image view that mac4DSTEM and macTEM share.
// An app package, not a kit: it has UI, Metal and (named, minimal) AppKit. Kits stay pure Swift and are not imported here
// except ImagoCore for `ScaleBarMath` (ShellControls). No numerics live here.
// Settings: Swift 6 language mode and MainActor default isolation, as macTEM; mac4DSTEM (Swift 5 mode) consumes it unchanged.
import PackageDescription

let shellSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "MacEMUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ShellMetal", targets: ["ShellMetal"]),
        .library(name: "ShellControls", targets: ["ShellControls"]),
        .library(name: "ShellInspector", targets: ["ShellInspector"]),
        .library(name: "ShellLayout", targets: ["ShellLayout"]),
        .library(name: "ShellSpectroscopy", targets: ["ShellSpectroscopy"]),
    ],
    dependencies: [
        // ScaleBarMath (PaneFooter/ScaleBar). The apps pin exact tags.
        .package(url: "https://github.com/mac4DSTEM/ImagoKit", from: "0.6.1"),
    ],
    targets: [
        .target(name: "ShellMetal",
                resources: [.process("Resources")],   // Colormaps.metal; library loads with makeDefaultLibrary(bundle: .module)
                swiftSettings: shellSettings),
        .target(name: "ShellControls",
                dependencies: ["ShellMetal", .product(name: "ImagoCore", package: "ImagoKit")],
                swiftSettings: shellSettings),
        .target(name: "ShellInspector", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        .target(name: "ShellLayout", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        .target(name: "ShellSpectroscopy", dependencies: ["ShellMetal", "ShellControls", "ShellInspector", "ShellLayout"], swiftSettings: shellSettings),
        .testTarget(name: "ShellMetalTests", dependencies: ["ShellMetal"], swiftSettings: shellSettings),
        .testTarget(name: "ShellControlsTests", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        .testTarget(name: "ShellInspectorTests", dependencies: ["ShellInspector"], swiftSettings: shellSettings),
        .testTarget(name: "ShellLayoutTests", dependencies: ["ShellLayout"], swiftSettings: shellSettings),
        .testTarget(name: "ShellSpectroscopyTests", dependencies: ["ShellSpectroscopy", "ShellMetal", "ShellControls"], swiftSettings: shellSettings),
    ]
)
