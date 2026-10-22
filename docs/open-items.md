# Open items

- `MapTileView` still accepts `colorbar:` and `valueText:` and ignores them (mac4DSTEM's call site); delete at 0.4.0.
- `MapTileGrid`, `MapTileSize`, `MapTileSizePicker` are superseded by the fitted grid; delete at 0.4.0 once mac4DSTEM has moved.
- `MapColorControls(startExpanded:)` stays for the EELS room's popover until it adopts `MapDisplayPopover`.
- A double click on a tile also fires its single click (the mix toggles twice, net nothing); a two-step tap gesture would avoid the flicker.
- The View menu's Zoom commands are not wired to `MapViewTransform` (the maps have VoiceOver's zoom actions and the wheel, pinch and double click).
