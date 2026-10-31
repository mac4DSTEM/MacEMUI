import AppKit
import SwiftUI
import XCTest
@testable import ShellInspector

/// The kit additions: `InspectorWarning` (the caption-size orange note) and
/// `InspectorAdaptiveMenu` (the menu twin of mac4DSTEM's `InspectorAdaptiveButton`).
/// Both are laid out through a hosting controller, the way
/// `InspectorWidthBudgetTests` measures a room.
nonisolated final class InspectorKitGapsTests: XCTestCase {
    @MainActor private func size<V: View>(_ view: V, width: CGFloat?) -> CGSize {
        let host = NSHostingController(rootView: view)
        let proposed = CGSize(width: width ?? 10_000, height: 10_000)
        return host.sizeThatFits(in: proposed)
    }

    /// Mutation: `.fixedSize()` added to the body — red, the note no longer
    /// wraps and its width exceeds the 248-pt column.
    @MainActor func testAWarningWrapsInsideTheInspectorColumn() {
        let text = "The selected reference-peak rank is absent in this pattern; "
            + "the relative filter cannot be evaluated."
        let wrapped = size(InspectorWarning(text), width: 248)
        let oneLine = size(InspectorWarning(text), width: nil)
        XCTAssertLessThanOrEqual(wrapped.width, 248)
        XCTAssertGreaterThan(oneLine.width, 248, "the probe text must be longer than the column")
        XCTAssertGreaterThan(wrapped.height, oneLine.height, "the note must wrap onto more lines")
    }

    @MainActor func testAWarningMatchesTheHandRolledLabelItReplaces() {
        let text = "From an earlier run — the settings above have changed."
        let kit = size(InspectorWarning(text, systemImage: "nosign"), width: 248)
        let handRolled = size(
            Label { Text(text) } icon: { Image(systemName: "nosign").foregroundStyle(.orange) }.font(.caption),
            width: 248)
        XCTAssertEqual(kit.width, handRolled.width, accuracy: 0.5)
        XCTAssertEqual(kit.height, handRolled.height, accuracy: 0.5)
    }

    // MARK: - Colour on the symbol only

    /// Renders `view` in the light appearance and returns the columns (in points) of every strongly orange pixel.
    @MainActor private func orangeColumns<V: View>(of view: V, width: CGFloat) throws -> [Int] {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light).frame(width: width, alignment: .leading))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "the view must render")
        let (w, h) = (image.width, image.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(drew)
        var columns = Set<Int>()
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let (r, g, b, a) = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
                // System orange is (255, 149, 0): strongly red, mid green, no blue, opaque. Black text and its
                // grey anti-aliasing never are.
                if a > 200, r > 200, g > 100, g < 190, b < 90 { columns.insert(x / 2) }
            }
        }
        return columns.sorted()
    }

    /// Mutation: `.foregroundStyle(.orange)` on the whole `Label` instead of on its `Image` -> red (orange pixels
    /// appear over the sentence, far to the right of the symbol).
    @MainActor func testAWarningColoursOnlyItsSymbol() throws {
        let text = "This sentence must stay in the label colour, not orange."
        let columns = try orangeColumns(of: InspectorWarning(text), width: 320)
        XCTAssertFalse(columns.isEmpty, "the symbol must carry the warning colour")
        // The symbol is ~10 pt wide at the leading edge; the sentence runs ~270 pt after it.
        XCTAssertLessThan((columns.last ?? 0) - (columns.first ?? 0), 16,
                          "orange belongs to the symbol, not the sentence: \(columns)")
        // The control: the hand-rolled form this replaced paints the sentence too.
        let old = try orangeColumns(of: Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange), width: 320)
        XCTAssertGreaterThan((old.last ?? 0) - (old.first ?? 0), 100, "the probe must be able to see orange text")
    }

    // MARK: - Reduce Motion

    /// Mutation: the function ignores its argument (always the ease) -> red.
    @MainActor func testSectionDisclosureDoesNotAnimateUnderReduceMotion() {
        XCTAssertNil(InspectorSectionMotion.animation(reduceMotion: true))
        XCTAssertNotNil(InspectorSectionMotion.animation(reduceMotion: false))
    }

    /// Mutation: the label replaced by a plain `Label` (no `ViewThatFits`) —
    /// red, the menu can no longer shrink below the title's width.
    @MainActor func testAnAdaptiveMenuCollapsesToItsSymbolWhenTheRowIsNarrow() {
        func menu() -> InspectorAdaptiveMenu<Button<Text>> {
            InspectorAdaptiveMenu("Add a phase from the library", systemImage: "plus") {
                Button("One") {}
            }
        }
        let roomy = size(menu(), width: nil)
        let narrow = size(menu(), width: 1)
        XCTAssertLessThan(narrow.width, roomy.width)
    }
}

/// `InspectorSection(startsExpanded:)` and `statusGlyph:`. Laid out through a hosting controller; each section has a scope of its
/// own, so no stored `@SceneStorage` value decides it.
nonisolated final class InspectorSectionOptionsTests: XCTestCase {
    @MainActor private func height<V: View>(_ view: V) -> CGFloat {
        NSHostingController(rootView: view.frame(width: 248)).sizeThatFits(in: CGSize(width: 248, height: 10_000)).height
    }

    @MainActor private func section(scope: String, startsExpanded: Bool) -> some View {
        InspectorSection("Export", startsExpanded: startsExpanded) {
            Color.clear.frame(height: 200)
        }
        .environment(\.inspectorScope, scope)
    }

    /// Mutation: `startsExpanded` not passed on to the `@SceneStorage` default -> red (both are open).
    @MainActor func testASectionThatStartsClosedShowsOnlyItsTitleRow() {
        let open = height(section(scope: "test.open.\(UUID().uuidString)", startsExpanded: true))
        let closed = height(section(scope: "test.closed.\(UUID().uuidString)", startsExpanded: false))
        XCTAssertGreaterThan(open - closed, 190, "closed hides its 200-pt content: open \(open), closed \(closed)")
    }

    /// The default is unchanged: a section built with the old init opens.
    @MainActor func testTheDefaultStillStartsOpen() {
        let old = height(InspectorSection("Export") { Color.clear.frame(height: 200) }
            .environment(\.inspectorScope, "test.default.\(UUID().uuidString)"))
        XCTAssertGreaterThan(old, 200)
    }

    /// Mutation: the glyph not drawn -> red (the title row is no wider).
    @MainActor func testTheGlyphIsDrawnOnTheTitleRow() {
        func ideal(_ glyph: Image?) -> CGFloat {
            NSHostingController(rootView: InspectorSection("Stage", statusGlyph: glyph, expanded: .constant(false)) { EmptyView() }.fixedSize())
                .sizeThatFits(in: CGSize(width: 10_000, height: 10_000)).width
        }
        XCTAssertGreaterThan(ideal(Image(systemName: "checkmark.circle.fill")), ideal(nil) + 8)
    }

    /// The glyph is drawn but never spoken: the header's value is the status and the open state alone.
    @MainActor func testTheGlyphDoesNotChangeTheSpokenValue() {
        let plain = InspectorSectionHeader(title: "Stage", icon: nil, emphasized: false, status: "Complete", statusGlyph: nil)
        let glyph = InspectorSectionHeader(title: "Stage", icon: nil, emphasized: false, status: "Complete",
                                           statusGlyph: Image(systemName: "checkmark.circle.fill"))
        XCTAssertEqual(glyph.spokenValue(expanded: false), plain.spokenValue(expanded: false))
        XCTAssertEqual(glyph.spokenValue(expanded: true), "Complete, Expanded")
    }
}
