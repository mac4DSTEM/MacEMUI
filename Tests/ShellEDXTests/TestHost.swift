//  The host the package's EDS-room tests run under: a neutral name and SpectroKit's own opener (a Velox EMD, a GMS DM4), without
//  either app's file routing.
import Foundation
import SpectroCore
import ShellEDXModel

extension EDXRoomHost {
    nonisolated static let test = EDXRoomHost(appName: "Test", roomSource: "Test EDS room", regionsTitle: "Test EDS regions",
                                  readableExtensions: ["emd", "dm4"]) { url, progress in
        try SpectrumImageOpener.open(path: url.path, kind: SpectrumImageOpener.kind(ofFileAt: url.path), progress: progress)
    }
}
