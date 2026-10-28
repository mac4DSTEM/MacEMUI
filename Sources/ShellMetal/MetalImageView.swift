import SwiftUI
import MetalKit

/// The one SwiftUI to Metal bridge in UI: a single-channel image already
/// normalised to [0, 1], drawn through `MetalEngine`'s display pipeline
/// (fullscreen triangle + colormap LUT), or packed RGBA8 bytes drawn
/// through the RGBA pipeline.
///
/// **Contract**
/// - `pixels` is already normalised (`FloatImage.normalized` /
///   `DiffractionPattern.normalized`). Masked pixels are the negative
///   `FloatImage.invalidDisplayValue` sentinel and render as neutral gray.
/// - `contentVersion` MUST change whenever `pixels` or `rgba` changes: the
///   coordinator re-uploads the texture only on a version change, which is
///   what keeps zooming and panning free. Passing a literal `0` here is the
///   defect that froze a comparison panel on the previous product's pixels.
///
/// **Why it is still a platform representable.** Everything else in UI is
/// plain SwiftUI, but there is no SwiftUI view that samples a float texture
/// through a LUT with a display window and gamma in the fragment shader, and
/// the alternative — rasterising to a `CGImage` per frame — would cost the
/// interactive contrast, gamma and colormap the science depends on. The
/// wrapper is deliberately shaped for both platforms: the shared body is
/// `makeMetalView`/`updateMetalView`, and only the two-line platform
/// conformance differs, so an iOS target needs no rewrite.
///
/// A zoomed pane does NOT scale this view with SwiftUI's `scaleEffect`: that
/// raised the hosted layer's scale and the drawable followed it (914² at 1×,
/// 14656² at 16× on a 458 pt pane, 1.3 GB resident, measured 2026-10-12). The
/// view stays pane-sized and untransformed behind the overlay layer, and the
/// vertex shader draws the image through one `MetalDisplayTransform` that
/// inverts the same zoom, offset, rotation and mirroring SwiftUI applies to
/// the overlays. `nil` means the whole image over the view's own bounds.
// AppKit: an NSViewRepresentable over MTKView, because no SwiftUI view samples a float texture through a LUT with window and gamma in the fragment shader (see Why above).
public struct MetalImageView {
    /// A version derived from the pixel VALUES and the dimensions. O(n)
    /// FNV-1a — call it where the pixels are produced, once per image, never
    /// inside a `body`. Dimensions are folded in because the coordinator
    /// short-circuits on the version before it looks at width and height, so
    /// identical pixels at transposed dimensions must still re-upload.
    public nonisolated static func contentVersion(
        of pixels: [Float], width: Int, height: Int
    ) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        hash = (hash ^ UInt64(truncatingIfNeeded: width)) &* 0x0000_0100_0000_01b3
        hash = (hash ^ UInt64(truncatingIfNeeded: height)) &* 0x0000_0100_0000_01b3
        for value in pixels {
            hash = (hash ^ UInt64(value.bitPattern)) &* 0x0000_0100_0000_01b3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }

    /// Folds packed RGBA bytes into a scalar version. An RGBA payload carries
    /// an all-zero `pixels` array, so hashing the pixels alone gives every
    /// same-sized RGBA product the same version — an IPF map and a DPC colour
    /// wheel of equal size would be indistinguishable and one would keep the
    /// other's texture.
    public nonisolated static func contentVersion(
        of pixels: [Float], rgba: [UInt8]?, width: Int, height: Int
    ) -> Int {
        let base = contentVersion(of: pixels, width: width, height: height)
        guard let rgba else { return base }
        return rgba.withUnsafeBytes { bytes -> Int in
            var hash = UInt64(bitPattern: Int64(base))
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
            return Int(bitPattern: UInt(truncatingIfNeeded: hash))
        }
    }

    public var pixels: [Float]          // normalised [0, 1], row-major
    public var width: Int
    public var height: Int
    public var contentVersion: Int
    public var colormap: ColormapKind
    /// When set, these packed RGBA8 bytes (width x height x 4) are drawn
    /// instead of `pixels` + colormap.
    public var rgba: [UInt8]?
    /// Display contrast window in normalised [0, 1] intensity, applied in the
    /// fragment shader — cheap, per frame.
    public var displayLo: Float
    public var displayHi: Float
    public var gamma: Float
    /// Where the image sits in the pane; nil = the whole image over the view.
    public var displayTransform: MetalDisplayTransform?

