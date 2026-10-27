import SwiftUI
import XCTest
@testable import ShellInspector

/// `AdjustmentSlider.clamp(_:to:)` — the one piece of the inspector's
/// Lightroom-style slider row that is not a view and can be tested without
/// hosting one. It is the sole place a typed `TextField` value can land
/// outside the slider's own `range` before it reaches the bound `value`.
nonisolated final class InspectorRowsTests: XCTestCase {
    @MainActor func testClampLeavesAValueInsideRangeUnchanged() {
        XCTAssertEqual(AdjustmentSlider.clamp(0.5, to: 0.2...3.0), 0.5)
    }

    @MainActor func testClampPullsAValueBelowRangeUpToTheLowerBound() {
        XCTAssertEqual(AdjustmentSlider.clamp(-4, to: 0.2...3.0), 0.2)
    }

    @MainActor func testClampPullsAValueAboveRangeDownToTheUpperBound() {
        XCTAssertEqual(AdjustmentSlider.clamp(99, to: 0.2...3.0), 3.0)
    }

    @MainActor func testClampAtEitherBoundReturnsThatBoundExactly() {
        XCTAssertEqual(AdjustmentSlider.clamp(0.2, to: 0.2...3.0), 0.2)
        XCTAssertEqual(AdjustmentSlider.clamp(3.0, to: 0.2...3.0), 3.0)
    }
}

/// `InspectorSection.sceneStorageKey(scope:title:)` — the other piece of the
/// inspector vocabulary that is pure and testable without hosting a view.
/// Two sections that share a title (F1: "Dataset" in the Info tab and
/// "Dataset" among the Settings tab's own actions) must resolve to two
/// different `@SceneStorage` keys once each is given its own `inspectorScope`,
/// or their expansion states collapse together.
nonisolated final class InspectorSectionScopeKeyTests: XCTestCase {
    @MainActor func testTheSameTitleUnderTwoScopesYieldsTwoDifferentKeys() {
        let infoKey = InspectorSection<EmptyView>.sceneStorageKey(scope: "info", title: "Dataset")
        let settingsKey = InspectorSection<EmptyView>.sceneStorageKey(scope: "settings", title: "Dataset")
        XCTAssertNotEqual(infoKey, settingsKey)
    }

    @MainActor func testTheKeyEmbedsScopeAndTitleInOrder() {
        XCTAssertEqual(
            InspectorSection<EmptyView>.sceneStorageKey(scope: "settings.map", title: "Result"),
            "inspector.section.settings.map.Result"
        )
    }
}
