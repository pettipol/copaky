import Combine
import XCTest
import UIKit
@testable import AzooKeyUtils
@testable import KeyboardViews

// Copaky: guard the canonical layout while projecting only the idle toolbar.
final class CompactIdleBarTests: XCTestCase {
    // Copaky: stale automatic heights shrink, while explicit resize choices remain literal.
    // Copaky: 保存済みの自動高さだけを縮め、ユーザーが指定した高さを維持する。
    func testPhoneLandscapeHeightResolutionPreservesExplicitOverridesAndScale() {
        XCTAssertEqual(Design.defaultPhoneLandscapeHeightCap, 240)
        let cases: [(stored: CGFloat?, overwritten: Bool, scale: CGFloat, expected: CGFloat)] = [
            (nil, false, 1, 240),
            (302.2, false, 1, 240),
            (220, false, 1, 220),
            (360, true, 1, 360),
            (nil, true, 1, 240), // A reset flag without a stored height is still a default.
            (302.2, false, 1.2, 288),
            (220, false, 1.2, 264),
            (360, true, 1.2, 432)
        ]
        for item in cases {
            let height = Design.resolvedInterfaceHeight(
                defaultHeight: 302.2, storedHeight: item.stored,
                userHasOverwrittenHeight: item.overwritten,
                isPhone: true, orientation: .horizontal, heightScale: item.scale)
            XCTAssertEqual(height, item.expected, accuracy: 0.0001,
                           "Stored height \(String(describing: item.stored)), override \(item.overwritten), scale \(item.scale)")
        }
    }

    func testLandscapeCapDoesNotChangePortraitOrTabletHeights() {
        for (isPhone, orientation) in [(true, KeyboardOrientation.vertical), (false, .horizontal), (false, .vertical)] {
            XCTAssertEqual(Design.resolvedInterfaceHeight(
                defaultHeight: 302.2, storedHeight: nil, userHasOverwrittenHeight: false,
                isPhone: isPhone, orientation: orientation, heightScale: 1.2), 362.64, accuracy: 0.0001)
            XCTAssertEqual(Design.resolvedInterfaceHeight(
                defaultHeight: 302.2, storedHeight: 360, userHasOverwrittenHeight: false,
                isPhone: isPhone, orientation: orientation, heightScale: 1.2), 432, accuracy: 0.0001)
        }
    }

