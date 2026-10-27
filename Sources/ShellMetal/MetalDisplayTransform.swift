import CoreGraphics
import simd

/// Where the image sits in the pane, as the pane's SwiftUI layer would draw it.
///
/// The chain SwiftUI applies to an image-local point `p` (`imageBox` coordinates,
/// origin top-left): `pc = p - imageBox/2`, rotate clockwise by `rotationDegrees`
/// (y down), mirror x if `mirrored`, scale by `zoom`, then
/// `screen = s + offset + paneSize/2`. The vertex shader draws through the exact
/// inverse, so the Metal view can stay pane-sized and untransformed while the
/// overlays keep the one SwiftUI transform.
public nonisolated struct MetalDisplayTransform: Equatable, Sendable {
    public var paneSize: CGSize          // the Metal view's size
    public var imageBox: CGSize          // the image's laid-out size before rotation, centred in the pane
    public var zoom: CGFloat = 1         // scaleEffect about the pane centre
    public var offset: CGSize = .zero    // .offset after the zoom, screen points
    public var rotationDegrees: Double = 0   // clockwise positive, y down
    public var mirrored: Bool = false    // x mirrored after the rotation

    public init(
        paneSize: CGSize, imageBox: CGSize, zoom: CGFloat = 1, offset: CGSize = .zero,
        rotationDegrees: Double = 0, mirrored: Bool = false
    ) {
        self.paneSize = paneSize
        self.imageBox = imageBox
        self.zoom = zoom
        self.offset = offset
        self.rotationDegrees = rotationDegrees
        self.mirrored = mirrored
    }

    public static func identity(_ size: CGSize) -> MetalDisplayTransform {
        MetalDisplayTransform(paneSize: size, imageBox: size)
    }

    /// Pane point (points, origin top-left) to image uv (0...1 inside the image).
    public func uv(atPanePoint p: CGPoint) -> CGPoint {
        // Inverse of the forward chain, step by step.
        let z = max(Double(zoom), 1e-9)
        let sx = (Double(p.x) - Double(offset.width) - Double(paneSize.width) / 2) / z
        let sy = (Double(p.y) - Double(offset.height) - Double(paneSize.height) / 2) / z
        let rx = mirrored ? -sx : sx
        let ry = sy
        let theta = rotationDegrees * Double.pi / 180
        let c = cos(theta), s = sin(theta)
        // R(theta)^-1 = [[c, s], [-s, c]]
        let pcx = c * rx + s * ry
        let pcy = -s * rx + c * ry
        let w = max(Double(imageBox.width), 1e-9)
        let h = max(Double(imageBox.height), 1e-9)
        return CGPoint(x: (pcx + w / 2) / w, y: (pcy + h / 2) / h)
    }

    /// The same map on pane-normalised q (0...1): uv = A q + t, as the two rows
    /// the vertex shader reads, (A00, A01, t0, 0) and (A10, A11, t1, 0).
    func shaderRows() -> (SIMD4<Float>, SIMD4<Float>) {
        let t = uv(atPanePoint: .zero)
        let ex = uv(atPanePoint: CGPoint(x: paneSize.width, y: 0))
        let ey = uv(atPanePoint: CGPoint(x: 0, y: paneSize.height))
        let a00 = ex.x - t.x, a10 = ex.y - t.y
        let a01 = ey.x - t.x, a11 = ey.y - t.y
        return (SIMD4<Float>(Float(a00), Float(a01), Float(t.x), 0),
                SIMD4<Float>(Float(a10), Float(a11), Float(t.y), 0))
    }
}
