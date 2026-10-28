// What the shared EDS room needs from the app it sits in: the names its export files carry and how the app opens a spectrum
// file. Each app opens files through its own routing (macTEM's `FileRouting`, mac4DSTEM's), so the reader is the app's; the room
// only calls it off the main actor.
import Foundation
import SpectroCore

/// The app's side of the shared EDS room, given once to `EDXSession(host:)`. `open` runs off the main actor: it must not touch the
/// app's main-actor state.
public nonisolated struct EDXRoomHost: Sendable {
    /// The app's name: the `.msa` creator and the first word of the results and spectrum CSV titles ("macTEM").
    public var appName: String
    /// The provenance source of an exported `.msa` ("macTEM EDX room").
    public var roomSource: String
    /// The first `#` line of the regions CSV ("macTEM EDX pins").
    public var regionsTitle: String
    /// File extensions the room's Open panel offers.
    public var readableExtensions: [String]
    /// Reads the whole spectrum image: called off the main actor, cancellable through the calling task, `progress` 0...1.
    public var open: @Sendable (_ url: URL, _ progress: @escaping @Sendable (Double) -> Void) throws -> LoadedSpectrumImage

    public init(appName: String, roomSource: String, regionsTitle: String, readableExtensions: [String],
                open: @escaping @Sendable (_ url: URL, _ progress: @escaping @Sendable (Double) -> Void) throws -> LoadedSpectrumImage) {
        self.appName = appName; self.roomSource = roomSource; self.regionsTitle = regionsTitle
        self.readableExtensions = readableExtensions; self.open = open
    }

    /// The first `#` line of the results CSV; the kit's own default is the neutral "Spectroscopy quantification".
    public var resultsTitle: String { "\(appName) Spectroscopy quantification" }
}
