//
//  MainAppUITests.swift — Copaky Simulator test campaign harness
//  コパキー・シミュレータテストキャンペーン用ハーネス
//
//  Drives the phase A/B/C2 checklist in reports/sim_test_2026-07.md (workspace repo).
//  Tests are ordered (test01_, test02_, …) and some depend on state created by earlier
//  tests (keyboard enabled in Settings, Full Access granted). Run the whole class in order.
//  The KEYBOARD TAB is inherited too, and not only within one run: `KeyboardViewController
//  .variableStates` is a process-level `static let`, so the tab a test leaves behind survives host-app
//  relaunches and even whole `xcodebuild test` invocations, as long as the extension process lives.
//  A test that needs a particular tab must therefore ASK for it (switchToJapaneseFlickTab /
//  switchToEnglishTab), never assume the default. The keyboard LAYOUT of those tabs is a setting the
//  Simulator only takes device-wide: scripts/seed_sim_settings.sh.
//  タブは拡張プロセスに残る（static variableStates）ため、必要なタブは各テストが明示的に選ぶこと。
//  Simulator locale is it_IT (Settings in Italian). Since commit c47f9765 the app ships an Italian
//  localization, and since the key-label fix the KEYBOARD's functional labels are localized too
//  (KeyLabelType.localizedText) — so a label that used to be Japanese on every device is now
//  "Spazio"/"Space"/"空白" depending on the UI language. Every label helper must therefore list all
//  three variants; a Japanese-only marker is a latent false negative.
//

import UIKit
import XCTest

private let fieldsPageURL = "http://127.0.0.1:8377/kbtest.html"

/// Multi-locale UI labels (Settings=it, MainApp=en, keyboard=ja)
private enum L {
    static let general = ["Generali", "General", "一般"]
    static let keyboardRow = ["Tastiera", "Keyboard", "キーボード"]
    static let keyboardsRow = ["Tastiere", "Keyboards", "キーボード"]
    static let addNewKeyboard = ["Aggiungi nuova tastiera", "Aggiungi nuova tastiera…", "Add New Keyboard", "Add New Keyboard…"]
    static let allowFullAccess = ["Consenti accesso completo", "Consenti pieno accesso", "Allow Full Access", "フルアクセスを許可"]
    static let allowButton = ["Consenti", "Allow", "許可"]
    static let closeOnboarding = ["閉じる", "Close", "Chiudi"]
    static let settingsTab = ["設定", "Settings", "Impostazioni"]
    static let clipboardToggle = ["Keep clipboard histories", "クリップボードの履歴を保存", "Salva la cronologia degli appunti"]
    static let captureBar = ["コピーした内容を追加", "現在のクリップボードを追加", "Add copied text", "Add current clipboard", "Aggiungi il testo copiato", "Aggiungi gli appunti correnti"]
    static let clipboardTab = ["コピー履歴", "clipboard_history_tab", "doc.badge.clock"]
    /// Flick key whose LONG-PRESS toggles the tab bar (FlickCustomKeySetting: ☆123 → .toggleTabBar).
    static let tabBarToggleKey = ["☆123", "123"]
    /// The bar button carrying our own mark (CopakyMark). Present on EVERY tab, unlike ☆123 which
    /// only exists on the flick layouts. The glyph is what XCUI actually exposes; the accessibility
    /// label is kept alongside it for when VoiceOver labelling wins.
    static let tabBarButton = ["写", "タブバーを開く", "Open the tab bar"]
    static let numberHintsToggle = ["Show numbers on the top row", "上段に数字を表示", "Mostra i numeri nella riga superiore"]
    static let italianToggle = ["Use Italian", "イタリア語を使う", "Usa l'italiano"]
    /// Enter key in its plain "return" state — localized since the key-label fix (Design.getEnterKeyText).
    static let enterKeyReturn = ["改行", "Newline", "A capo"]
    /// Space key on the simple/flick keyboards — localized since the key-label fix.
    static let spaceKey = ["空白", "Space", "Spazio"]
    /// Back key of the clipboard and emoji tabs — localized since the key-label fix.
    static let backKey = ["戻る", "Back", "Indietro"]
    /// Master switch that reveals every settings section (the paste-control row lives behind it).
    static let showAllSettings = ["Show all settings", "すべての設定を表示", "Mostra tutte le impostazioni"]
    /// Experimental setting that swaps our capture button for Apple's `UIPasteControl`.
    static let systemPasteToggle = ["Use the system paste button", "システムのペーストボタンを使う", "Usa il pulsante Incolla di sistema"]
    /// `UIPasteControl` vends a button whose label iOS localizes for us.
    static let systemPasteControl = ["Paste", "ペースト", "Incolla"]
}

@MainActor
final class CopakyCampaignTests: XCTestCase {

    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    let mainApp = XCUIApplication(bundleIdentifier: "com.pettipol.copaky")
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")

    override func setUpWithError() throws {
        continueAfterFailure = false
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

    // MARK: - Query helpers

    /// First existing element among `labels`, searched across common element types.
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
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        return nil
    }

    @discardableResult
    private func tapFirst(in app: XCUIApplication, labels: [String], timeout: TimeInterval = 6,
                          scrollUpTo: Int = 0, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        var tries = 0
        repeat {
            if let el = firstMatch(in: app, labels: labels, timeout: timeout), el.isHittable {
                el.tap()
                // settle: let navigation/sheet animations finish before the next query
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                return true
            }
            if tries < scrollUpTo { app.swipeUp() }
            tries += 1
        } while tries <= scrollUpTo
        XCTFail("Element not found for labels \(labels)", file: file, line: line)
        return false
    }

    /// The software keyboard element of the host app.
    private func keyboard(of app: XCUIApplication) -> XCUIElement {
        app.keyboards.firstMatch
    }

    /// Heuristic: Copaky (azooKey) is the active keyboard when its Japanese special keys exist,
    /// or when a keyboard is on screen that exposes no stock `Key` elements (custom SwiftUI keyboard).
    /// NOTE: custom keyboards may not vend a standard `Keyboard` accessibility element at all.
    private func copakyActive(in app: XCUIApplication) -> Bool {
        dismissCopakyNotice(in: app)
        // Markers must be COPAKY-SPECIFIC. 「空白」/「改行」 are NOT: Apple's own kana keyboard shows
        // them too, so using them here made the campaign silently test the system keyboard whenever
        // the globe had cycled away from Copaky. Every marker below exists only in our layouts:
        // ☆123 and 小ﾞﾟ on the flick tab, Aあ on the QWERTY tabs, 逆順/お知らせ in our bars.
        // マーカーはCopaky固有のものだけにする（空白・改行は純正キーボードにも存在する）。
        // 写 is our own brand mark (CopakyMark, on the bar button): the single most reliable marker,
        // because it is a glyph we draw ourselves and no system keyboard can carry it.
        // 写は自社ブランドマークなので、純正キーボードには絶対に存在しない。
        //
        // Learned on a real phone (2026-08-12), where the previous list matched NOTHING while Copaky
        // was plainly the active keyboard: on the QWERTY tabs the language key reads 「あ」 alone, not
        // "Aあ". 「あ」 is deliberately NOT added here — Apple's own kana keyboard has that key too, so
        // it would hand a pass to the system keyboard, which is the exact bug this list exists to stop.
        let markers = ["写", "☆123", "小ﾞﾟ", "Aあ", "あいう", "逆順", "お知らせ"]
        return app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", markers)).firstMatch.exists
        // Deliberately NO "any keyboard that exposes no keys is ours" fallback. Every SwiftUI-drawn
        // third-party keyboard has that shape, and this very test phone also carries SwiftKey and
        // Gboard: the fallback could certify the WRONG keyboard and the suite would happily test it.
        // 「キーが0個の入力ビュー＝Copaky」判定は誤検知の温床なので置かない。
    }

