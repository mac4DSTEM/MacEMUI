import SwiftUI

/// View > Zoom In, Zoom Out, Zoom to Fit: the mouse's and
/// the keyboard's way to what a pinch and a double-click do on the image panes.
///
/// The commands act on the pane that publishes its zoom as the focused scene value (`FocusedValues.paneZoom`, set by
/// `View.zoomCommandTarget`): the pane the reader last clicked, or the only image pane a room has. With none (no dataset, a room
/// without an image pane) they are disabled. The value is the pane's `PaneZoomModel`, a reference compared by identity; a closure
/// in a focused value would invalidate every reader on each update (swiftui-specialist, `environment.md`).
///
/// "Zoom to Fit" rather than "Actual Size": 1× here is the image fitted to the pane (`LayoutPolicy.fitted`), not one image pixel
/// per screen point, and a menu item must not say otherwise. The step is the VoiceOver step (a factor of 2). With the pointer
/// over the pane (the shortcut) the zoom is about the pointer; chosen with the mouse it is about the pane's centre.
///
/// Native menu items and the standard shortcuts (⌘+, ⌘−, ⌘0); no AppKit. Hooked up by one line in the app's `.commands`.
public struct ZoomCommands: Commands {
    @FocusedValue(\.paneZoom) private var zoom

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Zoom In") { zoom?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(zoom == nil)
            Button("Zoom Out") { zoom?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(zoom == nil)
            Button("Zoom to Fit") { zoom?.fit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(zoom == nil)
        }
    }
}
