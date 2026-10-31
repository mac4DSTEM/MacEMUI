// What the EDS room's views ask of the window around them: where a status line and an error go, the folder a UI journey's exports
// land in, the exports only one app makes, and the marks only one app draws over the maps. Each app builds it from its own window
// state; the room holds none of it.
import Foundation
import SwiftUI

/// The window's side of the shared EDS room's views, built by the app on the main actor. The views keep it, so its closures capture the
/// window weakly (`[weak self]`), as the session's `onEvent`, `onFailure` and `onQuantMapsChange` do.
///
/// The map overlay is here and not on `EDXRoomHost`: the host belongs to `ShellEDXModel`, which has no SwiftUI and runs its `open` off
/// the main actor; an overlay is a view, drawn on the main actor.
public struct EDXRoomActions {
    /// A line for the window's status bar ("Exported results.csv").
    public var report: (String) -> Void
    /// An error the person must see.
    public var present: (any Error) -> Void
    /// The folder exports are written to without a save panel (a UI journey's), read when an export starts; nil asks.
    public var exportDirectory: () -> URL?
    /// Every phase pool fitted with the room's method as one CSV (mac4DSTEM); nil hides the button.
    public var exportCompositionByClass: (() async -> Void)?
    /// The app's marks over a map tile (mac4DSTEM: its precipitate glyphs), drawn in `MapTileView`'s overlay slot: zoomed with the
    /// picture, under the regions, taking no clicks. Called with the tile's id (`"haadf"`, an element's symbol, or
    /// `EDXGridItem.mixID`) and the tile's `MapTileOverlayContext`; nil draws nothing. Read it only from values (no `@Observable`
    /// app state in the closure), or every tile redraws on any change of that state.
    public var mapOverlay: ((_ tileID: String, _ context: MapTileOverlayContext) -> AnyView)?

    public init(report: @escaping (String) -> Void, present: @escaping (any Error) -> Void, exportDirectory: @escaping () -> URL? = { nil },
                exportCompositionByClass: (() async -> Void)? = nil,
                mapOverlay: ((_ tileID: String, _ context: MapTileOverlayContext) -> AnyView)? = nil) {
        self.report = report; self.present = present; self.exportDirectory = exportDirectory
        self.exportCompositionByClass = exportCompositionByClass; self.mapOverlay = mapOverlay
    }
}
