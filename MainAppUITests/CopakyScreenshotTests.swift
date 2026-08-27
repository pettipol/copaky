//
//  CopakyScreenshotTests.swift — App Store 6.9" screenshot campaign (EN + JA)
//  コパキー・App Store 6.9インチ用スクリーンショット生成スイート（英語・日本語）
//
//  Produces the 6 ordered App Store screenshots for the iPhone 6.9" class
//  (iPhone 17 Pro Max, native 1320×2868). Runs SIGNED so the keyboard
//  extension keeps its App Group entitlement; the clipboard tab is made
//  visible by seeding the shared container from the Mac (see
//  scripts/seed_sim_clipboard.sh + scripts/store_screenshots.sh).
//
//  This suite is self-contained on purpose: it reimplements only the helpers
//  it needs (adapted from MainAppUITests.swift) so the existing campaign that
//  the orchestrator relies on for one-time setup (test00/test01/test10) is not
//  disturbed. Screenshots are full-res XCTAttachments named shot01…shot06.
//
//  Runtime inputs (passed as TEST_RUNNER_* env by the orchestrator):
//    COPAKY_DEMO_URL         demo page to host the keyboard (en=/demo, ja=/demo.ja)
//    COPAKY_CLIPBOARD_CANARY substring that MUST appear in the seeded clipboard tab
//

import UIKit
import XCTest

/// Multi-locale UI labels. Settings follows the SYSTEM language set by the
/// orchestrator (en or ja); the MainApp is localized (en/ja); keyboard-internal
/// strings are Japanese. Match all applicable variants.
private enum SL {
    static let closeOnboarding = ["閉じる", "Close", "Chiudi"]
    static let settingsTab = ["設定", "Settings", "Impostazioni"]
    static let themesTab = ["着せ替え", "Themes", "Temi"]
    static let clipboardToggle = ["Keep clipboard histories", "クリップボードの履歴を保存", "Salva la cronologia degli appunti"]
    static let clipboardTab = ["コピー履歴", "clipboard_history_tab", "doc.badge.clock"]
    static let captureBar = ["コピーした内容を追加", "現在のクリップボードを追加", "Add copied text", "Add current clipboard", "Aggiungi il testo copiato", "Aggiungi gli appunti correnti"]
    /// Existing slot whose LONG-PRESS opens Clipboard history when enabled, otherwise the tab bar.
    static let tabBarToggleKey = [
        "☆123", "123", "#+=", "numbers", "Numbers", "numeri", "Numeri", "数字",
        "textformat.123", "textformat.numbers",
    ]
    static let copakyPresets = ["Copaky Light", "Copaky Dark", "Copaky Red"]
    static let mainAppNoticeAction = ["更新", "追加", "OK", "アップデート", "Update"]
}

@MainActor
final class CopakyScreenshotTests: XCTestCase {

    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let mainApp = XCUIApplication(bundleIdentifier: "com.pettipol.copaky")
    private let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

    /// Demo page that hosts the keyboard. Overridable per language pass.
    private var demoURL: String {
        ProcessInfo.processInfo.environment["COPAKY_DEMO_URL"] ?? "https://copaky.app/demo"
    }
    /// Substring that must appear in the clipboard tab (canary for the seeding).
    private var clipboardCanary: String {
        ProcessInfo.processInfo.environment["COPAKY_CLIPBOARD_CANARY"] ?? "482913"
    }

    override func setUpWithError() throws {
        // Keep going after a soft assertion so a screenshot is still captured;
        // shot03 gates its store screenshot behind the canary explicitly.
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Evidence helpers

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(string: app.debugDescription)
        a.name = "tree-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Query helpers

    private func firstMatch(in app: XCUIApplication, labels: [String], timeout: TimeInterval = 6) -> XCUIElement? {
        let pred = NSPredicate(format: "label IN %@ OR identifier IN %@ OR title IN %@", labels, labels, labels)
        let queries: [XCUIElementQuery] = [
            app.buttons.matching(pred),
            app.cells.matching(pred),
            app.switches.matching(pred),
            app.staticTexts.matching(pred),
            app.otherElements.matching(pred),
            app.images.matching(pred),
        ]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for q in queries where q.firstMatch.exists {
                return q.firstMatch
            }
            settle(0.3)
        } while Date() < deadline
        return nil
    }

