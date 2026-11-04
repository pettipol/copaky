import XCTest
import UIKit
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
            for width: CGFloat in [320, 375, 440, 722, 956] {
                for standardHeight: CGFloat in [80, 120, 180, 300, 520] {
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
                        let latinTopInset = candidateBarCollapsed
                            ? width / (orientation == .vertical ? 100 : 214) : 0
                        XCTAssertEqual(flickHeight, offHeight - latinTopInset, accuracy: 0.000_001,
                                       "Flick geometry does not inherit the Latin hidden-bar inset")
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

    // Copaky: independently calculated phone fixtures catch missing or double-counted body inset.
    // Copaky: 独立計算したiPhoneの寸法例で、本体余白の不足と二重加算を検出する。
    @MainActor
    func testCollapsedLatinBodyHeightHasFixedNumericFixturesWithAndWithoutNumberRow() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("These numeric projections use the phone portrait and landscape height ratios.")
        }
        let fixtures: [(width: CGFloat, orientation: KeyboardOrientation, baseline: CGFloat, off: CGFloat, on: CGFloat)] = [
            (375, .vertical, 315, 251.7941176470588, 315.68014705882354),
            (440, .vertical, 315, 252.44411764705882, 316.6551470588235),
            (722, .horizontal, 240, 189.6483415796225, 237.90388491845337),
            (956, .horizontal, 240, 190.74179952354774, 239.54407183434122)
        ]
        for fixture in fixtures {
            for tab: KeyboardTab.ExistentialTab in [.qwerty_abc, .qwerty_numbers, .qwerty_symbols] {
                for (enabled, expected) in [(false, fixture.off), (true, fixture.on)] {
                    let rendered = Design.qwertyNumberRowVisibleHeight(
                        standardInterfaceHeight: fixture.baseline,
                        interfaceWidth: fixture.width, orientation: fixture.orientation,
                        tab: tab, enabled: enabled, candidateBarCollapsed: true)
                    XCTAssertEqual(rendered, expected, accuracy: 0.000_001,
                                   "The advertised body includes the inset once and preserves the canonical key heights")
                    let restored = Design.standardInterfaceHeightForQwertyNumberRow(
                        renderedVisibleHeight: expected,
                        interfaceWidth: fixture.width, orientation: fixture.orientation,
                        tab: tab, enabled: enabled, candidateBarCollapsed: true)
                    XCTAssertEqual(restored, fixture.baseline, accuracy: 0.000_1,
                                   "Resize must recover the baseline from an independently supplied rendered height")
                }
            }
        }
    }

    // Copaky: 120 pt covers the low landscape resize range; 80 pt is an analytical stress case.
    // Copaky: 120 ptは横向きの縮小範囲を検証し、80 ptは解析用の厳しい寸法例とする。
    @MainActor
    func testSmallPhoneBodyHeightFixturesPreserveVisibleAndCollapsedResizeProjection() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("These low-height fixtures use the phone height ratios.")
        }
        let fixtures: [(width: CGFloat, orientation: KeyboardOrientation, baseline: CGFloat,
                        hiddenOff: CGFloat, hiddenOn: CGFloat, visibleOn: CGFloat, keyHeight: CGFloat)] = [
            (375, .vertical, 120, 92.16176470588235, 116.13970588235294, 143.97794117647058, 16.477941176470587),
            (440, .vertical, 120, 92.81176470588235, 117.11470588235294, 144.3029411764706, 15.50294117647059),
            (722, .horizontal, 120, 91.609125893348, 115.35486531061022, 143.74573941726223, 16.99807586586036),
            (956, .horizontal, 120, 92.70258383727322, 116.99505222649807, 144.29246838922484, 15.357888949972512),
            (375, .vertical, 80, 59.416666666666664, 75.20833333333333, 95.79166666666667, 8.291666666666666),
            (440, .vertical, 80, 60.06666666666667, 76.18333333333334, 96.11666666666666, 7.316666666666666),
            (722, .horizontal, 80, 58.92938733125649, 74.50519210799585, 95.57580477673936, 8.828141225337488),
            (956, .horizontal, 80, 60.02284527518172, 76.14537902388369, 96.12253374870197, 7.187954309449637)
        ]
        for fixture in fixtures {
            let layout = Design.qwertyNumberRowLayout(
                for: .qwerty_abc, enabled: true,
                standardInterfaceSize: CGSize(width: fixture.width, height: fixture.baseline),
                orientation: fixture.orientation)
            XCTAssertEqual(layout.keyHeight, fixture.keyHeight, accuracy: 0.000_001,
                           "The small baseline must retain the independently calculated positive key height")
            XCTAssertGreaterThan(layout.keyHeight, 0, "This fixture must not exercise the zero-height clamp")
            for collapsed in [false, true] {
                let expectedOff = collapsed ? fixture.hiddenOff : fixture.baseline
                let expectedOn = collapsed ? fixture.hiddenOn : fixture.visibleOn
                for (enabled, expected) in [(false, expectedOff), (true, expectedOn)] {
                    let rendered = Design.qwertyNumberRowVisibleHeight(
                        standardInterfaceHeight: fixture.baseline,
                        interfaceWidth: fixture.width, orientation: fixture.orientation,
                        tab: .qwerty_abc, enabled: enabled, candidateBarCollapsed: collapsed)
                    XCTAssertEqual(rendered, expected, accuracy: 0.000_001,
                                   "Visible and hidden bars must preserve the low-height projection with either row count")
                    let restored = Design.standardInterfaceHeightForQwertyNumberRow(
                        renderedVisibleHeight: expected,
                        interfaceWidth: fixture.width, orientation: fixture.orientation,
                        tab: .qwerty_abc, enabled: enabled, candidateBarCollapsed: collapsed)
                    XCTAssertEqual(restored, fixture.baseline, accuracy: 0.000_1,
                                   "An independent low-height fixture must round-trip without persisting its inset")
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
        let standardLatin = QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.abcKeyboard(language: .en_US)
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
            to: QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.abcKeyboard(language: .en_US),
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
