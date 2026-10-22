# Status

What is live. 0.2.0 is tagged; 0.3.0 is on local main (2026-10-22), the corrected spectroscopy room: `MapTileView`, `AnchoredMapsBlock`,
`FittedMapGrid`, `HorizontalPaneSplit`, `PeriodicTable`, `SegmentedControl` and `SegmentedPicker` (AppKit, full width), `MapDisplayPopover`,
`MapHistogram`, `MapViewTransform` (shared zoom and pan), `onScrollWheel` (a bounded local monitor) and `zoomPanWheel`, `RegionDrawingLayer`,
`SpectrumLayerPlot`. Consumers: macTEM on `../MacEMUI` until 0.3.0 is tagged, mac4DSTEM on 0.2.0 until it adopts.

Last run (2026-10-23, Mac): `swift build` and `swift test -c release --parallel` green.