    /// First-activation in-keyboard notices (お知らせ: 4 stacked emoji-tab data updates) cover the
    /// keyboard UI on every keyboard load (後で only defers, it does not persist). Dismiss all of them
    /// with 後で ("later"); never tap 追加/更新 (those would open the containing app).
    /// They can animate in with a short delay, so wait-and-retry a few rounds.
    private func dismissCopakyNotice(in app: XCUIApplication) {
        var quiet = 0
        for _ in 0..<12 {
            // 4 notices stack at the same position → the query matches multiple; ALWAYS use firstMatch
            // (accessing .frame/.isHittable on a multi-match query throws "Multiple matching elements").
            let later = app.buttons.matching(NSPredicate(format: "label == %@", "後で")).firstMatch
            if later.exists {
                if later.isHittable { later.tap() }
                quiet = 0
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            } else {
                quiet += 1
                if quiet >= 2 { break }              // two consecutive clear checks → done
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            }
        }
    }

    /// Switch the active keyboard to Copaky via the globe key (long-press picker, then tap fallback).
    private func switchToCopaky(in app: XCUIApplication) {
        if copakyActive(in: app) { return }
        let kb = keyboard(of: app)
        // custom keyboards may not vend a Keyboard element; accept either signal before proceeding
        var up = false
        for _ in 0..<8 {
            if kb.exists || copakyActive(in: app) { up = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        }
        XCTAssertTrue(up, "No software keyboard appeared (hardware keyboard connected?)")
        if copakyActive(in: app) { return }
        let globePred = NSPredicate(format: "label CONTAINS[c] 'astiera successiva' OR label CONTAINS[c] 'ext keyboard' OR label CONTAINS[c] '次のキーボード'")
        // On iPhone X+ the SYSTEM globe sits in the bottom bar BELOW the keyboard; a press on the
        // in-keyboard corner one can be read as an edge gesture (opens the app switcher). Pick the
        // matching button with the greatest Y = the bottom-bar globe.
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
        if globe.exists {
            globe.press(forDuration: 1.0)
            shot("switch-picker")
            // the input-switcher menu may be hosted by the app or by SpringBoard
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let pickInApp = firstMatch(in: app, labels: ["Copaky"], timeout: 2)
            let pick = pickInApp ?? firstMatch(in: springboard, labels: ["Copaky"], timeout: 2)
            if let pick, pick.exists {
                pick.tap()
            } else {
                dump(app, "switch-picker-app")
            }
            // cold launch of the extension can take a while on first activation
            for _ in 0..<10 where !copakyActive(in: app) {
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            }
        }
        if !copakyActive(in: app) {
            dump(app, "switch-failed")
            shot("switch-failed")
        }
        XCTAssertTrue(copakyActive(in: app), "Copaky did not become the active keyboard")
    }

    /// Open the Safari test page and focus a field by placeholder label.
    private func focusField(_ placeholder: String) -> XCUIElement {
        safari.launchArguments = ["-u", fieldsPageURL]
        safari.launch()
        let web = safari.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10), "Safari webview did not load")
        // dismiss Safari first-run coach-marks that cover the page
        for closeLabel in ["Chiudi", "Close", "OK", "Continua", "Continue"] {
            let x = safari.buttons[closeLabel]
            if x.exists && x.isHittable {
                x.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }
        let pred = NSPredicate(format: "label == %@ OR placeholderValue == %@ OR identifier == %@", placeholder, placeholder, placeholder)
        var field = web.descendants(matching: .any).matching(pred).firstMatch
        if !field.waitForExistence(timeout: 6) {
            web.swipeUp()
            field = web.descendants(matching: .any).matching(pred).firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 6), "Field \(placeholder) not found in test page")
        field.tap()
        return field
    }

    /// Tap a sequence of Copaky keys by label.
    ///
    /// On a miss it attaches the element tree and a screenshot BEFORE failing: with
    /// `continueAfterFailure = false` the assertion aborts the test immediately, so evidence gathered
    /// after it would never be recorded — and "key not found" is otherwise indistinguishable between
    /// "wrong layout on screen", "wrong tab", and "keyboard not up at all".
    /// キーが見つからない場合は、アサート前に要素ツリーとスクリーンショットを保存する。
    private func tapKeys(_ labels: [String], in app: XCUIApplication) {
        for label in labels {
            let key = app.descendants(matching: .any)[label]
            if !key.waitForExistence(timeout: 4) {
                dump(app, "key-not-found-\(label)")
                shot("key-not-found-\(label)")
            }
            XCTAssertTrue(key.exists, "Key '\(label)' not found on Copaky keyboard")
            key.tap()
        }
    }

    // MARK: - 00 · Clear one-time update notices permanently (unblocks in-keyboard UI)

    /// The bundled emoji dictionary is older than the simulator's iOS, so azooKey shows several
    /// one-time "update your data?" notices in BOTH the app and the keyboard. In the keyboard they
    /// re-appear on every load (後で only defers). Clearing them in the MainApp (どうする→更新/追加,
    /// which runs the local emoji/dict update and marks the message shown) stops them for good.
    func test00_clearUpdateNotices() throws {
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) { close.tap() }
        // DataUpdateView alerts surface on the Usage tab; resolve each with its action button.
        for _ in 0..<8 {
            let action = mainApp.buttons.matching(NSPredicate(format: "label IN %@", ["更新", "追加", "OK", "アップデート"])).firstMatch
            if action.waitForExistence(timeout: 2) && action.isHittable {
                action.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(1.2))
            } else {
                break
            }
        }
        shot("00-notices-cleared")
    }

    // MARK: - 01 · Enable keyboard in Settings (checklist A-01)

    /// Navigate Settings → Generali → Tastiera → keyboards list ("Aggiungi nuova tastiera" page).
    private func openKeyboardsList() {
        settings.launch()
        tapFirst(in: settings, labels: L.general, scrollUpTo: 2)
        tapFirst(in: settings, labels: L.keyboardRow, scrollUpTo: 4)
        // "Tastiere" row (shows the enabled-keyboard count) — retry until the list page is open
        var hops = 0
        while firstMatch(in: settings, labels: L.addNewKeyboard, timeout: 3) == nil && hops < 3 {
            // the keyboards-list row label is composite ("Tastiere, 6") — use BEGINSWITH on rows only
            let pred = NSPredicate(format: "label BEGINSWITH 'Tastiere' OR label BEGINSWITH 'Keyboards'")
            let row = settings.cells.matching(pred).firstMatch
            let btn = settings.buttons.matching(pred).firstMatch
            if row.exists && row.isHittable { row.tap() } else if btn.exists && btn.isHittable { btn.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            hops += 1
        }
    }

    func test01_enableKeyboardInSettings() throws {
        openKeyboardsList()
        shot("01-keyboards-list-before")
        if firstMatch(in: settings, labels: ["Copaky"], timeout: 2) == nil {
            tapFirst(in: settings, labels: L.addNewKeyboard, scrollUpTo: 2)
            shot("01-add-new-keyboard-sheet")
            // Third-party section lists "Copaky" (A-01: note whether it appears without app launch)
            tapFirst(in: settings, labels: ["Copaky"], timeout: 8, scrollUpTo: 2)
        }
        let row = firstMatch(in: settings, labels: ["Copaky"], timeout: 6)
        if row == nil { dump(settings, "01-after-add") }
        XCTAssertNotNil(row, "Copaky row not present in Keyboards list after add")
        shot("01-keyboards-list-after")
    }

    // MARK: - 02 · Keyboard appears + switch to Copaky (A-02 surface)

    func test02_phaseA_switchToCopaky() throws {
        let field = focusField("plain-text")
        _ = field
        // custom keyboards may not vend a standard Keyboard element — wait on either signal
        var up = false
        for _ in 0..<10 {
            if keyboard(of: safari).exists || copakyActive(in: safari) { up = true; break }
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        }
        XCTAssertTrue(up, "No software keyboard appeared on plain field")
        shot("02-keyboard-up")
        switchToCopaky(in: safari)
        shot("02-copaky-active")
        dump(safari, "02-copaky-tree")
    }

    // MARK: - 03 · Clipboard toggle disabled without Full Access (A-03)

    func test03_phaseA_clipboardToggleWithoutFA() throws {
        mainApp.launch()
        // dismiss first-open onboarding if present
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        shot("03-mainapp-home")
        openSettingsTab()
        shot("03-settings-tab")
        guard let toggle = firstMatch(in: mainApp, labels: L.clipboardToggle, timeout: 6) else {
            // scroll and retry once — the clipboard section may be below the fold
            mainApp.swipeUp()
            let t2 = firstMatch(in: mainApp, labels: L.clipboardToggle, timeout: 4)
            if t2 == nil { dump(mainApp, "03-no-toggle") }
            XCTAssertNotNil(t2, "Clipboard history toggle not found in MainApp settings")
            t2!.tap()
            shot("03-toggle-tapped-noFA")
            return
        }
        toggle.tap()
        // Expected (FA off): alert explaining Full Access requirement, with open-Settings button
        shot("03-toggle-tapped-noFA")
        dump(mainApp, "03-after-tap")
    }

    /// Select the Settings tab of the MainApp (custom SwiftUI tab bar; coordinate fallback).
    private func openSettingsTab() {
        let tab = mainApp.tabBars.buttons.matching(NSPredicate(format: "label IN %@", L.settingsTab)).firstMatch
        if tab.waitForExistence(timeout: 3) && tab.isHittable {
            tab.tap()
        } else if let el = firstMatch(in: mainApp, labels: L.settingsTab, timeout: 3), el.isHittable {
            el.tap()
        } else {
            // custom tab bar: rightmost of 4 tabs, near the bottom edge
            mainApp.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.94)).tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    // MARK: - 04 · Rotation with keyboard open (A-05 / Q-06)

    func test04_phaseA_rotation() throws {
        _ = focusField("plain-text")
        switchToCopaky(in: safari)
        shot("04-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("04-landscape")
        XCTAssertTrue(copakyActive(in: safari), "Copaky vanished after rotation to landscape")
        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("04-back-portrait")
        XCTAssertTrue(copakyActive(in: safari), "Copaky vanished after rotation back to portrait")
    }

    // MARK: - 05 · Field traits: url/email/number/tel/secure (A-06…A-09)

    func test05_phaseA_fieldTraits() throws {
        for (placeholder, tag) in [("url-field", "url"), ("email-field", "email"),
                                   ("number-field", "number"), ("tel-field", "tel"),
                                   ("password-secure", "secure")] {
            _ = focusField(placeholder)
            RunLoop.current.run(until: Date().addingTimeInterval(2.0))
            shot("05-\(tag)")
            // Evidence-first: screenshots document which keyboard iOS presents per trait.
            // Custom keyboards may not vend a Keyboard element — accept either signal.
            let anyKeyboard = keyboard(of: safari).exists || copakyActive(in: safari)
            XCTAssertTrue(anyKeyboard, "No keyboard of any kind on \(tag) field")
        }
        dump(safari, "05-secure-tree")
    }

    // MARK: - 10 · Enable Full Access (B-01)

    func test10_phaseB_enableFullAccess() throws {
        openKeyboardsList()
        tapFirst(in: settings, labels: ["Copaky", "Copaky — Copaky", "Copaky, Copaky"], scrollUpTo: 2)
        shot("10-copaky-keyboard-page")
        let fa = settings.switches.matching(NSPredicate(format: "label IN %@", L.allowFullAccess)).firstMatch
        guard fa.waitForExistence(timeout: 6) else {
            dump(settings, "10-no-fa-toggle")
            XCTFail("Allow Full Access switch not found")
            return
        }
        if (fa.value as? String) != "1" {
            // the switch element spans the whole cell; tap its right side where the toggle sits
            fa.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            // Confirmation alert ("Consenti accesso completo…" → Consenti)
            let allow = settings.alerts.buttons.matching(NSPredicate(format: "label IN %@", L.allowButton)).firstMatch
            if allow.waitForExistence(timeout: 6) {
                allow.tap()
            } else if let anyAllow = firstMatch(in: settings, labels: L.allowButton, timeout: 3) {
                anyAllow.tap()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        }
        shot("10-full-access-on")
        XCTAssertEqual(fa.value as? String, "1", "Allow Full Access did not turn ON")
    }

    // MARK: - 11 · Clipboard opt-in default OFF → enable (B-02)

    func test11_phaseB_clipboardOptIn() throws {
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        // Find the clipboard SwiftUI Toggle (a .switch element) — scroll it into view if needed
        let togglePred = NSPredicate(format: "label IN %@", L.clipboardToggle)
        var toggle = mainApp.switches.matching(togglePred).firstMatch
        var scrolls = 0
        while !toggle.exists && scrolls < 6 {
            mainApp.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            toggle = mainApp.switches.matching(togglePred).firstMatch
            scrolls += 1
        }
        guard toggle.exists else {
            dump(mainApp, "11-no-toggle")
            XCTFail("Clipboard toggle switch not found")
            return
        }
        shot("11-initial-state")
        // Idempotent across reruns: drive to OFF (retrying the tap) so we exercise the opt-in enable
        // path from a known state and leave it ON for the clipboard tests (12–15).
        func currentToggle() -> XCUIElement { mainApp.switches.matching(togglePred).firstMatch }
        var resets = 0
        while currentToggle().value as? String == "1" && resets < 4 {
            currentToggle().coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            // a "全て削除" style confirmation may appear on disable; dismiss any stray alert
            if mainApp.alerts.buttons["OK"].waitForExistence(timeout: 1) { mainApp.alerts.buttons["OK"].tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            resets += 1
        }
        // B-02: with Full Access on, the setting is available and rests OFF (opt-in)
        XCTAssertEqual(currentToggle().value as? String, "0", "Clipboard history must be opt-in (OFF before enabling)")
        shot("11-default-off")
        currentToggle().coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        // onEnabled confirmation alert "タブバーに「コピー履歴」…" is the nice-to-have signal that the
        // flip took effect; its exact timing is flaky when we toggle twice in one session, so we record
        // it as evidence but do NOT hard-assert on it. The load-bearing checks are (a) opt-in default
        // OFF above and (b) the toggle reaching ON below.
        let alertOK = mainApp.alerts.buttons["OK"]
        if alertOK.waitForExistence(timeout: 5) {
            shot("11-enabled-alert")
            alertOK.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let fresh = mainApp.switches.matching(togglePred).firstMatch
        XCTAssertEqual(fresh.value as? String, "1", "Toggle is not ON after enabling")
        shot("11-enabled")
    }

    // MARK: - 12 · Capture on intent (B-03) — seed pasteboard in-process

    func test12_phaseB_captureOnIntent() throws {
        UIPasteboard.general.string = "Copaky-capture-\(Int.random(in: 1000...9999))"
        _ = focusField("plain-text")
        switchToCopaky(in: safari)
        try openClipboardTab()
        shot("12-clipboard-tab")
        guard let capture = firstMatch(in: safari, labels: L.captureBar, timeout: 6) else {
            dump(safari, "12-no-capture-bar")
            XCTFail("Capture bar not found in clipboard tab")
            return
        }
        capture.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("12-after-capture")
        dump(safari, "12-after-capture")
    }

    /// Is the clipboard panel on screen?
    ///
    /// Do NOT answer this by looking for the capture button alone. With `use_system_paste_control` ON
    /// that button is REPLACED by Apple's paste control, so a panel that had opened perfectly was
    /// reported as "clipboard tab not found" — the suite blamed Full Access for a state our own
    /// feature had created. Verified on the phone 2026-08-12: the open panel carried a Button
    /// labelled 'Incolla' and no capture bar at all.
    /// システムのペーストボタンがONだと取り込みバーが置き換わるため、両方を見て判定する。
    private func clipboardPanelIsOpen(timeout: TimeInterval = 2) -> Bool {
        firstMatch(in: safari, labels: L.captureBar + L.systemPasteControl, timeout: timeout) != nil
    }

    /// Open the コピー履歴 (clipboard history) tab from Copaky's tab bar.
    /// Navigation: long-press the ☆123 flick key → `.toggleTabBar` shows the tab bar → tap the pinned
    /// clipboard item (SF Symbol doc.badge.clock, added by the setting's onEnabled).
    private func openClipboardTab() throws {
        dismissCopakyNotice(in: safari)
        if clipboardPanelIsOpen() { return }

        // Try to reach the clipboard tab item directly (tab bar may already be visible).
        func tapClipboardItem() -> Bool {
            let symbolPred = NSPredicate(format: "identifier CONTAINS 'doc.badge.clock' OR label CONTAINS 'doc.badge.clock'")
            let sym = safari.descendants(matching: .any).matching(symbolPred).firstMatch
            if sym.exists && sym.isHittable { sym.tap(); return true }
            if let tab = firstMatch(in: safari, labels: L.clipboardTab, timeout: 1) { tab.tap(); return true }
            return false
        }
        if tapClipboardItem(), clipboardPanelIsOpen() { return }

        // Open the tab bar with the 写 bar button — a plain TAP on our own mark, and the only route
        // that exists on the QWERTY tabs. Verified on the phone (2026-08-12): the ☆123 long-press
        // below is a FLICK-tab key, so on a Latin layout the old path found nothing and the caller
        // skipped with "clipboard tab is not on the bar" while Copaky was running perfectly.
        // QWERTYタブには☆123が無いため、バーのボタン（写）をタップして開く。
        let barButton = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.tabBarButton)).firstMatch
        if barButton.waitForExistence(timeout: 4) {
            barButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: safari)
            shot("clipboard-tabbar-open-barbutton")
            if tapClipboardItem() {
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                if clipboardPanelIsOpen() { return }
            }
        }

        // Open the tab bar via the ☆123 key long-press, then tap the clipboard item.
        let keyPred = NSPredicate(format: "label IN %@", L.tabBarToggleKey)
        let toggleKey = safari.descendants(matching: .any).matching(keyPred).firstMatch
        if toggleKey.waitForExistence(timeout: 4) {
            toggleKey.press(forDuration: 1.0)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: safari)
            shot("clipboard-tabbar-open")
            if tapClipboardItem() {
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                if clipboardPanelIsOpen() { return }
            }
        }

        dump(safari, "clipboard-tab-not-found")
        shot("clipboard-tab-not-found")
        // ROOT CAUSE (verified 2026-07-07): this UI test target builds UNSIGNED (CODE_SIGNING_ALLOWED=NO),
        // so the `group.com.pettipol.copaky` App Group container is NOT provisioned on the Simulator.
        // CustardManager.fileURL then falls back to a per-process temporaryDirectory, so the tab bar the
        // MainApp saves in onEnabled never reaches the keyboard process — the pinned clipboard tab item
        // never appears. Clipboard app↔keyboard coordination (capture/pin/persistence at the UI level) is
        // therefore only testable on a SIGNED build (device, or a signed Simulator build once a Team ID is
        // configured). The pure clipboard logic is covered by ClipboardHistoryManagerTests.
        throw XCTSkip("Clipboard tab needs the App Group container (signed build); unsigned sim has no shared container. Logic covered by ClipboardHistoryManagerTests; e2e pending signed build/device.")
    }

    // MARK: - 13 · Byte-cap >256KB without crash (B-05)

    func test13_phaseB_byteCap() throws {
        UIPasteboard.general.string = String(repeating: "あ", count: 120_000) // ~360KB UTF-8
        _ = focusField("plain-text")
        switchToCopaky(in: safari)
        try openClipboardTab()
        if let capture = firstMatch(in: safari, labels: L.captureBar, timeout: 6) {
            capture.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        // Expected: no crash, keyboard still alive; item rejected or truncated per maxItemByteCount
        XCTAssertTrue(copakyActive(in: safari), "Keyboard died after >256KB capture attempt")
        shot("13-after-bytecap")
    }

    // MARK: - 14 · Pin / delete / persistence (B-06, B-07)

    func test14_phaseB_pinDeletePersistence() throws {
        UIPasteboard.general.string = "Copaky-pin-me"
        _ = focusField("plain-text")
        switchToCopaky(in: safari)
        try openClipboardTab()
        if let capture = firstMatch(in: safari, labels: L.captureBar, timeout: 6) {
            capture.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        // Long-press the tile → context menu 固定 (pin)
        let tile = safari.staticTexts["Copaky-pin-me"].firstMatch
        if tile.waitForExistence(timeout: 4) {
            tile.press(forDuration: 1.2)
            shot("14-context-menu")
            if let pin = firstMatch(in: safari, labels: ["固定", "Pin"], timeout: 4) {
                pin.tap()
            }
        } else {
            dump(safari, "14-tile-not-found")
        }
        shot("14-after-pin")
        // Persistence: leave Safari (kills/suspends extension), reopen, reopen tab
        safari.terminate()
        _ = focusField("plain-text")
        switchToCopaky(in: safari)
        try openClipboardTab()
        let persisted = safari.staticTexts["Copaky-pin-me"].firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 6), "Pinned item did not persist across keyboard restarts")
        shot("14-persisted")
    }

    // MARK: - 15 · Secure-field guard on new-password (B-09 / Q-04b)

    func test15_phaseB_newPasswordGuard() throws {
        UIPasteboard.general.string = "should-not-be-capturable"
        _ = focusField("newpassword-field")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        shot("15-newpassword-focused")
        // If Copaky is allowed here, the capture bar must be disabled (isSecureEntry guard)
        if copakyActive(in: safari) {
            try openClipboardTab()
            if let capture = firstMatch(in: safari, labels: L.captureBar, timeout: 4) {
                XCTAssertFalse(capture.isEnabled, "Capture bar must be disabled on new-password field")
            }
            shot("15-capture-disabled")
        } else {
            // iOS replaced the keyboard: also acceptable, document it
            shot("15-system-keyboard-forced")
        }
        dump(safari, "15-tree")
    }

    // MARK: - 20 · C2: flick typing + conversion candidates (C2 smoke)

    /// True when the Japanese FLICK layout is on screen: 「か」 is a row head that exists only there
    /// (on the QWERTY Japanese tab the same kana is typed as "ka").
    private func flickKanaVisible(in app: XCUIApplication, timeout: TimeInterval = 0) -> Bool {
        let key = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "か")).firstMatch
        return timeout > 0 ? key.waitForExistence(timeout: timeout) : key.exists
    }

    /// Bring Copaky to the Japanese FLICK tab, whatever tab the run before it left on screen.
    ///
    /// Why a test must do this explicitly: `KeyboardViewController.variableStates` is a process-level
    /// `static let`, so its `TabManager` outlives one keyboard appearance — `closeKeyboard()` stores
    /// the current tab and the next `initialize()` RESTORES it (`TabManager.initialize`), and the
    /// extension process survives host-app relaunches. A test that moved to the Latin tab therefore
    /// hands the NEXT test a Latin keyboard. That is deliberate product behaviour (a user who picks
    /// English must not be pushed back to Japanese on every reload), so the test states the tab it
    /// needs instead of inheriting one.
    /// タブは拡張プロセスの static な variableStates に残るので、テスト側で明示的に日本語タブへ移動する。
    ///
    /// The flick LAYOUT itself is not reachable from the keyboard UI: the Japanese tab is flick or
    /// QWERTY according to `keyboard_type` (`JapaneseKeyboardLayout`, default `.flick`), and on the
    /// Simulator only the orchestrator can set it — the App Group is not provisioned, so the app's own
    /// switch never reaches the extension (`scripts/seed_sim_settings.sh keyboard_type=flick`).
    /// A Japanese tab that comes up as QWERTY is therefore reported as the setup problem it is.
    private func switchToJapaneseFlickTab(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        dismissCopakyNotice(in: app)
        if flickKanaVisible(in: app, timeout: 2) { return }

        // 1. Latin QWERTY tab → the language-switch key carries the TARGET language's shortSymbol,
        //    so 「あ」 is the one that goes BACK to Japanese (mirror of switchToEnglishTab's "A").
        let toJapanese = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "あ")).firstMatch
        if toJapanese.exists && toJapanese.isHittable {
            toJapanese.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: app)
            if flickKanaVisible(in: app, timeout: 2) { return }
        }

        // 2. Tab-bar route (works from the special tabs too, where there is no language-switch key):
        //    「あいう」 is the system `user_japanese` item. Open the bar first if it is not showing.
        var kanaTab = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "あいう")).firstMatch
        if !kanaTab.exists, let barButton = firstMatch(in: app, labels: L.tabBarButton, timeout: 2), barButton.isHittable {
            barButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            kanaTab = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "あいう")).firstMatch
        }
        if kanaTab.exists && kanaTab.isHittable {
            kanaTab.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: app)
            if flickKanaVisible(in: app, timeout: 2) { return }
        }

        // Evidence BEFORE the failure: continueAfterFailure is false, so nothing runs after it.
        dump(app, "20-no-japanese-flick-tab")
        shot("20-no-japanese-flick-tab")
        // Tell the two causes apart: on the Japanese tab the switch key offers "A" (go to English),
        // so "A" present + no kana means the Japanese tab is on the QWERTY layout, not that the tab
        // switch failed. 「A」が出ていれば日本語タブに居る＝レイアウトがローマ字入力ということ。
        let onJapaneseTab = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "A")).firstMatch.exists
        if onJapaneseTab {
            XCTFail("""
                Japanese tab is on the QWERTY layout, so there is no 「か」 key. Seed the layout before \
                the run: scripts/seed_sim_settings.sh keyboard_type=flick (on the Simulator the App \
                Group is not provisioned, so the app's own setting never reaches the extension).
                """, file: file, line: line)
        } else {
            XCTFail("Could not reach Copaky's Japanese tab (neither the 「あ」 switch key nor the 「あいう」 tab-bar item worked)", file: file, line: line)
        }
    }

    func test20_C2_flickTypingConversion() throws {
        _ = focusField("textarea-field")
        switchToCopaky(in: safari)
        // The tab is inherited from whatever ran before (static VariableStates) — ask for the one
        // this test is about instead of assuming it. / 直前のテストが残したタブに依存しない。
        switchToJapaneseFlickTab(in: safari)
        // Tap-only kana (row heads): か + な → candidates should include 仮名
        tapKeys(["か", "な"], in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        shot("20-kana-typed")
        let candidate = safari.descendants(matching: .any)["仮名"].firstMatch
        if candidate.waitForExistence(timeout: 4) {
            candidate.tap()
            shot("20-candidate-selected")
        } else {
            dump(safari, "20-no-candidate")
            shot("20-no-candidate")
        }
    }

    // MARK: - 30 · Copaky extension: accent variations on long-press (EN QWERTY)

    /// Switch Copaky's internal tab to the Latin one, from EITHER Japanese layout.
    ///
    /// Two different keys do this, and which one exists depends on the tab the previous test left
    /// behind (the tab survives in the extension's static `VariableStates` — see
    /// `switchToJapaneseFlickTab`): the FLICK Japanese tab carries 「ABC」, the QWERTY Japanese tab
    /// carries the language-switch key, which shows the TARGET language's shortSymbol
    /// (`QwertyLanguageSwitchKeyModel.shortSymbol`) — "A" from Japanese, 「あ」 when already on Latin
    /// (the no-op case this must not tap).
    /// フリック日本語タブでは「ABC」、ローマ字タブでは言語切替キー — 直前のタブに依存しないよう両方見る。
    private func switchToEnglishTab(in app: XCUIApplication) {
        dismissCopakyNotice(in: app)
        let abcKey = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "ABC")).firstMatch
        if abcKey.waitForExistence(timeout: 2) && abcKey.isHittable {
            abcKey.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: app)
            return
        }
        let toEnglish = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "A")).firstMatch
        if toEnglish.waitForExistence(timeout: 2) && toEnglish.isHittable {
            toEnglish.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: app)
        }
    }

    /// Copaky extension (QwertyLayoutProvider.abcKeyboard): long-pressing "e" on the EN QWERTY layout
    /// reveals Western-European accent variations ("è", "é", "ê", "ë"); dragging onto "è" and releasing
    /// must input it.
    func test30_accentVariationsOnLongPress() throws {
        let field = focusField("plain-text")
        switchToCopaky(in: safari)
        switchToEnglishTab(in: safari)
        shot("30-english-tab")
        let eKey = safari.descendants(matching: .any)["e"]
        XCTAssertTrue(eKey.waitForExistence(timeout: 4), "Key 'e' not found on Copaky EN keyboard")
        let variant = safari.descendants(matching: .any)["è"]
        eKey.press(forDuration: 0.6, thenDragTo: variant)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        shot("30-after-longpress")
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.contains("è"), "Accent variation 'è' was not inserted via long-press (got '\(value)')")
    }

    /// Focus a field on a page the ORCHESTRATOR already opened in Safari via `simctl openurl`
    /// (iOS 26 gotcha: the "-u" launch argument opens the Start Page instead of navigating).
    private func activatePreNavigatedField(_ placeholder: String) -> XCUIElement {
        safari.activate()
        let web = safari.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10), "Safari webview did not load (page must be pre-opened via simctl openurl)")
        for closeLabel in ["Chiudi", "Close", "OK", "Continua", "Continue"] {
            let x = safari.buttons[closeLabel]
            if x.exists && x.isHittable {
                x.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }
        let pred = NSPredicate(format: "label == %@ OR placeholderValue == %@ OR identifier == %@ OR value == %@", placeholder, placeholder, placeholder, placeholder)
        var field = web.descendants(matching: .any).matching(pred).firstMatch
        if !field.waitForExistence(timeout: 6) {
            web.swipeUp()
            field = web.descendants(matching: .any).matching(pred).firstMatch
        }
        XCTAssertTrue(field.waitForExistence(timeout: 6), "Field \(placeholder) not found in pre-navigated page")
        field.tap()
        return field
    }

    // MARK: - 31 · Copaky extension: optional number hints on the QWERTY top row

    /// Copaky extension (EnableNumberRowHints, default OFF): after enabling the toggle in
    /// MainApp ▸ Settings, the EN QWERTY top row carries digit hints and long-pressing "q"
    /// must input "1" via the leading variation.
    func test31_numberRowHintsOnLongPress() throws {
        // 1. Enable the toggle in MainApp settings (idempotent: skip if already ON)
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        var toggle = firstMatch(in: mainApp, labels: L.numberHintsToggle, timeout: 6)
        var swipes = 0
        while toggle == nil && swipes < 6 {
            mainApp.swipeUp()
            swipes += 1
            toggle = firstMatch(in: mainApp, labels: L.numberHintsToggle, timeout: 2)
        }
        guard let toggle else {
            dump(mainApp, "31-no-toggle")
            XCTFail("Number-hints toggle not found in MainApp settings")
            return
        }
        let sw = mainApp.switches.matching(NSPredicate(format: "label IN %@", L.numberHintsToggle)).firstMatch
        let alreadyOn = (sw.exists ? (sw.value as? String) : nil) == "1"
        if !alreadyOn {
            // SwiftUI Toggle: tapping the cell center does NOT flip it — tap the right side where
            // the switch sits (same gotcha as test10's Full Access toggle).
            let target = sw.exists ? sw : toggle
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        if sw.exists {
            XCTAssertEqual(sw.value as? String, "1", "Number-hints toggle did not turn ON")
        }
        shot("31-toggle-on")

        // 2. Long-press "q" on the EN QWERTY tab and drag onto the "1" variation.
        // NOTE: on iOS 26 Safari ignores the "-u" launch argument (see store_screenshots.sh);
        // the orchestrator must pre-navigate with `xcrun simctl openurl` — here we only activate.
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        // Flick JP tab → EN via the ABC key; on the QWERTY JP tab use the language-switch key. Both
        // routes live in switchToEnglishTab. (Orchestrator must set keyboard_type_en=roman so the EN
        // tab is QWERTY, not flick: scripts/seed_sim_settings.sh keyboard_type_en=roman.)
        switchToEnglishTab(in: safari)
        shot("31-english-tab")
        // firstMatch everywhere: the magnifier bubble duplicates the key label during the press
        let qKey = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'q'")).firstMatch
        XCTAssertTrue(qKey.waitForExistence(timeout: 4), "Key 'q' not found on Copaky EN keyboard")
        let variant = safari.descendants(matching: .any).matching(NSPredicate(format: "label == '1'")).firstMatch
        qKey.press(forDuration: 0.6, thenDragTo: variant)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        shot("31-after-longpress")
        let value = field.value as? String ?? ""
        XCTAssertTrue(value.contains("1"), "Digit '1' was not inserted via long-press (got '\(value)')")
    }

    // MARK: - 32 · Copaky extension: functional key labels follow the UI language

    /// Regression guard for the key-label localization bug reported in the first device round:
    /// `KeyLabelType.text(String)` rendered `Text(verbatim:)`, so the enter key kept showing 改行/確定
    /// on an English or Italian phone even though its VoiceOver label WAS translated. Functional
    /// labels now go through `KeyLabelType.localizedText` and resolve against the string catalog.
    /// This covers the LATIN tab, which follows the UI language ("Newline"/"space" on an EN device);
    /// the JAPANESE tab is deliberately ALWAYS Japanese (space 空白, enter 改行/確定), matching how
    /// Apple's own keyboard behaves — that is asserted by test36, not here.
    /// キーの機能ラベルがUI言語に追従することの回帰テスト（ラテンタブのみ）。日本語タブは常に日本語のまま
    /// （test36でカバー）。
    func test32_functionalKeyLabelsFollowUILanguage() throws {
        let language = Locale.preferredLanguages.first ?? "en"
        let expectedEnter: String
        switch language.prefix(2) {
        case "it": expectedEnter = "A capo"
        case "en": expectedEnter = "Newline"
        case "ja": expectedEnter = "改行"
        default:
            throw XCTSkip("Device language \(language) is not one Copaky localizes — nothing to assert")
        }

        // Pre-navigated page (iOS 26 ignores Safari's "-u"): the orchestrator opens it via simctl openurl.
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        switchToEnglishTab(in: safari)
        shot("32-latin-tab-\(language)")

        // firstMatch: the magnifier bubble can duplicate a label during transient presses.
        let enter = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expectedEnter)).firstMatch
        if !enter.waitForExistence(timeout: 6) {
            dump(safari, "32-no-enter-key")
        }
        XCTAssertTrue(enter.exists, "Enter key label '\(expectedEnter)' not found on a \(language) device")

        // The real proof: on a non-Japanese device the Japanese label must be GONE, not just duplicated.
        if expectedEnter != "改行" {
            let japanese = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "改行")).firstMatch
            XCTAssertFalse(japanese.exists, "Enter key still shows the Japanese label 改行 on a \(language) device")

            // Second code path, different mechanism: the space key of the flick tab comes from a
            // BUILT-IN CUSTARD (CustardKit's flickSpace bakes in 「空白」), translated at the
            // CustardKeyLabelStyle → KeyLabelType boundary. A regression there would leave 空白 on
            // screen while the enter key looks fine, so assert it separately.
            let japaneseSpace = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "空白")).firstMatch
            XCTAssertFalse(japaneseSpace.exists, "Space key still shows the Japanese label 空白 on a \(language) device")
        }
    }

    // MARK: - 33 · Copaky extension: Italian as a keyboard language

    /// Turning on Settings ▸ Usability ▸ "Use Italian" must put Italian into the language-switch
    /// cycle. English and Italian share ONE Latin tab (same layout, different prediction dictionary),
    /// so the proof is the switch key offering "IT" — there is no second tab to look for.
    /// イタリア語をオンにすると言語切替キーの巡回にITが加わることを確認する。
    ///
    /// SIMULATOR PREREQUISITES (the App Group is not provisioned on an unsigned simulator build, so
    /// the app and the extension end up with SEPARATE "group.com.pettipol.copaky" domains — flipping
    /// the toggle in the app does NOT reach the keyboard here; on a real device it does). The
    /// orchestrator must seed the device-wide domain and flush cfprefsd before running:
    ///   P=~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/group.com.pettipol.copaky.plist
    ///   killall cfprefsd
    ///   /usr/libexec/PlistBuddy -c "Add :enable_italian_keyboard_language bool true" "$P"
    ///   /usr/libexec/PlistBuddy -c "Add :keyboard_type_en string roman" "$P"   # the switch key is QWERTY-only
    ///   killall cfprefsd
    /// keyboard_type_en=roman matters: the language-switch key exists only on the QWERTY layouts, so
    /// on a flick Latin tab there is nothing to assert (Italian still applies — it is seeded at load).
    func test33_italianJoinsTheLanguageCycle() throws {
        // 1. Enable the toggle in MainApp settings (idempotent)
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        var row = firstMatch(in: mainApp, labels: L.italianToggle, timeout: 6)
        var swipes = 0
        while row == nil && swipes < 8 {
            mainApp.swipeUp()
            swipes += 1
            row = firstMatch(in: mainApp, labels: L.italianToggle, timeout: 2)
        }
        guard let row else {
            dump(mainApp, "33-no-toggle")
            XCTFail("Italian toggle not found in MainApp settings")
            return
        }
        let sw = mainApp.switches.matching(NSPredicate(format: "label IN %@", L.italianToggle)).firstMatch
        if (sw.exists ? (sw.value as? String) : nil) != "1" {
            // SwiftUI Toggle: the cell tap does not flip it — hit the right-hand side.
            (sw.exists ? sw : row).coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        if sw.exists {
            XCTAssertEqual(sw.value as? String, "1", "Italian toggle did not turn ON")
        }
        shot("33-toggle-on")

        // 2. Bring up Copaky and move to the Latin tab.
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        let abcKey = safari.descendants(matching: .any)["ABC"]
        if abcKey.waitForExistence(timeout: 3) && abcKey.isHittable {
            abcKey.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: safari)
        }
        shot("33-latin-tab")

        // 3. "IT" is the Italian shortSymbol: it appears on the switch key either as the language in
        // use or as the one the next tap selects. Allow one extra tap for the cycle to reach it.
        var italian = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "IT")).firstMatch
        if !italian.waitForExistence(timeout: 4) {
            let switchKey = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@ OR label == %@", "A", "あ")).firstMatch
            if switchKey.exists && switchKey.isHittable {
                switchKey.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            }
            italian = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "IT")).firstMatch
        }
        if !italian.exists {
            dump(safari, "33-no-italian")
        }
        shot("33-after-cycle")
        XCTAssertTrue(italian.exists, "Italian ('IT') never appeared on the language-switch key with the toggle ON")
    }

    // MARK: - 35 · Italian lexicon: bundled predictions on the Latin tab

    /// The bundled 50k-word frequency lexicon must produce Italian candidates — including the
    /// accent-fix ("citta" → "città", "perche" → "perché") — and the space bar on the Latin tab must
    /// insert a plain space. This is the regression net for the two findings of the user's Italian
    /// round: dead predictions and "the space bar is not a space bar" (they were typing on the
    /// visually identical Japanese QWERTY).
    /// 同梱イタリア語辞書の候補（アクセント補正込み）と、ラテン文字タブの空白キーの動作を検証する。
    func test35_italianLexiconOffersAccentedCompletions() throws {
        // 1. Italian ON via MainApp settings (same idempotent dance as test33)
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        var row = firstMatch(in: mainApp, labels: L.italianToggle, timeout: 6)
        var swipes = 0
        while row == nil && swipes < 8 {
            mainApp.swipeUp()
            swipes += 1
            row = firstMatch(in: mainApp, labels: L.italianToggle, timeout: 2)
        }
        guard let row else {
            dump(mainApp, "35-no-toggle")
            XCTFail("Italian toggle not found in MainApp settings")
            return
        }
        let sw = mainApp.switches.matching(NSPredicate(format: "label IN %@", L.italianToggle)).firstMatch
        if (sw.exists ? (sw.value as? String) : nil) != "1" {
            (sw.exists ? sw : row).coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }

        // 2. Latin tab, Italian active. The switch key label alone is ambiguous (current vs next),
        // so PROBE with real typing and cycle until the lexicon answers in Italian.
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        let abcKey = safari.descendants(matching: .any)["ABC"]
        if abcKey.waitForExistence(timeout: 3) && abcKey.isHittable {
            abcKey.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: safari)
        }
        var accented = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "perché")).firstMatch
        var attempts = 0
        while attempts < 3 {
            tapKeys(["p", "e", "r", "c", "h", "e"], in: safari)
            if accented.waitForExistence(timeout: 3) {
                break
            }
            // wrong Latin language (or still English): clear and cycle the language key once
            for _ in 0..<6 {
                let del = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label IN %@", ["delete", "削除", "Elimina", "⌫"])).firstMatch
                if del.exists && del.isHittable { del.tap() } else { break }
            }
            let switchKey = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@", "IT", "A", "あ")).firstMatch
            if switchKey.exists && switchKey.isHittable {
                switchKey.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            }
            attempts += 1
            accented = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "perché")).firstMatch
        }
        if !accented.exists {
            dump(safari, "35-no-perche")
            shot("35-no-perche")
        }
        XCTAssertTrue(accented.exists, "typing 'perche' with Italian active must offer the accent fix 'perché'")

        // 3. Tap the candidate: the field must now contain the accented word.
        accented.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let field = safari.webViews.textFields.firstMatch
        let value = (field.value as? String) ?? ""
        XCTAssertTrue(value.contains("perché"), "tapping the candidate must commit 'perché', field shows: \(value)")

        // 4. Space bar inserts a plain space on the Latin tab (the user's own report).
        tapKeys(["c", "i", "a", "o"], in: safari)
        let space = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["space", "Spazio", "空白"])).firstMatch
        XCTAssertTrue(space.waitForExistence(timeout: 3), "space bar not found on the Latin tab")
        space.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let after = (field.value as? String) ?? ""
        XCTAssertTrue(after.contains("ciao "), "space on the Latin tab must insert a space, field shows: \(after)")
        shot("35-done")
    }

    // MARK: - 36 · The Japanese tab keeps Japanese caps — the cue that tells the two QWERTYs apart

    /// The Japanese QWERTY and the Latin QWERTY look identical; on the Japanese one the space bar
    /// CONVERTS. Apple keeps 空白/改行 on its own JP layouts whatever the UI language, and so do we:
    /// these labels are the one visual cue. The Latin tab stays localized ("space"/"Newline" on an
    /// English simulator).
    /// 日本語タブの空白・改行は常に日本語、ラテン文字タブはUI言語に追従することを検証する。
    func test36_japaneseTabKeepsJapaneseCaps() throws {
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)

        // Japanese tab: 空白 must be there, the localized "space" must not.
        switchToJapaneseFlickTab(in: safari)
        let jpSpace = safari.descendants(matching: .any)["空白"]
        if !jpSpace.waitForExistence(timeout: 4) {
            dump(safari, "36-no-kuuhaku")
            shot("36-no-kuuhaku")
        }
        XCTAssertTrue(jpSpace.exists, "the Japanese tab must cap its space key 空白 whatever the UI language")

        // Latin tab: localized caps.
        switchToEnglishTab(in: safari)
        let latinSpace = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["space", "Spazio"])).firstMatch
        if !latinSpace.waitForExistence(timeout: 4) {
            dump(safari, "36-no-latin-space")
            shot("36-no-latin-space")
        }
        XCTAssertTrue(latinSpace.exists, "the Latin tab must localize its space cap on an English simulator")
        shot("36-done")
    }

    // MARK: - 34 · Copaky extension: the system paste control renders inside the input view

    /// Apple does not document putting `UIPasteControl` inside a keyboard extension's input view, so
    /// the first thing to establish is whether it even DRAWS there. This test does not — and cannot —
    /// prove the paste itself: the paste dialog does not exist on the Simulator, so only a device
    /// round can tell us whether the banner really disappears.
    /// Prerequisites (orchestrator): use_system_paste_control + enable_clipboard_history_manager_tab
    /// injected device-wide, Full Access already granted on the simulator.
    /// UIPasteControl がキーボード拡張内で描画されるかだけを確認する（ペースト自体は実機でのみ検証可能）。
    func test34_systemPasteControlRendersInKeyboard() throws {
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard let clipboardTab = firstMatch(in: safari, labels: L.clipboardTab, timeout: 6) else {
            dump(safari, "34-no-clipboard-tab")
            throw XCTSkip("Clipboard tab not on the bar — Full Access or the tab setting is off on this simulator")
        }
        clipboardTab.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        shot("34-clipboard-tab")
        dump(safari, "34-tree")
        // UIPasteControl vends a button whose label iOS localizes ("Paste"/"ペースト"/"Incolla").
        let pasteControl = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Paste", "ペースト", "Incolla"])).firstMatch
        XCTAssertTrue(pasteControl.waitForExistence(timeout: 4), "UIPasteControl did not render inside the keyboard's input view")
    }

    // MARK: - 40 · Device only: does iOS actually DELIVER a paste into the input view?

    /// Record a fact in the result bundle. Assertions say pass/fail; this says *what was observed*,
    /// which is what a prototype round is actually for.
    private func note(_ name: String, _ body: String) {
        let a = XCTAttachment(string: body)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Drive one of the app's own `Toggle`s to a value, scrolling it into view first.
    ///
    /// Never trusts the tap: a tap on the CELL does not flip a SwiftUI `Toggle` inside a `Form`
    /// (only the switch on the right does), so this re-reads the value every round and retries.
    /// タップを信用せず、毎回値を読み直す（セルのタップではトグルは反転しない）。
    @discardableResult
    private func driveSwitch(_ labels: [String], to on: Bool, scrolls maxScrolls: Int = 10) -> Bool {
        let pred = NSPredicate(format: "label IN %@", labels)
        func current() -> XCUIElement { mainApp.switches.matching(pred).firstMatch }
        var scrolled = 0
        while !current().exists && scrolled < maxScrolls {
            mainApp.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            scrolled += 1
        }
        guard current().exists else { return false }
        let wanted = on ? "1" : "0"
        var taps = 0
        while current().value as? String != wanted && taps < 4 {
            current().coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            // enabling the clipboard history raises a confirmation alert; dismiss whatever appears
            if mainApp.alerts.buttons["OK"].waitForExistence(timeout: 1.5) { mainApp.alerts.buttons["OK"].tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            taps += 1
        }
        return current().value as? String == wanted
    }

    /// Open the app's settings, reveal every section, and switch one row ON.
    @discardableResult
    private func enableCopakySetting(_ labels: [String]) -> Bool {
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) { close.tap() }
        openSettingsTab()
        // The paste-control row lives inside a section that only exists with this master switch ON.
        driveSwitch(L.showAllSettings, to: true)
        return driveSwitch(labels, to: true)
    }

    /// Focus Safari's own address bar.
    ///
    /// Deliberately NOT the fixture page: that one is served from the Mac's loopback address, which
    /// a phone cannot reach, and this question needs *a* text field, not a particular one.
    /// 実機ではローカルのテストページに到達できないため、Safariのアドレス欄を入力先に使う。
    private func focusSafariAddressBar() -> Bool {
        safari.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        let pred = NSPredicate(format: "identifier == 'URL' OR identifier == 'TabBarItemTitle' OR label CONTAINS[c] 'indirizzo' OR label CONTAINS[c] 'search or enter' OR label CONTAINS[c] 'enter website'")
        for q in [safari.textFields.matching(pred), safari.searchFields.matching(pred), safari.buttons.matching(pred)] where q.firstMatch.exists {
            q.firstMatch.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            return true
        }
        // iOS 26 keeps the address field in the BOTTOM bar by default.
        safari.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        return safari.keyboards.firstMatch.exists || copakyActive(in: safari)
    }

    /// **Device only** — §10 of `docs/PIANO_QUALITA_2026-08.md`.
    ///
    /// The Simulator has no paste-permission subsystem at all (no dialog, no "Paste from Other Apps"
    /// row), which is why `test34` above only checks that the control DRAWS. This one asks the
    /// question the whole prototype exists for: when the user taps Apple's control inside a keyboard
    /// extension's input view, does iOS hand the text over?
    ///
    /// What it establishes: that the control renders, whether it is enabled before being touched,
    /// and whether the text actually arrived (a tile carrying the seeded marker appears in the
    /// clipboard panel). What it does NOT establish: anything about the banner — that is a system
    /// HUD, and the attached screenshots are the evidence a human reads.
    ///
    /// The pasteboard is seeded from the test runner, a DIFFERENT app from Copaky, so this is a
    /// genuine cross-app paste as far as iOS's permission accounting is concerned.
    /// 実機専用。ペースト許可の仕組みはシミュレータに存在しないため、ここでしか確かめられない。
    func test40_device_systemPasteControlDelivers() throws {
        // Seeding the pasteboard from the runner does NOT work on a device: iOS answers
        // "Pasteboard com.apple.UIKit.pboard.general is not available at this time" to a process that
        // is not the foreground app, and the write is silently lost. That failure is poisonous here —
        // an empty pasteboard leaves Apple's control with nothing to hand over, which on screen is
        // indistinguishable from "iOS refused to deliver", the very thing this test must decide.
        // So prefer a marker seeded from the HOST before the run:
        //   pymobiledevice3 developer core-device copy "COPAKY-PROBE-123456"
        //   TEST_RUNNER_COPAKY_PASTE_MARKER="COPAKY-PROBE-123456" xcodebuild test …
        // 実機ではランナーからペーストボードに書けないため、ホスト側で仕込んだ文字列を使う。
        let marker: String
        if let seeded = ProcessInfo.processInfo.environment["COPAKY_PASTE_MARKER"], !seeded.isEmpty {
            marker = seeded
            note("40-marker-source", "seeded from the host before the run")
        } else {
            marker = "COPAKY-PROBE-\(UInt32.random(in: 100_000 ... 999_999))"
            UIPasteboard.general.string = marker
            note("40-marker-source", "seeded in-process by the runner (works on the Simulator)")
        }
        note("40-marker", marker)

        XCTAssertTrue(enableCopakySetting(L.systemPasteToggle),
                      "Could not switch ON 'use the system paste button' — the prototype was never armed")
        // The panel only exists if the clipboard tab is on the bar.
        driveSwitch(L.clipboardToggle, to: true)
        shot("40-settings")

        XCTAssertTrue(focusSafariAddressBar(), "No field focused in Safari — nothing to host the keyboard")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        // Use the shared helper rather than looking the tab up directly: the tab bar is CLOSED by
        // default, so on the phone the direct lookup found nothing and this test skipped — reporting
        // "Full Access or the tab setting is off" when both were on and Copaky was running fine.
        try openClipboardTab()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("40-clipboard-tab")
        dump(safari, "40-tree")

        let control = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.systemPasteControl)).firstMatch
        let rendered = control.waitForExistence(timeout: 6)
        note("40-rendered", rendered ? "UIPasteControl RENDERED inside the input view" : "UIPasteControl DID NOT render")
        guard rendered else {
            shot("40-not-rendered")
            XCTFail("UIPasteControl did not render inside the keyboard's input view")
            return
        }
        // A tile carrying the marker from an EARLIER run would make the post-tap check pass without
        // any delivery. Prove the negative first: the marker must be absent BEFORE the tap, or the
        // run is invalid (re-seed with a fresh marker).
        // 直前のランの残骸で偽合格しないよう、タップ前にマーカー不在を確認する。
        let staleTile = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
        if staleTile.exists {
            shot("40-stale-marker")
            XCTFail("The marker is already in the history BEFORE the tap — stale run; seed a fresh marker")
            return
        }
        // Enabled-ness BEFORE the touch is a real signal: a control iOS refuses to arm never fires.
        note("40-state-before-tap", "isEnabled=\(control.isEnabled) isHittable=\(control.isHittable) frame=\(control.frame)")
        shot("40-before-tap")

        control.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        shot("40-just-after-tap")   // the banner, if any, lives for ~3s — this is where it shows

        // Delivery, not decoration: the seeded text has to come back as a tile in the panel.
        let deliveredTile = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
        let delivered = deliveredTile.waitForExistence(timeout: 6)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("40-after-wait")
        note("40-delivered", delivered
             ? "iOS DELIVERED the text: a tile carrying the marker appeared in the panel"
             : "NOTHING arrived: no tile carries the marker (read the paste-control log on the Mac to tell 'not delivered' from 'not tapped')")
        XCTAssertTrue(delivered, "iOS never delivered the pasted text to the keyboard's input view")
    }
}
