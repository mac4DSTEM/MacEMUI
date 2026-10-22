// swift-tools-version: 6.2
// MacEMUI: the window shell, controls and Metal image view that mac4DSTEM and macTEM share (suite task 8).
// An app package, not a kit: it has UI, Metal and (named, minimal) AppKit. Kits stay pure Swift and are not imported here
// except ImagoCore for `ScaleBarMath` (ShellControls). No numerics live here.
// Settings: Swift 6 language mode and MainActor default isolation, as macTEM; mac4DSTEM (Swift 5 mode) consumes it unchanged.
// NOT BUILT: this manifest and everything under Sources/ was written in the cloud, which has no Swift. See docs/split-plan.md.
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
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "ShellMetal", targets: ["ShellMetal"]),
        .library(name: "ShellControls", targets: ["ShellControls"]),
        .library(name: "ShellInspector", targets: ["ShellInspector"]),
        .library(name: "ShellLayout", targets: ["ShellLayout"]),
    ],
    dependencies: [
        // ScaleBarMath (PaneFooter/ScaleBar). `from:` so the 0.7.0 tag and the apps' pins both resolve; the apps pin exact.
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
        .testTarget(name: "ShellMetalTests", dependencies: ["ShellMetal"], swiftSettings: shellSettings),
        .testTarget(name: "ShellControlsTests", dependencies: ["ShellControls"], swiftSettings: shellSettings),
        .testTarget(name: "ShellInspectorTests", dependencies: ["ShellInspector"], swiftSettings: shellSettings),
        .testTarget(name: "ShellLayoutTests", dependencies: ["ShellLayout"], swiftSettings: shellSettings),
    ]
)
