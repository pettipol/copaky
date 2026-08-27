import enum KanaKanjiConverterModule.KeyboardLanguage
import XCTest
@testable import KeyboardViews

// Copaky: Lock the back target and preserve cycling semantics for language-bearing tabs.
// Copaky: 戻り先と通常タブの巡回動作を固定する。
final class QwertyLanguageSwitchDecisionTests: XCTestCase {
    func testLanguageLessTabReturnsActiveLatinLanguageWithoutGlobeKey() {
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: nil,
                keyboardLanguage: .en_US,
                cycle: [.ja_JP, .en_US, .it_IT],
                needsInputModeSwitchKey: false
            ),
            .en_US
        )
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: nil,
                keyboardLanguage: .it_IT,
                cycle: [.ja_JP, .en_US, .it_IT],
                needsInputModeSwitchKey: false
            ),
            .it_IT
        )
    }

    func testLanguageLessTabFallsBackWhenActiveLanguageIsOutsideCycle() {
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: nil,
                keyboardLanguage: .el_GR,
                cycle: [.ja_JP, .en_US],
                needsInputModeSwitchKey: false
            ),
            .ja_JP
        )
    }

    func testLanguageBearingTabStillAdvancesThroughCycle() {
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: .ja_JP,
                keyboardLanguage: .ja_JP,
                cycle: [.ja_JP, .en_US, .it_IT],
                needsInputModeSwitchKey: false
            ),
            .en_US
        )
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: .it_IT,
                keyboardLanguage: .it_IT,
                cycle: [.ja_JP, .en_US, .it_IT],
                needsInputModeSwitchKey: true
            ),
            .ja_JP
        )
    }

    func testLanguageBearingTabUsesTheConfiguredLatinOrder() {
        let cycle: [KeyboardLanguage] = [.ja_JP, .it_IT, .en_US]
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: .ja_JP,
                keyboardLanguage: .ja_JP,
                cycle: cycle,
                needsInputModeSwitchKey: false
            ),
            .it_IT
        )
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: .it_IT,
                keyboardLanguage: .it_IT,
                cycle: cycle,
                needsInputModeSwitchKey: false
            ),
            .en_US
        )
    }

    func testLanguageBearingFallbackStillDependsOnGlobeKey() {
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: .el_GR,
                keyboardLanguage: .it_IT,
                cycle: [.ja_JP, .en_US, .it_IT],
                needsInputModeSwitchKey: true
            ),
            .it_IT
        )
        XCTAssertEqual(
            QwertyLanguageSwitchDecision.targetLanguage(
                currentTabLanguage: .el_GR,
                keyboardLanguage: .it_IT,
                cycle: [.ja_JP, .en_US, .it_IT],
                needsInputModeSwitchKey: false
            ),
            .ja_JP
        )
    }
}
