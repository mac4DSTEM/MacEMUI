# Open items

- Public symbols neither app uses (`MapTileGrid`, `MapTileSize`, `MapTileSizePicker`, `MapMixControls`, `SpectrumPaneTabs`,
  the `colorbar:` and `valueText:` parameters of `MapTileView`, the UIKit branch of `MetalImageView`, and others) are
  removed in the 0.4.0 break: issue #8.
- The View menu's Zoom commands are not wired to `MapViewTransform` (the maps have VoiceOver's zoom actions and the wheel, pinch and double click).
