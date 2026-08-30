import XCTest
@testable import AzooKeyUtils
@testable import KeyboardViews

final class SpaceSlideCursorDecisionTests: XCTestCase {
    func testSettingContractIsOptInAndSnakeCase() {
        XCTAssertFalse(EnableSpaceSlideCursor.defaultValue)
        XCTAssertEqual(EnableSpaceSlideCursor.key, "enable_space_slide_cursor")
        XCTAssertEqual(SpaceSlideCursorSensitivitySetting.defaultValue, .medium)
        XCTAssertEqual(SpaceSlideCursorSensitivitySetting.key, "space_slide_cursor_sensitivity")
        XCTAssertEqual(SpaceSlideCursorSensitivity.slow.rawValue, "slow")
        XCTAssertEqual(SpaceSlideCursorSensitivity.medium.rawValue, "medium")
        XCTAssertEqual(SpaceSlideCursorSensitivity.fast.rawValue, "fast")
        XCTAssertEqual(SpaceSlideCursorSensitivity.get("medium"), .medium)
        XCTAssertNil(SpaceSlideCursorSensitivity.get("unknown"))
    }

    func testThresholdUsesTheThreeSensitivityMultipliers() {
        XCTAssertEqual(
            SpaceSlideCursorDecision.stepThreshold(keyWidth: 40, sensitivity: .slow),
            40,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SpaceSlideCursorDecision.stepThreshold(keyWidth: 40, sensitivity: .medium),
            28,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SpaceSlideCursorDecision.stepThreshold(keyWidth: 40, sensitivity: .fast),
            18,
            accuracy: 0.001
        )
    }

    func testBelowThresholdDoesNotMoveAndExactThresholdMovesOnce() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 39.9,
            keyWidth: 40,
            sensitivity: .slow,
            isEnabled: true
        ), 0)
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 40,
            keyWidth: 40,
            sensitivity: .slow,
            isEnabled: true
        ), 1)
    }

    func testEachSensitivityMovesOnceAtItsExactThreshold() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 40,
            keyWidth: 40,
            sensitivity: .slow,
            isEnabled: true
        ), 1)
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 28,
            keyWidth: 40,
            sensitivity: .medium,
            isEnabled: true
        ), 1)
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 18,
            keyWidth: 40,
            sensitivity: .fast,
            isEnabled: true
        ), 1)
    }

    func testDirectionFollowsHorizontalTranslation() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: -40,
            keyWidth: 40,
            sensitivity: .slow,
            isEnabled: true
        ), -1)
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 40,
            keyWidth: 40,
            sensitivity: .slow,
            isEnabled: true
        ), 1)
    }

    func testStepCountAndIncrementalEmission() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 95,
            keyWidth: 40,
            sensitivity: .slow,
            isEnabled: true
        ), 2)
        XCTAssertEqual(SpaceSlideCursorDecision.incrementalSteps(
            horizontalTranslation: 95,
            keyWidth: 40,
            sensitivity: .slow,
            emittedSteps: 1,
            isEnabled: true
        ), 1)
        XCTAssertEqual(SpaceSlideCursorDecision.incrementalSteps(
            horizontalTranslation: -95,
            keyWidth: 40,
            sensitivity: .slow,
            emittedSteps: -1,
            isEnabled: true
        ), -1)
    }

    func testDisabledStateNeverMoves() {
        XCTAssertEqual(SpaceSlideCursorDecision.totalSteps(
            horizontalTranslation: 1_000,
            keyWidth: 40,
            sensitivity: .fast,
            isEnabled: false
        ), 0)
        XCTAssertEqual(SpaceSlideCursorDecision.incrementalSteps(
            horizontalTranslation: -1_000,
            keyWidth: 40,
            sensitivity: .fast,
            emittedSteps: 3,
            isEnabled: false
        ), 0)
    }
}
