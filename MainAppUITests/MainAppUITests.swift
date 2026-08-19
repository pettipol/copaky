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
    // Copaky: the auto-accent toggle is localized in every shipped UI language.
    // Copaky: アクセント自動補正の設定名を全対応言語で検索する。
    static let italianAutoAccentToggle = ["Auto-accent on space (Italian)", "スペースでアクセントを自動補正（イタリア語）", "Accento automatico con lo spazio (italiano)"]
    /// Enter key in its plain "return" state — localized since the key-label fix (Design.getEnterKeyText).
    static let enterKeyReturn = ["改行", "Newline", "A capo"]
    /// Space key on the simple/flick keyboards — localized since the key-label fix.
    /// Lowercase variants included: the catalog ships them lowercase ("space"/"spazio", seen on
    /// the phone 2026-08-14) and XCUI label matching is case-sensitive.
    static let spaceKey = ["空白", "Space", "space", "Spazio", "spazio"]
    /// Back key of the clipboard and emoji tabs — localized since the key-label fix.
    static let backKey = ["戻る", "Back", "Indietro"]
    /// Master switch that reveals every settings section (the paste-control row lives behind it).
    static let showAllSettings = ["Show all settings", "すべての設定を表示", "Mostra tutte le impostazioni"]
    /// Experimental setting that swaps our capture button for Apple's `UIPasteControl`.
    static let systemPasteToggle = ["Use the system paste button", "システムのペーストボタンを使う", "Usa il pulsante Incolla di sistema"]
    /// `UIPasteControl` vends a button whose label iOS localizes for us.
    static let systemPasteControl = ["Paste", "ペースト", "Incolla"]
    /// iOS Settings root row that leads to the installed-apps list (bottom of the root list).
    static let settingsAppsRow = ["App", "Apps", "アプリ"]
    /// Per-app Settings row governing cross-app paste (the row the §10 protocol pivots on).
    /// Upstream writes ほかのApp, the shipped OS row says 他のApp — carry both.
    static let pasteFromOtherAppsRow = ["Incolla da altre app", "Paste from Other Apps", "他のAppからペースト", "ほかのAppからペースト", "ほかのアプリからペースト", "他のアプリからペースト"]   // iOS 18+ ja says アプリ, not App
    static let pasteFromOtherAppsRowParts = ["Incolla da altre", "Paste from Other", "からペースト"]   // CONTAINS fallback
    /// The three states of that row; the protocol needs ASK.
    static let pasteAsk = ["Chiedi", "Ask", "確認"]
    static let pasteDeny = ["Nega", "Deny", "拒否"]
    /// Buttons that let a system paste prompt proceed, across OS languages and phrasings.
    static let allowPasteButtons = ["Consenti di incollare", "Allow Paste", "ペーストを許可", "Consenti", "Allow", "許可", "Incolla", "Paste", "ペースト"]
    /// Tips tab (TabItem "使い方") — the app's default landing screen.
    static let tipsTab = ["使い方", "Usage", "Come si usa"]
    /// Themes tab (TabItem "着せ替え") — same set already proven in CopakyScreenshotTests.swift.
    static let themesTab = ["着せ替え", "Themes", "Temi"]
    /// NavigationLink into `OpenSourceSoftwaresLicenseView` from the Settings tab (base string is the
    /// English word itself, so it has no separate ja localization — see Resources/Localizable.xcstrings).
    static let ossAcknowledgements = ["Acknowledgements", "Ringraziamenti"]
    /// NavigationLink into `ContactView` from the Settings tab.
    static let contactLink = ["お問い合わせ", "Contact", "Contatti"]
    /// iOS Settings root row for the light/dark appearance picker (test44).
    static let displayBrightnessRow = ["Schermo e luminosità", "Display & Brightness", "画面表示と明るさ"]
    /// The two appearance swatches inside that row's top ASPETTO/APPEARANCE section.
    static let appearanceLight = ["Chiaro", "Light", "ライト"]
    static let appearanceDark = ["Scuro", "Dark", "ダーク"]
    /// Settings ▸ General row leading to the language/region picker (test44).
    static let languageAndRegionRow = ["Lingua e zona", "Lingua e Zona", "Lingua e Regione", "Language & Region", "言語と地域"]
    /// Row inside Language & Region whose value shows/sets the system UI language.
    static let iPhoneLanguageRow = ["Lingua iPhone", "Lingua dell'iPhone", "iPhone Language", "iPhoneの使用言語"]
    /// Confirmation button on the "change language?" sheet — label is a PREFIX/substring, not a
    /// fixed string (the target language name is interpolated into it), hence CONTAINS matching.
    static let changeToPrefixes = ["Cambia in", "Change to", "に変更", "Continua", "Continue", "続ける"]   // iOS 26: sheet «…iPhone verrà riavviato» → Continua
    /// Buttons that decline a system paste prompt (test45 asset capture).
    static let dontAllowButton = ["Non consentire", "Don't Allow", "許可しない"]
}

@MainActor
final class CopakyCampaignTests: XCTestCase {

    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    let mainApp = XCUIApplication(bundleIdentifier: "com.pettipol.copaky")
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    /// System paste prompts are HUD-level: on a device they can attach to SpringBoard rather than
    /// to the host app, so banner checks must look in both places.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// True when the suite is running on a real phone rather than the Simulator.
    ///
    /// The distinction matters for seeding: on the Simulator the runner CAN write the pasteboard
    /// in-process, on a device it cannot (iOS refuses the write to a non-foreground process), so
    /// device runs must fail closed when the page-driven seeding did not happen.
    /// 実機ではランナーからペーストボードに書けないため、シードの前提を厳格に扱う。
    private var isDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
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

    /// First existing element whose label CONTAINS (case-insensitive) any of `substrings`.
    ///
    /// Unlike `firstMatch` (exact label/identifier/title match), this is for rows whose accessibility
    /// label is COMPOSITE (e.g. Settings list cells that combine a title with a value, or a
    /// confirmation button whose label interpolates the target name) — used by test44/test45.
    /// ラベルが複合的な行（値を含むセルや、対象名を埋め込んだ確認ボタン）向けの部分一致版。
    private func firstMatchContains(in app: XCUIApplication, substrings: [String], timeout: TimeInterval = 6) -> XCUIElement? {
        let pred = NSCompoundPredicate(orPredicateWithSubpredicates:
            substrings.map { NSPredicate(format: "label CONTAINS[c] %@", $0) })
        let queries: [XCUIElementQuery] = [
            app.buttons.matching(pred),
            app.cells.matching(pred),
            app.staticTexts.matching(pred),
            app.otherElements.matching(pred),
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

    /// `firstMatchContains`, scrolling the screen down first when nothing is visible yet.
    @discardableResult
    private func tapContainsScrolling(in app: XCUIApplication, substrings: [String], maxSwipes: Int = 8, timeout: TimeInterval = 3) -> Bool {
        var el = firstMatchContains(in: app, substrings: substrings, timeout: timeout)
        var swipes = 0
        while (el == nil || el?.isHittable != true) && swipes < maxSwipes {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            el = firstMatchContains(in: app, substrings: substrings, timeout: timeout)
            swipes += 1
        }
        guard let target = el, target.isHittable else { return false }
        target.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        return true
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
            // firstMatch, never the exact-match subscript: during a tap the magnifier bubble
            // briefly DUPLICATES the key's label, and a multi-match crashes the runner with an
            // unswallowable ObjC exception (paid on the phone 2026-08-14, test35 typing "perche").
            // タップ中は拡大バブルがラベルを複製するため必ずfirstMatch。
            let key = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).firstMatch
            if !key.waitForExistence(timeout: 4) {
                dump(app, "key-not-found-\(label)")
                shot("key-not-found-\(label)")
            }
            XCTAssertTrue(key.exists, "Key '\(label)' not found on Copaky keyboard")
            key.tap()
        }
    }