    private func keyboard(of app: XCUIApplication) -> XCUIElement {
        app.keyboards.firstMatch
    }

    /// Heuristic: Copaky (azooKey) is active when its Japanese special keys exist, or when a
    /// keyboard is on screen that exposes no stock `Key` elements (custom SwiftUI keyboard).
    private func copakyActive(in app: XCUIApplication) -> Bool {
        dismissCopakyNotice(in: app)
        // Copaky-ONLY labels: never use generic or Latin key labels — the SYSTEM keyboard
        // exposes those too and a false positive here skips the switch (measured 2026-08-27
        // twice: «spazio/space/return» matched the stock Italian keyboard, and so did
        // «A capo», which is the stock return key's Italian accessibility label).
        // Japanese labels are safe: the stock Italian keyboard never shows them.
        // «#+=» and «Conferma» are visible on Copaky's Latin QWERTY at the letters layer;
        // the stock keyboard shows neither there («#+=» only on its symbols layer).
        let markers = ["空白", "改行", "あいう", "戻る", "逆順", "お知らせ", "☆123",
                       "#+=", "Conferma"]
        let match = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", markers)).firstMatch
        if match.exists { return true }
        let kb = app.keyboards.firstMatch
        return kb.exists && kb.keys.count == 0 && kb.frame.height > 150
    }

    /// Dismiss the first-activation in-keyboard notices (お知らせ) with 後で ("later").
    private func dismissCopakyNotice(in app: XCUIApplication) {
        var quiet = 0
        for _ in 0..<12 {
            let later = app.buttons.matching(NSPredicate(format: "label == %@", "後で")).firstMatch
            if later.exists {
                if later.isHittable { later.tap() }
                quiet = 0
                settle(0.5)
            } else {
                quiet += 1
                if quiet >= 2 { break }
                settle(0.6)
            }
        }
    }

    /// Switch the active keyboard to Copaky via the globe key (long-press picker, then tap fallback).
    private func switchToCopaky(in app: XCUIApplication) {
        if copakyActive(in: app) { return }
        let kb = keyboard(of: app)
        var up = false
        for _ in 0..<10 {
            if kb.exists || copakyActive(in: app) { up = true; break }
            settle(1.0)
        }
        XCTAssertTrue(up, "No software keyboard appeared (hardware keyboard connected?)")
        if copakyActive(in: app) { return }
        let globePred = NSPredicate(format: "label CONTAINS[c] 'astiera successiva' OR label CONTAINS[c] 'ext keyboard' OR label CONTAINS[c] '次のキーボード'")
        let globes = app.buttons.matching(globePred)
        var globe = globes.firstMatch
        var bestY: CGFloat = -1
        for i in 0..<globes.count {
            let el = globes.element(boundBy: i)
            if el.exists && el.frame.maxY > bestY {
                bestY = el.frame.maxY
                globe = el
            }
        }
        for attempt in 0..<3 where !copakyActive(in: app) {
            if globe.exists {
                globe.press(forDuration: 1.0)
                let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                let pickInApp = firstMatch(in: app, labels: ["Copaky"], timeout: 2)
                let pick = pickInApp ?? firstMatch(in: springboard, labels: ["Copaky"], timeout: 2)
                if let pick, pick.exists { pick.tap() }
                for _ in 0..<10 where !copakyActive(in: app) { settle(1.0) }
            } else {
                settle(1.0)
            }
            _ = attempt
        }
        if !copakyActive(in: app) {
            dump(app, "switch-failed")
        }
        XCTAssertTrue(copakyActive(in: app), "Copaky did not become the active keyboard")
    }

