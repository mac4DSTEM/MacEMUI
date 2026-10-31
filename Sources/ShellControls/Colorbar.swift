import ShellMetal
import SwiftUI

// MARK: - Colorbar

/// Numeric scalar legend for the exact colormap and contrast window displayed
/// by a pane. Pre-colored scientific images use their own directional keys.
public struct Colorbar: View {
    let colormap: ColormapKind
    let low: Double
    let high: Double
    let unitLabel: String
    var gamma: Float = 1
    var marksZero = false
    /// True when the displayed image contains masked (no-data) pixels, which
    /// render as neutral gray; adds a swatch so the gray is self-explanatory.
    var showsMasked = false

    public init(colormap: ColormapKind, low: Double, high: Double, unitLabel: String,
                gamma: Float = 1, marksZero: Bool = false, showsMasked: Bool = false) {
        self.colormap = colormap
        self.low = low
        self.high = high
        self.unitLabel = unitLabel
        self.gamma = gamma
        self.marksZero = marksZero
        self.showsMasked = showsMasked
    }

    /// Drawing geometry: the width of the colour strip and of the numeric row
    /// under it, which must agree so the end labels sit at the strip's ends.
    private static let stripWidth: CGFloat = 132
    private static let stripHeight: CGFloat = 9

    public var body: some View {
        // Built here, on the main actor, so the Canvas closure captures plain values.
        // The image's own LUT (`MetalImageView` uploads 256 entries), sampled as its shader samples it.
        let lut = Colormaps.lutRGBA(colormap, count: 256)
        let barGamma = gamma, barLow = low, barHigh = high, barMarksZero = marksZero
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                // One column per point, at least the old 128, so no step is wider than a point.
                let columns = max(128, Int(size.width.rounded(.up)))
                let stripWidth = size.width / CGFloat(columns)
                for index in 0..<columns {
                    let fraction = Float(index) / Float(columns - 1)
                    let mapped = pow(fraction, 1 / max(barGamma, 0.05))
                    let rgb = Self.stripRGB(lut, at: mapped)
                    let color = Color(red: rgb.x, green: rgb.y, blue: rgb.z)
                    context.fill(Path(CGRect(x: CGFloat(index) * stripWidth, y: 0,
                                             width: stripWidth + 0.5, height: size.height)),
                                 with: .color(color))
                }
                if barMarksZero, barLow < 0, barHigh > 0 {
                    let fraction = CGFloat(-barLow / (barHigh - barLow))
                    let x = fraction * size.width
                    context.stroke(Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }, with: .color(.white), lineWidth: 1)
                }
            }
            .frame(width: Self.stripWidth, height: Self.stripHeight)
            .overlay(RoundedRectangle(cornerRadius: 1)
                .stroke(Color.white.opacity(0.45), lineWidth: 0.5))

            HStack(spacing: 4) {
                Text(Self.format(low))
                Spacer()
                if marksZero, low < 0, high > 0 { Text("0") }
                Spacer()
                Text(Self.format(high))
            }
            .frame(width: Self.stripWidth)
            if !unitLabel.isEmpty {
                Text(unitLabel)
                    .foregroundStyle(.white.opacity(0.75))
            }
            if showsMasked {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1)
                        // The exact neutral gray the renderer writes for a
                        // masked (no-fit) pixel — a scientific key, not a tint.
                        .fill(Color(red: 0.32, green: 0.32, blue: 0.34))
                        .frame(width: 10, height: 7)
                        .overlay(RoundedRectangle(cornerRadius: 1)
                            .stroke(Color.white.opacity(0.45), lineWidth: 0.5))
                    Text("masked · no fit")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        // Legibility plate over the image, as on the scale bar.
        .background(Color.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 4))
        // This view is the LABEL of `ColormapChip`'s button (R23):
        // `.allowsHitTesting(false)` here would make the button's whole area
        // transparent to real clicks, though AXPress would still open the
        // popover. Plain (non-button) uses opt out at their call site instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color scale from \(Self.format(low)) to \(Self.format(high)) \(unitLabel)"
                            + (showsMasked ? ", gray marks masked pixels with no fit" : ""))
    }

    /// The strip colour at `v` (0...1, after gamma), as the Metal view samples its LUT texture: a linear filter
    /// between texel centres at (i + 0.5) / count, clamped to the edge entries (`Colormaps.metal`, `lutSampler`).
    /// The strip is then the same colour function as the image beside it, smooth at any width (MacEMUI#44).
    nonisolated static func stripRGB(_ lut: [UInt8], at v: Float) -> SIMD3<Double> {
        let count = lut.count / 4
        let position = Double(min(max(v, 0), 1)) * Double(count) - 0.5
        let below = Int(position.rounded(.down))
        let weight = position - Double(below)
        let lower = min(max(below, 0), count - 1), upper = min(max(below + 1, 0), count - 1)
        func entry(_ index: Int) -> SIMD3<Double> {
            SIMD3(Double(lut[index * 4]), Double(lut[index * 4 + 1]), Double(lut[index * 4 + 2]))
        }
        return (entry(lower) * (1 - weight) + entry(upper) * weight) / 255
    }

    /// The range ends in the reader's locale, the same decimal mark as the scale bar beside them.
    public nonisolated static func format(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        let text = magnitude >= 10_000 || magnitude < 0.001
            ? String(format: "%.2e", value) : String(format: "%.4g", value)
        guard let mark = locale.decimalSeparator, mark != "." else { return text }
        return text.replacingOccurrences(of: ".", with: mark)
    }
}

// MARK: - Colormap chip

/// Colormap choice lives ON the colorbar chip in each pane — click the
/// gradient you are already looking at, pick from real swatches (owner
/// decision D3). The chip exists wherever its pane exists, so there is no
/// separate scoping concern like the old sidebar Display row had.
///
/// **Popover, not Menu — R23.** AppKit hosts a menu-button's label itself and
/// does not render a SwiftUI `Canvas` there, so a `Menu`-based chip loses its
/// gradient. A `.popover` is presented SwiftUI-side, so the chip and the
/// swatches render exactly as authored.
///
/// The popover's content is the caller's: this type owns the button, its help and VoiceOver text and the popover's shell
/// (grouped Form look, fixed width, content height).
public struct ColormapChip<Chip: View, PopoverContent: View>: View {
    @State private var isPresented = false

    private let help: String
    private let accessibilityText: String
    private let identifier: String
    private let popoverWidth: CGFloat
    private let chip: Chip
    private let popoverContent: PopoverContent

    /// - `help`: the tooltip. `accessibilityText`: what VoiceOver says. `identifier`: the UI-test identifier
    ///   ("pane.colormap.diffraction"). `popoverWidth`: 280 is the apps' control-popover width.
    public init(help: String, accessibilityText: String, identifier: String, popoverWidth: CGFloat = 280,
                @ViewBuilder chip: () -> Chip, @ViewBuilder popover: () -> PopoverContent) {
        self.help = help
        self.accessibilityText = accessibilityText
        self.identifier = identifier
        self.popoverWidth = popoverWidth
        self.chip = chip()
        self.popoverContent = popover()
    }

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            chip
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(identifier)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            popoverContent
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(width: popoverWidth)
                // Content height, not a scroller's default: with the
                // histogram and gamma moved in, the grouped Form stopped at
                // ~300 pt and hid its last rows behind a scroll.
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
