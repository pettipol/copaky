import XCTest
@testable import KeyboardViews

// Copaky: Lock both branches of the 123 / #+= / ☆123 long-press decision.
// Copaky: 123 / #+= / ☆123 長押し判定の両分岐を固定する。
final class NumbersSlotLongPressDecisionTests: XCTestCase {
    func testClipboardHistoryEnabledMovesDirectlyToHistory() {
        XCTAssertEqual(
            NumbersSlotLongPressDecision.longPressActionsForNumbersSlot(
                clipboardHistoryEnabled: true
            ),
            [.moveTab(.system(.clipboard_history_tab))]
        )
    }

    func testClipboardHistoryDisabledKeepsTabBarToggle() {
        XCTAssertEqual(
            NumbersSlotLongPressDecision.longPressActionsForNumbersSlot(
                clipboardHistoryEnabled: false
            ),
            [.setTabBar(.toggle)]
        )
    }

    func testClipboardHistoryHintVisibilityMatchesHistorySetting() {
        XCTAssertTrue(ClipboardHistoryKeyHintDecision.shouldShow(clipboardHistoryEnabled: true))
        XCTAssertFalse(ClipboardHistoryKeyHintDecision.shouldShow(clipboardHistoryEnabled: false))
    }
}