    public func displayTransform(_ transform: MetalDisplayTransform) -> MetalImageView {
        var copy = self
        copy.displayTransform = transform
        return copy
    }

    public init(
        pixels: [Float],
        width: Int,
        height: Int,
        contentVersion: Int,
        colormap: ColormapKind = .viridis,
        rgba: [UInt8]? = nil,
        displayLo: Float = 0,
        displayHi: Float = 1,
        gamma: Float = 1
    ) {
        self.pixels = pixels
        self.width = width
        self.height = height
        self.contentVersion = contentVersion
        self.colormap = colormap
        self.rgba = rgba
        self.displayLo = displayLo
        self.displayHi = displayHi
        self.gamma = gamma
    }

    /// Everything that decides what the pane draws, minus the pixel arrays
    /// (their `contentVersion` stands in for them). `updateMetalView` skips the
    /// redraw when this equals what the coordinator last applied, so a SwiftUI
    /// update that changed nothing the pane shows (a hover or pan tick
    /// elsewhere in the room) does not re-encode a frame.
    struct AppliedState: Equatable {
        var contentVersion: Int
        var width: Int
        var height: Int
        var colormap: ColormapKind
        var displayLo: Float
        var displayHi: Float
        /// The gamma the shader receives (`max(gamma, 0.05)`), not the raw one.
        var effectiveGamma: Float
        var hasRGBA: Bool
        var displayTransform: MetalDisplayTransform?
    }

    /// The state this view asks the coordinator to show.
    var appliedState: AppliedState {
        AppliedState(
            contentVersion: contentVersion, width: width, height: height,
            colormap: colormap, displayLo: displayLo, displayHi: displayHi,
            effectiveGamma: max(gamma, 0.05), hasRGBA: rgba != nil,
            displayTransform: displayTransform)
    }

