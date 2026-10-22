# Changelog

MacEMUI follows semantic versioning; before 1.0.0 a minor version may break the API, and its Migration paragraph says how.

## Unreleased (0.2.0)

The spectroscopy rooms' shared chrome, built on what is new (design 2026-10-22): module `ShellSpectroscopy`.

### Added
- `VerticalPaneSplit`: maps over spectrum with a stored, keyboard-nudgeable, VoiceOver-adjustable divider.
- `MapTileGrid`, `MapTileSize`, `MapTileSizePicker`: the maps block reflows to a chosen tile size and shows one tile alone on a double click; `hoverChip(_:)` puts the pointer's value on a tile.

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
