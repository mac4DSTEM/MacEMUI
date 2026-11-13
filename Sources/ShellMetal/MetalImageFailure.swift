//
//  MetalImageFailure.swift
//  Role: Why an image pane shows nothing, in words on the pane (MacEMUI#124): Metal did not start, or the image is past what the
//        GPU can hold (a buffer past `maxBufferLength`, an RGBA texture past 16384 pixels a side). Before, the engine trapped at
//        start-up and an oversize image left the pane blank with no word.
//

import Foundation

public nonisolated enum MetalImageFailure: Equatable, Sendable {
    /// Metal did not start; the engine's reason.
    case noMetal(String)
    /// The image could not be placed on the GPU.
    case tooLarge(width: Int, height: Int)

    /// The longest side of a 2D texture on Apple GPUs.
    package static let maximumTextureSide = 16_384

    /// The line the pane shows.
    public var text: String {
        switch self {
        case .noMetal(let reason): return "Images cannot be drawn: Metal did not start. \(reason)"
        case .tooLarge(let width, let height):
            return "This image (\(width) × \(height) pixels) is larger than the GPU can draw. Crop or bin it to view it here."
        }
    }
}