    fileprivate func makeMetalView(_ coordinator: Coordinator) -> MTKView {
        let view = ScaleAwareMTKView(frame: .zero, device: MetalEngine.shared.device)
        view.colorPixelFormat = .bgra8Unorm            // must match displayPSO
        view.clearColor = MTLClearColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1)
        view.framebufferOnly = true
        view.layer?.isOpaque = false                    // outside the image the fragment is transparent
        view.isPaused = true                            // redraw only on demand
        view.enableSetNeedsDisplay = true
        view.delegate = coordinator
        // The shader samples the data texture nearest, so zoomed data pixels
        // stay crisp; this keeps the layer itself from interpolating either.
        view.layer?.magnificationFilter = .nearest
        return view
    }

    fileprivate func updateMetalView(_ view: MTKView, _ coordinator: Coordinator) {
        coordinator.colormap = colormap
        coordinator.updateContentIfNeeded(
            pixels: pixels, rgba: rgba,
            width: width, height: height, version: contentVersion
        )
        coordinator.displayRange = SIMD2<Float>(displayLo, displayHi)
        coordinator.gamma = max(gamma, 0.05)
        coordinator.displayTransform = displayTransform
        // Redraw only when something the pane shows changed (a size or scale
        // change redraws through `drawableSizeWillChange` and the window hooks).
        let state = appliedState
        guard coordinator.lastApplied != state else { return }
        coordinator.lastApplied = state
        view.needsDisplay = true
    }

    /// An `MTKView` that keeps its layer's `contentsScale` in step with the
    /// window it is in.
    ///
    /// Measured 2026-08-27: inside a SwiftUI sheet the hosted `MTKView`'s
    /// `CAMetalLayer` is left at `contentsScale == 0`, and a layer at scale 0
    /// cannot display a drawable — the pane stays exactly the background
    /// colour while every internal signal (drawable size, render pass,
    /// current drawable, uploaded texture) looks healthy. What writes the 0
    /// was never identified, which is why the `!=` guard matters: this must
    /// not fight whatever does the writing.
    final class ScaleAwareMTKView: MTKView {
        private func matchWindowScale() {
            #if os(macOS)
            guard let scale = window?.backingScaleFactor, scale > 0 else { return }
            #else
            guard let scale = window?.screen.scale, scale > 0 else { return }
            #endif
            guard layer?.contentsScale != scale else { return }
            layer?.contentsScale = scale
            #if os(macOS)
            needsDisplay = true
            #else
            setNeedsDisplay()
            #endif
        }

        #if os(macOS)
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            matchWindowScale()
            // An update that arrived before the view had a window drew nothing
            // (and updates no longer redraw unconditionally), so draw on entry.
            if window != nil { needsDisplay = true }
        }
        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            matchWindowScale()
        }
        #else
        override func didMoveToWindow() {
            super.didMoveToWindow()
            matchWindowScale()
            if window != nil { setNeedsDisplay() }
        }
        #endif
    }

    // MARK: - Coordinator (the MTKView delegate / renderer)

    public final class Coordinator: NSObject, MTKViewDelegate {
        /// Setting the same colormap again (every SwiftUI update does) must not
        /// rebuild the LUT and allocate a new texture.
        var colormap: ColormapKind = .viridis {
            didSet { if colormap != oldValue { lutDirty = true } }
        }
        /// What the last requested redraw was for; nil until the first update
        /// and again after a draw that could not present, so the next update
        /// draws.
        var lastApplied: AppliedState?
        var displayRange = SIMD2<Float>(0, 1)
        var gamma: Float = 1
        var displayTransform: MetalDisplayTransform?

        private var dataTexture: MTLTexture?
        private var rgbaTexture: MTLTexture?
        private var lutTexture: MTLTexture?
        private(set) var lutDirty = true
        private var version = Int.min

        func updateContentIfNeeded(
            pixels: [Float], rgba: [UInt8]?, width: Int, height: Int, version v: Int
        ) {
            guard v != version else { return }
            version = v
            guard width > 0, height > 0 else {
                dataTexture = nil
                rgbaTexture = nil
                return
            }
            if let rgba, rgba.count == width * height * 4 {
                rgbaTexture = MetalEngine.shared.device.makeRGBATexture(
                    rgba: rgba, width: width, height: height)
                dataTexture = nil
            } else if pixels.count == width * height {
                dataTexture = MetalEngine.shared.device.makeFloatTexture(
                    pixels: pixels, width: width, height: height)
                rgbaTexture = nil
            } else {
                dataTexture = nil
                rgbaTexture = nil
            }
        }

        func rebuildLUTIfNeeded() {
            guard lutDirty || lutTexture == nil else { return }
            lutTexture = MetalEngine.shared.device.makeLUTTexture(
                rgba: Colormaps.lutRGBA(colormap, count: 256))
            lutDirty = false
        }

        public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // `updateMetalView` no longer redraws on every update, so a resize
            // or a backing-scale change asks for its own frame.
            #if os(macOS)
            view.needsDisplay = true
            #else
            view.setNeedsDisplay()
            #endif
        }

        public func draw(in view: MTKView) {
            rebuildLUTIfNeeded()

            guard let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = MetalEngine.shared.queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
            else {
                // Nothing was presented (no window or drawable yet): forget the
                // applied state so the next update draws instead of being skipped.
                lastApplied = nil
                return
            }

            let engine = MetalEngine.shared
            if rgbaTexture != nil {
                encoder.setRenderPipelineState(engine.displayRGBAPSO)
            } else if dataTexture != nil, lutTexture != nil {
                encoder.setRenderPipelineState(engine.displayPSO)
            } else {
                encoder.endEncoding()
                buffer.present(drawable)
                buffer.commit()
                return
            }

            // Two rows (pane-normalised q -> image uv); identity without a transform.
            let identityRows = (SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0))
            let r = displayTransform?.shaderRows() ?? identityRows
            var rows = [r.0, r.1]
            encoder.setVertexBytes(
                &rows, length: 2 * MemoryLayout<SIMD4<Float>>.stride, index: 0)

            if let rgbaTexture {
                encoder.setFragmentTexture(rgbaTexture, index: 0)
            } else {
                var display = SIMD4<Float>(displayRange.x, displayRange.y, gamma, 0)
                encoder.setFragmentBytes(
                    &display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.setFragmentTexture(dataTexture, index: 0)
                encoder.setFragmentTexture(lutTexture, index: 1)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

#if os(macOS)
extension MetalImageView: NSViewRepresentable {
    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> MTKView { makeMetalView(context.coordinator) }
    public func updateNSView(_ view: MTKView, context: Context) {
        updateMetalView(view, context.coordinator)
    }
}
#else
extension MetalImageView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> MTKView { makeMetalView(context.coordinator) }
    func updateUIView(_ view: MTKView, context: Context) {
        updateMetalView(view, context.coordinator)
    }
}
#endif