    /// Focus the compose textarea (#demo-field) of the demo page. The orchestrator has
    /// already navigated Safari to the demo page via `simctl openurl` (the `-u` launch arg
    /// does NOT navigate on iOS 26); here we only bring Safari forward and focus the field.
    @discardableResult
    private func focusDemoField() -> XCUIElement {
        safari.activate()
        let web = safari.webViews.firstMatch
        if !web.waitForExistence(timeout: 15) {
            safari.activate()
            _ = web.waitForExistence(timeout: 10)
        }
        // dismiss Safari first-run coach-marks / popovers that can cover the compose field
        for closeLabel in ["Continue", "Continua", "Start Browsing", "続ける", "Close", "Chiudi", "OK", "Not Now", "後で"] {
            let x = safari.buttons[closeLabel]
            if x.exists && x.isHittable { x.tap(); settle(0.4) }
        }
        let pred = NSPredicate(format: "identifier == 'demo-field' OR placeholderValue CONTAINS 'Type a note' OR value CONTAINS 'Type a note' OR label CONTAINS 'Type a note'")
        var field = web.descendants(matching: .any).matching(pred).firstMatch
        if !field.waitForExistence(timeout: 8) {
            web.swipeUp()
            settle(0.5)
            field = web.descendants(matching: .any).matching(pred).firstMatch
        }
        if field.waitForExistence(timeout: 4) && field.isHittable {
            field.tap()
            settle(0.5)
            return field
        }
        // last resort: tap the bottom compose area where the textarea lives
        safari.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.84)).tap()
        settle(0.6)
        return web
    }

    /// Tap a sequence of Copaky keys by label. On an empty field auto-capitalization shifts
    /// the QWERTY, so the key labels are uppercase — fall back to the other case rather than
    /// failing (measured 2026-08-27: shot06 on a freshly loaded page found "H", not "h").
    private func tapKeys(_ labels: [String], in app: XCUIApplication) {
        for label in labels {
            var key = app.descendants(matching: .any)[label]
            if !(key.waitForExistence(timeout: 4) && key.isHittable) {
                let other = label == label.lowercased() ? label.uppercased() : label.lowercased()
                key = app.descendants(matching: .any)[other]
                guard key.waitForExistence(timeout: 2) && key.isHittable else {
                    XCTFail("Key '\(label)' (or '\(other)') not found on Copaky keyboard")
                    continue
                }
            }
            key.tap()
            settle(0.2)
        }
    }

    /// Switch Copaky's internal tab to the Latin QWERTY. From the JP flick tab the tab key is
    /// labelled "ABC" ("A" is the QWERTY language key); the demo page text can also match those
    /// labels, so among the candidates pick the BOTTOM-most hittable one (the keyboard) — the
    /// same trick the globe lookup uses. Verify the switch happened (q/Q on screen) and fail
    /// loudly otherwise (measured 2026-08-27: the old silent no-op left shot06 on the flick tab).
    private func switchToEnglishTab(in app: XCUIApplication) {
        dismissCopakyNotice(in: app)
        let latinProbe = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch
        if latinProbe.exists { return }
        for label in ["ABC", "A"] {
            let matches = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label))
            var key: XCUIElement?
            var bestY: CGFloat = -1
            for i in 0..<min(matches.count, 8) {
                let el = matches.element(boundBy: i)
                if el.exists && el.isHittable && el.frame.maxY > bestY {
                    bestY = el.frame.maxY
                    key = el
                }
            }
            if let key {
                key.tap()
                settle(0.8)
                dismissCopakyNotice(in: app)
                if latinProbe.waitForExistence(timeout: 2) { return }
            }
        }
        XCTFail("Could not switch to the Latin QWERTY tab (no q/Q after tapping bottom-most ABC/A)")
    }

    /// Open Clipboard history through A-11's direct long-press, or through the tab-bar fallback.
    /// Returns true if the clipboard tab (capture bar) is reached.
    @discardableResult
    private func openClipboardTab(in app: XCUIApplication) -> Bool {
        dismissCopakyNotice(in: app)
        if firstMatch(in: app, labels: SL.captureBar, timeout: 2) != nil { return true }

        func tapClipboardItem() -> Bool {
            let symbolPred = NSPredicate(format: "identifier CONTAINS 'doc.badge.clock' OR label CONTAINS 'doc.badge.clock'")
            let sym = app.descendants(matching: .any).matching(symbolPred).firstMatch
            if sym.exists && sym.isHittable { sym.tap(); return true }
            if let tab = firstMatch(in: app, labels: SL.clipboardTab, timeout: 1) { tab.tap(); return true }
            return false
        }
        if tapClipboardItem(), firstMatch(in: app, labels: SL.captureBar, timeout: 2) != nil { return true }

        let keyPred = NSPredicate(format: "label IN %@", SL.tabBarToggleKey)
        let toggleKey = app.descendants(matching: .any).matching(keyPred).firstMatch
        if toggleKey.waitForExistence(timeout: 4) {
            toggleKey.press(forDuration: 1.0)
            settle(0.8)
            dismissCopakyNotice(in: app)
            if firstMatch(in: app, labels: SL.captureBar, timeout: 2) != nil { return true }
            if tapClipboardItem() {
                settle(0.8)
                if firstMatch(in: app, labels: SL.captureBar, timeout: 3) != nil { return true }
            }
        }
        return false
    }

    // MARK: - MainApp helpers

    private func launchMainApp() {
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: SL.closeOnboarding, timeout: 4), close.isHittable {
            close.tap(); settle(0.5)
        }
        // clear any DataUpdateView notices that overlay the MainApp
        for _ in 0..<6 {
            let action = mainApp.buttons.matching(NSPredicate(format: "label IN %@", SL.mainAppNoticeAction)).firstMatch
            if action.waitForExistence(timeout: 1) && action.isHittable {
                action.tap()
                settle(1.0)
            } else {
                break
            }
        }
    }

    /// Select a MainApp bottom-bar tab by label, falling back to a normalized coordinate.
    private func openMainTab(labels: [String], normalizedX: CGFloat) {
        let tab = mainApp.tabBars.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        if tab.waitForExistence(timeout: 3) && tab.isHittable {
            tab.tap()
        } else if let el = firstMatch(in: mainApp, labels: labels, timeout: 2), el.isHittable {
            el.tap()
        } else {
            mainApp.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.96)).tap()
        }
        settle(1.0)
    }

    // MARK: - 00 · Warmup — launch the keyboard once to CREATE the App Group container.
    //
    // This is run by the orchestrator BEFORE seeding, so the shared container
    // exists (get_app_container resolves) and seed_sim_clipboard.sh can write into it.
    // It is not a store screenshot; excluded from the screenshot run via -only-testing.

    func test_shot00_warmup() throws {
        _ = focusDemoField()
        switchToCopaky(in: safari)
        settle(1.0)
        shot("shot00_warmup")
        XCTAssertTrue(copakyActive(in: safari), "Warmup: Copaky did not activate; container may not be created")
    }

    // MARK: - 01 · Hero — JP flick keyboard active, text in composition.

    func test_shot01_hero() throws {
        _ = focusDemoField()
        switchToCopaky(in: safari)
        // compose "さかな" (fish) with tap-only row heads → marked text + candidate row
        tapKeys(["さ", "か", "な"], in: safari)
        settle(1.0)
        XCTAssertTrue(copakyActive(in: safari), "Copaky not active for hero shot")
        shot("shot01")
    }

    // MARK: - 02 · Conversion candidates visible after typing kana.

    func test_shot02_conversion() throws {
        _ = focusDemoField()
        switchToCopaky(in: safari)
        // "かな" → conversion candidates include 仮名 (known-good, per campaign test20)
        tapKeys(["か", "な"], in: safari)
        settle(1.0)
        let candidate = safari.descendants(matching: .any)["仮名"].firstMatch
        if !candidate.waitForExistence(timeout: 4) {
            // best-effort: candidate strip may vary; still capture the conversion state
            NSLog("shot02: expected candidate 仮名 not found; capturing current conversion state anyway")
        }
        shot("shot02")
    }

    // MARK: - 03 · Clipboard tab with SEEDED history. Canary: fail (no fake shot) if absent.

    func test_shot03_clipboard() throws {
        _ = focusDemoField()
        switchToCopaky(in: safari)
        let opened = openClipboardTab(in: safari)
        // Canary #1: the clipboard tab itself must open (seeded tab bar present).
        // Canary #2: a seeded item's text must be visible (seeded history present).
        let canaryPred = NSPredicate(format: "label CONTAINS[c] %@", clipboardCanary)
        let canaryEl = safari.descendants(matching: .any).matching(canaryPred).firstMatch
        let canaryVisible = canaryEl.waitForExistence(timeout: 6)
        if !opened || !canaryVisible {
            dump(safari, "shot03-clipboard-missing")
            shot("shot03_FAILED_diagnostic")
            XCTFail("Clipboard seeding canary failed (opened=\(opened), canary '\(clipboardCanary)' visible=\(canaryVisible)). No store screenshot produced.")
            return
        }
        shot("shot03")
    }

    // MARK: - 04 · Privacy — MainApp settings with the clipboard opt-in toggle.

    func test_shot04_privacy() throws {
        launchMainApp()
        openMainTab(labels: SL.settingsTab, normalizedX: 0.875)
        // scroll the clipboard toggle into view
        let togglePred = NSPredicate(format: "label IN %@", SL.clipboardToggle)
        var toggle = mainApp.switches.matching(togglePred).firstMatch
        var scrolls = 0
        while !toggle.exists && scrolls < 6 {
            mainApp.swipeUp()
            settle(0.5)
            toggle = mainApp.switches.matching(togglePred).firstMatch
            scrolls += 1
        }
        if !toggle.exists {
            // fall back to matching the label as static text (row may not vend a switch until near view)
            if let row = firstMatch(in: mainApp, labels: SL.clipboardToggle, timeout: 3) {
                _ = row
            } else {
                dump(mainApp, "shot04-no-toggle")
                NSLog("shot04: clipboard toggle not located; capturing settings screen anyway")
            }
        }
        settle(0.5)
        shot("shot04")
        XCTAssertTrue(firstMatch(in: mainApp, labels: SL.clipboardToggle, timeout: 2) != nil,
                      "Clipboard opt-in toggle not visible in MainApp settings")
    }

    // MARK: - 05 · Themes — MainApp theme gallery with the 3 Copaky presets.

    func test_shot05_themes() throws {
        launchMainApp()
        openMainTab(labels: SL.themesTab, normalizedX: 0.375)
        // The Copaky presets sit at the top of the "choose" section on a fresh install.
        var found = firstMatch(in: mainApp, labels: SL.copakyPresets, timeout: 4) != nil
        var scrolls = 0
        while !found && scrolls < 5 {
            mainApp.swipeUp()
            settle(0.5)
            found = firstMatch(in: mainApp, labels: SL.copakyPresets, timeout: 2) != nil
            scrolls += 1
        }
        // try to bring the presets to the top of the visible area for a clean gallery shot
        if found { mainApp.swipeDown(); settle(0.4) }
        shot("shot05")
        XCTAssertTrue(firstMatch(in: mainApp, labels: SL.copakyPresets, timeout: 3) != nil,
                      "Copaky theme presets not visible in Themes tab")
    }

    // MARK: - 06 · English — QWERTY EN active with typed text.

    func test_shot06_english() throws {
        let field = focusDemoField()
        switchToCopaky(in: safari)
        switchToEnglishTab(in: safari)
        settle(0.5)
        // type a short word so the QWERTY layout is clearly in use — Italian on the
        // Italian demo page, English elsewhere (this shot feeds the per-locale listing)
        let word = demoURL.contains("demo.it") ? ["c", "i", "a", "o"] : ["h", "e", "l", "l", "o"]
        tapKeys(word, in: safari)
        settle(0.6)
        // (The old best-effort accent-popup long-press typed a stray letter on release —
        // measured 2026-08-27: «helloe» — so it is gone.)
        shot("shot06")
        if let value = field.value as? String {
            NSLog("shot06 field value: \(value)")
        }
        XCTAssertTrue(copakyActive(in: safari), "Copaky QWERTY not active for English shot")
    }
}
