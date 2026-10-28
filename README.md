<p align="center"><img src="docs/banner.png" width="100%" alt="MacEMUI: one window for both apps, with rooms, inspector and a Metal image view, in SwiftUI"></p>

# MacEMUI

The shared user interface of the macEM apps, [mac4DSTEM](https://github.com/mac4DSTEM/mac4DSTEM) and
[macTEM](https://github.com/mac4DSTEM/macTEM): the window shell, the controls, the inspector rows, the Metal image view
and the spectroscopy room's pieces, as a Swift package. SwiftUI and Metal, with AppKit only where SwiftUI cannot do the
job (each such place is named in the code). It holds no numerics: the science lives in the macEM kits, and MacEMUI only
draws what an app hands it.

**Who it is for.** The two macEM apps first. Anyone building a native macOS app for microscopy images and spectra can use
it too: the pieces take values and bindings, not an app's model.

## Products

| Product | Holds |
|---|---|
| `ShellMetal` | `MetalEngine`, `MetalImageView`, `MetalDisplayTransform`, the shared colormaps and their shader |
| `ShellControls` | zoom and pan (pinch, wheel, two-finger scroll), `NumericField`, `PaneFooter`, `ScaleBar`, colorbar, `HistogramChart`, `SegmentedControl` |
| `ShellInspector` | the inspector row kit (`InspectorRows`) |
| `ShellLayout` | the window skeleton: rooms (`WorkspaceRoom`, `PanelNavigation`), toolbar, sidebar and inspector frames, the centre column, `LayoutPolicy`, `MenuActionRelay`, `ActivityLog`, `SystemMonitor` |
| `ShellSpectroscopy` | the spectroscopy room: map tiles and the fitted map grid, the colour mix, regions (draw, edit, list), spectrum and profile panes, the periodic table, the map display popover |

`CHANGELOG.md` lists every public piece as it was added.

## Use it

Requirements: macOS 26, Swift 6.2 tools or newer. It builds with Xcode 27 and with Xcode 26.6.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/mac4DSTEM/MacEMUI", exact: "0.3.1"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "ShellLayout", package: "MacEMUI"),
        .product(name: "ShellMetal", package: "MacEMUI"),
    ]),
]
```

Import only the modules you use. Versions follow semver; before 1.0 a minor version may change the API, and its
CHANGELOG entry has a Migration paragraph saying what to change.

## Build and test

```sh
swift build
swift test -c release --parallel
```

The Metal tests need a GPU; on a machine without one they are skipped, not failed.

## Licence

GPL-3.0. See `LICENSE`.
