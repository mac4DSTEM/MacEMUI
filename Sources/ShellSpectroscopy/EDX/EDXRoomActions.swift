// What the EDS room's views ask of the window around them: where a status line and an error go, the folder a UI journey's exports
// land in, and the exports only one app makes. Each app builds it from its own window state; the room holds none of it.
import Foundation

/// The window's side of the shared EDS room's views, built by the app on the main actor. The views keep it, so its closures capture the
/// window weakly (`[weak self]`), as the session's `onEvent`, `onFailure` and `onQuantMapsChange` do.
public struct EDXRoomActions {
    /// A line for the window's status bar ("Exported results.csv").
    public var report: (String) -> Void
    /// An error the person must see.
    public var present: (any Error) -> Void
    /// The folder exports are written to without a save panel (a UI journey's), read when an export starts; nil asks.
    public var exportDirectory: () -> URL?
    /// Every phase pool fitted with the room's method as one CSV (mac4DSTEM); nil hides the button.
    public var exportCompositionByClass: (() async -> Void)?

    public init(report: @escaping (String) -> Void, present: @escaping (any Error) -> Void, exportDirectory: @escaping () -> URL? = { nil },
                exportCompositionByClass: (() async -> Void)? = nil) {
        self.report = report; self.present = present; self.exportDirectory = exportDirectory
        self.exportCompositionByClass = exportCompositionByClass
    }
}
