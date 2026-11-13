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

public nonisolated enum MetalError: LocalizedError, Sendable {
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

    /// The engine, or why Metal could not start (no GPU, no queue, no shader library, no pipeline). Built once, at first use.
    public static let startup: Result<MetalEngine, MetalError> = Result { try MetalEngine() }.mapError { $0 as? MetalError ?? .noDevice }

    /// The engine when Metal started, nil when it did not. The shell's panes use this and show why instead of crashing.
    public static var available: MetalEngine? { try? startup.get() }

    /// The engine. Traps when Metal did not start; a caller that can carry on without the GPU uses `available` (MacEMUI#124).
    public static var shared: MetalEngine {
        switch startup {
        case .success(let engine): return engine
        case .failure(let error): fatalError(error.localizedDescription)
        }
    }

    public let device: MTLDevice
    public let queue: MTLCommandQueue
    let library: MTLLibrary

    // Render pipelines for the textured-quad image display:
    // scalar (LUT colormap) and pre-colored RGBA results.
    let displayPSO: MTLRenderPipelineState
    let displayRGBAPSO: MTLRenderPipelineState

    private init() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else { throw MetalError.noDevice }
        guard let q = dev.makeCommandQueue() else { throw MetalError.noDevice }
        let lib: MTLLibrary
        do { lib = try Self.loadLibrary(dev) } catch { throw MetalError.noLibrary }
        self.device = dev
        self.queue = q
        self.library = lib

        // Display render pipelines (fullscreen triangle; LUT and RGBA fragments).
        func display(fragment: String) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            guard let vertex = lib.makeFunction(name: "displayVertex") else { throw MetalError.functionMissing("displayVertex") }
            guard let shader = lib.makeFunction(name: fragment) else { throw MetalError.functionMissing(fragment) }
            desc.vertexFunction = vertex
            desc.fragmentFunction = shader
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm   // MTKView default
            do { return try dev.makeRenderPipelineState(descriptor: desc) } catch { throw MetalError.dispatchFailed("display pipeline \(fragment)") }
        }
        self.displayPSO = try display(fragment: "colormapFragment")
        self.displayRGBAPSO = try display(fragment: "rgbaFragment")

        print("[MetalEngine] GPU: \(dev.name), maxWorkingSet ≈ \(dev.recommendedMaxWorkingSetSize / 1_048_576) MB")
    }

    /// Colormaps.metal is a resource of this package, so its library is in the package's bundle, not the app's default
    /// library. Xcode compiles it to the bundle's default.metallib; `swift build` with Xcode 26.6 copies the source
    /// unchanged (the bundle holds Colormaps.metal and no metallib, MTLLibraryErrorDomain code 6), so the library is
    /// then compiled from that source at first use.
    static func loadLibrary(_ dev: MTLDevice) throws -> MTLLibrary {
        if let lib = try? dev.makeDefaultLibrary(bundle: .module) { return lib }
        guard let url = Bundle.module.url(forResource: "Colormaps", withExtension: "metal") else {
            throw MetalError.noLibrary
        }
        return try dev.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
    }
}