    @MainActor
    func testThreeHeightUpdatePathsPreserveStoredSettings() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("The phone-only wiring requires an iPhone test host; pure resolution covers tablet and portrait.")
        }
        for (storedHeight, overwritten, scale, expected) in [
            (CGFloat(302.2), false, CGFloat(1), CGFloat(240)),
            (CGFloat(220), false, CGFloat(1), CGFloat(220)),
            (CGFloat(360), true, CGFloat(1), CGFloat(360)),
            (CGFloat(302.2), false, CGFloat(1.2), CGFloat(288))
        ] {
            let suite = "CompactLandscapeHeight.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let states = VariableStates(clipboardHistoryManagerConfig: ClipboardHistoryManagerConfig(),
                                        tabManagerConfig: TabManagerConfig(), userDefaults: defaults)
            states.setInterfaceSize(orientation: .horizontal, screenWidth: 722)
            states.heightScaleFromKeyboardHeightSetting = scale
            states.keyboardInternalSettingManager.update(\.oneHandedModeSetting) { setting in
                setting.set(orientation: .horizontal,
                            size: CGSize(width: 722, height: storedHeight), position: .zero)
                if overwritten { setting.setUserHasOverwrittenKeyboardHeightSetting(orientation: .horizontal) }
            }
            func assertHeightAndPersistedChoice(_ path: String) {
                XCTAssertEqual(states.interfaceSize.height, expected, accuracy: 0.0001, path)
                let current = states.keyboardInternalSettingManager.oneHandedModeSetting.heightItem(orientation: .horizontal)
                let reloaded = KeyboardInternalSettingManager(userDefaults: defaults)
                    .oneHandedModeSetting.heightItem(orientation: .horizontal)
                XCTAssertEqual(current.height, storedHeight, "\(path) must not migrate stored height")
                XCTAssertEqual(reloaded.height, storedHeight, "\(path) must not rewrite persisted height")
                XCTAssertEqual(current.userHasOverwrittenKeyboardHeightSetting, overwritten, path)
                XCTAssertEqual(reloaded.userHasOverwrittenKeyboardHeightSetting, overwritten, path)
            }
            states.setInterfaceSize(orientation: .horizontal, screenWidth: 722)
            assertHeightAndPersistedChoice("setInterfaceSize")
            states.setResizingMode(.fullwidth)
            assertHeightAndPersistedChoice("setResizingMode fullwidth")
            states.setResizingMode(.resizing)
            assertHeightAndPersistedChoice("setResizingMode resizing")
        }
    }

    @MainActor
    func testCompactProjectionPreservesKeyAndNumberRowHeights() {
        for orientation in [KeyboardOrientation.vertical, .horizontal] {
            for height: CGFloat in [180, 315, 520] {
                for width: CGFloat in [320, 440, 1024, 1366] {
                    for enabled in [false, true] {
                        let normal = Design.qwertyNumberRowVisibleHeight(
                            standardInterfaceHeight: height, interfaceWidth: width, orientation: orientation,
                            tab: .qwerty_abc, enabled: enabled, candidateBarCollapsed: false)
                        let compact = Design.qwertyNumberRowVisibleHeight(
                            standardInterfaceHeight: height, interfaceWidth: width, orientation: orientation,
                            tab: .qwerty_abc, enabled: enabled, candidateBarCollapsed: false, candidateBarCompact: true)
                        let hidden = Design.qwertyNumberRowVisibleHeight(
                            standardInterfaceHeight: height, interfaceWidth: width, orientation: orientation,
                            tab: .qwerty_abc, enabled: enabled, candidateBarCollapsed: true, candidateBarCompact: true)
                        let reserved = Design.keyboardBarReservedHeight(interfaceHeight: height, orientation: orientation)
                        let visible = Design.keyboardBarVisibleReservedHeight(interfaceHeight: height, interfaceWidth: width, orientation: orientation, collapsed: false, compact: true)
                        let content = Design.keyboardBarCompactContentHeight(interfaceHeight: height, interfaceWidth: width, orientation: orientation)
                        let firstRowOverlap = width / (orientation == .vertical ? 100 : 214)
                        XCTAssertGreaterThanOrEqual(visible - content + 0.0001, firstRowOverlap, "Toolbar controls must clear the expanded first-row touch cells")
                        XCTAssertEqual(normal - compact, reserved - visible, accuracy: 0.0001)
                        XCTAssertEqual(compact - hidden, visible, accuracy: 0.0001,
                                       "Only the toolbar changes; keys and optional number row keep the same height")
                        XCTAssertLessThanOrEqual(compact, normal, "A narrow or resized toolbar must never increase height")
                    }
                }
            }
        }
    }

    @MainActor
    func testResizeSpecialTabsAndAlternateContentDoNotUseCompactProjection() {
        let suite = "CompactIdleBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let states = VariableStates(clipboardHistoryManagerConfig: ClipboardHistoryManagerConfig(),
                                    tabManagerConfig: TabManagerConfig(), userDefaults: defaults)
        func compact(_ tab: KeyboardTab.ExistentialTab = .qwerty_abc) -> Bool {
            states.shouldUseCompactIdleBar(for: tab, copakyButtonVisible: true)
        }
        XCTAssertTrue(compact())
        XCTAssertTrue(compact(.flick_hira))
        XCTAssertFalse(compact(.special(.emoji)))
        XCTAssertFalse(compact(.special(.clipboard_history_tab)))
        XCTAssertFalse(states.shouldUseCompactIdleBar(for: .qwerty_abc, copakyButtonVisible: false))
        XCTAssertFalse(states.shouldUseCompactIdleBar(for: .qwerty_abc, copakyButtonVisible: true, hasMessageView: true))
        XCTAssertFalse(states.shouldUseCompactIdleBar(for: .qwerty_abc, copakyButtonVisible: true, hasTemporalMessage: true))
        states.resizingState = .resizing
        XCTAssertFalse(compact(), "The inverse resize projection must continue to store canonical height")
        states.resizingState = .onehanded
        XCTAssertTrue(compact())
        states.barState = .tab
        XCTAssertFalse(compact())
        states.barState = .cursor
        XCTAssertFalse(compact())
        states.barState = .none
        XCTAssertTrue(compact())
    }

    @MainActor
    func testPreviewPermissionStateIsObservableAndFailClosedAtInitialization() {
        let suite = "CompactIdleBarPermissions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let states = VariableStates(clipboardHistoryManagerConfig: ClipboardHistoryManagerConfig(),
                                    tabManagerConfig: TabManagerConfig(), userDefaults: defaults)
        XCTAssertFalse(states.hasFullAccess)
        var permissions: [Bool] = []
        var secure: [Bool] = []
        let accessObserver = states.$hasFullAccess.sink { permissions.append($0) }
        let secureObserver = states.$isSecureEntry.sink { secure.append($0) }
        states.setHasFullAccess(true)
        states.setHasFullAccess(true)
        states.setHasFullAccess(false)
        states.setSecureEntry(true)
        states.setSecureEntry(true)
        states.setSecureEntry(false)
        XCTAssertEqual(permissions, [false, true, false], "Revocation must invalidate previews without redundant updates")
        XCTAssertEqual(secure, [false, true, false])
        withExtendedLifetime((accessObserver, secureObserver)) {}
    }
}
