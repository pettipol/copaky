import Foundation
import XCTest
@testable import AzooKeyUtils
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

    func testFourRenderedSitesMapToThreePersistedSlots() {
        XCTAssertEqual(ClipboardLongPressSlotDecision.slot(for: .qwertyNumbers), .qwertyNumbers)
        XCTAssertEqual(ClipboardLongPressSlotDecision.slot(for: .qwertySymbols), .qwertySymbols)
        XCTAssertEqual(ClipboardLongPressSlotDecision.slot(for: .flickStar123), .flickStar123)
        XCTAssertEqual(ClipboardLongPressSlotDecision.slot(for: .qwertyDynamicNumbers), .qwertyNumbers)
    }

    func testDefaultEnablesOnlyNumbersAndItsDynamicVariant() {
        let slots = ClipboardLongPressSlotsSetting.defaultValue
        XCTAssertEqual(slots.slots, [.qwertyNumbers])
        XCTAssertTrue(ClipboardLongPressSlotDecision.isEnabled(
            for: .qwertyNumbers,
            clipboardHistoryEnabled: true,
            enabledSlots: slots
        ))
        XCTAssertFalse(ClipboardLongPressSlotDecision.isEnabled(
            for: .qwertySymbols,
            clipboardHistoryEnabled: true,
            enabledSlots: slots
        ))
        XCTAssertFalse(ClipboardLongPressSlotDecision.isEnabled(
            for: .flickStar123,
            clipboardHistoryEnabled: true,
            enabledSlots: slots
        ))
        XCTAssertTrue(ClipboardLongPressSlotDecision.isEnabled(
            for: .qwertyDynamicNumbers,
            clipboardHistoryEnabled: true,
            enabledSlots: slots
        ))
    }

    func testHistoryOffDisablesEveryConfiguredSite() {
        let allSlots = ClipboardLongPressSlots(slots: Set(ClipboardLongPressSlot.allCases))
        for site in ClipboardLongPressSite.allCases {
            XCTAssertFalse(ClipboardLongPressSlotDecision.isEnabled(
                for: site,
                clipboardHistoryEnabled: false,
                enabledSlots: allSlots
            ))
        }
    }

    func testSavableRoundTripAndStableOrdering() throws {
        let value = ClipboardLongPressSlots(slots: [.flickStar123, .qwertyNumbers])
        XCTAssertEqual(ClipboardLongPressSlots.get(value.saveValue), value)
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: value.saveValue),
            ["qwertyNumbers", "flickStar123"]
        )
    }

    func testMalformedUnknownAndEmptyStorageFallBack() throws {
        XCTAssertNil(ClipboardLongPressSlots.get(Data("not-json".utf8)))
        XCTAssertNil(ClipboardLongPressSlots.get(try JSONEncoder().encode(["unknown"])))
        XCTAssertNil(ClipboardLongPressSlots.get(try JSONEncoder().encode([String]())))
        XCTAssertEqual(ClipboardLongPressSlots(slots: []).slots, [.qwertyNumbers])
    }
}
