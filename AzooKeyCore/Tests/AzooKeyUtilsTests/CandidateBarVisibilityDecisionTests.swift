import XCTest
@testable import KeyboardViews

// Copaky [E-12]: lock the pure visibility policy independently from SwiftUI and extension height.
final class CandidateBarVisibilityDecisionTests: XCTestCase {
    func testJapaneseTabIsAlwaysVisible() {
        XCTAssertTrue(CandidateBarVisibilityDecision.isVisible(
            isLatinQwertyTab: false,
            hasCandidates: false,
            hasPredictions: false,
            hasNoticeOrAlternateBarContent: false,
            copakyButtonVisible: false,
            hideEmptyLatinBarEnabled: true
        ))
    }

    func testLatinTabWithCandidatesIsVisible() {
        XCTAssertTrue(CandidateBarVisibilityDecision.isVisible(
            isLatinQwertyTab: true,
            hasCandidates: true,
            hasPredictions: false,
            hasNoticeOrAlternateBarContent: false,
            copakyButtonVisible: false,
            hideEmptyLatinBarEnabled: true
        ))
    }

    func testEmptyLatinTabWithoutCopakyButtonIsHiddenWhenEnabled() {
        XCTAssertFalse(CandidateBarVisibilityDecision.isVisible(
            isLatinQwertyTab: true,
            hasCandidates: false,
            hasPredictions: false,
            hasNoticeOrAlternateBarContent: false,
            copakyButtonVisible: false,
            hideEmptyLatinBarEnabled: true
        ))
    }

    func testSettingOffAlwaysKeepsLatinTabVisible() {
        XCTAssertTrue(CandidateBarVisibilityDecision.isVisible(
            isLatinQwertyTab: true,
            hasCandidates: false,
            hasPredictions: false,
            hasNoticeOrAlternateBarContent: false,
            copakyButtonVisible: false,
            hideEmptyLatinBarEnabled: false
        ))
    }

    func testPredictionsNoticeAndCopakyButtonEachKeepLatinTabVisible() {
        XCTAssertTrue(CandidateBarVisibilityDecision.isVisible(
            isLatinQwertyTab: true,
            hasCandidates: false,
            hasPredictions: true,
            hasNoticeOrAlternateBarContent: false,
            copakyButtonVisible: false,
            hideEmptyLatinBarEnabled: true
        ))
        XCTAssertTrue(CandidateBarVisibilityDecision.isVisible(
            isLatinQwertyTab: true,
            hasCandidates: false,
            hasPredictions: false,
            hasNoticeOrAlternateBarContent: true,
            copakyButtonVisible: false,
            hideEmptyLatinBarEnabled: true
        ))
        XCTAssertTrue(CandidateBarVisibilityDecision.isVisible(
            isLatinQwertyTab: true,
            hasCandidates: false,
            hasPredictions: false,
            hasNoticeOrAlternateBarContent: false,
            copakyButtonVisible: true,
            hideEmptyLatinBarEnabled: true
        ))
    }
}
