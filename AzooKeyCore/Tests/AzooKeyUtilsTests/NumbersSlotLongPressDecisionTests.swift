import Foundation
import SwiftUI
import XCTest
@testable import AzooKeyUtils
@testable import KeyboardViews

private struct SettingUpdaterReloadProbe: KeyboardSettingKey {
    static let defaultValue = false
    static let title: LocalizedStringKey = "Probe"
    static let explanation: LocalizedStringKey = "Probe"
    @MainActor static var storedValue: Bool? = nil
    @MainActor static var writeCount = 0

    @MainActor static var value: Bool {
        get { storedValue ?? defaultValue }
        set {
            storedValue = newValue
            writeCount += 1
        }
    }
}

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

    func testDefaultEnablesNumbersDynamicAndFlickStar() {
        let slots = ClipboardLongPressSlotsSetting.defaultValue
        XCTAssertEqual(slots.slots, [.qwertyNumbers, .flickStar123])
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
        XCTAssertTrue(ClipboardLongPressSlotDecision.isEnabled(
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

    @MainActor
    func testPersistedLegacySlotsSurviveDefaultUpgrade() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let legacyValue = ClipboardLongPressSlots(slots: [.qwertyNumbers])
        userDefaults.set(legacyValue.saveValue, forKey: ClipboardLongPressSlotsSetting.key)

        XCTAssertEqual(
            ClipboardLongPressSlotsSetting.resolvedValue(from: userDefaults).slots,
            [.qwertyNumbers],
            "A stored pre-G-04 selection must not gain the new ☆123 default"
        )
    }

    @MainActor
    func testMissingSlotsUseNewDefaultWithoutMaterializing() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(
            ClipboardLongPressSlotsSetting.resolvedValue(from: userDefaults).slots,
            [.qwertyNumbers, .flickStar123]
        )
        XCTAssertNil(userDefaults.object(forKey: ClipboardLongPressSlotsSetting.key))
    }

    @MainActor
    func testSettingUpdaterReloadDoesNotPersistResolvedDefault() {
        SettingUpdaterReloadProbe.storedValue = nil
        SettingUpdaterReloadProbe.writeCount = 0
        var updater = SettingUpdater<SettingUpdaterReloadProbe>()

        XCTAssertFalse(updater.value)
        updater.reload()
        XCTAssertEqual(SettingUpdaterReloadProbe.writeCount, 0, "reload() must refresh UI state without invoking the persistence setter")

        updater.value = true
        XCTAssertEqual(SettingUpdaterReloadProbe.writeCount, 1, "An explicit UI edit must still persist")
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

    private func makeUserDefaults() throws -> (UserDefaults, String) {
        let suiteName = "NumbersSlotLongPressDecisionTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
