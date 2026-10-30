# Open items

- Public symbols neither app uses (`MapTileGrid`, `MapTileSize`, `MapTileSizePicker`, `MapMixControls`, `SpectrumPaneTabs`,
  the `colorbar:` and `valueText:` parameters of `MapTileView`, the UIKit branch of `MetalImageView`, and others) are
  removed in the 0.4.0 break: issue #8.
- A double click on a tile also fires its single click (the mix toggles twice, net nothing); a two-step tap gesture would avoid the flicker.
