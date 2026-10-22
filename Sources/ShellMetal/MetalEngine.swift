// MOVED FROM: mac4DSTEM@8c4c06d mac4DSTEM/Core/Compute/MetalEngine.swift (macTEM@51c944c Sources/TEMCore/Compute/MetalEngine.swift folded in: `: Sendable`; mac4DSTEM's extra lines were only the role comment and `import MetalKit`)
// Changes: made public (shared, device, queue); library and display pipelines internal; library loads from this package's bundle; comment no longer names an app type.
// END MOVED FROM
//
//  MetalEngine.swift
//  Role: The one place that owns the GPU — MTLDevice, command queue, the
//        compiled shader library, the render pipelines used by MetalImageView,
//        (compute lives in the kits: CuboKit's reducers, DiffractoKit's matchers).
//
//  ISOLATION: marked `nonisolated` so it is NOT bound to the project's default
//  MainActor isolation. GPU dispatches block on waitUntilCompleted, so they
//  must run on background tasks — this lets an app's state object call them from
//  Task.detached without hopping back to the main actor.
//

import Foundation
import Metal

public nonisolated enum MetalError: LocalizedError {
    case noDevice
    case noLibrary
    case functionMissing(String)
    case dispatchFailed(String)
    public var errorDescription: String? {
        switch self {
        case .noDevice: return "No Metal-capable GPU was found."
        case .noLibrary: return "Could not load the compiled Metal shader library (default.metallib)."
        case .functionMissing(let n): return "Metal function '\(n)' was not found in the library."
        case .dispatchFailed(let n): return "GPU dispatch '\(n)' failed."
        }
    }
}

// MARK: - MetalEngine

public nonisolated final class MetalEngine: Sendable {  // DEVIATION: `: Sendable` — Swift 6 refuses a non-Sendable `static let shared`; this subset holds only Sendable Metal objects

    public static let shared = MetalEngine()

    public let device: MTLDevice
    public let queue: MTLCommandQueue
    let library: MTLLibrary

    // Render pipelines for the textured-quad image display:
    // scalar (LUT colormap) and pre-colored RGBA results.
    let displayPSO: MTLRenderPipelineState
    let displayRGBAPSO: MTLRenderPipelineState

    private init() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            fatalError(MetalError.noDevice.localizedDescription)
        }
        guard let q = dev.makeCommandQueue() else {
            fatalError("Could not create a Metal command queue.")
        }
        // Colormaps.metal is a resource of this package, so its library is in the package's bundle,
        // not the app's default library.
        guard let lib = try? dev.makeDefaultLibrary(bundle: .module) else {
            fatalError(MetalError.noLibrary.localizedDescription)
        }
        self.device = dev
        self.queue = q
        self.library = lib

        // Display render pipelines (fullscreen triangle; LUT and RGBA fragments).
        func display(fragment: String) -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "displayVertex")
            desc.fragmentFunction = lib.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm   // MTKView default
            do { return try dev.makeRenderPipelineState(descriptor: desc) }
            catch { fatalError("Display pipeline (\(fragment)) build failed: \(error)") }
        }
        self.displayPSO = display(fragment: "colormapFragment")
        self.displayRGBAPSO = display(fragment: "rgbaFragment")

        print("[MetalEngine] GPU: \(dev.name), maxWorkingSet ≈ \(dev.recommendedMaxWorkingSetSize / 1_048_576) MB")
    }
}
