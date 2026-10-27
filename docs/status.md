# Status

What is live. 0.3.0 is tagged (2026-10-22), the corrected spectroscopy room: `MapTileView`, `AnchoredMapsBlock`,
`FittedMapGrid`, `HorizontalPaneSplit`, `PeriodicTable`, `SegmentedControl` and `SegmentedPicker` (AppKit, full width), `MapDisplayPopover`,
`MapHistogram`, `MapViewTransform` (shared zoom and pan), `onScrollWheel` (a bounded local monitor) and `zoomPanWheel`, `RegionDrawingLayer`,
`SpectrumLayerPlot`. 0.3.1 (2026-10-27) builds with Xcode 26.6 again and adds
MacEMUI's own CI (macos-26 and xcode-27); the apps re-pin to it next.

Last run (2026-10-27, Mac): `swift build` and `swift test -c release --parallel` green.
