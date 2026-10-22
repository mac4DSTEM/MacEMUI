# Changelog

MacEMUI follows semantic versioning; before 1.0.0 a minor version may break the API, and its Migration paragraph says how.

## 0.3.0 (2026-10-22)

The corrected spectroscopy room (design 2026-10-22, approved by the owner after a drive on the real 1.7 GB file): the colour mix as the anchor tile where regions are drawn, maps fitted to the space they are given, one cursor, every
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

### Changed
- `MapTileView` draws nothing over a picture but the cursor: the hover value chip and the hover colour scale are gone (control placement standard, rule 7: the status line carries the value, the popover's histogram the scale). `colorbar:` and `valueText:` are still accepted and ignored so mac4DSTEM compiles; delete at 0.4.0. `MapColorbarView` stays public.

### Fixed
- The scroll wheel reaches a view under SwiftUI content: `onScrollWheel` uses a local event monitor bounded to its own window and view (call sites unchanged).
- The one-map colour popover: no toggle icon (the sliders are always shown), and Reset acts on that map only and leaves the colour mix untouched.

### Added (from 0.2.1)
- `MapColoring` (black to one colour, or one of the shared colormaps), `MapAppearance` (the person's choice per map and the colour mix; Codable), `ColorMix`, `MapRaster` (`rgba` for one map, `mix` for the colour mix of several, pure) and `MapColorControls`, the Maps section's rows: a colour or colormap per map and the Colour mix with the maps in it. `ColormapKind` is Codable.
- `MapAdjustment` (a map's contrast window as fractions of its scale, and its gamma) kept in `MapAppearance.adjustments`, applied by `MapRaster.rgba(…adjustment:)` and each `MixLayer`, and set by a slider disclosure on every row of `MapColorControls`; an appearance saved before it still decodes.
- `RegionDrawingLayer(onDrag:)`: the geometry so far while a region is being drawn (`id` nil) or moved or resized (`id` set), nil when the drag ends, so a room can follow the pointer with its spectrum.

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
An app adds the product `ShellSpectroscopy` to its target and imports it where it uses a piece; no call site of 0.1.0 changes. The region model is plain values in scan pixels (the app maps its own regions to `SpectralRegionSet`, and a drawn `RegionGeometry` to the kit's shape); `docs/macemui.md` in macEM-suite lists the pieces.

## 0.1.0 (2026-10-22)

The shared window shell of mac4DSTEM and macTEM, cut from mac4DSTEM `8c4c06d` and macTEM `51c944c`, compiled and adopted by both apps
the same day. Four products: ShellMetal (the Metal image view, display transform, colormaps), ShellControls (zoom and pan, number
fields, scale bar, colorbar, histogram chart, pane footer), ShellInspector (the inspector row kit) and ShellLayout (layout policy, panel
navigation, menu relay, activity log, system monitor, window skeleton, toolbar, sidebar and inspector frames, the infobar and process area,
Output). The histogram footer prints 4 significant digits with Reset Range on its own line.

### Migration
Both apps add the package (local path `../MacEMUI` in development, exact tag `0.1.0` at closeout), import the modules they use
(`MemberImportVisibility` is on), delete their copies and the `PROVENANCE` headers. An app's own room enum conforms to `WorkspaceRoom`
(`nonisolated`), holds a `PanelNavigation` as `panels`, and takes `ShellWindow`, `WorkspaceColumn`, `WorkspaceSidebarFrame` and
`WorkspaceInspectorFrame` for its chrome; `docs/split-reports` in macEM-suite lists every call-site change.
