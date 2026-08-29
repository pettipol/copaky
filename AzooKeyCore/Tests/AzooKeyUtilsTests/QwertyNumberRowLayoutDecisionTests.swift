import XCTest
@testable import AzooKeyUtils
@testable import KeyboardViews

final class QwertyNumberRowLayoutDecisionTests: XCTestCase {
    func testSettingContractIsOptInWithStableSnakeCaseKey() {
        XCTAssertFalse(EnableQwertyNumberRow.defaultValue)
        XCTAssertEqual(EnableQwertyNumberRow.key, "enable_qwerty_number_row")
    }

    func testEveryBuiltInQwertyTabUsesFiveRowsOnlyWhenEnabled() {
        let tabs: [KeyboardTab.ExistentialTab] = [
            .qwerty_hira,
            .qwerty_abc,
            .qwerty_numbers,
            .qwerty_symbols,
        ]

        for tab in tabs {
            XCTAssertEqual(
                QwertyNumberRowLayoutDecision.rowCount(for: tab, enabled: false),
                4,
                "\(tab) must keep the standard row count while the setting is off"
            )
            XCTAssertEqual(
                QwertyNumberRowLayoutDecision.rowCount(for: tab, enabled: true),
                5,
                "\(tab) must gain the real number row while the setting is on"
            )
        }
    }

    func testFlickClipboardAndEmojiTabsAreUnaffected() {
        let tabs: [KeyboardTab.ExistentialTab] = [
            .flick_hira,
            .flick_abc,
            .flick_numbersymbols,
            .special(.clipboard_history_tab),
            .special(.emoji),
        ]

        for tab in tabs {
            let layout = QwertyNumberRowLayoutDecision.resolve(
                tab: tab,
                enabled: true,
                standardInterfaceHeight: 300,
                standardKeysHeight: 240,
                verticalSpacing: 8
            )
            XCTAssertEqual(layout.rowCount, 4, "\(tab) must not adopt QWERTY geometry")
            XCTAssertEqual(layout.interfaceHeight, 300, accuracy: 0.000_001)
            XCTAssertEqual(layout.keysHeight, 240, accuracy: 0.000_001)
            XCTAssertEqual(layout.additionalHeight, 0, accuracy: 0.000_001)
        }
    }

    func testGrowthIsExactlyOneStandardKeyPlusSpacingAndPreservesKeyHeight() {
        let standardInterfaceHeight: CGFloat = 300
        let standardKeysHeight: CGFloat = 240
        let spacing: CGFloat = 8
        let layout = QwertyNumberRowLayoutDecision.resolve(
            tab: .qwerty_abc,
            enabled: true,
            standardInterfaceHeight: standardInterfaceHeight,
            standardKeysHeight: standardKeysHeight,
            verticalSpacing: spacing
        )

        let fourRowKeyHeight = (standardKeysHeight - 3 * spacing) / 4
        let fiveRowKeyHeight = (layout.keysHeight - 4 * spacing) / 5
        XCTAssertEqual(layout.additionalHeight, fourRowKeyHeight + spacing, accuracy: 0.000_001)
        XCTAssertEqual(layout.interfaceHeight - standardInterfaceHeight, layout.additionalHeight, accuracy: 0.000_001)
        XCTAssertEqual(fiveRowKeyHeight, fourRowKeyHeight, accuracy: 0.000_001)
        XCTAssertEqual(layout.keyHeight, fourRowKeyHeight, accuracy: 0.000_001)
    }

    func testHeightPolicyScalesFromTheCurrentManualBaselineWithoutAccumulating() {
        for standardKeysHeight: CGFloat in [140, 220, 360] {
            let first = QwertyNumberRowLayoutDecision.resolve(
                tab: .qwerty_hira,
                enabled: true,
                standardInterfaceHeight: standardKeysHeight + 60,
                standardKeysHeight: standardKeysHeight,
                verticalSpacing: 6
            )
            let second = QwertyNumberRowLayoutDecision.resolve(
                tab: .qwerty_hira,
                enabled: true,
                standardInterfaceHeight: standardKeysHeight + 60,
                standardKeysHeight: standardKeysHeight,
                verticalSpacing: 6
            )
            XCTAssertEqual(first, second, "Projection must derive from, not mutate, the manual baseline")
        }
    }

