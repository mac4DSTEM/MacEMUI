# Changelog

MacEMUI follows semantic versioning; before 1.0.0 a minor version may break the API, and its Migration paragraph says how.

## Unreleased (0.2.1)

### Added
- `MapColoring` (black to one colour, or one of the shared colormaps), `MapAppearance` (the person's choice per map and the colour mix; Codable), `ColorMix`, `MapRaster` (`rgba` for one map, `mix` for the colour mix of several, pure) and `MapColorControls`, the Maps section's rows: a colour or colormap per map and the Colour mix with the maps in it. `ColormapKind` is Codable.
- `MapAdjustment` (a map's contrast window as fractions of its scale, and its gamma) kept in `MapAppearance.adjustments`, applied by `MapRaster.rgba(…adjustment:)` and each `MixLayer`, and set by a slider disclosure on every row of `MapColorControls`; an appearance saved before it still decodes.
- `RegionDrawingLayer(onDrag:)`: the geometry so far while a region is being drawn (`id` nil) or moved or resized (`id` set), nil when the drag ends, so a room can follow the pointer with its spectrum.

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