    // Copaky: tap the actual Latin space key; accepting a next-candidate label here could hide an
    // accidental return to the Japanese conversion tab.
    // Copaky: 日本語の次候補キーを誤認せず、ラテン文字タブの空白キーだけを押す。
    private func tapLatinSpace(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let space = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.spaceKey)).firstMatch
        guard space.waitForExistence(timeout: 4), space.isHittable else {
            dump(app, "latin-space-not-found")
            shot("latin-space-not-found")
            XCTFail("Latin space key not found", file: file, line: line)
            return
        }
        space.tap()
    }

    // Copaky: stateful campaign tests reuse the same Safari field, so exact-value assertions must
    // clear committed text through Copaky before typing their own fixture.
    // Copaky: 連続テストで同じ入力欄を使うため、検証前にCopakyの削除キーで内容を空にする。
    private func clearFocusedField(_ field: XCUIElement, placeholder: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let currentValue = (field.value as? String) ?? ""
        guard !currentValue.isEmpty, currentValue != placeholder else {
            return
        }
        for _ in currentValue {
            let delete = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", ["delete", "削除", "Elimina", "⌫"])).firstMatch
            guard delete.waitForExistence(timeout: 3), delete.isHittable else {
                dump(app, "clear-field-delete-not-found")
                shot("clear-field-delete-not-found")
                XCTFail("Delete key not found while clearing the fixture field", file: file, line: line)
                return
            }
            delete.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let clearedValue = (field.value as? String) ?? ""
        XCTAssertTrue(clearedValue.isEmpty || clearedValue == placeholder, "Fixture field did not clear: \(clearedValue)", file: file, line: line)
    }

    /// Non-asserting variant of `tapKeys` for LOAD exercises (test42): taps what it finds, records
    /// what it does not, and reports how many keys were actually pressed instead of failing.
    /// 負荷試験向けの非アサート版: 見つかったキーだけを押し、押せた数を返す。
    @discardableResult
    private func softTapKeys(_ labels: [String], in app: XCUIApplication, timeout: TimeInterval = 2) -> Int {
        var pressed = 0
        for label in labels {
            let key = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).firstMatch
            if key.waitForExistence(timeout: timeout), key.isHittable {
                key.tap()
                pressed += 1
            } else {
                note("soft-key-missing", label)
            }
        }
        return pressed
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
        // Reach the LATIN tab from EITHER JP layout with the proven helper: the bare "ABC" key
        // only exists on the flick tab, so a phone left on the QWERTY JP tab typed straight into
        // the IME (field read ペrチェ…, paid 2026-08-14 — the JP tab converts romaji, it does not
        // fail loudly). Then one more cycle reaches Italian (order JP→EN→IT): the switch key
        // exposes the NEXT language as its own "IT" sub-element (the anchor test33 verifies).
        switchToEnglishTab(in: safari)
        dismissCopakyNotice(in: safari)
        let itNext = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "IT")).firstMatch
        if itNext.waitForExistence(timeout: 4), itNext.isHittable {
            itNext.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
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
            // Exact labels only: CONTAINS 'A' matched half the page and the first hit was
            // rarely the switch key (paid 2026-08-14 on the phone).
            let switchKey = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", ["IT", "A", "あ"])).firstMatch
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
        // While COMPOSING with candidates on screen the same physical key relabels itself to the
        // next-candidate caption («successivo»/次候補 — seen on the phone 2026-08-14), so the
        // lookup must accept both states. What the user presses is the physical key; whether it
        // INSERTS A SPACE is decided by the content assert below, not by the label.
        tapKeys(["c", "i", "a", "o"], in: safari)
        let spaceLabels = L.spaceKey + ["successivo", "次候補", "next candidate", "Next candidate"]
        let space = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", spaceLabels)).firstMatch
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

    // MARK: - 37 · Italian auto-accent on space

    /// With both Italian and auto-accent enabled, space fixes a missing accent while preserving
    /// legitimate plain words. / イタリア語の空白確定で必要なアクセントだけを補正する。
    func test37_italianAutoAccentOnSpace() throws {
        // 1. Enable both settings idempotently in the containing app.
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        XCTAssertTrue(driveSwitch(L.italianToggle, to: true), "Italian toggle did not turn ON")
        XCTAssertTrue(driveSwitch(L.italianAutoAccentToggle, to: true), "Italian auto-accent toggle did not turn ON")

        // 2. Open the fixture field and reach the Italian variant of the shared Latin tab.
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        switchToEnglishTab(in: safari)
        clearFocusedField(field, placeholder: "plain-text", in: safari)

        // The key exposes both current and next language, so prove IT with a real candidate instead
        // of blindly tapping an "IT" child that may already denote the current language.
        var accented = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "perché")).firstMatch
        for _ in 0..<2 {
            tapKeys(["p", "e", "r", "c", "h", "e"], in: safari)
            if accented.waitForExistence(timeout: 4) {
                break
            }
            clearFocusedField(field, placeholder: "plain-text", in: safari)
            let switchKey = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "IT")).firstMatch
            guard switchKey.waitForExistence(timeout: 3), switchKey.isHittable else {
                dump(safari, "37-language-switch-not-found")
                XCTFail("Could not reach the Italian Latin tab")
                return
            }
            switchKey.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            accented = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", "perché")).firstMatch
        }
        XCTAssertTrue(accented.exists, "typing 'perche' must prove that the Italian lexicon is active")

        // 3. The missing accent is fixed as the word is committed by a literal space.
        tapLatinSpace(in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(field.value as? String, "perché ", "space must auto-accent 'perche'")

        // 4. A more frequent legitimate plain form must remain untouched.
        tapKeys(["s", "i"], in: safari)
        tapLatinSpace(in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(field.value as? String, "perché si ", "space must not change legitimate plain 'si'")
        shot("37-done")
    }

    // MARK: - 38 · Latin number tab keeps Latin punctuation and return target

    /// Copaky: the QWERTY number tab must type a literal dot and return to its originating Latin tab.
    /// Copaky: QWERTY数字タブは半角ピリオドを入力し、元のラテン文字タブへ戻る。
    func test38_latinNumbersTabReturnsToLatin() throws {
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)

        let latinSpaceLabels = L.spaceKey.filter { $0 != "空白" }
        func latinQwertyVisible(timeout: TimeInterval) -> Bool {
            let letter = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch
            let space = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", latinSpaceLabels)).firstMatch
            return letter.waitForExistence(timeout: timeout) && space.exists
        }

        switchToEnglishTab(in: safari)
        if !latinQwertyVisible(timeout: 2) {
            // Copaky: A persisted language-less tab may expose only its full back label beside Globe.
            // Copaky: 保持された言語なしタブではGlobe横の完全な戻り先表示を使う。
            if let back = firstMatch(in: safari, labels: ["ABC", "ITA", "あいう"], timeout: 2), back.isHittable {
                back.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            }
        }
        if !latinQwertyVisible(timeout: 2) {
            // Copaky: Returning to Japanese first requires one normal language-switch tap afterward.
            // Copaky: いったん日本語へ戻った場合は通常の言語切替をもう一度行う。
            switchToEnglishTab(in: safari)
        }
        guard latinQwertyVisible(timeout: 4) else {
            dump(safari, "38-no-initial-latin-qwerty")
            shot("38-no-initial-latin-qwerty")
            XCTFail("Latin QWERTY not reached; seed keyboard_type_en=roman")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)

        // Copaky: SwiftUI may expose this SF Symbol by spoken label or symbol identifier.
        // Copaky: SF Symbolは読み上げ名または識別子で公開される場合がある。
        let numberKeyLabels = ["123", "numbers", "Numbers", "numeri", "Numeri", "数字", "textformat.123", "textformat.numbers"]
        guard let numbersKey = firstMatch(in: safari, labels: numberKeyLabels, timeout: 4) else {
            dump(safari, "38-numbers-key-not-found")
            shot("38-numbers-key-not-found")
            XCTFail("Latin QWERTY numbers key not found")
            return
        }
        numbersKey.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        tapKeys(["."], in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        // Copaky: Select the left language key; the second bottom key may also read ABC.
        // Copaky: 2番目のキーもABCになり得るため、左端の言語キーを選ぶ。
        let returnCandidates = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["ABC", "ITA", "あいう"]))
        var backKey: XCUIElement?
        var leftmostX = CGFloat.greatestFiniteMagnitude
        for index in 0..<returnCandidates.count {
            let candidate = returnCandidates.element(boundBy: index)
            if candidate.exists, candidate.isHittable, candidate.frame.minX < leftmostX {
                backKey = candidate
                leftmostX = candidate.frame.minX
            }
        }
        guard let backKey else {
            dump(safari, "38-latin-back-key-not-found")
            shot("38-latin-back-key-not-found")
            XCTFail("Numbers-tab language/back key not found")
            return
        }
        backKey.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        let value = field.value as? String ?? ""
        let returnedToLatin = latinQwertyVisible(timeout: 4)
        if !returnedToLatin {
            dump(safari, "38-did-not-return-to-latin")
        }
        shot("38-latin-return")
        XCTAssertEqual(value, ".", "Latin numbers tab must input a literal ASCII dot")
        XCTAssertFalse(value.contains("。") || value.contains("．"), "No Japanese/full-width dot may be input")
        XCTAssertTrue(returnedToLatin, "Numbers-tab back key returned to Japanese or stayed on numbers")
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
        var marker: String
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

        // SELF-SEEDING (device): every host-side seeding route failed us at least once — the
        // runner cannot write the pasteboard on a device, pymobiledevice3's tunnel needs sudo, and
        // a human with 60 seconds is not an API. So the qa page carries a "Copy test marker"
        // button: one in-page tap (user-gesture path) puts a FRESH unique marker on the pasteboard
        // and shows its value for us to read back. Orchestrator pre-navigates Safari with:
        //   xcrun devicectl device process launch --device <id> \
        //     --payload-url https://copaky.app/qa com.apple.mobilesafari
        // Falls back to the env/in-process marker + address bar when the page is not open.
        // 実機はqaページのボタンで自己シード（ホストからの書き込みは全滅したため）。
        // FAIL CLOSED on a device (Codex review 2026-08-14): if the page, the button, the echo or
        // the field are missing, the runner-generated marker is NOT on the phone's pasteboard —
        // Apple's control would then have nothing to hand over, and the run would report
        // "iOS did not deliver" for what is really a broken setup. An unmet prerequisite must
        // SKIP, never masquerade as a product verdict.
        // 前提が整わない場合はスキップ（配信失敗と誤報しないため）。
        safari.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        let seededFromHost = !(ProcessInfo.processInfo.environment["COPAKY_PASTE_MARKER"] ?? "").isEmpty
        let copyButton = safari.webViews.buttons["Copy test marker"].firstMatch
        if copyButton.waitForExistence(timeout: 5), copyButton.isHittable {
            copyButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            let shown = safari.webViews.staticTexts
                .matching(NSPredicate(format: "label BEGINSWITH %@", "COPAKY-PROBE-")).firstMatch
            if shown.waitForExistence(timeout: 3) {
                marker = shown.label
                note("40-marker-source", "self-seeded by the qa page button")
                note("40-marker", marker)
            } else if isDevice && !seededFromHost {
                dump(safari, "40-no-marker-echo")
                throw XCTSkip("The qa page did not echo a marker: the pasteboard was never seeded, so a paste result would mean nothing")
            }
            // Host the keyboard on the page's plain field — steadier than the address bar.
            let plain = safari.webViews.textFields.firstMatch
            if plain.exists, plain.isHittable {
                plain.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(1.2))
            } else if isDevice {
                dump(safari, "40-no-plain-field")
                throw XCTSkip("No field to host the keyboard on the qa page")
            }
        } else if isDevice && !seededFromHost {
            dump(safari, "40-no-copy-button")
            throw XCTSkip("qa page not open in Safari (pre-navigate with devicectl --payload-url https://copaky.app/qa) and no COPAKY_PASTE_MARKER seeded from the host — prerequisite unmet, not a delivery failure")
        } else {
            XCTAssertTrue(focusSafariAddressBar(), "No field focused in Safari — nothing to host the keyboard")
        }
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
        // run is invalid (re-seed with a fresh marker). Scoped to the keyboard area: the qa page
        // ECHOES the marker in the web content, and an unscoped query matches that echo (paid
        // 2026-08-14: the guard killed a valid run by reading the page, not the panel).
        // 直前のランの残骸で偽合格しないよう、タップ前にマーカー不在を確認する。
        let panelTop = control.frame.minY - 24
        if markerTile(marker, in: safari, notAbove: panelTop) != nil {
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

        // Delivery, not decoration: the seeded text has to come back as a tile IN THE PANEL
        // (keyboard-area scoped — the page's own echo of the marker must not count).
        let delivered = waitForMarkerTile(marker, in: safari, notAbove: panelTop, timeout: 6)
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("40-after-wait")
        note("40-delivered", delivered
             ? "iOS DELIVERED the text: a tile carrying the marker appeared in the panel"
             : "NOTHING arrived: no tile carries the marker (read the paste-control log on the Mac to tell 'not delivered' from 'not tapped')")
        XCTAssertTrue(delivered, "iOS never delivered the pasted text to the keyboard's input view")
    }

    // MARK: - 41 · Device only: §10 banner protocol (baseline → capsule → negative control)

    /// Set iOS Settings ▸ Apps ▸ Copaky ▸ "Paste from Other Apps" to one of its three states.
    /// Navigates by scrolling, never by typing: the search field would engage whatever keyboard is
    /// active system-wide (possibly Copaky itself), which is the object under test.
    /// 検索欄は使わない（被験対象のキーボードが出てしまう）。スクロールだけで辿る。
    private func setPasteFromOtherApps(to value: [String]) throws {
        settings.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        settingsGoRoot()
        guard tapFirst(in: settings, labels: L.settingsAppsRow, timeout: 4, scrollUpTo: 12) else { return }
        // The apps list is alphabetical; Copaky sits under C, a few swipes at most.
        // The CELLS carry no label (paid 2026-08-14: a cells-query matched nothing and the loop
        // swiped past the whole alphabet) — the label and the bundle-id identifier live on the
        // inner BUTTON, so query buttons, anchored on the bundle id.
        let copaky = settings.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "com.pettipol.copaky", "Copaky")).firstMatch
        var swipes = 0
        while !copaky.exists && swipes < 20 {
            settings.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            swipes += 1
        }
        guard copaky.waitForExistence(timeout: 3) else {
            dump(settings, "41-no-copaky-in-apps")
            XCTFail("Copaky not found in the Settings apps list")
            return
        }
        copaky.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        if !tapFirst(in: settings, labels: L.pasteFromOtherAppsRow, timeout: 5, scrollUpTo: 8) {
            guard tapContainsScrolling(in: settings, substrings: L.pasteFromOtherAppsRowParts, maxSwipes: 8, timeout: 4) else {
                dump(settings, "41-no-paste-row")
                XCTFail("'Paste from Other Apps' row not found on Copaky's settings page")
                return
            }
        }
        guard tapFirst(in: settings, labels: value, timeout: 5) else { return }
        shot("41-permission-row-set")
    }

    /// A history TILE carrying `marker`, distinguished from the qa page's own echo of it.
    ///
    /// Self-seeding displays the marker's value in the WEB CONTENT, so a bare
    /// `descendants… CONTAINS marker` matches the page and not the panel — the stale guard then
    /// kills valid runs and, worse, the delivery check could false-PASS without any delivery.
    /// Only a match INSIDE the keyboard area counts: at or below `floorY` when the caller knows
    /// where the panel starts (capsule/capture-bar top), else the bottom 55% of the screen.
    /// qaページはマーカー値を画面に表示するため、キーボード領域内の一致だけをタイルと数える。
    private func markerTile(_ marker: String, in app: XCUIApplication, notAbove floorY: CGFloat? = nil) -> XCUIElement? {
        let cutoff = floorY ?? (app.frame.height * 0.45)
        let q = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", marker))
        for i in 0..<min(q.count, 8) {
            let el = q.element(boundBy: i)
            if el.exists, el.frame.minY >= cutoff { return el }
        }
        return nil
    }

    /// Poll `markerTile` for up to `timeout` seconds (per-index queries have no waitForExistence).
    private func waitForMarkerTile(_ marker: String, in app: XCUIApplication, notAbove floorY: CGFloat? = nil,
                                   timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if markerTile(marker, in: app, notAbove: floorY) != nil { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        } while Date() < deadline
        return false
    }

    /// The system paste prompt, wherever iOS hangs it (host app or SpringBoard).
    private func pastePrompt(timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in [safari.alerts.firstMatch, springboard.alerts.firstMatch] where candidate.exists {
                return candidate
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        return nil
    }

    /// Tap the qa page's "Copy test marker" button (fresh unique value each tap), read the value
    /// back from the page, and park the caret in the page's plain field. Requires Safari to be
    /// PRE-NAVIGATED to https://copaky.app/qa by the orchestrator (devicectl --payload-url).
    private func seedMarkerFromQaPage(evidence prefix: String) throws -> String {
        safari.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        let copyButton = safari.webViews.buttons["Copy test marker"].firstMatch
        guard copyButton.waitForExistence(timeout: 6), copyButton.isHittable else {
            dump(safari, "\(prefix)-no-copy-button")
            throw XCTSkip("qa page not open in Safari — pre-navigate with devicectl --payload-url https://copaky.app/qa")
        }
        copyButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let shown = safari.webViews.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "COPAKY-PROBE-")).firstMatch
        guard shown.waitForExistence(timeout: 4) else {
            dump(safari, "\(prefix)-no-marker-label")
            throw XCTSkip("qa page did not echo the marker value back")
        }
        let marker = shown.label
        note("\(prefix)-marker", marker)
        let plain = safari.webViews.textFields.firstMatch
        if plain.exists, plain.isHittable {
            plain.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        }
        return marker
    }

    /// **Device only** — the OTHER half of §10, the one test40 cannot answer: the banner.
    ///
    /// With "Paste from Other Apps" on ASK, tapping OUR old capture button must raise the system
    /// paste prompt — that arms the probe (a silent run with the permission on Allow proves
    /// nothing, the trap already paid for once). Then Apple's `UIPasteControl` capsule is tapped
    /// under the same ASK regime: whether the prompt appears again is THE observation this test
    /// exists to record — it is noted and screenshotted, not asserted, because either outcome is
    /// decision-relevant. Delivery, however, IS asserted on both paths. Ends with a negative
    /// control: a second capsule tap with no fresh copy must not conjure new content.
    /// バナーの有無は記録すべき観察であり、断定はしない。配信は両経路とも断定する。
    func test41_device_pasteBannerProtocol() throws {
        // 0 — permission → ASK (the §10 precondition that voids every earlier "no banner" claim)
        try setPasteFromOtherApps(to: L.pasteAsk)

        // 1 — baseline arm: clipboard tab ON, capsule OFF (the OLD capture button must be on duty)
        XCTAssertTrue(enableCopakySetting(L.clipboardToggle), "Could not switch the clipboard tab ON")
        driveSwitch(L.systemPasteToggle, to: false)
        shot("41-settings-baseline")

        let marker1 = try seedMarkerFromQaPage(evidence: "41-baseline")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        try openClipboardTab()
        // Tap with retry, re-resolving each round: the お知らせ notice can animate in BETWEEN the
        // lookup and the tap, and a tap on a stale element crashes the runner with an unswallowable
        // ObjC exception (paid 2026-08-14). The panel top is remembered BEFORE tapping — the element
        // may be gone afterwards.
        var baselineFloor = safari.frame.height * 0.45
        var baselineTapped = false
        for _ in 0..<3 {
            dismissCopakyNotice(in: safari)
            if let el = firstMatch(in: safari, labels: L.captureBar, timeout: 4), el.isHittable {
                baselineFloor = el.frame.minY - 24
                el.tap()
                baselineTapped = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        guard baselineTapped else {
            dump(safari, "41-no-capture-bar")
            shot("41-no-capture-bar")
            XCTFail("Old capture bar not found/hittable — baseline cannot be armed")
            return
        }
        let baselinePrompt = pastePrompt(timeout: 5)
        shot("41-baseline-after-tap")   // the prompt, if any, is IN this shot
        note("41-baseline-banner", baselinePrompt != nil
             ? "ARMED: the system paste prompt appeared for the old capture button"
             : "NOT ARMED: no prompt for the old button — permission flip did not take, round is void")
        XCTAssertNotNil(baselinePrompt,
                        "With 'Paste from Other Apps' on ASK the old capture button must raise the system prompt; nothing appeared, so the probe is not armed and no capsule observation would mean anything")
        if let prompt = baselinePrompt {
            let allow = prompt.buttons.matching(NSPredicate(format: "label IN %@", L.allowPasteButtons)).firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        }
        note("41-baseline-delivered", waitForMarkerTile(marker1, in: safari, notAbove: baselineFloor, timeout: 6)
             ? "old path delivered after Allow"
             : "old path did NOT deliver even after Allow")
        shot("41-baseline-delivered")

        // 2 — capsule under ASK: the observation the §10 decision hangs on
        XCTAssertTrue(enableCopakySetting(L.systemPasteToggle),
                      "Could not switch ON 'use the system paste button'")
        let marker2 = try seedMarkerFromQaPage(evidence: "41-capsule")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        try openClipboardTab()
        dismissCopakyNotice(in: safari)
        let control = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.systemPasteControl)).firstMatch
        guard control.waitForExistence(timeout: 6) else {
            shot("41-capsule-not-rendered")
            XCTFail("UIPasteControl did not render — capsule phase impossible")
            return
        }
        let capsuleFloor = control.frame.minY - 24
        if markerTile(marker2, in: safari, notAbove: capsuleFloor) != nil {
            XCTFail("marker already in history BEFORE the capsule tap — stale run")
            return
        }
        note("41-capsule-state-before-tap", "isEnabled=\(control.isEnabled) isHittable=\(control.isHittable)")
        control.tap()
        let capsulePrompt = pastePrompt(timeout: 4)
        shot("41-capsule-after-tap")    // banner lives ~3s; this shot is the evidence
        note("41-capsule-banner", capsulePrompt != nil
             ? "the system prompt APPEARED for UIPasteControl too (capsule does not bypass ASK)"
             : "NO prompt for UIPasteControl (user-intent tap accepted silently under ASK)")
        if let prompt = capsulePrompt {
            let allow = prompt.buttons.matching(NSPredicate(format: "label IN %@", L.allowPasteButtons)).firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        }
        let capsuleDelivered = waitForMarkerTile(marker2, in: safari, notAbove: capsuleFloor, timeout: 6)
        shot("41-capsule-delivered")
        note("41-capsule-delivered", capsuleDelivered
             ? "capsule path delivered: tile with the fresh marker is in the panel"
             : "capsule path did NOT deliver")
        XCTAssertTrue(capsuleDelivered, "The capsule never delivered the fresh marker under ASK")

        // 3 — negative control: no fresh copy → a second tap must not conjure new content.
        // Counts are keyboard-area scoped for the same reason as the tile checks above.
        func probeTileCount() -> Int {
            let q = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "COPAKY-PROBE-"))
            var n = 0
            for i in 0..<min(q.count, 12) {
                let el = q.element(boundBy: i)
                if el.exists, el.frame.minY >= capsuleFloor { n += 1 }
            }
            return n
        }
        let tilesBefore = probeTileCount()
        if control.exists, control.isHittable { control.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        let tilesAfter = probeTileCount()
        shot("41-negative-control")
        note("41-negative-control", "probe tiles before=\(tilesBefore) after=\(tilesAfter) (re-paste of the SAME pasteboard may legally re-deliver; what must not happen is a NEW unknown value)")
        XCTAssertLessThanOrEqual(tilesAfter, tilesBefore + 1, "Negative control: unexpected flood of new tiles after a tap with no fresh copy")
    }

    // MARK: - 42 · Memory protocol phase C: sustained Japanese across many kana, then Italian, then back

    /// Print a memory-protocol phase marker. The actual SAMPLING (physFootprint over time) is a HOST
    /// concern — `scripts/memory_phase_c.sh` watches the keyboard extension process from outside this
    /// test — so all this needs to produce is timestamped, greppable markers the host can align its
    /// samples against.
    ///
    /// One phase gets TWO markers — `start` before its load and `end` after — instead of one printed
    /// after the fact: a single post-load marker made the host script attribute samples to the WRONG
    /// phase (it had no choice but to treat "marker seen" as "phase begins here"). `at:` lets a caller
    /// back-date the `start` edge to before an outcome (e.g. clipboard open vs. skipped) was known,
    /// so the bracket still covers the real load window even though the phase NAME is resolved late.
    /// 1フェーズにつきマーカーを2個（開始・終了）出す。事後の1個だけでは負荷区間の帰属がずれてしまう。
    private func memcMarker(_ phase: String, _ edge: String, at date: Date = Date()) {
        print("MEMC|\(phase)|\(edge)|\(ISO8601DateFormatter().string(from: date))")
    }

    /// Clear whatever the last kana group produced (composing buffer, or — once a candidate has been
    /// cycled onto the space key and tapped — plain committed text) before the next group starts.
    /// Repeated DELETE, not a candidate pick: telling "genuine kanji/kana candidate" apart from "kana
    /// row-head key relabelled" by label alone is not reliable enough for an unattended load pass
    /// (playbook §4.2/§5), so this sweep does not try — it only needs the field empty for the next group.
    /// 次のグループの前に入力内容を消す。候補選択ではなく削除キー連打（ラベルだけでは候補と鍵の区別が
    /// 信頼できないため）。
    /// Reach the Japanese tab and report its layout: `true` = flick (kana keys on screen), `false` =
    /// QWERTY/romaji (letter keys under Japanese labels such as 「空白」). Falls back to the strict
    /// flick helper (which fails with evidence) only when neither layout can be reached.
    /// 日本語タブへ移動し、レイアウトを返す（true=フリック、false=QWERTY/ローマ字）。
    private func ensureJapaneseTab(in app: XCUIApplication) -> Bool {
        dismissCopakyNotice(in: app)
        if flickKanaVisible(in: app, timeout: 2) { return true }
        if japaneseQwertyVisible(in: app) { return false }
        // Not on a Japanese tab: the language key shows 「あ」 when Japanese is the NEXT language.
        let toJapanese = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "あ")).firstMatch
        if toJapanese.waitForExistence(timeout: 2), toJapanese.isHittable {
            toJapanese.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: app)
            if flickKanaVisible(in: app, timeout: 2) { return true }
            if japaneseQwertyVisible(in: app) { return false }
        }
        switchToJapaneseFlickTab(in: app)   // strict path: dumps + fails with evidence
        return true
    }

    /// QWERTY Japanese tab = a Latin letter key AND a Japanese function label on the same keyboard
    /// (the Japanese tab keeps 「空白」/「改行」 by design; the Latin tab shows space/spazio).
    private func japaneseQwertyVisible(in app: XCUIApplication) -> Bool {
        let k = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "k")).firstMatch
        let jpLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["空白", "変換", "確定", "改行"])).firstMatch
        return k.waitForExistence(timeout: 2) && jpLabel.exists
    }

    /// Type one kana group either as flick keys or as romaji on the QWERTY Japanese tab. Returns how
    /// many keys were pressed (for `clearTyped`). Soft: a missing key is noted, not asserted.
    /// かなグループをフリックまたはローマ字で入力し、押したキー数を返す。
    private func typeKanaGroup(_ group: [String], flick: Bool, in app: XCUIApplication) -> Int {
        if flick {
            return softTapKeys(group, in: app)
        }
        let romaji: [String: String] = ["あ": "a", "か": "ka", "さ": "sa", "た": "ta", "な": "na",
                                        "は": "ha", "ま": "ma", "や": "ya", "ら": "ra", "わ": "wa"]
        let letters = group.flatMap { (romaji[$0] ?? "").map { String($0) } }
        return softTapKeys(letters, in: app)
    }

    private func clearTyped(atLeast charCount: Int, in app: XCUIApplication) {
        let delLabels = ["delete", "削除", "Elimina", "⌫"]
        for _ in 0..<(charCount + 3) {
            let del = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", delLabels)).firstMatch
            if del.exists && del.isHittable {
                del.tap()
            } else {
                break
            }
        }
    }

    /// Phase C of the memory protocol (reports/sim_test_2026-07.md): sustained Japanese typing across
    /// MANY different kana row-heads (dictionary/candidate lookup on many different reading prefixes,
    /// not the same one repeated), a clipboard-tab detour, a run of Italian Latin typing, then back to
    /// Japanese — the shape `scripts/memory_phase_c.sh` is built to watch from outside.
    ///
    /// This test does NOT assert on memory itself — the Simulator's absolute values are not meaningful
    /// for the jetsam budget (playbook §1 point 3) — it only has to exercise the keyboard in a
    /// recognisable, repeatable way and print `MEMC|` markers the host script can align its samples
    /// against. A candidate that never appears, or a clipboard tab that is unreachable on the unsigned
    /// Simulator (playbook §5), must not fail this test — it is a load pass, not a functional check.
    /// メモリ自体はここでは断定しない（シミュレータの絶対値は無意味）。この関数の役割は再現性のある負荷と
    /// タイムスタンプ付きマーカーの提供のみ。候補が出ない・クリップボードタブに届かない、はここでは失敗にしない。
    func test42_memoryPhaseC_japaneseTypingAcrossKana() throws {
        let kanaGroups: [[String]] = [
            ["か", "な"], ["さ", "か"], ["た", "な"], ["は", "な"], ["ま", "た"], ["や", "ま"],
            ["ら", "か"], ["わ", "た"], ["あ", "さ"], ["な", "ま"], ["か", "さ", "た"], ["は", "ま", "や"],
        ]

        // Simulator: Safari is launched on the local fixture (127.0.0.1:8377). Phone: 127.0.0.1 is the
        // phone itself and `launch()` restores whatever tab the user had open (seen 2026-08-15:
        // roma.corriere.it) — so the orchestrator pre-navigates Safari to https://copaky.app/kbtest
        // (memory_phase_c.sh --mode device) and the test only ACTIVATES it, like test33/35 do.
        // 実機では 127.0.0.1 は端末自身: スクリプトが copaky.app/kbtest を開いておき、テストは activate だけ行う。
        #if targetEnvironment(simulator)
        _ = focusField("textarea-field")
        #else
        _ = activatePreNavigatedField("textarea-field")
        #endif
        switchToCopaky(in: safari)
        // The Japanese tab may be FLICK (Simulator seed, most Japanese users) or QWERTY/romaji (the
        // test phone: its owner types romaji). Both build the same reading → the same dictionary
        // lookups; on QWERTY each kana group is typed as its romaji ("か","な" → "kana").
        // 日本語タブはフリック（シミュレータ）でも QWERTY/ローマ字（実機）でもよい: 読みが同じなら辞書検索も同じ。
        let jpFlick = ensureJapaneseTab(in: safari)
        print("MEMC-INFO|japanese-layout|\(jpFlick ? "flick" : "qwerty-romaji")")

        for (i, group) in kanaGroups.enumerated() {
            memcMarker("jp-\(i)", "start")
            let typed = typeKanaGroup(group, flick: jpFlick, in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))   // let candidates compute
            if i == 0 || i == kanaGroups.count - 1 {
                shot("42-jp-\(i)")
            }
            clearTyped(atLeast: typed, in: safari)
            memcMarker("jp-\(i)", "end")
        }

        // Clipboard tab detour — best-effort, same dance as test11/test12. `openClipboardTab` throws
        // `XCTSkip` when the App Group is not provisioned (unsigned Simulator, playbook §5); catching
        // it here converts that into a marker instead of skipping the WHOLE test. `clipboardStart` is
        // captured BEFORE the attempt so the bracket still covers the real load even though the phase
        // NAME (clipboard vs clipboard-skipped) is only known once the attempt is over.
        let clipboardStart = Date()
        var clipboardPhase = "clipboard"
        var clipboardOpened = false
        do {
            try openClipboardTab()
            clipboardOpened = true
        } catch {
            clipboardPhase = "clipboard-skipped"
        }
        // Close the detour EXPLICITLY: an open clipboard tab was left on screen here before, and
        // switchToEnglishTab() below no-ops silently when it cannot find ABC/A — so the Italian phase
        // ran on top of the clipboard panel instead of the Latin tab. Prefer the tab's own back key;
        // fall back to re-selecting the Japanese flick tab to guarantee a known state either way.
        // クリップボードタブは明示的に閉じる（開けっ放しだとイタリア語フェーズが違う画面を測ってしまう）。
        if clipboardOpened {
            let back = firstMatch(in: safari, labels: L.backKey, timeout: 3)
            if let back, back.isHittable {
                back.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            }
        }
        if clipboardPanelIsOpen(timeout: 1) {
            _ = ensureJapaneseTab(in: safari)
        }
        // Layout-agnostic "the keyboard is back": flick kana, QWERTY Japanese, or a Latin letter key.
        let keyboardBack = flickKanaVisible(in: safari, timeout: 4) || japaneseQwertyVisible(in: safari)
            || safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "a")).firstMatch.waitForExistence(timeout: 2)
        XCTAssertTrue(keyboardBack, "main Copaky keyboard did not return after the clipboard detour")
        memcMarker(clipboardPhase, "start", at: clipboardStart)
        memcMarker(clipboardPhase, "end")

        // Italian on the Latin tab — Italian must be SELECTED, never assumed: the default of
        // enable_italian_keyboard_language is false (BoolKeyboardSetting.swift:249-253), so typing on
        // an unselected Latin tab would silently measure English. Same proven transition as
        // test33/test35 (switchToEnglishTab, then one more tap of the language-switch key to reach the
        // "IT" shortSymbol); a soft skip with a reason is recorded instead of failing the whole load
        // pass when the tab or the language cannot be reached (this test's own contract).
        switchToEnglishTab(in: safari)
        dismissCopakyNotice(in: safari)
        let reachedLatin = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR label == %@", "IT", "あ")).firstMatch
            .waitForExistence(timeout: 4)
        var itPhase = "it-skipped"
        var itSkipReason = "latin-tab-not-reached"
        if reachedLatin {
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
            if italian.exists && italian.isHittable {
                italian.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                shot("42-after-it-tap")
                // Evidence from the first Simulator run: the tap on «IT» landed the keyboard on the
                // Japanese FLICK tab (screenshot in the xcresult), so verify the LATIN letters are
                // really on screen before typing; if the flick tab came up, go back to the Latin tab
                // once — latinKeyboardLanguage was already set to Italian by the tap — and re-check.
                // 「IT」タップ後にフリック日本語タブへ戻る事象を観測: ラテン文字が本当に表示されているか確認する。
                if flickKanaVisible(in: safari, timeout: 1) {
                    switchToEnglishTab(in: safari)
                }
                let latinLetter = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", "p")).firstMatch
                if latinLetter.waitForExistence(timeout: 4) {
                    itPhase = "it"
                    // Which Latin language is active is readable from the switch key itself: it
                    // shows the NEXT language of the cycle (ja → en → it), so 「あ」 means Italian is
                    // active, 「IT」 means English still is. Recorded as evidence, not asserted.
                    // 言語切替キーは次の言語を示す: 「あ」ならイタリア語が有効、「IT」ならまだ英語。
                    let nextIsJapanese = safari.descendants(matching: .any)
                        .matching(NSPredicate(format: "label == %@", "あ")).firstMatch.exists
                    let nextIsItalian = safari.descendants(matching: .any)
                        .matching(NSPredicate(format: "label == %@", "IT")).firstMatch.exists
                    let active = nextIsJapanese ? "italian" : (nextIsItalian ? "english" : "unknown")
                    print("MEMC-INFO|latin-language-active|\(active)")
                    note("42-latin-language-active", active)
                } else {
                    itSkipReason = "latin-letters-not-on-screen-after-it-tap"
                }
            } else {
                itSkipReason = "italian-not-enabled"
            }
        }
        if itPhase == "it-skipped" {
            note("42-it-skip-reason", itSkipReason)
            dump(safari, "42-it-skipped-\(itSkipReason)")
        }
        memcMarker(itPhase, "start")
        if itPhase == "it" {
            let italianWords = ["perche", "citta", "andro", "piu", "cosi", "puo", "societa", "grazie"]
            let spaceLabels = L.spaceKey + ["successivo", "次候補", "next candidate", "Next candidate"]
            for word in italianWords {
                // Soft taps: this is a load exercise, a missing key must not abort the phase (the
                // marker pair still brackets whatever was typed).
                _ = softTapKeys(word.map { String($0) }, in: safari)
                let space = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label IN %@", spaceLabels)).firstMatch
                if space.waitForExistence(timeout: 3), space.isHittable {
                    space.tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                }
            }
        }
        memcMarker(itPhase, "end")

        // Back to Japanese for a final push.
        let jpFlickFinal = ensureJapaneseTab(in: safari)
        for (i, group) in kanaGroups.prefix(3).enumerated() {
            memcMarker("jp-final-\(i)", "start")
            _ = typeKanaGroup(group, flick: jpFlickFinal, in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            clearTyped(atLeast: group.count, in: safari)
            memcMarker("jp-final-\(i)", "end")
        }
        memcMarker("end", "end")
    }

    // MARK: - 43 · Device Q-06: keyboard usable across rotation (landscape L/R, back to portrait)

    /// Q-06 of the device protocol: the keyboard must stay usable when the device rotates. Runs on
    /// the Simulator too (rotation works there) as well as on a device.
    /// デバイスプロトコルQ-06: 回転してもキーボードが使用できることを確認する（シミュレータでも検証可）。
    func test43_device_landscapeRotation() throws {
        #if targetEnvironment(simulator)
        _ = focusField("plain-text")
        #else
        _ = activatePreNavigatedField("plain-text")
        #endif
        switchToCopaky(in: safari)
        defer { XCUIDevice.shared.orientation = .portrait }

        // A letter key from either layout (QWERTY "q", flick "あ"/"a") or the space key — whichever
        // tab was left active by an earlier test — must exist and be hittable.
        let usableKeyLabels = ["a", "あ", "q"] + L.spaceKey
        @discardableResult
        func assertKeyboardUsable(_ context: String) -> XCUIElement? {
            guard let key = firstMatch(in: safari, labels: usableKeyLabels, timeout: 4), key.isHittable else {
                dump(safari, "43-\(context)-no-key")
                XCTFail("No letter or space key hittable in \(context)")
                return nil
            }
            return key
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("43-landscape-left")
        let leftKey = assertKeyboardUsable("landscape-left")
        // Soft: 3 taps of whatever key was proven hittable above — this is a usability probe, not a
        // typing correctness check, so a miss here must not fail the rotation assertion already made.
        if let label = leftKey?.label {
            softTapKeys(Array(repeating: label, count: 3), in: safari)
        }

        XCUIDevice.shared.orientation = .landscapeRight
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("43-landscape-right")

        XCUIDevice.shared.orientation = .portrait
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        shot("43-portrait")
        assertKeyboardUsable("portrait")
    }

    // MARK: - 44 · Device only: system language / appearance switch, parametrized by the runner

    /// Settings ▸ Apps ▸ Copaky, stopping at the app's OWN settings page — the read-only prefix of
    /// `setPasteFromOtherApps`, reused by test45 to screenshot the "Paste from Other Apps" row
    /// itself (asset capture) rather than to change its value.
    /// `setPasteFromOtherApps` と同じ前半のナビゲーション（値は変更しない、行の撮影専用）。
    /// Settings restores its last page across launches (paid 2026-08-15: a second visit in the same
    /// test found no «Apps» row because Settings reopened INSIDE Copaky's page). Walk back to the
    /// root until the Apps row is visible.
    /// 設定アプリは前回のページを復元する → Apps 行が見えるまで戻る。
    private func settingsGoRoot() {
        for _ in 0..<7 {
            if firstMatch(in: settings, labels: L.settingsAppsRow, timeout: 1) != nil { return }
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            if back.exists && back.isHittable {
                back.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            } else {
                settings.swipeDown()
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }
        }
    }

    private func openCopakyAppSettingsPage() {
        settings.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        settingsGoRoot()
        guard tapFirst(in: settings, labels: L.settingsAppsRow, timeout: 4, scrollUpTo: 12) else { return }
        let copaky = settings.buttons.matching(
            NSPredicate(format: "identifier == %@ OR label BEGINSWITH %@", "com.pettipol.copaky", "Copaky")).firstMatch
        var swipes = 0
        while !copaky.exists && swipes < 20 {
            settings.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            swipes += 1
        }
        guard copaky.waitForExistence(timeout: 3) else {
            dump(settings, "45-no-copaky-in-apps")
            return
        }
        copaky.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    /// Drives iOS Settings to change the system UI language and/or the light/dark appearance,
    /// entirely parametrized by the runner's environment — there is no in-test way to know what the
    /// phone SHOULD end up as. The phone's CURRENT language may itself be it/en/ja, so every Settings
    /// label needed here is carried in all three variants, mirroring `L`.
    ///
    /// The language change ends in a respring: nothing may be asserted past that tap, only recorded
    /// — the runner can lose the device connection mid-call.
    /// 言語変更はrespringで終わるため、それ以降は断定せずnoteのみで締めくくる（実行中に接続が切れうる）。
    func test44_device_setSystemLanguageAndAppearance() throws {
        let env = ProcessInfo.processInfo.environment
        let targetLang = env["COPAKY_TARGET_LANG"]
        let appearance = env["COPAKY_APPEARANCE"]
        guard targetLang != nil || appearance != nil else {
            throw XCTSkip("Neither COPAKY_TARGET_LANG nor COPAKY_APPEARANCE is set — nothing for this test to drive")
        }

        // Appearance FIRST, from the Settings root — soft (a miss here must not block the language
        // change below, the two are independent runner knobs).
        if let appearance, appearance == "light" || appearance == "dark" {
            settings.launch()
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            if softTapScrolling(L.displayBrightnessRow, in: settings) {
                let target = appearance == "dark" ? L.appearanceDark : L.appearanceLight
                if !softTapScrolling(target, in: settings) {
                    // the swatches are sometimes plain staticTexts rather than buttons/images
                    if let text = firstMatch(in: settings, labels: target, timeout: 4) {
                        text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                    } else {
                        note("44-appearance-skip", "\(appearance) swatch not found under Display & Brightness")
                        dump(settings, "44-appearance-tree-\(appearance)")
                    }
                }
                shot("44-appearance-\(appearance)")
            } else {
                note("44-appearance-skip", "Display & Brightness row not found")
                dump(settings, "44-no-display-brightness")
            }
        }

        guard let targetLang, ["en", "ja", "it"].contains(targetLang) else {
            if let targetLang { note("44-lang-skip", "COPAKY_TARGET_LANG must be en/ja/it, got '\(targetLang)'") }
            return
        }
        let nativeName: String
        switch targetLang {
        case "en": nativeName = "English"
        case "ja": nativeName = "日本語"
        default:   nativeName = "Italiano"
        }

        settings.launch()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        tapFirst(in: settings, labels: L.general, scrollUpTo: 2)
        tapFirst(in: settings, labels: L.languageAndRegionRow, scrollUpTo: 6)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // iOS 26 layout (read from the phone's tree, 2026-08-15): «Lingua e zona» shows a PREFERRED
        // LANGUAGES list whose cells carry the locale as identifier ('it-IT', 'en-IT'…) — the first
        // cell is the iPhone language (subtitle «Lingua iPhone») — plus «Aggiungi lingua…»
        // (identifier ADD_PREFERRED_LANGUAGE). There is no separate «iPhone Language» picker row.
        // Two ways to make another language primary: drag its cell to the top (a confirmation sheet
        // «Cambia in …»/«Change to …»/«…に変更» follows), or add it via «Aggiungi lingua…» and answer
        // «Usa <lingua>» to the prompt. Both end in a respring.
        // iOS 26 の「言語と地域」は優先言語リスト（識別子はロケール）。先頭が iPhone の言語。ドラッグで先頭へ移すか、
        // 「言語を追加…」から追加して「〜を使用」を選ぶ。どちらも respring で終わる。
        let names: [String]   // how the target may be spelled anywhere in this UI (native + it/en/ja names)
        switch targetLang {
        case "en": names = ["English", "Inglese", "inglese", "英語"]
        case "ja": names = ["日本語", "Giapponese", "giapponese", "Japanese"]
        default:   names = ["Italiano", "italiano", "Italian", "イタリア語"]
        }
        let cells = settings.cells
        let targetCell = cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", targetLang)).firstMatch
        let primaryCell = cells.matching(NSPredicate(format: "identifier CONTAINS '-'")).firstMatch   // first locale cell = iPhone language
        if primaryCell.waitForExistence(timeout: 6), primaryCell.identifier.hasPrefix(targetLang) {
            note("44-language", "already \(targetLang) — \(primaryCell.identifier) is the iPhone language")
            return
        }
        var confirmed = false
        if targetCell.exists {
            // Present but not primary: enter edit mode («Modifica»/«Edit»/«編集»), then drag the target's
            // REORDER HANDLE («Riordina English»/«Reorder English»/«並べ替え English») onto the primary's
            // handle. A plain long-press drag on the cell only scrolls the page (tried 2026-08-15).
            // 「編集」に入り、並べ替えハンドルを先頭のハンドルへドラッグする（セル自体のドラッグはスクロールになるだけ）。
            let editButton = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Modifica", "Edit", "編集"])).firstMatch
            if editButton.waitForExistence(timeout: 3), editButton.isHittable {
                editButton.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            }
            // «Riordina English» / «Reorder English» / «Englishを並べ替え» (Japanese puts the verb LAST).
            func handle(for cell: XCUIElement) -> XCUIElement {
                cell.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Riordina' OR label BEGINSWITH 'Reorder' OR label CONTAINS '並べ替え'")).firstMatch
            }
            shot("44-language-before-drag-\(targetLang)")
            // Move the target UP one row at a time until it is first: an element-to-element drag of the
            // reorder handle onto the handle of the row just above is what worked (en, ja); a longer
            // jump from 3rd place, or a coordinate-based drop, landed short (it, 2026-08-15/16).
            // 一段ずつ上へ: 隣の行のハンドルへドラッグするのが確実（3段跳びや座標指定は失敗した）。
            let localeCells = cells.matching(NSPredicate(format: "identifier CONTAINS '-'"))
            for _ in 0..<4 {
                var idx = -1
                for i in 0..<localeCells.count where localeCells.element(boundBy: i).identifier.hasPrefix(targetLang) { idx = i; break }
                if idx <= 0 { break }
                let above = localeCells.element(boundBy: idx - 1)
                let th = handle(for: localeCells.element(boundBy: idx)), ah = handle(for: above)
                if th.waitForExistence(timeout: 3), ah.exists {
                    th.press(forDuration: 0.8, thenDragTo: ah)
                } else {
                    localeCells.element(boundBy: idx).press(forDuration: 1.2, thenDragTo: above)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(1.2))
                // A confirmation sheet means we reached the top: stop dragging.
                if firstMatchContains(in: settings, substrings: L.changeToPrefixes, timeout: 1) != nil
                    || firstMatchContains(in: springboard, substrings: L.changeToPrefixes, timeout: 1) != nil { break }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1.5))
            shot("44-language-after-drag-\(targetLang)")
            let confirmLabels = L.changeToPrefixes + names.map { "Usa \($0)" } + names.map { "Use \($0)" }
            var confirm = firstMatchContains(in: settings, substrings: confirmLabels, timeout: 4)
                ?? firstMatchContains(in: springboard, substrings: confirmLabels, timeout: 2)
            if confirm == nil {
                // Some builds only ask once edit mode is left («Fine»/«Done»/«完了»).
                let done = settings.buttons.matching(NSPredicate(format: "label IN %@", ["Fine", "Done", "完了"])).firstMatch
                if done.exists, done.isHittable {
                    done.tap()
                    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
                }
                confirm = firstMatchContains(in: settings, substrings: confirmLabels, timeout: 4)
                    ?? firstMatchContains(in: springboard, substrings: confirmLabels, timeout: 2)
            }
            if let confirm {
                confirm.tap()
                confirmed = true
            }
        } else {
            // Not in the list: add it, then answer the "which language do you prefer" prompt.
            let add = settings.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@", "ADD_PREFERRED_LANGUAGE")).firstMatch
            guard add.waitForExistence(timeout: 6) else {
                dump(settings, "44-no-add-language")
                XCTFail("Neither the '\(targetLang)' cell nor 'Aggiungi lingua…' found on Language & Region")
                return
            }
            add.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            // Search field speeds the pick up; fall back to scrolling the list.
            let search = settings.searchFields.firstMatch
            if search.waitForExistence(timeout: 3) {
                search.tap()
                search.typeText(names[0])
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            }
            guard tapContainsScrolling(in: settings, substrings: names, maxSwipes: 20, timeout: 5) else {
                dump(settings, "44-no-language-in-add-list")
                XCTFail("'\(names[0])' not found in the Add Language list")
                return
            }
            shot("44-language-picked-\(targetLang)")
            let useLabels = names.map { "Usa \($0)" } + names.map { "Use \($0)" } + names.map { "\($0)を使用" } + L.changeToPrefixes
            if let use = firstMatchContains(in: settings, substrings: useLabels, timeout: 6)
                ?? firstMatchContains(in: springboard, substrings: useLabels, timeout: 2) {
                use.tap()
                confirmed = true
            }
        }
        guard confirmed else {
            dump(settings, "44-no-change-to-confirm")
            XCTFail("Confirmation to switch the iPhone language to '\(targetLang)' not found")
            return
        }
        // A respring follows immediately — nothing may be asserted past this point.
        note("44-language-changed", "requested change to \(targetLang) (\(nativeName)); device is resetting (respring)")
    }

    // MARK: - 45 · Device only: asset capture (paste dialog + Settings "Paste from Other Apps" row)

    /// **Asset capture, not a pass/fail check.** Screenshots the system paste prompt (arming it the
    /// same way test41's baseline arm does) and the Settings row that governs it. The Simulator has
    /// no paste-permission subsystem at all (see test41's doc comment), so a missing dialog here is
    /// EXPECTED, not a failure — the Settings-row screenshot is the part validated on the Simulator.
    /// アセット撮影用（合否判定ではない）。ダイアログが出ないSimulatorでも失敗にしない。
    func test45_device_captureFullAccessPasteAssets() throws {
        // Deny → Ask, not just Ask: iOS remembers a per-source-app decision (after one «Allow» or
        // «Don't Allow» from Safari the prompt stopped coming, and the marker was delivered silently
        // — en/dark ×4, 2026-08-16). Flipping the permission through Deny resets that memory.
        // 一度応答すると次回から聞かれない → Deny を経由して Ask に戻し、記憶をリセットする。
        try setPasteFromOtherApps(to: L.pasteDeny)
        try setPasteFromOtherApps(to: L.pasteAsk)
        _ = try seedMarkerFromQaPage(evidence: "45")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        try openClipboardTab()

        // Tap the OLD capture bar (same predicate/retry shape as test41's baseline arm) — this is
        // the path that raises the system paste prompt.
        var tapped = false
        for _ in 0..<3 {
            dismissCopakyNotice(in: safari)
            // Either our capture bar or the system paste capsule (`use_system_paste_control` ON, as
            // on the test phone): with the permission on Ask BOTH raise the system prompt (test41).
            // The capsule is matched INSIDE the keyboard area only: «Paste» is a common label (the
            // en/dark runs tapped a "Paste" that was not the capsule and no prompt came).
            let keyboardTop = safari.frame.height * 0.55
            var target: XCUIElement? = firstMatch(in: safari, labels: L.captureBar, timeout: 2)
            if target == nil {
                let capsules = safari.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", L.systemPasteControl))
                for i in 0..<min(capsules.count, 6) {
                    let c = capsules.element(boundBy: i)
                    if c.exists, c.frame.minY > keyboardTop, c.isHittable { target = c; break }
                }
            }
            if target == nil { dump(safari, "45-no-capsule-in-keyboard-area") }
            if let el = target, el.isHittable {
                el.tap()
                tapped = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        guard tapped else {
            dump(safari, "45-no-capture-bar")
            note("45-no-dialog", "capture bar not found/hittable — cannot arm the paste prompt on this run")
            openCopakyAppSettingsPage()
            var swipesRow = 0
            while firstMatch(in: settings, labels: L.pasteFromOtherAppsRow, timeout: 1) == nil
                    && firstMatchContains(in: settings, substrings: L.pasteFromOtherAppsRowParts, timeout: 1) == nil && swipesRow < 8 {
                settings.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                swipesRow += 1
            }
            shot("45-settings-paste-row")
            return
        }

        // Wait for the prompt itself (it is SpringBoard's), not a fixed 1.5 s: one run shot the screen
        // before it came up (en/dark, 2026-08-16). Retry the tap once if it never shows.
        var promptUp = springboard.alerts.firstMatch.waitForExistence(timeout: 5) || safari.alerts.firstMatch.exists
        if !promptUp {
            if let el = firstMatch(in: safari, labels: L.captureBar + L.systemPasteControl, timeout: 3), el.isHittable {
                el.tap()
                promptUp = springboard.alerts.firstMatch.waitForExistence(timeout: 5) || safari.alerts.firstMatch.exists
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        shot("45-paste-dialog")   // the system prompt, if any, is IN this shot
        note("45-prompt-up", promptUp ? "yes" : "no")
        // The prompt's frame (points) for the asset composer: it belongs to SpringBoard, not Safari.
        for host in [springboard, safari] {
            let alert = host.alerts.firstMatch
            if alert.exists {
                let f = alert.frame
                note("45-paste-dialog-frame", "\(host == springboard ? "springboard" : "safari") x=\(f.origin.x) y=\(f.origin.y) w=\(f.size.width) h=\(f.size.height) screen=\(host.frame.size.width)x\(host.frame.size.height)")
                break
            }
        }

        // Do NOT answer the prompt: iOS remembers «Don't Allow» for the (Safari → Copaky) pair and then
        // stops asking — the next language's capture found no prompt at all (en/dark ×2, 2026-08-16,
        // right after the en/light run had tapped Don't Allow). Terminating Safari dismisses the alert
        // without recording a decision, so the next run can arm the prompt again.
        // 「許可しない」を押すと記憶されて次回は出ない → 決定を残さず Safari を終了して閉じる。
        note("45-dialog", promptUp ? "system paste prompt appeared; left unanswered (Safari terminated)" : "no system paste prompt appeared")
        safari.terminate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        // Settings-row asset: Impostazioni ▸ Apps ▸ Copaky ▸ "Paste from Other Apps" row, left
        // VISIBLE but not tapped (tapping it replaces the row with its own Ask/Allow/Deny picker).
        openCopakyAppSettingsPage()
        var swipes = 0
        while firstMatch(in: settings, labels: L.pasteFromOtherAppsRow, timeout: 1) == nil
                && firstMatchContains(in: settings, substrings: L.pasteFromOtherAppsRowParts, timeout: 1) == nil && swipes < 8 {
            settings.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            swipes += 1
        }
        shot("45-settings-paste-row")
    }

    // MARK: - 50 · Accessibility audit inventory across the Settings screens

    /// One collected accessibility-audit issue, flattened to plain strings so it can be JSON-encoded
    /// without depending on the shape of `XCUIAccessibilityAuditIssue` itself (playbook §4.2).
    @available(iOS 17.0, *)
    private struct A11yIssueRecord: Codable {
        let screen: String
        let auditType: String
        let compact: String
        let detailed: String
        let element: String
    }

    /// `XCUIAccessibilityAuditType` has no `CustomStringConvertible`; name the iOS-available bits (the
    /// header gates `.action`/`.parentChild` to macOS only — XCUIAccessibilityAuditTypes.h) so log
    /// lines read "contrast"/"dynamicType"/… instead of an opaque option-set integer.
    @available(iOS 17.0, *)
    private func auditTypeName(_ type: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"),
            (.elementDetection, "elementDetection"),
            (.hitRegion, "hitRegion"),
            (.sufficientElementDescription, "sufficientElementDescription"),
            (.dynamicType, "dynamicType"),
            (.textClipped, "textClipped"),
            (.trait, "trait"),
        ]
        let matched = names.filter { type.contains($0.0) }.map(\.1)
        return matched.isEmpty ? "unknown" : matched.joined(separator: "+")
    }

    /// Runs `performAccessibilityAudit` against whatever is on screen and RETURNS every issue found
    /// instead of letting the closure fail the test: this is an inventory (playbook §4.2), not a gate.
    /// Prints one `A11Y-ISSUE|` line per issue (greppable straight from the xcodebuild log, no xcresult
    /// export needed) plus a trailing `A11Y-SUMMARY|` count. Returns an array rather than taking an
    /// `inout` collector: `performAccessibilityAudit`'s optional closure parameter is implicitly
    /// `@escaping`, and an escaping closure cannot capture an `inout` parameter.
    /// 監査は一覧作成であってゲートではないため、closureは常にtrueを返しテストを失敗させない。
    @available(iOS 17.0, *)
    private func auditScreen(_ name: String, in app: XCUIApplication) -> [A11yIssueRecord] {
        var found: [A11yIssueRecord] = []
        do {
            try app.performAccessibilityAudit { issue in
                let compact = issue.compactDescription.replacingOccurrences(of: "\n", with: " ")
                let type = self.auditTypeName(issue.auditType)
                let elementBrief = issue.element.map { String($0.debugDescription.prefix(200)) } ?? "(no element)"
                found.append(A11yIssueRecord(
                    screen: name, auditType: type, compact: compact,
                    detailed: issue.detailedDescription, element: elementBrief
                ))
                print("A11Y-ISSUE|\(name)|\(type)|\(compact)")
                return true   // inventory only — never fail the test on a found issue
            }
        } catch {
            print("A11Y-SKIP|\(name)|audit threw: \(error)")
        }
        print("A11Y-SUMMARY|\(name)|\(found.count)")
        return found
    }

    /// Best-effort tap for the audit sweep below: returns false instead of failing the test when the
    /// element never shows up, so one missing/renamed screen does not abort the whole inventory.
    /// 監査の網羅性を優先し、要素が無くてもテストを落とさない探索専用のタップ（スクロールなし）。
    @discardableResult
    private func softTap(_ labels: [String], in app: XCUIApplication, timeout: TimeInterval = 6) -> Bool {
        guard let el = firstMatch(in: app, labels: labels, timeout: timeout), el.isHittable else { return false }
        el.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        return true
    }

    /// Same as `softTap`, but scrolls the Form down first — several Settings rows targeted by test50
    /// (Acknowledgements, Contact) sit below the fold and `firstMatch` alone does not scroll.
    @discardableResult
    private func softTapScrolling(_ labels: [String], in app: XCUIApplication, maxSwipes: Int = 10) -> Bool {
        var el = firstMatch(in: app, labels: labels, timeout: 2)
        var swipes = 0
        while (el == nil || el?.isHittable != true) && swipes < maxSwipes {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            el = firstMatch(in: app, labels: labels, timeout: 2)
            swipes += 1
        }
        guard let target = el, target.isHittable else { return false }
        target.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        return true
    }

    /// Pop the current navigation stack via the leading nav-bar button (back chevron), best-effort.
    private func softBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable {
            back.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
    }

    /// Accessibility-audit inventory (playbook §4.2) over every principal screen reachable from the tab
    /// bar / Settings root: Tips, Settings in its short "Essenziali" form, Settings with every section
    /// shown, the OSS-license screen, the Contact screen, and the Themes tab. Every issue found is
    /// RECORDED, never failed on — the closure always returns `true` — because this is a census for a
    /// human to triage (reports/a11y_audit_*.md), not a regression gate. The only thing this test can
    /// fail on is the harness throwing before any screen is reached; a screen that cannot be navigated
    /// to is logged as `A11Y-SKIP` and the sweep continues to the next one.
    /// 各画面の監査結果を収集するだけの一覧作成テスト。個々のissueでは失敗させない
    /// （画面遷移の失敗のみSKIPとして記録し、次の画面へ続行する）。
    func test50_accessibilityAudit_settingsScreens() throws {
        guard #available(iOS 17.0, *) else {
            throw XCTSkip("performAccessibilityAudit (XCUIAccessibilityAuditType) needs iOS 17+, this run is older")
        }

        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) { close.tap() }

        var issues: [A11yIssueRecord] = []

        // 1 · Tips — the app's default landing tab (ContentView.TabSelection.tips)
        if softTap(L.tipsTab, in: mainApp) {
            shot("50-tips")
            issues += auditScreen("Tips", in: mainApp)
        } else {
            print("A11Y-SKIP|Tips|tab bar item not found")
        }

        // 2 · Settings — "Essenziali" short list (settings_show_all_sections OFF)
        openSettingsTab()
        if driveSwitch(L.showAllSettings, to: false) {
            shot("50-settings-essentials")
            issues += auditScreen("Impostazioni (Essenziali)", in: mainApp)
        } else {
            print("A11Y-SKIP|Impostazioni (Essenziali)|could not confirm 'Mostra tutte le impostazioni' OFF")
        }

        // 3 · Settings — every section (settings_show_all_sections ON)
        if driveSwitch(L.showAllSettings, to: true) {
            shot("50-settings-all")
            issues += auditScreen("Impostazioni (tutte le sezioni)", in: mainApp)
        } else {
            print("A11Y-SKIP|Impostazioni (tutte le sezioni)|could not confirm 'Mostra tutte le impostazioni' ON")
        }

        // 4 · OSS license screen (OpenSourceSoftwaresLicenseView), reached from the all-sections list
        if softTapScrolling(L.ossAcknowledgements, in: mainApp) {
            shot("50-oss-license")
            issues += auditScreen("Licenze OSS", in: mainApp)
            softBack(mainApp)
        } else {
            print("A11Y-SKIP|Licenze OSS|link 'Acknowledgements' not found")
        }

        // 5 · Contact screen (ContactView)
        if softTapScrolling(L.contactLink, in: mainApp) {
            shot("50-contact")
            issues += auditScreen("Contatti", in: mainApp)
            softBack(mainApp)
        } else {
            print("A11Y-SKIP|Contatti|link 'お問い合わせ' not found")
        }

        // 6 · Themes tab (ThemeTabView)
        if softTap(L.themesTab, in: mainApp) {
            shot("50-themes")
            issues += auditScreen("Temi", in: mainApp)
        } else {
            print("A11Y-SKIP|Temi|tab bar item not found")
        }

        // 7 · "Appunti" (clipboard) — there is no such MainApp screen: clipboard history lives INSIDE
        // the keyboard extension's own tab bar (openClipboardTab), which needs a signed build /
        // provisioned App Group (playbook §5) — an unsigned-sim UI test cannot reach it from here.
        // 「Appunti」画面はMainApp側に存在しない（キーボード拡張のタブとしてのみ存在し、署名ビルドが必要）。
        print("A11Y-SKIP|Appunti|not a standalone MainApp screen — it is the keyboard extension's own clipboard tab, unreachable without a signed build (see openClipboardTab)")

        // Report: JSON + a human-readable list, both attached to the result bundle, on top of the
        // per-issue A11Y-ISSUE / A11Y-SUMMARY lines already printed above.
        XCTContext.runActivity(named: "Accessibility audit inventory") { activity in
            if let jsonData = try? JSONEncoder().encode(issues) {
                let jsonAttachment = XCTAttachment(data: jsonData, uniformTypeIdentifier: "public.json")
                jsonAttachment.name = "a11y-audit-issues.json"
                jsonAttachment.lifetime = .keepAlways
                activity.add(jsonAttachment)
            }
            let readable = issues.isEmpty
                ? "No accessibility issues recorded across the audited screens."
                : issues.map { "[\($0.screen)] \($0.auditType): \($0.compact)" }.joined(separator: "\n")
            let textAttachment = XCTAttachment(string: readable)
            textAttachment.name = "a11y-audit-issues.txt"
            textAttachment.lifetime = .keepAlways
            activity.add(textAttachment)
        }
    }
}
