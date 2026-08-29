import XCTest
@testable import AzooKeyUtils
@testable import KeyboardViews

final class SpaceSlideCursorDecisionTests: XCTestCase {
    func testSettingContractIsOptInAndSnakeCase() {
        XCTAssertFalse(EnableSpaceSlideCursor.defaultValue)
        XCTAssertEqual(EnableSpaceSlideCursor.key, "enable_space_slide_cursor")
    }

    func testThresholdIsOneRenderedOrdinaryKeyWidth() {
        XCTAssertEqual(SpaceSlideCursorDecision.stepThreshold(keyWidth: 40), 40, accuracy: 0.001)
    }

    func testBelowThresholdDoesNotMoveAndExactThresholdMovesOnce() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 39.9,
            keyWidth: 40,
            isEnabled: true
        ), 0)
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 40,
            keyWidth: 40,
            isEnabled: true
        ), 1)
    }

    func testDirectionFollowsHorizontalTranslation() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: -40,
            keyWidth: 40,
            isEnabled: true
        ), -1)
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 40,
            keyWidth: 40,
            isEnabled: true
        ), 1)
    }

    func testStepCountAndIncrementalEmission() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 95,
            keyWidth: 40,
            isEnabled: true
        ), 2)
        XCTAssertEqual(SpaceSlideCursorDecision.incrementalSteps(
            horizontalTranslation: 95,
            keyWidth: 40,
            emittedSteps: 1,
            isEnabled: true
        ), 1)
        XCTAssertEqual(SpaceSlideCursorDecision.incrementalSteps(
            horizontalTranslation: -95,
            keyWidth: 40,
            emittedSteps: -1,
            isEnabled: true
        ), -1)
    }

    func testDisabledStateNeverMoves() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 1_000,
            keyWidth: 40,
            isEnabled: false
        ), 0)
        XCTAssertEqual(SpaceSlideCursorDecision.incrementalSteps(
            horizontalTranslation: -1_000,
            keyWidth: 40,
            emittedSteps: 3,
            isEnabled: false
        ), 0)
    }
}
