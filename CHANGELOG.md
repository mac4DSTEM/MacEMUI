# Changelog

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). MacEMUI follows semantic versioning; before 1.0.0 a minor version may break the API, and its Migration paragraph says how.

## [0.5.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.4.0...0.5.0) (2026-11-01)


### ⚠ BREAKING CHANGES

* see the Migration paragraph of the pull request. A room that declared isAvailable keeps it as a plain property; pass the availability to WorkspaceRoomsSection(isAvailable:). Use ColorMix.toggle(_:among:) and ColorMix.selection(among:).
* EDXRoom(session:state:actions:) is now EDXRoom(session:state:actions:openExtensions:). The members made package are no longer visible to an app; see the Migration paragraph of the PR.
* delete the superseded map tile API; wire operationReadoutWidth ([#30](https://github.com/mac4DSTEM/MacEMUI/issues/30))

### Features

* a keyboard route to draw and move a region in the EDS room ([#40](https://github.com/mac4DSTEM/MacEMUI/issues/40)) ([a2e9e06](https://github.com/mac4DSTEM/MacEMUI/commit/a2e9e061859594deeda7c636e6894af00248d979))
* a SegmentedPicker segment can be disabled, with its reason ([#33](https://github.com/mac4DSTEM/MacEMUI/issues/33)) ([576ee05](https://github.com/mac4DSTEM/MacEMUI/commit/576ee051d6dfa3314eb32bd9bbc1fe1747ea4a7a))
* an overlay slot on MapTileView, and the map tiles sit in ImageViewport ([#57](https://github.com/mac4DSTEM/MacEMUI/issues/57)) ([29e4160](https://github.com/mac4DSTEM/MacEMUI/commit/29e4160a39833aca343f9eda7b1def20a879d952))
* delete the public API left unused after the map tile deletions ([#54](https://github.com/mac4DSTEM/MacEMUI/issues/54)) ([86f9e27](https://github.com/mac4DSTEM/MacEMUI/commit/86f9e2749aea106c1f208ed98b86389e13a2bca2))
* delete the superseded map tile API; wire operationReadoutWidth ([#30](https://github.com/mac4DSTEM/MacEMUI/issues/30)) ([a4f4683](https://github.com/mac4DSTEM/MacEMUI/commit/a4f4683ec68f62559d7872686e8b2b7e598326e8))
* Esc returns the EDS room to the arrow tool ([#36](https://github.com/mac4DSTEM/MacEMUI/issues/36)) ([9b8baec](https://github.com/mac4DSTEM/MacEMUI/commit/9b8baecd45150030e920dc64d883d293497b2199))
* ImageViewport, one zoomable container for every room picture ([#43](https://github.com/mac4DSTEM/MacEMUI/issues/43)) ([d701da6](https://github.com/mac4DSTEM/MacEMUI/commit/d701da67c0f491832289197bfac5160150fa5962))
* InspectorSection can start closed and draws a status glyph ([#32](https://github.com/mac4DSTEM/MacEMUI/issues/32)) ([83f96a7](https://github.com/mac4DSTEM/MacEMUI/commit/83f96a7bf54a3201dbfa1f231210bed8c2b38607))
* narrow the shared EDS room public API; the room takes its Open panel extensions ([#56](https://github.com/mac4DSTEM/MacEMUI/issues/56)) ([4d6371c](https://github.com/mac4DSTEM/MacEMUI/commit/4d6371cba8e5adc1157dedbeab0a152acd79f0d8))
* the EDS room no longer labels results as unvalidated ([#63](https://github.com/mac4DSTEM/MacEMUI/issues/63)) ([72455f6](https://github.com/mac4DSTEM/MacEMUI/commit/72455f6d747d339f06bfc99bce03de53d4ada3b3))
* the maps zoom by the panes' ZoomPan; ⌥-scroll pans; View &gt; Zoom acts on the maps ([8ab277f](https://github.com/mac4DSTEM/MacEMUI/commit/8ab277f5cf96e6fad72283c10f5fa31b7b00cfc2))
* the maps zoom by ZoomPan, option-scroll pans, View &gt; Zoom acts on the maps ([#34](https://github.com/mac4DSTEM/MacEMUI/issues/34)) ([8ab277f](https://github.com/mac4DSTEM/MacEMUI/commit/8ab277f5cf96e6fad72283c10f5fa31b7b00cfc2))


### Bug Fixes

* a double click on a map tile no longer also fires its single click ([#31](https://github.com/mac4DSTEM/MacEMUI/issues/31)) ([78c1852](https://github.com/mac4DSTEM/MacEMUI/commit/78c1852dce16207c8d8f9016da79fc445b95668d))
* a late progress update of a replaced EDS open no longer overwrites the newer open ([#55](https://github.com/mac4DSTEM/MacEMUI/issues/55)) ([b83da8e](https://github.com/mac4DSTEM/MacEMUI/commit/b83da8e32d24e9a50b2e2e1fec03dd9d5b776a63))
* a room row whose selection is disabled no longer keeps its highlight ([#50](https://github.com/mac4DSTEM/MacEMUI/issues/50)) ([d29581d](https://github.com/mac4DSTEM/MacEMUI/commit/d29581d49be8e6da81c32b0036279bcb4dfa0dd5))
* histogram captions read low and high while windowed ([#53](https://github.com/mac4DSTEM/MacEMUI/issues/53)) ([b1b0ffd](https://github.com/mac4DSTEM/MacEMUI/commit/b1b0ffda4a1b970fbdccc4fe13a03c14eb2cf31b))
* the busy line speaks the same elapsed time it draws ([#45](https://github.com/mac4DSTEM/MacEMUI/issues/45)) ([ea886b1](https://github.com/mac4DSTEM/MacEMUI/commit/ea886b1adf8a044bc2b09b9ebb492ba3002dcd45))
* the colourbar strip interpolates its LUT like the image does ([#47](https://github.com/mac4DSTEM/MacEMUI/issues/47)) ([afd24f5](https://github.com/mac4DSTEM/MacEMUI/commit/afd24f5f3547401b24ce75e243023ec89ee5035a))
* the EDS results columns hold the whole value and its sigma ([#58](https://github.com/mac4DSTEM/MacEMUI/issues/58)) ([eba6ac1](https://github.com/mac4DSTEM/MacEMUI/commit/eba6ac132f3e6e4a11b664ab6e75e62d1179b280))
* the EDS room reads a typed beam energy everywhere and refuses a Fit to below 0.2 keV in words ([#41](https://github.com/mac4DSTEM/MacEMUI/issues/41)) ([c6397eb](https://github.com/mac4DSTEM/MacEMUI/commit/c6397ebcb475b424cf54e1ddd26c6b1dd0b7013b))
* the maps PNG draws the pinned regions and lines as the colour mix does ([#60](https://github.com/mac4DSTEM/MacEMUI/issues/60)) ([34b2721](https://github.com/mac4DSTEM/MacEMUI/commit/34b2721f4ae080168a3ef715bf4f8ddad321f749))
* typing the shown text over a finer stored value sets it ([#46](https://github.com/mac4DSTEM/MacEMUI/issues/46)) ([8e5f497](https://github.com/mac4DSTEM/MacEMUI/commit/8e5f49773fd7500de37ad5242db2f1a9f9be3ea3))

## [0.4.0](https://github.com/mac4DSTEM/MacEMUI/compare/0.3.2...0.4.0) (2026-10-29)


### Features

* the shared EDS room (ShellEDXModel, EDXRoom in ShellSpectroscopy) ([#24](https://github.com/mac4DSTEM/MacEMUI/issues/24)) ([ecd5266](https://github.com/mac4DSTEM/MacEMUI/commit/ecd5266291c2cfe3a61c2d8170bf0cc005532a94))


### Bug Fixes

* compile the colormap shaders from source when the bundle has no metallib ([#21](https://github.com/mac4DSTEM/MacEMUI/issues/21)) ([066cfab](https://github.com/mac4DSTEM/MacEMUI/commit/066cfab71e3ac96e9cc4df5516b6f5adfbf64b3d))

## 0.3.2 (2026-10-28)

MacEMUI deploys to macOS 26, so the apps can build and run their CI on the macos-26 runner (SDK 26.x).

### Changed
- `Package.swift`: platform `.macOS(.v26)` (was `.macOS("27.0")`). `ToolbarItem.highVisibilityPriority()` applies
  `visibilityPriority(.high)` only on macOS 26.1 or newer, where SwiftUI has it; on 26.0 the item keeps the default priority.
- Source and test comments no longer carry move history or pointers to material outside this repository.

### Added
- `NOTICE`, `CONTRIBUTING.md` and `SECURITY.md`.

### Migration
- None for consumers on macOS 27. An app may now lower its own deployment target to macOS 26.

## 0.3.1 (2026-10-27)

MacEMUI builds with Xcode 26.6 again, so both apps' CI can go green, and it has CI of its own.

### Fixed
- `ShellToolbar`: both `visibilityPriority(.high)` call sites (the verb and the document menu) go through one helper that
  applies it only with Swift 6.4 or newer (Xcode 27). 0.3.0 guarded one site at Swift 6.3, which the macos-26 runner's
  Xcode 26.6 (Swift 6.3.3) passes without having the member, and left the other unguarded. Nothing changes on Xcode 27.
- The Metal tests (`MTLTextureFloatTests`, `MetalEngineDisplayTests`) are skipped on a machine without a Metal device
  instead of failing or stopping the run.

### Added
- CI: `swift test -c release --parallel` on macos-26 (Xcode 26.6) and on xcode-27 for every push and pull request, a
  check that a tag equals the CHANGELOG's top version, and Dependabot for the workflow's actions.
- A README for the public: what MacEMUI is, its products, how to depend on it, the licence.

### Migration
None. An app re-pins `exact: "0.3.1"`; no call site changes.

## 0.3.0 (2026-10-22)

The corrected spectroscopy room (design 2026-10-22, approved after a drive on a real 1.7 GB file): the colour mix as the anchor tile where regions are drawn, maps fitted to the space they are given, one cursor, every
control in the inspector, the scale bar as the way into a map's colour, an element control with the role and line menu on the cell.

### Added
- `MapTileView` (the map's frame: name and line on one row, calibrated scale bar that opens the map's controls, the colour scale and the pointer's value while hovered, one cursor, a ring and a click for the colour mix, regions and tools on the anchor
  tile only), `MapTileRegions`, `MapColorbarSpec`, `MapColorbarView`; `AnchoredMapsBlock`, `FittedMapGrid`, `FittedTileLayout` (pure) and `HorizontalPaneSplit`: the anchor beside the fitted maps with a draggable divider, tiles keeping their identity across a resize.
- `PeriodicTable` with `PeriodicTableActions`, `PeriodicCellState`, `ElementRoleChoice`, `ElementLineFamily`: the periodic table moved from mac4DSTEM, session-free (click toggles Quantify and Off; right-click gives the role and, per family, the lines with their energies, and Default lines);
  `PeriodicTableGrid` holds the symbols and the shape.
- `MapMixControls`: which maps are in the colour mix. `MapColorControls` can open with its sliders expanded and without the mix switch (a one-map popover).
- `MapAppearance.reset(maps:)`: returns only the listed maps to their default colouring and adjustment, leaving other maps and the colour mix.
- `zoomPanWheel(_:box:)` and `ZoomPan.wheel(delta:isPrecise:at:in:)` (ShellControls): the wheel and a two-finger scroll zoom a pane about the pointer by `ScrollZoom.factor`, every event, through the pinch's clamp; opt-in beside `zoomPan`, through the bounded `onScrollWheel` (no application-wide monitor).
- `SegmentedControl` and `SegmentedPicker` (ShellControls): the inspector's one segmented control, always the full width it is given (`NSSegmentedControl` with `.fillEqually`, named as the one AppKit piece: SwiftUI's segmented `Picker` keeps its intrinsic width on macOS), titles or SF symbols per segment, a tooltip and an accessibility label each; a selection not among the items shows none.
- `MapDisplayPopover` and `MapHistogram` (pure bins and statistics): the display popover a tile's scale bar opens, the one both apps show (the Spectroscopy room's): an element map's colour, the reference image's colormap or the colour mix's members, then the map's histogram with its contrast-window handles, Reset Range and a gamma slider. Values and bindings in, no model.
- `MapTileView(filteredTag:)`: a small "filtered" tag beside the title while the picture is drawn through a display filter.
- `MapColoring` (black to one colour, or one of the shared colormaps), `MapAppearance` (the person's choice per map and the colour mix; Codable), `ColorMix`, `MapRaster` (`rgba` for one map, `mix` for the colour mix of several, pure) and `MapColorControls`, the Maps section's rows: a colour or colormap per map and the Colour mix with the maps in it. `ColormapKind` is Codable.
- `MapAdjustment` (a map's contrast window as fractions of its scale, and its gamma) kept in `MapAppearance.adjustments`, applied by `MapRaster.rgba(…adjustment:)` and each `MixLayer`, and set by a slider disclosure on every row of `MapColorControls`; an appearance saved before it still decodes.
- `RegionDrawingLayer(onDrag:)`: the geometry so far while a region is being drawn (`id` nil) or moved or resized (`id` set), nil when the drag ends, so a room can follow the pointer with its spectrum.

### Changed
- `MapTileView` draws nothing over a picture but the cursor: the hover value chip and the hover colour scale are gone (control placement standard, rule 7: the status line carries the value, the popover's histogram the scale). `colorbar:` and `valueText:` are still accepted and ignored so mac4DSTEM compiles; delete at 0.4.0. `MapColorbarView` stays public.

### Fixed
- `ShellToolbar`: the verb's `visibilityPriority(.high)` is compiled only with Swift 6.3 or newer (the Xcode 27 beta); the CI runners' Xcode 26 has no such member on `ToolbarItem`, which had both apps' CI red on main. The item itself is unchanged.
- The scroll wheel reaches a view under SwiftUI content: `onScrollWheel` uses a local event monitor bounded to its own window and view (call sites unchanged).
- The one-map colour popover: no toggle icon (the sliders are always shown), and Reset acts on that map only and leaves the colour mix untouched.

### Superseded
- `MapTileGrid`, `MapTileSize` and `MapTileSizePicker` (a size to choose): the fitted grid scales with the panes instead. They stay until 0.4.0 so mac4DSTEM can move; macTEM no longer uses them.


### Migration
`RegionTool` gained `.pointer` as its FIRST case: `allCases` starts with it and a stored tool decodes by its raw value (the strings are unchanged), so a room that indexed the cases by position re-reads them by case; the default tool of a room is its own choice (macTEM's rooms start on `.pointer`). `ColorMix.isShown` (members only) is gone: `isShown(among:)` takes the maps, so the default mix (every map in) counts. `MapDisplayPopover` takes a `MapDisplayHistogram` value, not a tuple. A tile no longer shows the pointer's value or a colour scale: a room puts the value in its status line (`onHover`) and opens `MapDisplayPopover` from the scale bar (`controls:`); `colorbar:` and `valueText:` are ignored until 0.4.0 removes them. A room that wants the corrected layout builds `AnchoredMapsBlock` of `MapTileView`s (macTEM's `EDXMapsBlock` is the reference wiring), puts the region tool, the maps' quantity and the lower pane's choices in its inspector instead of a strip above the maps, and answers
`PeriodicTable` from its model.

## 0.2.0 (2026-10-22)

The spectroscopy rooms' shared chrome (design 2026-10-22): a new product `ShellSpectroscopy`, built in macTEM's EDS and EELS rooms and offered to mac4DSTEM's Spectroscopy room. Nothing of 0.1.0 changed.

### Added
- `VerticalPaneSplit`: maps over spectrum with a stored, keyboard-nudgeable, VoiceOver-adjustable divider.
- `SpectralRegionSet`, `SpectralRegion`, `RegionGeometry` (rectangle, ellipse, polygon, line), `RegionColor`, `RegionPalette`: any number of regions with a name, colour and visible flag, Codable for the session; `RegionsList` (inspector list: select, rename, recolour, show/hide, delete) and `RegionOverlay` (outlines over a map tile). No pixel or number is computed here: the app turns a geometry into the kit's shape.
- `SpectrumLayer`, `SpectrumScale`, `SpectrumLayerPlot` (min-max thinning, peak, shape normalisation, `draw` into the room's Canvas) and `SpectrumLayerLegend`: one spectrum per region in its colour, plus a dashed temporary pixel layer.
- `SpectrumPane`, `SpectrumPaneTabs` (Spectrum, Profile, Table) and `ProfileSeries`, `ProfileChart` (Swift Charts, distance on x, one coloured line per series).
- `RegionTool` and `RegionDrawingLayer`: the drawing gestures over a map tile (drag a rectangle, ellipse or line, click a polygon's vertices) that hand back what was drawn in scan pixels and mark the pointer's pixel; `RegionDrawing` holds the pure geometry.
- `RegionEditing` and the layer's `onEdit`: the selected region shows handles (eight on a rectangle or ellipse, a vertex each on a polygon, the two ends of a line); a drag on a handle resizes, a drag inside moves; boxes snap to whole pixels. Editing a polygon works under every tool.
- `MapTileGrid`, `MapTileSize`, `MapTileSizePicker` (a segmented control that becomes a menu in a column too narrow for it): the maps block reflows to a chosen tile size and shows one tile alone on a double click; `hoverChip(_:)` puts the pointer's value on a tile.

### Migration
An app adds the product `ShellSpectroscopy` to its target and imports it where it uses a piece; no call site of 0.1.0 changes. The region model is plain values in scan pixels (the app maps its own regions to `SpectralRegionSet`, and a drawn `RegionGeometry` to the kit's shape).

## 0.1.0 (2026-10-22)

The shared window shell of mac4DSTEM and macTEM, cut from mac4DSTEM `8c4c06d` and macTEM `51c944c`, compiled and adopted by both apps
the same day. Four products: ShellMetal (the Metal image view, display transform, colormaps), ShellControls (zoom and pan, number
fields, scale bar, colorbar, histogram chart, pane footer), ShellInspector (the inspector row kit) and ShellLayout (layout policy, panel
navigation, menu relay, activity log, system monitor, window skeleton, toolbar, sidebar and inspector frames, the infobar and process area,
Output). The histogram footer prints 4 significant digits with Reset Range on its own line.

### Migration
Both apps add the package (local path `../MacEMUI` in development, exact tag `0.1.0` at closeout), import the modules they use
(`MemberImportVisibility` is on), delete their copies and their provenance headers. An app's own room enum conforms to `WorkspaceRoom`
(`nonisolated`), holds a `PanelNavigation` as `panels`, and takes `ShellWindow`, `WorkspaceColumn`, `WorkspaceSidebarFrame` and
`WorkspaceInspectorFrame` for its chrome.