    @MainActor
    func testVisibleHeightProjectionRoundTripsManualResizeAcrossRotationAndCollapsedBar() {
        for orientation in [KeyboardOrientation.vertical, .horizontal] {
            for width: CGFloat in [320, 430, 760] {
                for standardHeight: CGFloat in [180, 300, 520] {
                    for candidateBarCollapsed in [false, true] {
                        let standardSize = CGSize(width: width, height: standardHeight)
                        let layout = Design.qwertyNumberRowLayout(
                            for: .qwerty_abc,
                            enabled: true,
                            standardInterfaceSize: standardSize,
                            orientation: orientation
                        )
                        let offHeight = Design.qwertyNumberRowVisibleHeight(
                            standardInterfaceHeight: standardHeight,
                            interfaceWidth: width,
                            orientation: orientation,
                            tab: .qwerty_abc,
                            enabled: false,
                            candidateBarCollapsed: candidateBarCollapsed
                        )
                        let onHeight = Design.qwertyNumberRowVisibleHeight(
                            standardInterfaceHeight: standardHeight,
                            interfaceWidth: width,
                            orientation: orientation,
                            tab: .qwerty_abc,
                            enabled: true,
                            candidateBarCollapsed: candidateBarCollapsed
                        )
                        XCTAssertEqual(
                            onHeight - offHeight,
                            layout.additionalHeight,
                            accuracy: 0.000_001,
                            "Projection must add exactly one key plus spacing"
                        )

                        let restoredOnHeight = Design.standardInterfaceHeightForQwertyNumberRow(
                            renderedVisibleHeight: onHeight,
                            interfaceWidth: width,
                            orientation: orientation,
                            tab: .qwerty_abc,
                            enabled: true,
                            candidateBarCollapsed: candidateBarCollapsed
                        )
                        XCTAssertEqual(
                            restoredOnHeight,
                            standardHeight,
                            accuracy: 0.000_1,
                            "Resize persistence must recover the canonical baseline"
                        )

                        let restoredOffHeight = Design.standardInterfaceHeightForQwertyNumberRow(
                            renderedVisibleHeight: offHeight,
                            interfaceWidth: width,
                            orientation: orientation,
                            tab: .qwerty_abc,
                            enabled: false,
                            candidateBarCollapsed: candidateBarCollapsed
                        )
                        XCTAssertEqual(restoredOffHeight, standardHeight, accuracy: 0.000_001)

                        let flickHeight = Design.qwertyNumberRowVisibleHeight(
                            standardInterfaceHeight: standardHeight,
                            interfaceWidth: width,
                            orientation: orientation,
                            tab: .flick_hira,
                            enabled: true,
                            candidateBarCollapsed: candidateBarCollapsed
                        )
                        XCTAssertEqual(flickHeight, offHeight, accuracy: 0.000_001)
                        let restoredFlickHeight = Design.standardInterfaceHeightForQwertyNumberRow(
                            renderedVisibleHeight: flickHeight,
                            interfaceWidth: width,
                            orientation: orientation,
                            tab: .flick_hira,
                            enabled: true,
                            candidateBarCollapsed: candidateBarCollapsed
                        )
                        XCTAssertEqual(restoredFlickHeight, standardHeight, accuracy: 0.000_001)
                    }
                }
            }
        }
    }

    func testDigitOrderIsLanguageNeutral() {
        XCTAssertEqual(QwertyNumberRowLayoutDecision.digits.joined(), "1234567890")
    }

    @MainActor
    func testQwertyProvidersPrependTheSameTopRowWithoutChangingExistingGeometry() {
        typealias Layout = QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.Layout

        func assertExpansion(from standard: Layout, to expanded: Layout, variant: String) {
            let expectedTopRow = Set((0..<10).map {
                UnifiedPositionSpecifier(x: CGFloat($0), y: 0)
            })
            let actualTopRow = Set(expanded.keys.filter { $0.y == 0 })
            XCTAssertEqual(actualTopRow, expectedTopRow, "\(variant) must render ten real digit positions")

            let shiftedStandard = Set(standard.keys.map {
                UnifiedPositionSpecifier(
                    x: $0.x,
                    y: $0.y + 1,
                    width: $0.width,
                    height: $0.height
                )
            })
            let expandedExistingRows = Set(expanded.keys.filter { $0.y > 0 })
            XCTAssertEqual(
                expandedExistingRows,
                shiftedStandard,
                "\(variant) must preserve every existing key position below the new row"
            )
        }

        let previousValue = EnableQwertyNumberRow.get()
        defer {
            if let previousValue {
                EnableQwertyNumberRow.value = previousValue
            } else {
                SharedStore.userDefaults.removeObject(forKey: EnableQwertyNumberRow.key)
            }
        }

        EnableQwertyNumberRow.value = false
        let standardHiragana = QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.hiraKeyboard()
        // A-03/A-04 deliberately use this one qwerty_abc provider after both EN and IT reseeds.
        let standardLatin = QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.abcKeyboard()
        let standardNumbers = QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.numberKeyboard(language: .it_IT)
        let standardSymbols = QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.symbolsKeyboard(language: .en_US)

        EnableQwertyNumberRow.value = true
        assertExpansion(
            from: standardHiragana,
            to: QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.hiraKeyboard(),
            variant: "qwerty_hira"
        )
        assertExpansion(
            from: standardLatin,
            to: QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.abcKeyboard(),
            variant: "qwerty_abc (shared by EN and IT)"
        )
        assertExpansion(
            from: standardNumbers,
            to: QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.numberKeyboard(language: .it_IT),
            variant: "qwerty_numbers"
        )
        assertExpansion(
            from: standardSymbols,
            to: QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.symbolsKeyboard(language: .en_US),
            variant: "qwerty_symbols"
        )
    }
}
