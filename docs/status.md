# Status

What is live. 0.5.1 (2026-11-05) is tagged; both apps take MacEMUI by version range and build on it.

- The window shell (`ShellLayout`): rooms, toolbar, sidebar and inspector frames, the centre column, `LayoutPolicy`,
  `MenuActionRelay`, `ActivityLog`, `UITestingPlacement`; `InspectorSection` can start closed and draws a status glyph.
- The controls (`ShellControls`, `ShellInspector`): zoom and pan, `NumericField` (typing the shown text over a finer stored
  value sets it), `PaneFooter`, `ScaleBar`, colorbar, `HistogramChart`, `SegmentedControl` and `SegmentedPicker` (a segment can be
  disabled, with its reason), the inspector row kit.
- The Metal image view (`ShellMetal`): `MetalEngine`, `MetalImageView`, `MetalDisplayTransform`, the shared colormaps and
  their shader (compiled from source when the bundle has no metallib); `ImageViewport`, one zoomable container for every room picture.
- The spectroscopy room (`ShellSpectroscopy`): map tiles (with an overlay slot) and the fitted map grid, the colour mix, regions
  (draw, edit, list, a keyboard route; Esc returns to the arrow tool), spectrum and profile panes, the periodic table, the map display popover.
- The shared EDS room (`ShellEDXModel` and `EDXRoom` in `ShellSpectroscopy`, 0.4.0): the model and session (`EDXSession`, regions,
  pins, maps, exports) that both apps showed as copies; each app passes `EDXRoomHost`, `EDXRoomActions` and its Open panel
  extensions. Results name the kept region, carry the whole value and its sigma, and say no "unvalidated"; the typed-k and
  factors sheets read either decimal separator and keep their accessibility identifiers.
- The agent door (`ShellAgentDoor`, since 0.6.0): a local API, off until the person turns it on in Settings, through which
  an agent on this Mac looks at the app's open windows; each app registers its own tools. The app is the MCP server itself,
  over HTTP at `/mcp`; Claude desktop connects through the extension in `DesktopExtension/` (`docs/agent-door.md`). Since
  0.7.0: typed inputs and tools that act (`AgentParameter`, `AgentTool(acts:)`), behind a second switch, "Let agents run
  analyses" (`runsAllowed`).

Since 0.3.2: 0.4.0 (2026-10-29) brought the shared EDS room; 0.5.0 (2026-11-01) `ImageViewport`, the keyboard and zoom routes,
the narrowed EDS room API and the deletion of the superseded map tile API; 0.5.1 (2026-11-05) the EDS sheet and header fixes.
Details and the migration notes: `CHANGELOG.md`.

Builds with Xcode 26.6 (macOS 26, what the apps' CI builds it with) and Xcode 27.1; CI runs `swift test -c release --parallel`
on both on every push (the Metal tests skip on a runner without a Metal device). What is open: the GitHub issues.
