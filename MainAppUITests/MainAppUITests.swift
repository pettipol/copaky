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
    static let clipboardAdvancedLink = ["clipboard-long-press-slots-settings-link"]
    static let captureBar = ["コピーした内容を追加", "現在のクリップボードを追加", "Add copied text", "Add current clipboard", "Aggiungi il testo copiato", "Aggiungi gli appunti correnti"]
    static let clipboardTab = [
        "コピー履歴", "クリップボードの履歴", "Clipboard histories", "Cronologia degli appunti",
        "clipboard_history_tab", "doc.badge.clock",
    ]
    static let clipboardEmptyState = [
        "コピーした後、上の「追加」ボタンを押すとここに保存されます",
        "After you copy text, tap “Add” above to save it here",
        "Dopo aver copiato il testo, tocca «Aggiungi» qui sopra per salvarlo qui",
    ]
    static let oversizedClipboardToast = [
        "クリップボードが大きすぎるため追加できませんでした",
        "The clipboard is too large to add",
        "Gli appunti sono troppo grandi per essere aggiunti",
    ]
    /// Existing slot whose LONG-PRESS opens Clipboard history when enabled, otherwise the tab bar.
    static let tabBarToggleKey = [
        "☆123", "123", "#+=", "numbers", "Numbers", "numeri", "Numeri", "数字",
        "textformat.123", "textformat.numbers",
    ]
    /// Optional candidate-bar button carrying our own mark (CopakyMark). When shown it works on every
    /// tab, unlike ☆123 which only exists on flick layouts. Keep the glyph and accessibility labels.
    static let tabBarButton = ["写", "タブバーを開く", "Open tab bar", "Open the tab bar", "Apri la barra dei tab"]
    static let numberHintsToggle = ["Show numbers on the top row", "上段に数字を表示", "Mostra i numeri nella riga superiore"]
    static let realNumberRowToggle = ["Add a number row to QWERTY", "QWERTYに数字行を追加", "Aggiungi una riga numerica alla QWERTY"]
    static let spaceSlideCursorToggle = ["Slide space to move the cursor", "スペースをスライドしてカーソルを移動", "Scorri sullo spazio per spostare il cursore"]
    static let hideEmptyCandidateBarToggle = [
        "候補がないとき候補バーを隠す（ラテン文字キーボード）",
        "Hide the suggestion bar when it is empty (Latin keyboards)",
        "Nascondi la barra dei suggerimenti quando è vuota (tastiere latine)",
    ]
    static let italianToggle = ["Use Italian", "イタリア語を使う", "Usa l'italiano"]
    static let activeLanguages = ["Active languages", "使用する言語", "Lingue attive"]
    static let japaneseLanguage = ["Japanese", "日本語", "Giapponese"]
    static let englishLanguage = ["English", "英語", "Inglese"]
    static let pinnedFirst = ["Pinned first", "先頭に固定", "Fissato in cima"]
    static let edit = ["Edit", "編集", "Modifica"]
    static let done = ["Done", "完了", "Fine"]
    static let activeLanguagesEditorIdentifier = "active-languages-editor"
    static let japaneseLanguageRowIdentifier = "active-language-row-ja_JP"
    static let englishLanguageRowIdentifier = "active-language-row-en_US"
    static let italianLanguageRowIdentifier = "active-language-row-it_IT"
    static let italianLanguageToggleIdentifier = italianLanguageRowIdentifier
    static let activeLanguagesEditButtonIdentifier = "active-language-edit-button"
    // Copaky: the auto-accent toggle is localized in every shipped UI language.
    // Copaky: アクセント自動補正の設定名を全対応言語で検索する。
    static let italianAutoAccentToggle = ["Auto-accent on space (Italian)", "スペースでアクセントを自動補正（イタリア語）", "Accento automatico con lo spazio (italiano)"]
    /// Enter key in its plain "return" state — localized since the key-label fix (Design.getEnterKeyText).
    static let enterKeyReturn = ["改行", "Newline", "A capo"]
    /// Space key on the simple/flick keyboards — localized since the key-label fix.
    /// Lowercase variants included: the catalog ships them lowercase ("space"/"spazio", seen on
    /// the phone 2026-08-14) and XCUI label matching is case-sensitive.
    static let spaceKey = ["空白", "Space", "space", "Spazio", "spazio"]
    // E-18 gives every image key an explicit product-localized label while retaining its SF-Symbol
    // identifier. Keep legacy labels only in broad lookup helpers; exact gates use the arrays below.
    // E-18: 画像キーは明示的な製品翻訳labelを持ち、SF Symbolのidentifierは維持する。
    static let deleteKey = ["delete", "削除", "Delete", "Cancella", "Elimina", "⌫"]
    static let deleteKeyIdentifiers = ["delete.left", "delete.backward"]
    static let deleteKeyA11y = ["削除", "Delete", "Cancella"]
    static let numbersKeyA11y = ["数字", "Numbers", "Numeri"]
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
    static let pasteDeny = ["Rifiuta", "Nega", "Deny", "拒否"]
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
class CopakyCampaignTests: XCTestCase {

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

    /// Custom keyboards vend NO XCUI `Keyboard` element on this project (tree dump, 30/08): the
    /// honest measurable container is UIKit's UIInputView, exposed as `identifier == "inputView"`.
    /// Mid-transition more than one window can carry a copy, so re-query and take the tallest
    /// existing frame each sample.
    /// カスタムキーボードはXCUIのKeyboard要素を持たない（30/08実測）。UIKitのinputView識別子を
    /// 使い、遷移中は複製があるため毎回最も高いフレームを選ぶ。
    func keyboardInputViewFrame(of app: XCUIApplication) -> CGRect? {
        let query = app.descendants(matching: .other)
            .matching(NSPredicate(format: "identifier == 'inputView'"))
        var best: CGRect?
        for index in 0..<min(query.count, 6) {
            let element = query.element(boundBy: index)
            guard element.exists else { continue }
            let frame = element.frame
            guard frame.width > 1, frame.height > 1 else { continue }
            if best == nil || frame.height > best!.height {
                best = frame
            }
        }
        return best
    }

    /// Waits until the keyboard inputView frame is available (any non-degenerate sample).
    private func waitForKeyboardInputViewFrame(of app: XCUIApplication, timeout: TimeInterval) -> CGRect? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let frame = keyboardInputViewFrame(of: app) {
                return frame
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        return nil
    }

    /// Resolve an SF-Symbol-backed key by its stable identifier, restricted to the visual keyboard.
    /// E-18 changes the spoken label, never these identifiers.
    /// SF Symbolの安定identifierで画像キーを探す。E-18で変えるのはlabelだけ。
    private func keyboardImageKey(identifier: String, in app: XCUIApplication, timeout: TimeInterval = 4) -> XCUIElement? {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let root = keyboard(of: app)
            let matches = root.exists
                ? root.descendants(matching: .any).matching(predicate)
                : app.descendants(matching: .any).matching(predicate)
            for index in 0..<min(matches.count, 12) {
                let element = matches.element(boundBy: index)
                if element.exists, element.frame.minY >= app.frame.height * 0.45 {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return nil
    }

    /// Regression gate for E-18's three always-visible Latin image keys. The exact labels are ours,
    /// not the OS-localized SF Symbol names; identifiers remain unchanged for the existing harness.
    /// E-18の回帰ゲート：labelは製品翻訳、identifierは既存値を維持する。
    private func assertLatinImageKeyAccessibility(in app: XCUIApplication,
                                                  file: StaticString = #filePath, line: UInt = #line) {
        let contracts: [(identifier: String, labels: [String], role: String)] = [
            ("delete.left", L.deleteKeyA11y, "delete"),
            ("textformat.123", L.numbersKeyA11y, "numbers"),
            ("arrow.turn.down.left", L.enterKeyReturn, "newline"),
        ]
        for contract in contracts {
            guard let key = keyboardImageKey(identifier: contract.identifier, in: app) else {
                XCTFail("E-18: \(contract.role) image key is missing stable identifier '\(contract.identifier)'", file: file, line: line)
                continue
            }
            XCTAssertEqual(key.identifier, contract.identifier,
                           "E-18 must preserve the \(contract.role) key identifier", file: file, line: line)
            XCTAssertTrue(contract.labels.contains(key.label),
                          "E-18: \(contract.role) must use an explicit ja/en/it label, got '\(key.label)'", file: file, line: line)
        }
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
        // The clipboard panel replaces all of those keys, so admit only its Copaky-specific full labels;
        // never add its generic Back/History/Paste labels, which Safari or the stock keyboard can expose.
        // クリップボード画面では通常キーが消えるため、Copaky固有の完全な文言だけを追加する。
        let clipboardMarkers = L.captureBar
            + L.clipboardTab.filter { $0 != "doc.badge.clock" }
            + L.clipboardEmptyState + L.oversizedClipboardToast
        // A-04 made the Latin language key show "current/next" from the ACTIVE LIST, so its composite
        // label depends on the list order: A→IT ("AIT"), IT→A ("ITA"), IT→あ ("ITあ") joined "Aあ".
        // Measured 20th session: with the Copaky bar button OFF (A-11 default) a Latin QWERTY tab
        // carried NONE of the previous markers and copakyActive returned false while the keyboard
        // was plainly on screen (UIRemoteKeyboardWindow present in the failure snapshot).
        // これらの複合ラベルはA-04のアクティブリスト由来で、Copaky固有（純正には存在しない）。
        // 「あA」/「あIT」: the JP ROMAJI QWERTY tab (device users with keyboard_type=roman) shows the
        // A-04 composite ja→next-Latin — measured on a real phone (20th session): Copaky was plainly
        // active on qwerty_hira and NO other marker existed on screen.
        // 「あA」「あIT」はローマ字入力ユーザーの日本語QWERTYタブの言語キー（実機で実測）。
        // "copaky_clipboard_back": the panel with the system paste control ON exposes no other
        // Copaky-only label (capture bar → Apple capsule, header → generic "Cronologia"/"History") —
        // measured 29/08 (21ª) on the real phone, capsule phase of test41.
        let markers = ["写", "☆123", "小ﾞﾟ", "Aあ", "あA", "AIT", "ITA", "ITあ", "あIT", "あいう", "逆順", "お知らせ",
                       "copaky_clipboard_back"]
            + clipboardMarkers
        // The A-04 language key does not always put the composite in the LABEL: on the sim build
        // (29/08, 21ª — tree at test05 failure) it exposes identifier
        // 'keyboard-language-switch-A-IT' with label just 'A' (correctly NOT a marker: Apple has
        // plain-A keys too). The identifier namespace is ours alone, so the prefix is a
        // Copaky-specific marker robust to any active-list pair; the composite labels above stay
        // for the real-phone shape measured in the 20th session.
        // 言語キーの複合表記はlabelではなくidentifier側に出ることがある（実測）。接頭辞で掴む。
        let predicate = NSPredicate(
            format: "label IN %@ OR identifier IN %@ OR identifier BEGINSWITH %@",
            markers, markers, "keyboard-language-switch-"
        )
        let keyboardRoot = keyboard(of: app)
        if keyboardRoot.exists {
            return keyboardRoot.descendants(matching: .any).matching(predicate).firstMatch.exists
        }
        // Some custom keyboards expose no XCUI keyboard root. Keep the fallback inside the visual
        // keyboard region instead of letting matching page/Safari text certify liveness.
        // Keyboard要素がない場合も画面下部の入力領域だけを対象にする。
        let marker = app.descendants(matching: .any).matching(predicate).firstMatch
        return marker.exists && marker.frame.minY >= app.frame.height * 0.45
        // Deliberately NO "any keyboard that exposes no keys is ours" fallback. Every SwiftUI-drawn
        // third-party keyboard has that shape, and this very test phone also carries SwiftKey and
        // Gboard: the fallback could certify the WRONG keyboard and the suite would happily test it.
        // 「キーが0個の入力ビュー＝Copaky」判定は誤検知の温床なので置かない。
    }

    /// First-activation in-keyboard notices (お知らせ: 4 stacked emoji-tab data updates) cover the
    /// keyboard UI on every keyboard load (後で only defers, it does not persist). Dismiss all of them
    /// with 後で ("later"); never tap 追加/更新 (those would open the containing app).
    /// They can animate in with a short delay, so wait-and-retry a few rounds.
    func dismissCopakyNotice(in app: XCUIApplication) {
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
    func switchToCopaky(in app: XCUIApplication) {
        if copakyActive(in: app) { return }
        let kb = keyboard(of: app)
        // custom keyboards may not vend a Keyboard element; accept either signal before proceeding.
        // On a REAL phone, re-presenting after a Settings round trip can outlast 8 s (measured
        // 29/08, 21ª: the panel was plainly up in the final video frame while the 8 s assert had
        // already failed) — wait 20 s and re-tap the focused field once at half-time as a belt.
        // 実機では設定往復後の再表示が8秒を超える（実測）。20秒待ち、途中で一度フィールドを叩き直す。
        var up = false
        for attempt in 0..<20 {
            if kb.exists || copakyActive(in: app) { up = true; break }
            if attempt == 9 {
                let focused = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
                if focused.exists, focused.isHittable { focused.tap() }
            }
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
            let x = safari.buttons.matching(NSPredicate(format: "label == %@", closeLabel)).firstMatch
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
            // StaticText first (05/09): with the empty candidate bar hidden the top-row key CONTAINERS
            // (`Other`) report an invalid activation point and `.any` would pick them before the label.
            let staticKey = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
            let key = staticKey.waitForExistence(timeout: 4)
                ? staticKey
                : app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            if !key.waitForExistence(timeout: 4) {
                dump(app, "key-not-found-\(label)")
                shot("key-not-found-\(label)")
            }
            XCTAssertTrue(key.exists, "Key '\(label)' not found on Copaky keyboard")
            key.tap()
        }
    }

    /// Copaky [G-01]: web fields publish their value with a short delay — poll instead of reading once
    /// (measured 05/09: the failure dump already showed value "Q" while the immediate read did not).
    private func waitForFieldValue(_ field: XCUIElement, _ expected: String, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (field.value as? String) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return (field.value as? String) == expected
    }

    /// Copaky [G-01]: freeze the key coordinate because its SF Symbol node changes after tap one.
    /// Two short presses keep the gesture inside the product's double-tap recognition window.
    private func doubleTapKey(_ element: XCUIElement, in app: XCUIApplication) {
        // Two synthesized presses land too far apart for the product's double-press window
        // (measured 05/09: caps lock never engaged); XCUI's native doubleTap() is fast enough.
        let frame = element.frame
        let appFrame = app.frame
        let coordinate = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: frame.midX - appFrame.minX,
            dy: frame.midY - appFrame.minY
        ))
        coordinate.doubleTap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
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
                .matching(NSPredicate(format: "label IN %@ OR identifier IN %@", L.deleteKey, L.deleteKeyIdentifiers)).firstMatch
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
        // Copaky [H-21]: the OS switch is the evidence; Show all settings only changes row visibility.
        // Copaky: OSのフルアクセスを確認する。「すべての設定」は表示範囲だけを変える。
        settings.launch()
        for _ in 0..<7 {
            if firstMatch(in: settings, labels: L.general, timeout: 1) != nil { break }
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            guard back.exists, back.isHittable else { break }
            back.tap()
        }
        openKeyboardsList()
        guard tapFirst(in: settings, labels: ["Copaky", "Copaky — Copaky", "Copaky, Copaky"], scrollUpTo: 2) else { return }
        let fa = settings.switches.matching(NSPredicate(format: "label IN %@", L.allowFullAccess)).firstMatch
        guard fa.waitForExistence(timeout: 6) else {
            dump(settings, "03-no-full-access-switch")
            XCTFail("H-21 prerequisite: Copaky's Allow Full Access switch must be visible in iOS Settings")
            return
        }
        if fa.value as? String == "1" {
            fa.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitForFieldValue(fa, "0"), "iOS Allow Full Access must be OFF before testing")
        shot("03-os-full-access-off")

        #if targetEnvironment(simulator)
        let field = focusField("plain-text")
        #else
        let field = activatePreNavigatedField("plain-text")
        #endif
        switchToCopaky(in: safari)
        // Copaky [H-21]: XCUI can retain the extension tree below the screen after a Settings trip.
        // Require a hittable product control, then allow ONE field refocus before failing setup.
        // Copaky: 設定から戻ると画面外の拡張ツリーが残ることがある。再フォーカスは一度だけ試す。
        func waitForPresentedCopaky(timeout: TimeInterval) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                let controls = safari.descendants(matching: .any).matching(NSPredicate(
                    format: "identifier == %@ OR identifier BEGINSWITH %@",
                    "keyboard-flick-star-123", "keyboard-language-switch-"
                ))
                for index in 0..<min(controls.count, 6) {
                    let control = controls.element(boundBy: index)
                    if control.exists && control.isHittable { return true }
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            } while Date() < deadline
            return false
        }
        var keyboardPresented = waitForPresentedCopaky(timeout: 3)
        if !keyboardPresented {
            dump(safari, "03-before-keyboard-refocus")
            shot("03-before-keyboard-refocus")
            if field.exists && field.isHittable {
                field.tap()
                keyboardPresented = waitForPresentedCopaky(timeout: 6)
            }
        }
        guard keyboardPresented else {
            dump(safari, "03-software-keyboard-not-presented")
            shot("03-software-keyboard-not-presented")
            XCTFail("H-21 prerequisite: no hittable Copaky software keyboard after one field refocus; check Simulator hardware-keyboard attachment/presentation")
            return
        }
        XCTAssertTrue(switchToLatinQwertyTab(in: safari), "Copaky Latin tab unavailable with Full Access OFF")
        clearFocusedField(field, placeholder: "plain-text", in: safari)
        func typeProbe() {
            for label in ["c", "a"] {
                // Copaky: the EN language switch can expose label "A"; it is not the letter key.
                // Copaky: 言語切替の「A」を文字キーと誤認しない。
                let letters = safari.descendants(matching: .any).matching(NSPredicate(
                    format: "label IN %@ AND NOT (identifier BEGINSWITH %@)",
                    [label, label.uppercased()], "keyboard-language-switch-"
                ))
                let key = letters.allElementsBoundByIndex.first {
                    $0.isHittable && $0.frame.minY >= safari.frame.height * 0.45
                }
                guard let key else {
                    XCTFail("Copaky typing key missing with Full Access OFF: \(label)")
                    return
                }
                key.tap()
            }
            XCTAssertTrue(waitForFieldValue(field, "ca") || waitForFieldValue(field, "Ca"),
                          "Copaky must insert the probe with Full Access OFF")
        }
        typeProbe()
        shot("03-typing-without-full-access")

        // Use the system's lowest globe, then prove a stock keyboard replaced Copaky before returning.
        // システムの最下部Globeから切り替え、純正キーとCopaky消失の両方を確認する。
        let globePredicate = NSPredicate(format: "label CONTAINS[c] 'astiera successiva' OR label CONTAINS[c] 'ext keyboard' OR label CONTAINS[c] '次のキーボード'")
        var switchedAway = false
        for _ in 0..<8 {
            let globes = safari.buttons.matching(globePredicate).allElementsBoundByIndex
                .filter { $0.exists && $0.isHittable }
            guard let globe = globes.max(by: { $0.frame.maxY < $1.frame.maxY }) else { break }
            globe.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            if !copakyActive(in: safari), safari.keyboards.keys.firstMatch.exists {
                switchedAway = true
                break
            }
        }
        XCTAssertTrue(switchedAway, "Could not switch from Copaky to a system keyboard with Full Access OFF")
        shot("03-switched-away-without-full-access")
        // Copaky [H-21]: observed iOS first-switch coachmark covers the globe until Continue.
        // Match only the Italian title captured in this campaign; never dismiss an unrelated prompt.
        // Copaky: 初回切替の案内がGlobeを覆う。実測したイタリア語の案内だけを一度閉じる。
        let switchCoachmark = safari.staticTexts.matching(NSPredicate(
            format: "label == %@", "Cambia tastiera velocemente"
        )).firstMatch
        if switchCoachmark.waitForExistence(timeout: 1) {
            let proceed = safari.buttons.matching(NSPredicate(format: "label == %@", "Continua")).firstMatch
            guard proceed.exists && proceed.isHittable else {
                dump(safari, "03-switch-coachmark-not-dismissible")
                shot("03-switch-coachmark-not-dismissible")
                XCTFail("Observed iOS keyboard-switch coachmark has no hittable Continue action")
                return
            }
            proceed.tap()
            let deadline = Date().addingTimeInterval(4)
            while switchCoachmark.exists && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            guard !switchCoachmark.exists else {
                dump(safari, "03-switch-coachmark-remained")
                shot("03-switch-coachmark-remained")
                XCTFail("iOS keyboard-switch coachmark remained after one Continue tap")
                return
            }
        }
        switchToCopaky(in: safari)
        XCTAssertTrue(switchToLatinQwertyTab(in: safari), "Copaky did not recover after the keyboard switch")
        clearFocusedField(field, placeholder: "plain-text", in: safari)
        typeProbe()
        shot("03-returned-and-typed-without-full-access")

        // Relaunch: the containing app reads its Full Access state during setup.
        mainApp.terminate()
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) { close.tap() }
        openSettingsTab()
        let showAll = mainApp.switches.matching(NSPredicate(format: "label IN %@", L.showAllSettings)).firstMatch
        if showAll.waitForExistence(timeout: 2), showAll.value as? String == "1" {
            showAll.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        let toggle = mainApp.switches.matching(NSPredicate(format: "label IN %@", L.clipboardToggle)).firstMatch
        for _ in 0..<6 where !toggle.exists || !toggle.isHittable { mainApp.swipeUp() }
        guard toggle.exists, toggle.isHittable else {
            dump(mainApp, "03-no-clipboard-switch")
            XCTFail("Clipboard history switch not found")
            return
        }
        XCTAssertEqual(toggle.value as? String, "0", "H-21 prerequisite: clipboard history must start OFF")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let alert = mainApp.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 4), "Full Access requirement alert did not appear")
        let explanations = [
            "この機能にはフルアクセスが必要です。この機能を使いたい場合は、「設定」>「キーボード」でフルアクセスを有効にしてください。",
            "This feature requires full access. To use this feature, please enable full access at 'Settings' > 'Keyboard'.",
            "Questa funzione richiede l'accesso completo. Per utilizzarla, attiva l'accesso completo in \"Impostazioni\" > \"Tastiera\".",
        ]
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label IN %@", explanations)).firstMatch.exists,
                      "Unexpected alert: Full Access requirement text is missing")
        XCTAssertTrue(alert.buttons.matching(NSPredicate(format: "label IN %@", ["「設定」アプリを開く", "Open 'Settings' app", "Apri l'app «Impostazioni»"])).firstMatch.exists,
                      "Full Access alert must offer the Settings action")
        shot("03-full-access-required-alert")
        let cancel = alert.buttons.matching(NSPredicate(format: "label IN %@", ["キャンセル", "Cancel", "Annulla"])).firstMatch
        XCTAssertTrue(cancel.exists && cancel.isHittable, "Expected cancel action is absent")
        cancel.tap()
        XCTAssertTrue(waitForFieldValue(toggle, "0"), "Clipboard history must remain OFF after the rejected attempt")
        shot("03-clipboard-remains-off")
        settings.activate()
        XCTAssertTrue(fa.waitForExistence(timeout: 4), "Could not re-observe the OS Full Access switch")
        XCTAssertEqual(fa.value as? String, "0", "Full Access must remain OFF throughout H-21")
        shot("03-os-full-access-still-off")
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

    private func activeLanguageElement(identifier: String) -> XCUIElement {
        mainApp.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
    }

    /// Reveal the inline active-language editor without depending on the current Form scroll offset.
    /// Copaky: Formの保持スクロール位置に依存せず、言語エディタを表示する。
    @discardableResult
    /// A swipe starts with a press at the app's centre: when the list has scrolled the help «?»
    /// there, the gesture degenerates into a tap and the explanation ALERT swallows every later tap
    /// (measured: the canonical-restore drags all "missed" under an open alert). Dismiss first.
    private func dismissMainAppAlertIfAny() {
        let alert = mainApp.alerts.firstMatch
        guard alert.exists else { return }
        let dismiss = alert.buttons.firstMatch
        if dismiss.exists, dismiss.isHittable {
            dismiss.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        }
    }

    private func revealActiveLanguagesEditor() -> Bool {
        func editor() -> XCUIElement {
            dismissMainAppAlertIfAny()
            return activeLanguageElement(identifier: L.activeLanguagesEditorIdentifier)
        }
        if editor().exists { return true }
        for _ in 0..<8 where !editor().exists {
            mainApp.swipeDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        for _ in 0..<10 where !editor().exists {
            mainApp.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return editor().exists
    }

    /// Enable/disable Italian through the new list row, retaining the legacy localized-label fallback.
    /// Copaky: 新しい言語一覧のトグルを操作し、旧ラベル検索も互換用に残す。
    @discardableResult
    private func setItalianActive(_ active: Bool) -> Bool {
        guard revealActiveLanguagesEditor() else { return false }
        let identifierPredicate = NSPredicate(
            format: "identifier == %@",
            L.italianLanguageToggleIdentifier
        )
        let labelPredicate = NSPredicate(format: "label IN %@", L.italianToggle)
        func toggle() -> XCUIElement {
            let identified = mainApp.switches.matching(identifierPredicate).firstMatch
            return identified.exists ? identified : mainApp.switches.matching(labelPredicate).firstMatch
        }
        let wanted = active ? "1" : "0"
        var taps = 0
        while toggle().exists, toggle().value as? String != wanted, taps < 4 {
            toggle().coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            taps += 1
        }
        return toggle().exists && toggle().value as? String == wanted
    }

    private func latinLanguageRowsHaveOrder(italianFirst: Bool) -> Bool {
        let english = activeLanguageElement(identifier: L.englishLanguageRowIdentifier)
        let italian = activeLanguageElement(identifier: L.italianLanguageRowIdentifier)
        guard english.exists, italian.exists else { return false }
        return italianFirst
            ? italian.frame.midY < english.frame.midY
            : english.frame.midY < italian.frame.midY
    }

    /// Reorder EN/IT through SwiftUI EditMode and the row's trailing drag grip.
    /// Copaky: EditModeで右端のグリップをドラッグし、EN/ITの順序を確定する。
    @discardableResult
    private func setLatinLanguageOrder(italianFirst: Bool) -> Bool {
        guard setItalianActive(true) else { return false }
        if latinLanguageRowsHaveOrder(italianFirst: italianFirst) { return true }

        let edit = mainApp.buttons
            .matching(NSPredicate(format: "identifier == %@", L.activeLanguagesEditButtonIdentifier))
            .firstMatch
        guard edit.waitForExistence(timeout: 4), edit.isHittable else { return false }
        dismissMainAppAlertIfAny()
        edit.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        defer {
            let done = mainApp.buttons
                .matching(NSPredicate(format: "identifier == %@", L.activeLanguagesEditButtonIdentifier))
                .firstMatch
            if done.exists, done.isHittable {
                done.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }

        let sourceIdentifier = italianFirst
            ? L.italianLanguageRowIdentifier
            : L.englishLanguageRowIdentifier
        let destinationIdentifier = italianFirst
            ? L.englishLanguageRowIdentifier
            : L.italianLanguageRowIdentifier
        func cell(containing identifier: String) -> XCUIElement {
            let direct = mainApp.cells
                .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
            return direct.exists
                ? direct
                : mainApp.cells.containing(.any, identifier: identifier).firstMatch
        }
        func reorderHandle(in cell: XCUIElement) -> XCUIElement {
            cell.buttons.matching(NSPredicate(
                format: "label BEGINSWITH 'Riordina' OR label BEGINSWITH 'Reorder' OR label CONTAINS '並べ替え'"
            )).firstMatch
        }
        // Dropping on the destination HANDLE's centre can fall back into the source slot (measured:
        // the same one-row swap took in one direction and silently no-opped in the other). Drop PAST
        // the destination row's far edge instead, and retry: SwiftUI reorders on crossing the row
        // boundary, not on landing near it.
        for _ in 0..<3 {
            let sourceHandle = reorderHandle(in: cell(containing: sourceIdentifier))
            let destinationCell = cell(containing: destinationIdentifier)
            guard sourceHandle.waitForExistence(timeout: 3), destinationCell.exists else { return false }
            let movingUp = sourceHandle.frame.midY > destinationCell.frame.midY
            let target = destinationCell.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: movingUp ? 0.08 : 0.92)
            )
            // Slow velocity + a hold before release: an instantaneous drag can release before the
            // rows have animated apart, and SwiftUI silently drops the move (seen intermittently).
            sourceHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.9, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.7)
            let deadline = Date().addingTimeInterval(3)
            while !latinLanguageRowsHaveOrder(italianFirst: italianFirst), Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            if latinLanguageRowsHaveOrder(italianFirst: italianFirst) { return true }
        }

        return latinLanguageRowsHaveOrder(italianFirst: italianFirst)
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
        answerPastePermissionIfPrompted()
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

    /// Perform A-11's shipped one-gesture route from the 123/#+= slot.
    /// A false result means the key was absent or not hittable; callers decide whether that is a
    /// failed assertion or a best-effort skip. / 123枠の長押し経路を一か所に集約する。
    private func longPressClipboardShortcut(labels: [String] = L.tabBarToggleKey,
                                             identifiers: [String] = [],
                                             timeout: TimeInterval = 4) -> Bool {
        let key = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@ OR identifier IN %@", labels, identifiers)).firstMatch
        guard key.waitForExistence(timeout: timeout), key.isHittable else { return false }
        key.press(forDuration: 1.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        dismissCopakyNotice(in: safari)
        return true
    }

    /// The clipboard panel's back key is the lowest hittable match; Safari can expose its own Back.
    private func clipboardBackKey(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let predicate = NSPredicate(format: "label IN %@ OR identifier IN %@", L.backKey, L.backKey)
        let candidates = app.descendants(matching: .any).matching(predicate)
        guard candidates.firstMatch.waitForExistence(timeout: timeout) else { return nil }
        var match: XCUIElement?
        for index in 0..<candidates.count {
            let candidate = candidates.element(boundBy: index)
            guard candidate.exists, candidate.isHittable else { continue }
            if let current = match {
                if candidate.frame.maxY > current.frame.maxY { match = candidate }
            } else {
                match = candidate
            }
        }
        return match
    }

    /// Open the コピー履歴 (clipboard history) tab through either A-11's direct long-press or the bar.
    /// The clipboard item remains pinned in the tab bar for the optional Copaky-button route.
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

        // Open the tab bar with the optional 写 button — a plain tap on our own mark.
        // The direct long-press fallback below also works when this button is hidden.
        // 任意表示のバー用ボタンを先に試し、非表示なら下の長押し経路を使う。
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

        // A-11 opens Clipboard history directly when enabled; otherwise this still toggles the bar.
        if longPressClipboardShortcut() {
            shot("clipboard-direct-or-tabbar-open")
            if clipboardPanelIsOpen() { return }
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
        let seedPrefix = "COPAKY_OVERSIZED_SEED_"
        let externallyPreseeded = ProcessInfo.processInfo.environment["COPAKY_PASTEBOARD_PRESEEDED"] == "1"
        if externallyPreseeded {
            // The wrapper used simctl pbcopy. A readback here would be runner-side and Simulator-only;
            // do not overwrite the simulator-wide value with the historically flaky in-process path.
        } else {
            let runnerSeed = String(repeating: "あ", count: 120_000) // ~360KB UTF-8
            var verified = false
            for _ in 0..<3 {
                UIPasteboard.general.string = runnerSeed
                if UIPasteboard.general.string == runnerSeed {
                    verified = true
                    break
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            guard verified else {
                XCTFail("HARNESS: UIPasteboard seeding failed after 3 attempts; rerun with scripts/run_ui_test.sh --pbseed-bytes 300000 test13_phaseB_byteCap")
                return
            }
        }
        _ = focusField("plain-text")
        switchToCopaky(in: safari)
        try openClipboardTab()
        guard let capture = firstMatch(in: safari, labels: L.captureBar, timeout: 6), capture.isHittable else {
            dump(safari, "13-no-capture-bar")
            XCTFail("HARNESS: capture bar not found/hittable in the clipboard tab")
            return
        }
        let panelFloor = capture.frame.minY - 24
        capture.tap()

        // ORDER MATTERS (measured 2026-08-27): while the SpringBoard-hosted paste-permission alert
        // («…vorrebbe incollare elementi da "CoreSimulatorBridge"») is on screen, ANY query against
        // Safari blocks until the alert goes away — the first toast.exists after the tap took ~180 s
        // and the whole prompt window expired unconsulted. So watch SPRINGBOARD alone first, answer
        // the alert, and only then start polling the toast through Safari.
        let toast = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.oversizedClipboardToast)).firstMatch
        var toastSeen = false
        var alertAppeared = false
        let sbAlert = springboard.alerts.firstMatch
        if sbAlert.waitForExistence(timeout: 6) {
            alertAppeared = true
            let allow = sbAlert.buttons
                .matching(NSPredicate(format: "label IN %@", L.allowPasteButtons)).firstMatch
            guard allow.waitForExistence(timeout: 2), allow.isHittable else {
                dump(safari, "13-paste-prompt-without-allow")
                XCTFail("HARNESS: paste-permission prompt appeared but no Allow Paste button was hittable")
                return
            }
            allow.tap()
        }
        // Alert answered (or permission remembered): Safari is queryable again. The toast lives
        // ~1.5 s from the moment the read actually happened, which is right after Allow.
        let toastDeadline = Date().addingTimeInterval(8)
        repeat {
            if toast.exists {
                toastSeen = true
                shot("13-oversized-toast")
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < toastDeadline

        if !toastSeen {
            dump(safari, "13-no-oversized-toast")
            shot("13-no-oversized-toast")
        }
        if alertAppeared {
            // Deterministic path: the read happened right after Allow, so the 8 s poll brackets the
            // toast's whole 1.5 s life — its absence here is a real graceful-rejection regression.
            XCTAssertTrue(toastSeen, "Graceful-rejection toast did not appear after Allow on the >256KB capture")
        } else if !toastSeen {
            // Permission was remembered: the read (and the 1.5 s toast) predate the poll window that
            // starts only after the 6 s alert watch. Rejection is then proven behaviourally below
            // (panel still open, keyboard alive, oversized item NOT in history) — not a regression.
            XCTContext.runActivity(named: "toast-window-missed-permission-remembered") { activity in
                activity.add(XCTAttachment(string: "No permission alert appeared (remembered), so the 1.5s toast expired before polling began; graceful rejection asserted behaviourally instead."))
            }
        }
        // Expected: no crash, the same clipboard panel remains alive after rejection.
        XCTAssertNotNil(firstMatch(in: safari, labels: L.captureBar, timeout: 2),
                        "Clipboard tab did not remain open after oversized rejection")
        XCTAssertTrue(copakyActive(in: safari), "Keyboard died after >256KB capture attempt")
        if externallyPreseeded {
            XCTAssertNil(markerTile(seedPrefix, in: safari, notAbove: panelFloor),
                         "Oversized simulator seed was added to clipboard history instead of rejected")
        }
        shot("13-after-bytecap")
    }

    /// Copaky (05/09): a fresh install resets the paste permission, and the SpringBoard alert
    /// («"Copaky" vorrebbe incollare elementi da…») blocks every Safari query until answered AND survives
    /// the run. Watch SpringBoard alone, allow, and only then touch Safari again (test13's recipe).
    /// 新規インストール後はペースト許可のアラートが出る。SpringBoard側で先に許可してからSafariに触る。
    @discardableResult
    private func answerPastePermissionIfPrompted(timeout: TimeInterval = 6) -> Bool {
        let sbAlert = springboard.alerts.firstMatch
        guard sbAlert.waitForExistence(timeout: timeout) else { return false }
        let allow = sbAlert.buttons
            .matching(NSPredicate(format: "label IN %@", L.allowPasteButtons)).firstMatch
        guard allow.waitForExistence(timeout: 2), allow.isHittable else {
            XCTFail("HARNESS: paste-permission prompt appeared but no Allow Paste button was hittable")
            return false
        }
        allow.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        return true
    }

    // MARK: - 14 · Pin / delete / persistence (B-06, B-07)

    func test14_phaseB_pinDeletePersistence() throws {
        UIPasteboard.general.string = "Copaky-pin-me"
        _ = focusField("plain-text")
        switchToCopaky(in: safari)
        try openClipboardTab()
        if let capture = firstMatch(in: safari, labels: L.captureBar, timeout: 6) {
            capture.tap()
            answerPastePermissionIfPrompted()
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
    func switchToJapaneseFlickTab(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        dismissCopakyNotice(in: app)
        if flickKanaVisible(in: app, timeout: 2) { return }

        // 1. Cycle a Latin QWERTY through every active language. 「あ」 may no longer be the next
        //    target now that EN/IT are reorderable, so do not assume a fixed JP→EN→IT order.
        //    Copaky: EN/ITの並び替え後も固定順を仮定せず、日本語まで最大一周する。
        for _ in 0..<3 where latinQwertyVisible(in: app, timeout: 0.3) {
            let switchKey = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", ["あ", "IT"])).firstMatch
            guard switchKey.exists, switchKey.isHittable else { break }
            switchKey.tap()
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

    /// Switch Copaky's internal tab to the first active Latin language, from EITHER Japanese layout.
    ///
    /// Two different keys do this, and which one exists depends on the tab the previous test left
    /// behind (the tab survives in the extension's static `VariableStates` — see
    /// `switchToJapaneseFlickTab`): the FLICK Japanese tab carries 「ABC」, the QWERTY Japanese tab
    /// carries the language-switch key. Tap its unique current-language marker 「あ」 so an uppercase
    /// letter key cannot be mistaken for the English target "A". The legacy name is retained for
    /// existing call sites.
    /// フリック日本語タブでは「ABC」、ローマ字タブでは言語切替キー — 直前のタブに依存しないよう両方見る。
    private func switchToEnglishTab(in app: XCUIApplication) {
        dismissCopakyNotice(in: app)
        if latinQwertyVisible(in: app, timeout: 0.5) { return }
        let abcKey = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "ABC")).firstMatch
        if abcKey.waitForExistence(timeout: 2) && abcKey.isHittable {
            abcKey.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: app)
            if latinQwertyVisible(in: app, timeout: 2) { return }
        }
        let toLatin = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "あ")).firstMatch
        if toLatin.waitForExistence(timeout: 2) && toLatin.isHittable {
            toLatin.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            dismissCopakyNotice(in: app)
        }
    }

    /// True only when QWERTY letters/Space are visible and the stable language-switch identifier says
    /// the current script is Latin. Space itself localizes to 空白 under ja-JP on every tab, so its
    /// label cannot distinguish Japanese Roman input. / 言語キー識別子でラテン文字タブを判定する。
    private func latinQwertyVisible(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let letter = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch
        let space = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.spaceKey)).firstMatch
        guard letter.waitForExistence(timeout: timeout), space.exists,
              let languageState = currentLanguageSwitchState(in: app, timeout: timeout) else {
            return false
        }
        return languageState.current == "A" || languageState.current == "IT"
    }

    private func languageSwitchElement(
        current: String,
        next: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 4
    ) -> XCUIElement? {
        let identifier = "keyboard-language-switch-\(current)-\(next)"
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier)).firstMatch
        return element.waitForExistence(timeout: timeout) ? element : nil
    }

    private func currentLanguageSwitchState(
        in app: XCUIApplication,
        timeout: TimeInterval = 4
    ) -> (current: String, next: String, element: XCUIElement)? {
        let pairs = [("あ", "A"), ("あ", "IT"), ("A", "IT"), ("A", "あ"), ("IT", "A"), ("IT", "あ")]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for (current, next) in pairs {
                if let element = languageSwitchElement(
                    current: current,
                    next: next,
                    in: app,
                    timeout: 0
                ) {
                    return (current, next, element)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return nil
    }

    private func tapLanguageSwitch(_ element: XCUIElement, in app: XCUIApplication) {
        let frame = element.frame
        let appFrame = app.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX - appFrame.minX, dy: frame.midY - appFrame.minY))
            .tap()
    }

    /// Select one direct-menu index without querying the transient popup: freeze the switch key,
    /// derive one variation pitch from q→w, then hold and drag in a single continuous gesture.
    /// Index zero still needs a small positive dx so release commits the first variation, not tap.
    /// Copaky: 一時ポップアップを検索せず、q→w間隔で各候補へ一筆ドラッグする。
    @discardableResult
    private func selectActiveLanguageMenuIndex(
        _ index: Int,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let languageKey = currentLanguageSwitchState(in: app)?.element
        let q = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch
        let w = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["w", "W"])).firstMatch
        guard let languageKey, languageKey.waitForExistence(timeout: 4), languageKey.isHittable,
              q.waitForExistence(timeout: 4), w.waitForExistence(timeout: 4) else {
            dump(app, "language-menu-prerequisite-missing-index-\(index)")
            shot("language-menu-prerequisite-missing-index-\(index)")
            XCTFail("Language key or q→w pitch keys missing before menu index \(index)", file: file, line: line)
            return false
        }

        let pitch = abs(w.frame.midX - q.frame.midX)
        guard pitch > 1 else {
            dump(app, "language-menu-invalid-pitch-index-\(index)")
            shot("language-menu-invalid-pitch-index-\(index)")
            XCTFail("Could not derive a positive QWERTY key pitch", file: file, line: line)
            return false
        }
        let keyFrame = languageKey.frame
        let appFrame = app.frame
        let appOrigin = app.coordinate(withNormalizedOffset: .zero)
        let start = appOrigin.withOffset(CGVector(
            dx: keyFrame.midX - appFrame.minX,
            dy: keyFrame.midY - appFrame.minY
        ))
        let target = start.withOffset(CGVector(
            dx: pitch * (CGFloat(index) + 0.4),
            dy: 0
        ))
        start.press(forDuration: 0.8, thenDragTo: target)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        return true
    }

    /// Reach the Latin letters tab even when the extension restored a language-less or Japanese tab.
    /// Copaky: 言語なしタブや日本語タブが復元されても、ラテン文字タブまで明示的に戻す。
    func switchToLatinQwertyTab(in app: XCUIApplication) -> Bool {
        if latinQwertyVisible(in: app, timeout: 0.5) { return true }
        switchToEnglishTab(in: app)
        if !latinQwertyVisible(in: app, timeout: 2) {
            // Copaky: A persisted language-less tab may expose only its full back label beside Globe.
            // Copaky: 保持された言語なしタブではGlobe横の完全な戻り先表示を使う。
            if let back = firstMatch(in: app, labels: ["ABC", "ITA", "あいう"], timeout: 2), back.isHittable {
                back.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            }
        }
        if !latinQwertyVisible(in: app, timeout: 2) {
            // Copaky: Returning to Japanese first requires one normal language-switch tap afterward.
            // Copaky: いったん日本語へ戻った場合は通常の言語切替をもう一度行う。
            switchToEnglishTab(in: app)
        }
        return latinQwertyVisible(in: app, timeout: 4)
    }

    /// Copaky extension (QwertyLayoutProvider.abcKeyboard): long-pressing "e" on the EN QWERTY layout
    /// reveals Western-European accent variations ("è", "é", "ê", "ë"); dragging onto "è" and releasing
    /// must input it.
    func test30_accentVariationsOnLongPress() throws {
        if isDevice {
            // On a signed device the app and extension share the App Group, so keep the existing
            // self-contained setting path. / 実機ではApp Group経由の設定をそのまま使う。
            mainApp.launch()
            if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
                close.tap()
            }
            openSettingsTab()
            guard driveSwitch(L.numberHintsToggle, to: false) else {
                dump(mainApp, "30-number-hints-not-off")
                XCTFail("Number hints could not be turned OFF before the accent-variation probe")
                return
            }
        }
        // Simulator app/extension preference domains are split: only the external seed can establish
        // the variation ordering. / Simulatorではアプリ側トグルは拡張に届かない。

        let field = focusField("plain-text")
        switchToCopaky(in: safari)
        switchToEnglishTab(in: safari)
        shot("30-english-tab")
        // StaticText (05/09): the key container `Other` can report an invalid activation point.
        let eKey = safari.staticTexts
            .matching(NSPredicate(format: "label == %@", "e")).firstMatch
        // No `isHittable` (05/09): on the hidden-empty-bar layout the top-row StaticText reports an
        // invalid activation point; the gesture below is coordinate-based and only needs the frame.
        guard eKey.waitForExistence(timeout: 4), eKey.frame.height > 1 else {
            dump(safari, "30-e-key-not-found")
            shot("30-e-key-not-found")
            XCTFail("Key 'e' not found on Copaky EN keyboard")
            return
        }

        // XCUI has no split touch-down/move/up API. Freeze the key's screen position before the
        // magnifier duplicates its label, then perform one continuous gesture: press "e" first,
        // hold until the popup is live, and move vertically through its first ("è") variation.
        // Copaky: e の位置を先に固定し、長押し中に表示された先頭候補「è」へ一筆で移動する。
        let valueBeforeGesture = field.value as? String ?? ""
        let keyFrame = eKey.frame
        let appFrame = safari.frame
        let appOrigin = safari.coordinate(withNormalizedOffset: .zero)
        let start = appOrigin.withOffset(CGVector(
            dx: keyFrame.midX - appFrame.minX,
            dy: keyFrame.midY - appFrame.minY
        ))
        let firstVariant = start.withOffset(CGVector(dx: 0, dy: -keyFrame.height))
        start.press(forDuration: 0.8, thenDragTo: firstVariant)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        shot("30-after-longpress")
        let value = field.value as? String ?? ""
        let inserted = value.hasPrefix(valueBeforeGesture)
            ? String(value.dropFirst(valueBeforeGesture.count))
            : value
        if inserted.rangeOfCharacter(from: .decimalDigits) != nil {
            let message = isDevice
                ? "HARNESS: number-row hints are still active after the device in-app toggle"
                : "HARNESS: number-row hints are still active; run scripts/seed_sim_settings.sh enable_qwerty_number_row_hints=false before test30"
            XCTFail(message)
            return
        }
        XCTAssertTrue(value.contains("è"), "Accent variation 'è' was not inserted via long-press (got '\(value)')")
    }

    /// Focus a field on a page the ORCHESTRATOR already opened in Safari via `simctl openurl`
    /// (iOS 26 gotcha: the "-u" launch argument opens the Start Page instead of navigating).
    func activatePreNavigatedField(_ placeholder: String) -> XCUIElement {
        safari.activate()
        let web = safari.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10), "Safari webview did not load (page must be pre-opened via simctl openurl)")
        for closeLabel in ["Chiudi", "Close", "OK", "Continua", "Continue"] {
            let x = safari.buttons.matching(NSPredicate(format: "label == %@", closeLabel)).firstMatch
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

    /// Enable Italian, move it before English in the active-language editor, then prove the circular
    /// order JP→IT→EN→JP. English and Italian still share one physical Latin QWERTY tab.
    /// イタリア語を英語より前へ移動し、JP→IT→EN→JPの巡回順を確認する。
    ///
    /// SIMULATOR PREREQUISITES (the App Group is not provisioned on an unsigned simulator build, so
    /// the app and the extension end up with SEPARATE "group.com.pettipol.copaky" domains — flipping
    /// or reordering in the app does NOT reach the keyboard here; on a real device it does). For this
    /// reordered-cycle test the orchestrator must seed the exact array and flush cfprefsd:
    ///   P=~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/group.com.pettipol.copaky.plist
    ///   killall cfprefsd
    ///   /usr/libexec/PlistBuddy -c "Delete :active_keyboard_languages_order" "$P" 2>/dev/null || true
    ///   /usr/libexec/PlistBuddy -c "Add :active_keyboard_languages_order array" "$P"
    ///   /usr/libexec/PlistBuddy -c "Add :active_keyboard_languages_order:0 string ja_JP" "$P"
    ///   /usr/libexec/PlistBuddy -c "Add :active_keyboard_languages_order:1 string it_IT" "$P"
    ///   /usr/libexec/PlistBuddy -c "Add :active_keyboard_languages_order:2 string en_US" "$P"
    ///   /usr/libexec/PlistBuddy -c "Add :enable_italian_keyboard_language bool true" "$P"
    ///   /usr/libexec/PlistBuddy -c "Add :keyboard_type string flick" "$P"
    ///   /usr/libexec/PlistBuddy -c "Add :keyboard_type_en string roman" "$P"
    ///   killall cfprefsd
    /// `keyboard_type_en=roman` exposes the cycle key; JP stays flick. A signed run also proves the
    /// live first-Latin reseed; a persistent unsigned extension may retain a manual Latin choice.
    func test33_italianJoinsTheLanguageCycle() throws {
        // 1. Exercise the inline editor itself: enable IT, establish EN→IT, then drag IT before EN.
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        guard revealActiveLanguagesEditor() else {
            dump(mainApp, "33-no-active-languages-editor")
            XCTFail("Active-languages editor not found in MainApp settings")
            return
        }
        let japaneseRow = activeLanguageElement(identifier: L.japaneseLanguageRowIdentifier)
        let englishRow = activeLanguageElement(identifier: L.englishLanguageRowIdentifier)
        let italianRow = activeLanguageElement(identifier: L.italianLanguageRowIdentifier)
        guard japaneseRow.exists, englishRow.exists, italianRow.exists,
              firstMatch(in: mainApp, labels: L.pinnedFirst, timeout: 2) != nil else {
            dump(mainApp, "33-active-language-rows-incomplete")
            XCTFail("JP pinned row or EN/IT rows missing from the active-languages editor")
            return
        }
        guard setItalianActive(true) else {
            dump(mainApp, "33-italian-not-active")
            XCTFail("Italian activation toggle did not turn ON")
            return
        }
        guard setLatinLanguageOrder(italianFirst: false) else {
            dump(mainApp, "33-reorder-failed")
            XCTFail("Could not establish canonical English-before-Italian order")
            return
        }
        if isDevice {
            // Make the live extension observe the intermediate canonical list. This gives the next
            // appearance a real EN→IT-first setting transition even when its static state survived
            // an earlier test invocation.
            _ = activatePreNavigatedField("plain-text")
            switchToCopaky(in: safari)
            mainApp.activate()
            openSettingsTab()
            guard revealActiveLanguagesEditor() else {
                XCTFail("Active-languages editor disappeared after the live-reseed baseline")
                return
            }
        }
        guard setLatinLanguageOrder(italianFirst: true) else {
            dump(mainApp, "33-reorder-failed")
            XCTFail("Could not move Italian before English through EditMode/onMove")
            return
        }
        let pinnedAfterMove = activeLanguageElement(identifier: L.japaneseLanguageRowIdentifier)
        let englishAfterMove = activeLanguageElement(identifier: L.englishLanguageRowIdentifier)
        let italianAfterMove = activeLanguageElement(identifier: L.italianLanguageRowIdentifier)
        XCTAssertLessThan(pinnedAfterMove.frame.midY, italianAfterMove.frame.midY, "Japanese must stay pinned above Italian")
        XCTAssertLessThan(pinnedAfterMove.frame.midY, englishAfterMove.frame.midY, "Japanese must stay pinned above English")
        XCTAssertLessThan(italianAfterMove.frame.midY, englishAfterMove.frame.midY, "Italian must be ordered before English")
        shot("33-active-languages-jp-it-en")

        var restoreCanonicalOrder = true
        defer {
            if restoreCanonicalOrder {
                mainApp.activate()
                openSettingsTab()
                _ = revealActiveLanguagesEditor()
                _ = setLatinLanguageOrder(italianFirst: false)
            }
        }

        // 2. Start on JP flick. On a signed run the observed list change makes ABC enter IT first.
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        switchToJapaneseFlickTab(in: safari)
        let abcKey = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "ABC")).firstMatch
        guard abcKey.waitForExistence(timeout: 3), abcKey.isHittable else {
            dump(safari, "33-no-abc-from-japanese")
            XCTFail("ABC key missing on the Japanese flick tab")
            return
        }
        abcKey.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let seededItalianLatin = latinQwertyVisible(in: safari, timeout: 4)
        let seededFlick = flickKanaVisible(in: safari)
        XCTAssertTrue(seededItalianLatin, "JP→IT must land on Latin QWERTY")
        XCTAssertFalse(seededFlick, "JP→IT must not remain on Japanese flick")
        if isDevice {
            // 3 (device). The shared App Group lets the extension observe the app-side reorder, so
            // the STRICT proof runs: IT is the first Latin, and the key closes IT→EN→JP in order.
            guard let italianCurrent = languageSwitchElement(current: "IT", next: "A", in: safari) else {
                dump(safari, "33-first-latin-not-italian")
                XCTFail("Reordered JP→IT→EN list did not expose Italian as the first Latin language")
                return
            }
            tapLanguageSwitch(italianCurrent, in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            XCTAssertTrue(latinQwertyVisible(in: safari, timeout: 4), "IT→EN must stay on Latin QWERTY")

            guard let toJapanese = languageSwitchElement(current: "A", next: "あ", in: safari) else {
                dump(safari, "33-en-to-jp-key-missing")
                XCTFail("English language key did not offer Japanese next")
                return
            }
            tapLanguageSwitch(toJapanese, in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            XCTAssertTrue(flickKanaVisible(in: safari, timeout: 4), "EN→JP must close the cycle on Japanese flick")
            shot("33-cycle-jp-it-en-jp")
        } else {
            // 3 (Simulator). Split preference domains: the unsigned extension can NEVER observe the
            // app-side reorder, so the reordered-cycle proof is impossible here by construction. The
            // honest keyboard-phase check is that the key cycles the SEEDED canonical list
            // (JP▸EN▸IT): A→IT, IT→あ, and the tap closes on the flick tab. The reordered cycle
            // stays a device assert above; the editor-side reorder was already proven on the rows.
            var englishCurrent = languageSwitchElement(current: "A", next: "IT", in: safari)
            if englishCurrent == nil {
                // ABC lands on whichever Latin was last active; align to EN via the direct menu.
                guard selectActiveLanguageMenuIndex(1, in: safari) else { return }
                englishCurrent = languageSwitchElement(current: "A", next: "IT", in: safari)
            }
            guard let englishCurrent else {
                dump(safari, "33-seeded-canonical-en-missing")
                XCTFail("Seeded canonical list did not expose English with Italian next")
                return
            }
            tapLanguageSwitch(englishCurrent, in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            XCTAssertTrue(latinQwertyVisible(in: safari, timeout: 4), "EN→IT must stay on Latin QWERTY")
            guard let italianKey = languageSwitchElement(current: "IT", next: "あ", in: safari) else {
                dump(safari, "33-seeded-canonical-it-missing")
                XCTFail("EN→IT did not reach Italian with Japanese next under the seeded canonical order")
                return
            }
            tapLanguageSwitch(italianKey, in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            XCTAssertTrue(flickKanaVisible(in: safari, timeout: 4), "IT→JP must close the seeded canonical cycle on Japanese flick")
            shot("33-cycle-canonical-sim")
        }

        // 4. Do not leak the noncanonical order into test35/test37/test42 or later standalone runs.
        mainApp.activate()
        openSettingsTab()
        guard revealActiveLanguagesEditor(), setLatinLanguageOrder(italianFirst: false) else {
            dump(mainApp, "33-canonical-restore-failed")
            XCTFail("Could not restore canonical JP→EN→IT order after the reordered-cycle test")
            return
        }
        restoreCanonicalOrder = false
        shot("33-restored-jp-en-it")
    }

    // MARK: - 33b · Direct active-language menu + Japanese flick integrity

    /// One held gesture selects every direct-menu index in whichever EN/IT order the extension
    /// actually loaded. Each selection starts from a different language; Latin targets must never
    /// fall through to Japanese flick. JP must preserve its grid and the 空白 conversion behavior.
    /// 拡張が読み込んだEN/IT順で全候補を選び、異なる言語からの遷移・FLICK誤遷移・日本語配列を検証する。
    ///
    /// Simulator seed: either Latin order is accepted, but IT must be active. Also seed
    /// `keyboard_type=flick` and `keyboard_type_en=roman`.
    func test33b_longPressLanguageMenuSelectsEveryActiveLanguage() throws {
        // Establish canonical order through the real editor on signed runs; the legacy seed supplies
        // the same order on an unsigned Simulator where App Group writes cannot cross processes.
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        guard revealActiveLanguagesEditor(),
              setItalianActive(true),
              setLatinLanguageOrder(italianFirst: false) else {
            dump(mainApp, "33b-canonical-list-not-ready")
            XCTFail("Could not establish canonical JP→EN→IT active languages")
            return
        }
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "33b-no-initial-latin-qwerty")
            XCTFail("Latin QWERTY not reached before opening the language menu")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)

        guard let loadedState = currentLanguageSwitchState(in: safari) else {
            dump(safari, "33b-language-order-unreadable")
            XCTFail("Could not read the extension's current/next language state")
            return
        }
        let italianFirst: Bool
        switch (loadedState.current, loadedState.next) {
        case ("IT", "A"), ("A", "あ"):
            italianFirst = true
        case ("A", "IT"), ("IT", "あ"):
            italianFirst = false
        default:
            dump(safari, "33b-unexpected-language-state")
            XCTFail("Unexpected Latin language state \(loadedState.current)→\(loadedState.next)")
            return
        }
        let firstLatin = italianFirst ? "IT" : "A"
        let secondLatin = italianFirst ? "A" : "IT"

        for index in 0..<3 {
            if !latinQwertyVisible(in: safari, timeout: 0.5) {
                guard switchToLatinQwertyTab(in: safari) else {
                    dump(safari, "33b-no-latin-source-index-\(index)")
                    XCTFail("Could not return to Latin QWERTY before menu index \(index)")
                    return
                }
            }
            if index == 1 {
                // Index 1 targets the first Latin language. Start from the second so a no-op menu
                // action cannot pass. Returning from JP may preserve either previous Latin state.
                guard let source = currentLanguageSwitchState(in: safari) else { return }
                if source.current == firstLatin {
                    tapLanguageSwitch(source.element, in: safari)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                }
                guard languageSwitchElement(
                    current: secondLatin,
                    next: "あ",
                    in: safari
                ) != nil else {
                    dump(safari, "33b-index-1-source-not-second-latin")
                    XCTFail("Menu index 1 must start from the second Latin language")
                    return
                }
            } else if index == 2 {
                // Index 2 targets the second Latin language; index 1 must have left the first active.
                guard languageSwitchElement(
                    current: firstLatin,
                    next: secondLatin,
                    in: safari
                ) != nil else {
                    dump(safari, "33b-index-2-source-not-first-latin")
                    XCTFail("Menu index 2 must start from the first Latin language")
                    return
                }
            }
            guard selectActiveLanguageMenuIndex(index, in: safari) else { return }

            switch index {
            case 0:
                let flickVisible = flickKanaVisible(in: safari, timeout: 4)
                let latinVisible = latinQwertyVisible(in: safari, timeout: 0.3)
                XCTAssertTrue(flickVisible, "Menu index 0 (JP) must land on Japanese flick")
                XCTAssertFalse(latinVisible, "Menu index 0 (JP) must not stay on Latin QWERTY")
                guard flickVisible else { return }

                let exactJapaneseSpace = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", "空白")).firstMatch
                guard exactJapaneseSpace.waitForExistence(timeout: 4) else {
                    dump(safari, "33b-jp-space-missing")
                    XCTFail("Japanese flick space key must remain exactly 「空白」")
                    return
                }

                let expectedRows = [
                    ["あ", "か", "さ"],
                    ["た", "な", "は"],
                    ["ま", "や", "ら"],
                ]
                var rowMidpoints: [CGFloat] = []
                var middleColumnX: CGFloat?
                for (rowIndex, labels) in expectedRows.enumerated() {
                    let keys = labels.map { label in
                        safari.descendants(matching: .any)
                            .matching(NSPredicate(format: "label == %@", label)).firstMatch
                    }
                    guard keys.allSatisfy({ $0.waitForExistence(timeout: 3) }) else {
                        dump(safari, "33b-jp-row-\(rowIndex)-missing")
                        XCTFail("Japanese flick row \(labels) is incomplete")
                        return
                    }
                    XCTAssertLessThan(keys[0].frame.midX, keys[1].frame.midX, "Japanese flick row \(rowIndex) changed column order")
                    XCTAssertLessThan(keys[1].frame.midX, keys[2].frame.midX, "Japanese flick row \(rowIndex) changed column order")
                    let ys = keys.map { $0.frame.midY }
                    let ySpread = (ys.max() ?? 0) - (ys.min() ?? 0)
                    XCTAssertLessThan(ySpread, 12, "Japanese flick row \(rowIndex) is no longer horizontally aligned")
                    rowMidpoints.append(ys.reduce(0, +) / CGFloat(ys.count))
                    if rowIndex == 1 { middleColumnX = keys[1].frame.midX }
                }
                XCTAssertLessThan(rowMidpoints[0], rowMidpoints[1], "Japanese flick first/second rows swapped")
                XCTAssertLessThan(rowMidpoints[1], rowMidpoints[2], "Japanese flick second/third rows swapped")

                let wa = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", "わ")).firstMatch
                guard wa.waitForExistence(timeout: 3), let middleColumnX else {
                    dump(safari, "33b-jp-wa-missing")
                    XCTFail("Japanese flick bottom-row 「わ」 key missing")
                    return
                }
                XCTAssertGreaterThan(wa.frame.midY, rowMidpoints[2], "Japanese flick 「わ」 must stay below the third kana row")
                XCTAssertLessThan(abs(wa.frame.midX - middleColumnX), 12, "Japanese flick 「わ」 left its middle column")
                XCTAssertGreaterThan(exactJapaneseSpace.frame.midX, wa.frame.midX, "Japanese 「空白」 key must stay in the right system-key column")

                clearFocusedField(field, placeholder: "plain-text", in: safari)
                tapKeys(["か", "な"], in: safari)
                let candidate = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", "仮名")).firstMatch
                guard candidate.waitForExistence(timeout: 4) else {
                    dump(safari, "33b-jp-kana-candidate-missing")
                    XCTFail("Japanese flick か+な must offer 仮名")
                    return
                }
                let beforeSpace = field.value as? String ?? ""
                let conversionSpace = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", "空白")).firstMatch
                guard conversionSpace.exists, conversionSpace.isHittable else {
                    XCTFail("Japanese conversion key lost its exact 「空白」 label while composing")
                    return
                }
                conversionSpace.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
                let afterSpace = field.value as? String ?? ""
                XCTAssertNotEqual(afterSpace, beforeSpace, "Japanese 「空白」 conversion action was a no-op")
                XCTAssertTrue(
                    afterSpace.contains("仮名"),
                    "Japanese 「空白」 must immediately commit the visible 仮名 conversion"
                )
                shot("33b-menu-japanese-intact")

            case 1:
                // Anti-regression: assert the raw result immediately, before any corrective helper.
                let latinVisible = latinQwertyVisible(in: safari, timeout: 4)
                let flickVisible = flickKanaVisible(in: safari)
                XCTAssertTrue(latinVisible, "Menu index 1 (\(firstLatin)) must land on Latin QWERTY")
                XCTAssertFalse(flickVisible, "Menu index 1 (\(firstLatin)) must NOT land on Japanese flick")
                guard languageSwitchElement(
                    current: firstLatin,
                    next: secondLatin,
                    in: safari
                ) != nil else {
                    dump(safari, "33b-menu-first-latin-wrong-language")
                    XCTFail("Menu index 1 did not select the first active Latin language \(firstLatin)")
                    return
                }
                shot("33b-menu-first-latin")

            case 2:
                // Explicit test35-quirk guard: no fallback to ABC/switchToLatin is allowed here.
                let latinVisible = latinQwertyVisible(in: safari, timeout: 4)
                let flickVisible = flickKanaVisible(in: safari)
                XCTAssertTrue(latinVisible, "Menu index 2 (\(secondLatin)) must land on Latin QWERTY")
                XCTAssertFalse(flickVisible, "Menu index 2 (\(secondLatin)) must NOT land on Japanese flick")
                guard languageSwitchElement(
                    current: secondLatin,
                    next: "あ",
                    in: safari
                ) != nil else {
                    dump(safari, "33b-menu-second-latin-wrong-language")
                    XCTFail("Menu index 2 did not select the second active Latin language \(secondLatin)")
                    return
                }
                shot("33b-menu-second-latin")

            default:
                XCTFail("Unexpected active-language menu index \(index)")
            }
        }
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
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "35-no-initial-latin-qwerty")
            shot("35-no-initial-latin-qwerty")
            XCTFail("Latin QWERTY not reached before selecting Italian; seed keyboard_type_en=roman")
            return
        }
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
            // A failed probe may cycle IT → JP; re-establish Latin immediately before every typing run.
            // 候補が出ない時は IT → JP を通るため、各入力の直前にラテン文字タブを再確認する。
            guard switchToLatinQwertyTab(in: safari) else {
                dump(safari, "35-no-latin-qwerty-attempt-\(attempts)")
                shot("35-no-latin-qwerty-attempt-\(attempts)")
                XCTFail("Latin QWERTY not reached before typing Italian probe attempt \(attempts + 1)")
                return
            }
            tapKeys(["p", "e", "r", "c", "h", "e"], in: safari)
            if accented.waitForExistence(timeout: 3) {
                break
            }
            // wrong Latin language (or still English): clear and cycle the language key once
            for _ in 0..<6 {
                let del = safari.descendants(matching: .any)
                    .matching(NSPredicate(format: "label IN %@ OR identifier IN %@", L.deleteKey, L.deleteKeyIdentifiers)).firstMatch
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

        // Latin tab: localized caps. Use the shared list: the it-IT catalog caps the key
        // lowercase «spazio» (空白 → en "space" / it "spazio"), which the old inline
        // ["space", "Spazio"] list missed — measured 29/08 (21ª) on the it-IT Pro Max.
        // ラテンタブのキャップは端末言語に従う（it-ITは小文字「spazio」）。共有リストで照合する。
        switchToEnglishTab(in: safari)
        let latinSpace = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.spaceKey.filter { $0 != "空白" })).firstMatch
        if !latinSpace.waitForExistence(timeout: 4) {
            dump(safari, "36-no-latin-space")
            shot("36-no-latin-space")
        }
        XCTAssertTrue(latinSpace.exists, "the Latin tab must cap its space key in the device language, not in Japanese")
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

    // MARK: - 61 · H-46 ambiguous Italian accent, general autocorrect OFF and ON

    /// Copaky: run twice with explicit seeds: italian_auto_accent_on_space=true,
    /// live_conversion=false, enable_latin_autocorrect=false/true and matching
    /// TEST_RUNNER_COPAKY_EXPECT_LATIN_AUTOCORRECT. Live conversion must stay OFF so that a
    /// rejected correction cannot still commit lastUsedCandidate instead of the literal word.
    /// Copaky: 一般補正のOFF/ONを別実行で確認。設定は変更せず読み、実キーで否定例と肯定例を検証する。
    func test61_italianAmbiguousAccentPreservesCosi() throws {
        // Copaky: pre-opened Safari hit the background scene watchdog while releasing its keyboard
        // during MainApp setup. Stop that process first; the fixture is restored when reactivated.
        safari.terminate()
        let environment = ProcessInfo.processInfo.environment
        // xcodebuild forwards TEST_RUNNER_* to the test process without that prefix.
        let expected = environment["COPAKY_EXPECT_LATIN_AUTOCORRECT"]
            ?? environment["TEST_RUNNER_COPAKY_EXPECT_LATIN_AUTOCORRECT"]
        guard let expected, ["false", "true"].contains(expected) else {
            XCTFail("H-46 prerequisite: TEST_RUNNER_COPAKY_EXPECT_LATIN_AUTOCORRECT must be explicitly false or true")
            return
        }
        let mode = expected == "true" ? "on" : "off"
        let dictionaries = UITextChecker.availableLanguages.map {
            $0.replacingOccurrences(of: "_", with: "-").lowercased()
        }
        guard dictionaries.contains("it-it") else {
            XCTFail("H-46 prerequisite: the it-IT spell-check dictionary is required for the positive control")
            return
        }
        func fail(_ app: XCUIApplication, _ name: String, _ message: String) {
            dump(app, "61-general-\(mode)-\(name)")
            shot("61-general-\(mode)-\(name)")
            XCTFail(message)
        }

        mainApp.terminate()
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) { close.tap() }
        openSettingsTab()
        let contracts: [(key: String, labels: [String], value: String)] = [
            ("live_conversion", ["ライブ変換", "Live Conversion", "Conversione live"], "0"),
            ("italian_auto_accent_on_space", L.italianAutoAccentToggle, "1"),
            ("enable_latin_autocorrect", ["ラテン文字の自動修正", "Autocorrect typos (Latin keyboards)",
                                          "Correzione automatica dei refusi (tastiere latine)"], expected == "true" ? "1" : "0"),
        ]
        for contract in contracts {
            let toggle = mainApp.switches.matching(NSPredicate(format: "label IN %@", contract.labels)).firstMatch
            // Search both directions because the Form can retain its previous scroll offset.
            for _ in 0..<8 where !toggle.exists || !toggle.isHittable {
                mainApp.swipeDown()
                dismissMainAppAlertIfAny()
            }
            for _ in 0..<10 where !toggle.exists || !toggle.isHittable {
                mainApp.swipeUp()
                dismissMainAppAlertIfAny()
            }
            guard toggle.exists, toggle.isHittable, waitForFieldValue(toggle, contract.value) else {
                let observed = toggle.exists ? String(describing: toggle.value) : "missing"
                fail(mainApp, "seed-mismatch-\(contract.key)",
                     "H-46 prerequisite: seeded \(contract.key) must read \(contract.value) in MainApp; got \(observed)")
                return
            }
            print("H46-SETTING|\(contract.key)|\(contract.value)")
            shot("61-general-\(mode)-setting-\(contract.key)")
        }

        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        // As in test03, presence in the AX tree alone does not prove an onscreen keyboard.
        var presented = false
        for attempt in 0..<2 {
            let deadline = Date().addingTimeInterval(attempt == 0 ? 3 : 6)
            repeat {
                let controls = safari.descendants(matching: .any).matching(NSPredicate(
                    format: "identifier == %@ OR identifier BEGINSWITH %@",
                    "keyboard-flick-star-123", "keyboard-language-switch-"
                ))
                presented = controls.allElementsBoundByIndex.contains { $0.exists && $0.isHittable }
                if presented { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            } while Date() < deadline
            if presented { break }
            if attempt == 0, field.exists, field.isHittable {
                dump(safari, "61-general-\(mode)-before-refocus")
                shot("61-general-\(mode)-before-refocus")
                field.tap()
            }
        }
        guard presented, switchToLatinQwertyTab(in: safari) else {
            fail(safari, "no-latin-keyboard", "H-46 prerequisite: no hittable Copaky Latin keyboard after one refocus")
            return
        }
        for _ in 0..<3 {
            guard let state = currentLanguageSwitchState(in: safari, timeout: 2), state.element.isHittable else {
                fail(safari, "no-language-key", "H-46 prerequisite: Copaky language-switch identifier missing")
                return
            }
            if state.current == "IT" { break }
            tapLanguageSwitch(state.element, in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            guard switchToLatinQwertyTab(in: safari) else {
                fail(safari, "lost-latin-keyboard", "H-46 prerequisite: could not reach the Italian Latin tab")
                return
            }
        }
        guard currentLanguageSwitchState(in: safari, timeout: 2)?.current == "IT" else {
            fail(safari, "italian-not-active", "H-46 prerequisite: current keyboard language must be IT")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)

        var prefix = ""
        for (word, committed) in [("cosi", "cosi "), ("perche", "perché ")] {
            for character in word {
                let keys = safari.staticTexts.matching(NSPredicate(
                    format: "label == %@ AND NOT (identifier BEGINSWITH %@)",
                    String(character), "keyboard-language-switch-"
                ))
                guard let key = keys.allElementsBoundByIndex.first(where: {
                    $0.exists && $0.isHittable && $0.frame.minY >= safari.frame.height * 0.45
                }) else {
                    fail(safari, "missing-key-\(character)", "H-46 prerequisite: lowercase Copaky letter key missing; seed auto-capitalization OFF")
                    return
                }
                key.tap()
            }
            guard waitForFieldValue(field, prefix + word) else {
                fail(safari, "typing-\(word)", "H-46: literal input must equal \(prefix + word) before space; got \(String(describing: field.value))")
                return
            }
            tapLatinSpace(in: safari)
            guard waitForFieldValue(field, prefix + committed) else {
                fail(safari, "commit-\(word)", "H-46: space must commit \(prefix + committed) with general autocorrect \(mode); got \(String(describing: field.value))")
                return
            }
            shot("61-general-\(mode)-committed-\(word)")
            prefix += committed
        }
        print("H46-RESULT|general=\(expected)|autoaccent=true|live_conversion=false|cosi=unchanged|perche=perché|PASS")
    }

    // MARK: - 38 · Latin number tab keeps Latin punctuation and return target

    /// Copaky: the QWERTY number tab must type a literal dot and return to its originating Latin tab.
    /// Copaky: QWERTY数字タブは半角ピリオドを入力し、元のラテン文字タブへ戻る。
    func test38_latinNumbersTabReturnsToLatin() throws {
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)

        guard switchToLatinQwertyTab(in: safari) else {
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
        let returnedToLatin = latinQwertyVisible(in: safari, timeout: 4)
        if !returnedToLatin {
            dump(safari, "38-did-not-return-to-latin")
        }
        shot("38-latin-return")
        XCTAssertEqual(value, ".", "Latin numbers tab must input a literal ASCII dot")
        XCTAssertFalse(value.contains("。") || value.contains("．"), "No Japanese/full-width dot may be input")
        XCTAssertTrue(returnedToLatin, "Numbers-tab back key returned to Japanese or stayed on numbers")
    }

    // MARK: - 39 · One-gesture Clipboard history from the Latin 123 slot

    /// Copaky: with Clipboard history enabled, one long press on the Latin 123 key opens its tab.
    /// Simulator seed: `keyboard_type_en=roman`, `enable_clipboard_history_manager_tab=true`,
    /// `display_tab_bar_button=true`, and `use_shift_key=false` (the optional button is used only to
    /// prove the prerequisite; no-shift keeps the 123 slot present);
    /// the clipboard tab also needs Full Access and the signed App Group container. An unavailable
    /// Simulator is skipped with the same prerequisite wording used by test14.
    /// Copaky: クリップボード履歴ON時、ラテン123キーの長押し1回で履歴タブを開く。
    func test39_longPressNumbersKeyOpensClipboardHistory() throws {
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)

        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "39-no-initial-latin-qwerty")
            shot("39-no-initial-latin-qwerty")
            XCTFail("Latin QWERTY not reached; seed keyboard_type_en=roman")
            return
        }

        // Prove that Clipboard history is actually available before testing the gesture. This keeps
        // the unsigned-Simulator prerequisite skip, but a signed Simulator with the seeded App Group
        // can no longer turn an A-11 regression into a skip. Leaving the bar visible is intentional:
        // a stale `.setTabBar(.toggle)` action would close it, while the new action opens the panel.
        func clipboardTabItem() -> XCUIElement? {
            let symbolPred = NSPredicate(format: "identifier CONTAINS 'doc.badge.clock' OR label CONTAINS 'doc.badge.clock'")
            let symbol = safari.descendants(matching: .any).matching(symbolPred).firstMatch
            if symbol.exists, symbol.isHittable { return symbol }
            return firstMatch(in: safari, labels: L.clipboardTab, timeout: 1)
        }
        if clipboardTabItem() == nil,
           let barButton = firstMatch(in: safari, labels: L.tabBarButton, timeout: 3),
           barButton.isHittable {
            barButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        guard clipboardTabItem() != nil else {
            dump(safari, "39-clipboard-prerequisite-unavailable")
            shot("39-clipboard-prerequisite-unavailable")
            // Prerequisite (App Group + Full Access + the setting on), not the gesture under test: skip with
            // the reason on every build — the same contract as test14.
            throw XCTSkip("Clipboard tab not reachable on this build (App Group / Full Access / «Save clipboard history» off) — prerequisite, not a long-press failure; on a signed build seed the setting and grant Full Access first.")
        }

        // Copaky [G-04] (05/09): «#+=» is NOT a default long-press slot any more (123 + ☆123 are; #+= is
        // optional). With it in the list, firstMatch sometimes picked the «#+=» StaticText instead of the 123
        // Image (identifier textformat.123) and the long press did nothing — round 12 of the 24th session.
        let numberKeyLabels = ["123", "numbers", "Numbers", "numeri", "Numeri", "数字", "textformat.123", "textformat.numbers"]
        guard longPressClipboardShortcut(labels: numberKeyLabels) else {
            dump(safari, "39-numbers-key-not-found")
            shot("39-numbers-key-not-found")
            XCTFail("Latin QWERTY numbers key not found")
            return
        }

        let marker = firstMatch(
            in: safari,
            labels: L.backKey + ["ピン留め", "Pinned", "Fissati"],
            timeout: 4
        )
        let opened = marker != nil && clipboardPanelIsOpen(timeout: 2)
        if !opened {
            dump(safari, "39-clipboard-not-open")
            shot("39-clipboard-not-open")
            XCTFail("Long-pressing the Latin 123 key did not open Clipboard history")
            return
        }

        XCTAssertTrue(opened, "Long-pressing the Latin 123 key must open Clipboard history directly")
        shot("39-clipboard-open")

        // Copaky: touch-up must release the exact reservation so the same long press remains reusable
        // after returning from Clipboard history.
        // Copaky: touch-upで同じ予約を解放し、履歴から戻った後も同じ長押しを再利用できること。
        guard let clipboardBack = clipboardBackKey(in: safari, timeout: 4),
              clipboardBack.isHittable else {
            dump(safari, "39-clipboard-back-not-found")
            shot("39-clipboard-back-not-found")
            XCTFail("Clipboard history back key not found")
            return
        }
        clipboardBack.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        guard latinQwertyVisible(in: safari, timeout: 4) else {
            dump(safari, "39-latin-qwerty-did-not-return")
            shot("39-latin-qwerty-did-not-return")
            XCTFail("Clipboard history back key did not return to Latin QWERTY")
            return
        }
        shot("39-latin-qwerty-returned")

        // The shared helper re-queries after the tab transition; the first key view is gone.
        // タブ遷移後は削除済みビューを再利用せず、123キーを取り直す。
        guard longPressClipboardShortcut(labels: numberKeyLabels) else {
            dump(safari, "39-second-numbers-key-not-found")
            shot("39-second-numbers-key-not-found")
            XCTFail("Latin QWERTY numbers key not found after returning from Clipboard history")
            return
        }

        let secondMarker = firstMatch(
            in: safari,
            labels: L.backKey + ["ピン留め", "Pinned", "Fissati"],
            timeout: 4
        )
        let reopened = secondMarker != nil && clipboardPanelIsOpen(timeout: 2)
        if !reopened {
            dump(safari, "39-clipboard-not-open-second-time")
            shot("39-clipboard-not-open-second-time")
            XCTFail("Long-pressing the Latin 123 key did not reopen Clipboard history")
            return
        }

        XCTAssertTrue(reopened, "The Latin 123 long press must open Clipboard history repeatedly")
        shot("39-clipboard-open-second-time")
    }

    // MARK: - 34 · Copaky extension: the system paste control renders inside the input view

    /// Apple does not document putting `UIPasteControl` inside a keyboard extension's input view, so
    /// the first thing to establish is whether it even DRAWS there. This test does not — and cannot —
    /// prove the paste itself: the paste dialog does not exist on the Simulator, so only a device
    /// round can tell us whether the banner really disappears.
    /// Prerequisites (orchestrator): use_system_paste_control + enable_clipboard_history_manager_tab
    /// enabled on the phone, with Full Access already granted. Simulator execution is skipped.
    /// UIPasteControl はSimulatorのキーボード拡張では描画されないため、実機のみで検証する。
    func test34_systemPasteControlRendersInKeyboard() throws {
        guard isDevice else {
            throw XCTSkip("UIPasteControl never renders inside a keyboard extension on Simulator; test40 is the authoritative device check (passed on the phone on 2026-08-26).")
        }
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard let clipboardTab = firstMatch(in: safari, labels: L.clipboardTab, timeout: 6) else {
            dump(safari, "34-no-clipboard-tab")
            throw XCTSkip("Clipboard tab not on the bar — Full Access or the tab setting is off on this device/build")
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
        // Budget 10, NOT 4: scroll rounds spend from the same counter, and on the narrower real
        // iPhone 17 Pro the A-04/B-03/E-09 rows push deep rows (the clipboard toggle) beyond four
        // swipes — measured 29/08 (21ª): the run ended at the bottom of the Form without ever
        // resolving the row. Ten rounds cover the full Settings list on every current device.
        // 実機ProではB-03/E-09の新行で4スワイプでは届かない（実測）。予算を10に。
        while taps < 10 {
            // Re-resolve and re-check EVERY round: SwiftUI Forms virtualize rows, and on the
            // smaller phone the A-04/B-03 rows push this switch to the render-window edge — it can
            // vanish from the tree between the existence guard and a coordinate tap, which then
            // fails HARD ("Failed to get matching snapshot", measured on device, 20th session).
            // 毎回再解決する：Form の仮想化で行が消えると座標タップは致命的エラーになる（実測）。
            let sw = current()
            if !sw.exists {
                mainApp.swipeUp()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                taps += 1
                continue
            }
            if sw.value as? String == wanted { break }
            sw.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            // enabling the clipboard history raises a confirmation alert; dismiss whatever appears
            let alertOK = mainApp.alerts.buttons
                .matching(NSPredicate(format: "label == %@", "OK")).firstMatch
            if alertOK.waitForExistence(timeout: 1.5) { alertOK.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            taps += 1
        }
        return current().exists && current().value as? String == wanted
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
        // activate(), NOT launch(): launch() terminates Safari and discards the very page the
        // orchestrator pre-navigated, and on a REAL phone Safari restores the USER's tabs anyway
        // (measured 20th session: the front tab was an unrelated user page in three runs).
        // Self-navigate from the address bar when the qa page is not already up.
        // launch()はSafariを終了させ事前ナビの頁を捨てる上、実機はユーザーのタブを復元する（実測）。
        // qaページが無ければアドレスバーから自前で移動する。
        safari.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        var copyButton = safari.webViews.buttons["Copy test marker"].firstMatch
        if !copyButton.waitForExistence(timeout: 6) {
            if focusSafariAddressBar() {
                safari.typeText("https://copaky.app/qa\n")
                RunLoop.current.run(until: Date().addingTimeInterval(3.0))
                copyButton = safari.webViews.buttons["Copy test marker"].firstMatch
            }
        }
        // Re-entry with a field still focused: the open keyboard shrinks the viewport and Safari
        // auto-scrolls to the field, parking the button at the top edge — it EXISTS in the tree
        // (measured 29/08, 21ª: frame y=-7) but is not hittable. Dismiss the keyboard via the
        // accessory-bar «Fine»/«Done» and scroll back up before giving up.
        // 再入時はキーボードでビューポートが縮み、ボタンが上端外へ（実測）。「完了」で閉じて上へ戻す。
        if copyButton.waitForExistence(timeout: 10), !copyButton.isHittable {
            let done = safari.buttons
                .matching(NSPredicate(format: "label IN %@", ["Fine", "Done", "完了"])).firstMatch
            if done.exists, done.isHittable { done.tap() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            if !copyButton.isHittable {
                safari.swipeDown()
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            }
            copyButton = safari.webViews.buttons["Copy test marker"].firstMatch
        }
        guard copyButton.waitForExistence(timeout: 10), copyButton.isHittable else {
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
        // 0 — prime iOS's per-app paste settings row. On a virgin install the row does not exist until
        // Copaky has read the pasteboard once, so establish the legacy capture path before navigating
        // Settings. / 初回は一度読み取るまで「他のAppからペースト」が作られない。
        XCTAssertTrue(enableCopakySetting(L.clipboardToggle), "Could not switch the clipboard tab ON")
        XCTAssertTrue(driveSwitch(L.systemPasteToggle, to: false),
                      "Could not switch OFF the system paste control for permission-row priming")
        _ = try seedMarkerFromQaPage(evidence: "41-prime")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        try openClipboardTab()
        var primingTapped = false
        for _ in 0..<3 {
            dismissCopakyNotice(in: safari)
            if let capture = firstMatch(in: safari, labels: L.captureBar, timeout: 4),
               capture.isHittable {
                capture.tap()
                primingTapped = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        guard primingTapped else {
            dump(safari, "41-prime-no-capture-bar")
            XCTFail("Old capture bar not found/hittable — paste-permission row cannot be primed")
            return
        }
        if let prompt = pastePrompt(timeout: 6) {
            let allow = prompt.buttons
                .matching(NSPredicate(format: "label IN %@", L.allowPasteButtons)).firstMatch
            guard allow.waitForExistence(timeout: 3), allow.isHittable else {
                dump(safari, "41-prime-prompt-without-allow")
                XCTFail("Paste prompt appeared during priming but no Allow Paste button was hittable")
                return
            }
            allow.tap()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // 1 — permission → ASK (the §10 precondition that voids every earlier "no banner" claim)
        try setPasteFromOtherApps(to: L.pasteAsk)
        shot("41-settings-baseline")

        // 2 — baseline arm: clipboard tab ON, capsule OFF (the OLD capture button must be on duty)
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

        // 3 — capsule under ASK: the observation the §10 decision hangs on
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

        // 4 — negative control: no fresh copy → a second tap must not conjure new content.
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

    /// Copaky [E-01]: retain millisecond timestamps so a skipped/instantaneous phase cannot look valid.
    /// Copaky: ミリ秒付き時刻で、未実行・瞬時終了のフェーズを隠さない。
    private func memcMarker(_ phase: String, _ edge: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        print("MEMC|\(phase)|\(edge)|\(formatter.string(from: Date()))")
    }

    /// Copaky: use our current-language identifier, independent of localized functional labels/order.
    /// Copaky: 機能ラベルの翻訳や言語順に依存せず、現在言語の識別子を確認する。
    private func ensureJapaneseTab(in app: XCUIApplication) -> Bool? {
        for attempt in 0..<4 {
            guard copakyActive(in: app) else { return nil }
            if flickKanaVisible(in: app, timeout: 1) { return true }
            guard let state = currentLanguageSwitchState(in: app, timeout: 1) else { return nil }
            if state.current == "あ" {
                let letter = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch
                return letter.waitForExistence(timeout: 2) ? false : nil
            }
            guard attempt < 3 else { return nil }
            tapLanguageSwitch(state.element, in: app)
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        return nil
    }

    /// Phase C supplies observable workloads; scripts/memory_phase_c.sh owns memory qualification.
    /// Copaky [E-01]: every required phase must run. Missing FA/App Group/IT prerequisites FAIL with
    /// evidence instead of producing a green partial load. Each load stays visible for >=3 seconds
    /// for the host's 1 Hz sampler. This does not qualify the absolute memory budget on Simulator.
    /// Copaky: 必須フェーズは省略不可。前提不足は明示的に失敗し、各負荷を3秒以上維持する。
    func test42_memoryPhaseC_japaneseTypingAcrossKana() throws {
        let kanaGroups: [[String]] = [
            ["か", "な"], ["さ", "か"], ["た", "な"], ["は", "な"], ["ま", "た"], ["や", "ま"],
            ["ら", "か"], ["わ", "た"], ["あ", "さ"], ["な", "ま"], ["か", "さ", "た"], ["は", "ま", "や"],
        ]
        #if targetEnvironment(simulator)
        let field = focusField("textarea-field")
        #else
        // The device runner pre-navigates Safari; localhost would address the phone itself.
        let field = activatePreNavigatedField("textarea-field")
        #endif
        switchToCopaky(in: safari)
        clearFocusedField(field, placeholder: "textarea-field", in: safari)

        // Copaky: PASS is emitted only after the body and the Copaky liveness check succeed.
        // Copaky: 負荷とCopaky生存確認の成功後だけPASSを出す。
        func runPhase(_ phase: String, _ body: () -> String?) -> Bool {
            memcMarker(phase, "start")
            let reason = body() ?? (copakyActive(in: safari) ? nil : "copaky-not-active-after-load")
            memcMarker(phase, "end")
            print("MEMC-RESULT|\(phase)|\(reason == nil ? "PASS" : "FAIL")|\(reason ?? "workload-observed")")
            guard let reason else { return true }
            note("42-\(phase)-failure", reason)
            dump(safari, "42-\(phase)-failure")
            shot("42-\(phase)-failure")
            XCTFail("Required memory phase \(phase) was not exercised: \(reason)")
            return false
        }
        func pressKeys(_ labels: [String]) -> Bool {
            guard copakyActive(in: safari) else { return false }
            for label in labels {
                let predicate = NSPredicate(format: "label ==[c] %@", label)
                let text = safari.staticTexts.matching(predicate).firstMatch
                let key = text.waitForExistence(timeout: 1) ? text
                    : safari.descendants(matching: .any).matching(predicate).firstMatch
                guard key.waitForExistence(timeout: 2), key.isHittable,
                      key.frame.minY >= safari.frame.height * 0.45 else { return false }
                key.tap()
            }
            return true
        }
        func fieldIsEmpty() -> Bool {
            let value = field.value as? String
            return value == "" || value == "textarea-field"
        }
        func typeJapaneseGroup(_ group: [String]) -> String? {
            guard let flick = ensureJapaneseTab(in: safari) else { return "japanese-tab-not-reached" }
            guard fieldIsEmpty() else { return "field-not-empty-before-japanese-load" }
            let romaji = ["あ": "a", "か": "ka", "さ": "sa", "た": "ta", "な": "na",
                          "は": "ha", "ま": "ma", "や": "ya", "ら": "ra", "わ": "wa"]
            let keys = flick ? group : group.flatMap { (romaji[$0] ?? "").map { String($0) } }
            guard pressKeys(keys) else { return "japanese-key-missing" }
            guard waitForFieldValue(field, group.joined()) else { return "japanese-text-not-inserted" }
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            clearFocusedField(field, placeholder: "textarea-field", in: safari)
            return fieldIsEmpty() ? nil : "japanese-load-did-not-clear"
        }

        memcMarker("begin", "start")
        for (index, group) in kanaGroups.enumerated() {
            guard runPhase("jp-\(index)", { typeJapaneseGroup(group) }) else { return }
        }

        guard runPhase("clipboard", {
            guard switchToLatinQwertyTab(in: safari), longPressClipboardShortcut(),
                  clipboardPanelIsOpen(timeout: 3) else {
                return "clipboard-not-opened-requires-full-access-signed-app-group-and-history-enabled"
            }
            shot("42-clipboard-open")
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            guard let back = clipboardBackKey(in: safari, timeout: 3), back.isHittable else {
                return "clipboard-back-key-missing"
            }
            back.tap()
            guard switchToLatinQwertyTab(in: safari), !clipboardPanelIsOpen(timeout: 1) else {
                return "keyboard-did-not-return-from-clipboard"
            }
            return nil
        }) else { return }

        guard runPhase("it", {
            // Select IT from the actual current/next identifier, including reordered active lists.
            // 実際の現在言語を確認し、並び替え済みリストでもITを選ぶ。
            for _ in 0..<3 {
                if currentLanguageSwitchState(in: safari, timeout: 1)?.current == "IT" { break }
                guard switchToLatinQwertyTab(in: safari),
                      let state = currentLanguageSwitchState(in: safari, timeout: 1) else {
                    return "italian-language-switch-unavailable"
                }
                if state.current == "IT" { break }
                tapLanguageSwitch(state.element, in: safari)
                RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            }
            guard currentLanguageSwitchState(in: safari, timeout: 2)?.current == "IT",
                  latinQwertyVisible(in: safari, timeout: 2) else { return "italian-not-active" }
            print("MEMC-INFO|latin-language-active|italian")
            for word in ["perche", "citta", "andro", "piu", "cosi", "puo", "societa", "grazie"] {
                let before = field.value as? String
                guard pressKeys(word.map { String($0) }) else { return "italian-key-missing" }
                tapLatinSpace(in: safari)
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                guard let after = field.value as? String, after != before, !after.isEmpty,
                      after != "textarea-field" else { return "italian-text-not-inserted" }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(3))
            guard currentLanguageSwitchState(in: safari, timeout: 1)?.current == "IT" else {
                return "italian-language-changed-during-load"
            }
            shot("42-italian-typed")
            clearFocusedField(field, placeholder: "textarea-field", in: safari)
            return fieldIsEmpty() ? nil : "italian-load-did-not-clear"
        }) else { return }

        for (index, group) in kanaGroups.prefix(3).enumerated() {
            guard runPhase("jp-final-\(index)", { typeJapaneseGroup(group) }) else { return }
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

    // MARK: - 46 · Copaky extension: real QWERTY number row grows without compressing letters

    /// Runs both states in one signed App Group session: OFF proves no standalone digit row, then ON
    /// proves the row, its tap action, and unchanged letter-key frames. Number hints are kept OFF so
    /// the two independent features remain distinguishable.
    func test46_realQwertyNumberRowPreservesLetterHeights() throws {
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        guard driveSwitch(L.realNumberRowToggle, to: false) else {
            dump(mainApp, "46-real-row-not-off")
            XCTFail("Could not switch the real QWERTY number row OFF; run test46 through scripts/run_ui_test.sh --fresh-install")
            return
        }
        guard driveSwitch(L.numberHintsToggle, to: false) else {
            dump(mainApp, "46-number-hints-not-off")
            XCTFail("Could not isolate B-03 by switching the independent number hints OFF")
            return
        }

        /// Resolve one key strictly inside the visual input region so matching page text cannot pass.
        /// XCUI match ORDER is not stable across runs (measured 20th session: the "a" query bound an
        /// element two rows below q in one run and the real key in the next, both stable in-run), so
        /// when a reference key frame is available, admit only KEY-SIZED candidates and take the
        /// topmost. / XCUIのマッチ順は run 間で不定（実測）。キー寸法の候補だけ許可し最上段を取る。
        func keyboardKey(labels: [String], sizedLike reference: CGRect? = nil) -> XCUIElement? {
            let matches = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "label IN %@", labels))
            let cutoff = safari.frame.height * 0.45
            var best: XCUIElement?
            var bestMinY = CGFloat.greatestFiniteMagnitude
            for index in 0..<min(matches.count, 12) {
                let element = matches.element(boundBy: index)
                guard element.exists else { continue }
                let frame = element.frame
                guard frame.minY >= cutoff else { continue }
                if let reference {
                    guard abs(frame.height - reference.height) <= reference.height * 0.3,
                          abs(frame.width - reference.width) <= reference.width * 0.5 else { continue }
                }
                if frame.minY < bestMinY {
                    bestMinY = frame.minY
                    best = element
                }
            }
            return best
        }

        /// Wait until the q-key frame stops moving: a frame captured mid-transition measured a
        /// 26 pt letter (measured 20th session, confirmation run) — the tab-switch/grow animation
        /// must finish before any geometry assert. / タブ切替アニメ中の計測を避ける（実測26ptの誤測定）。
        func settleKeyboardGeometry() {
            var previous = CGRect.null
            for _ in 0..<10 {
                guard let key = keyboardKey(labels: ["q", "Q"]) else {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                    continue
                }
                let current = key.frame
                if !previous.isNull,
                   abs(current.height - previous.height) < 0.5,
                   abs(current.midY - previous.midY) < 0.5 {
                    return
                }
                previous = current
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }

        func letterFrames(evidence: String) -> [CGRect]? {
            settleKeyboardGeometry()
            let labels = [["q", "Q"], ["a", "A"], ["z", "Z"]]
            var frames: [CGRect] = []
            for variants in labels {
                // q anchors the key size; a/z are then admitted only at key dimensions (see keyboardKey).
                guard let key = keyboardKey(labels: variants, sizedLike: frames.first), key.isHittable else {
                    dump(safari, "46-\(evidence)-letter-missing-\(variants[0])")
                    shot("46-\(evidence)-letter-missing-\(variants[0])")
                    XCTFail("QWERTY letter key \(variants) missing during the \(evidence) phase")
                    return nil
                }
                frames.append(key.frame)
            }
            return frames
        }

        let offField = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "46-off-latin-tab-missing")
            XCTFail("Could not establish the Latin QWERTY tab for the OFF baseline")
            return
        }
        clearFocusedField(offField, placeholder: "plain-text", in: safari)
        guard let offFrames = letterFrames(evidence: "off") else { return }
        // Copaky [G-05]: `sizedLike` keeps the number-row HINT digit (an 18 pt StaticText inside the
        // "t" key, exposed by XCUI) out of this check — only a letter-sized standalone "5" counts.
        XCTAssertNil(keyboardKey(labels: ["5"], sizedLike: offFrames.first), "A standalone 5 key exists while the real number row is OFF")
        shot("46-real-number-row-off")

        // Re-activating the SAME Safari/keyboard session after the MainApp round trip leaves the
        // field focused but never re-presents the keyboard body on the iOS 26 Simulator (measured
        // 20th session: 3 runs, keyboard window present, body absent; same-field re-taps and a
        // focus bounce both ineffective) — while the product path is healthy: the live flag flip on
        // the ALIVE process renders the 5-row Latin tab correctly when driven by hand. Like test33's
        // Simulator branch, prove the ON phase through first-entry semantics instead: terminate
        // Safari so the next activation starts a fresh keyboard session that reads the new setting.
        // iOS 26シミュレータではMainApp往復後の同一セッション再入でキーボード本体が再提示されない
        // （実測3回）。手動では生きたプロセスでも5段QWERTYが正しく出る＝プロダクトは健全。
        // test33と同じく「初回入場」の意味論で検証する：Safariを終了して新しいセッションで入る。
        safari.terminate()
        mainApp.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        openSettingsTab()
        guard driveSwitch(L.realNumberRowToggle, to: true) else {
            dump(mainApp, "46-real-row-not-on")
            XCTFail("Could not switch the real QWERTY number row ON")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        let onField = activatePreNavigatedField("plain-text")
        // Re-entering Safari after a MainApp round trip restores the OFF-phase focus WITHOUT raising
        // the keyboard, and re-tapping the SAME focused field never re-presents it (measured 20th
        // session, twice: no keyboard within 8 s and within a 3×2 s re-tap loop, while a direct
        // out-of-runner tap on a clean state showed the keyboard instantly). Only a focus CHANGE
        // re-presents the keyboard: bounce to another fixture field, then back to the target.
        // MainApp往復後は同じフィールドの再タップではキーボードが出ない。別フィールドへ一度
        // フォーカスを移してから戻すと再提示される（フォーカス変化が必要、実測）。
        let bouncePred = NSPredicate(format: "placeholderValue == %@ OR label == %@", "url-field", "url-field")
        for _ in 0..<3 where !keyboard(of: safari).exists && !copakyActive(in: safari) {
            let bounce = safari.webViews.firstMatch.descendants(matching: .any).matching(bouncePred).firstMatch
            if bounce.exists && bounce.isHittable {
                bounce.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            }
            onField.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        }
        switchToCopaky(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "46-on-latin-tab-missing")
            XCTFail("Could not re-establish the Latin QWERTY tab for the ON phase")
            return
        }
        clearFocusedField(onField, placeholder: "plain-text", in: safari)
        guard let onFrames = letterFrames(evidence: "on") else { return }

        var digitKeys: [XCUIElement] = []
        for digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            guard let key = keyboardKey(labels: [digit], sizedLike: onFrames.first), key.isHittable else {
                dump(safari, "46-digit-row-missing-\(digit)")
                shot("46-digit-row-missing-\(digit)")
                XCTFail("Real digit key '\(digit)' is missing or not hittable")
                return
            }
            digitKeys.append(key)
        }
        let firstDigitY = digitKeys[0].frame.midY
        for index in digitKeys.indices {
            XCTAssertEqual(digitKeys[index].frame.midY, firstDigitY, accuracy: 1.0, "Digit keys must share one top row")
            if index > 0 {
                XCTAssertGreaterThan(digitKeys[index].frame.midX, digitKeys[index - 1].frame.midX, "Digits must remain ordered 1234567890")
            }
        }
        XCTAssertLessThan(firstDigitY, onFrames[0].midY, "The real digit row must sit above the QWERTY letters")

        for index in offFrames.indices {
            XCTAssertEqual(
                onFrames[index].height,
                offFrames[index].height,
                accuracy: 2.0,
                "Enabling the number row must not compress QWERTY letter row \(index)"
            )
            XCTAssertEqual(
                onFrames[index].midY,
                offFrames[index].midY,
                accuracy: 2.0,
                "Existing QWERTY rows should retain their screen position when growth occurs above them"
            )
        }
        let digitToQPitch = onFrames[0].midY - digitKeys[4].frame.midY
        let qToAPitch = onFrames[1].midY - onFrames[0].midY
        XCTAssertEqual(digitToQPitch, qToAPitch, accuracy: 2.0, "The real row must use the existing row pitch")

        digitKeys[4].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(onField.value as? String, "5", "Tapping the real 5 key must insert the plain digit 5")
        shot("46-real-number-row-on")
    }

    // MARK: - 47 · Copaky extension: slide the Latin QWERTY space bar to move the cursor

    /// Requires external App Group seeds because Simulator app/extension preference domains can
    /// diverge: `scripts/run_ui_test.sh --fresh-install --seed enable_space_slide_cursor=true
    /// --seed space_slide_cursor_sensitivity=slow --seed live_conversion=true
    /// test47_spaceSlideCursorOnLatinQwerty`. A roughly two-letter-key
    /// drag emits two unit actions:
    /// one commits live composition and one produces the visible cursor step. A later ordinary tap
    /// still inserts Space.
    func test47_spaceSlideCursorOnLatinQwerty() throws {
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "47-latin-tab-missing")
            shot("47-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY; seed keyboard_type_en=roman")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)
        tapKeys(["a", "b"], in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(field.value as? String, "ab", "Fixture must contain exactly 'ab' before the cursor gesture")

        let qKey = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch
        let wKey = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["w", "W"])).firstMatch
        guard qKey.waitForExistence(timeout: 4), wKey.waitForExistence(timeout: 4) else {
            dump(safari, "47-pitch-keys-missing")
            XCTFail("Could not derive the Latin QWERTY key pitch")
            return
        }
        let keyPitch = abs(wKey.frame.midX - qKey.frame.midX)
        XCTAssertGreaterThan(keyPitch, 1, "Latin QWERTY key pitch must be positive")

        // Select the wide, lower-screen space key rather than any page text with the same label.
        let spaceLabels = L.spaceKey.filter { $0 != "空白" }
        let matches = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", spaceLabels))
        let keyboardCutoff = safari.frame.height * 0.45
        var space: XCUIElement?
        var widest = CGFloat.zero
        for index in 0..<min(matches.count, 10) {
            let candidate = matches.element(boundBy: index)
            guard candidate.exists, candidate.isHittable,
                  candidate.frame.minY >= keyboardCutoff,
                  candidate.frame.width > widest else { continue }
            widest = candidate.frame.width
            space = candidate
        }
        guard let space else {
            dump(safari, "47-space-not-found")
            shot("47-space-not-found")
            XCTFail("Latin QWERTY space bar not found")
            return
        }

        // Two unit actions are intentional here: the first commits Copaky's live composition and
        // returns; the second moves one visible character through the same upstream action path.
        //
        // The E-09 threshold is the RENDERED key width (Design.swift keyViewWidth ≈ 0.82 × cell on
        // a 10-column portrait tab), which XCUI cannot see: a key's accessibility frame is its
        // padded CELL — measured on the it-IT Pro Max, q's frame (43.67 pt) is even wider than the
        // q→w pitch (43.5 pt), so cell-based bounds mis-assert (this exact line failed 29/08).
        // 2.05 pitches ≈ 2.5 thresholds: safely past two, and a third would need spacing ≥ ~32 %
        // of the pitch — roughly double the real design ratio in either orientation.
        // E-09の閾値は描画キー幅（セルではない）。XCUIのframeはセル全体なので、ピッチ基準で判定する。
        let dragDistance = keyPitch * 2.05
        XCTAssertGreaterThan(dragDistance, keyPitch * 2, "The drag must exceed two key pitches, hence two E-09 thresholds (threshold < pitch since spacing > 0)")

        let appFrame = safari.frame
        let appOrigin = safari.coordinate(withNormalizedOffset: .zero)
        let start = appOrigin.withOffset(CGVector(
            dx: space.frame.midX - appFrame.minX,
            dy: space.frame.midY - appFrame.minY
        ))
        // Include small vertical drift deliberately: only horizontal translation participates.
        let target = start.withOffset(CGVector(dx: -dragDistance, dy: keyPitch * 0.15))
        start.press(
            forDuration: 0.05,
            thenDragTo: target,
            withVelocity: .fast,
            thenHoldForDuration: 0.05
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        field.typeText("X")
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(field.value as? String, "aXb", "One leftward space slide must place X between a and b")

        tapLatinSpace(in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(field.value as? String, "aX b", "An ordinary tap after a slide must still insert one space")
        shot("47-space-slide-cursor")
    }

    // MARK: - 48 · Empty Latin candidate bar shortens the keyboard by default

    /// F-05 height gate. Run through `scripts/run_ui_test.sh --fresh-install`: the orchestrator pins
    /// the new TRUE default first, then this test changes the real shared setting to FALSE and
    /// re-enters the same fixture field / Latin layout. A signed App Group is required so the second
    /// phase reaches the extension; failure to observe the height change is a failure, never a skip.
    /// F-05高さゲート。新しいTRUE既定値とFALSEを同じフィールド／ラテン配列で比較する。
    func test48_hiddenCandidateBarReducesHeight() throws {
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) {
            close.tap()
        }
        openSettingsTab()
        guard driveSwitch(L.hideEmptyCandidateBarToggle, to: true) else {
            dump(mainApp, "48-hide-empty-setting-not-on")
            XCTFail("Could not establish F-05's TRUE default; run test48 through scripts/run_ui_test.sh --fresh-install")
            return
        }

        /// Wait for a non-zero, stable keyboard inputView frame. The container is required here:
        /// inferring height from a key would silently omit the candidate-bar region under test.
        /// Custom keyboards vend no XCUI `Keyboard` element (30/08) — measure UIKit's inputView.
        /// 候補バー自体を含むため、キー位置からは推定せずinputViewのframeを必須とする。
        func stableKeyboardHeight(evidence: String, greaterThan baseline: CGFloat? = nil) -> CGFloat? {
            guard waitForKeyboardInputViewFrame(of: safari, timeout: 6) != nil else {
                dump(safari, "48-\(evidence)-keyboard-root-missing")
                shot("48-\(evidence)-keyboard-root-missing")
                XCTFail("F-05 height gate cannot measure the total keyboard: no inputView frame is exposed")
                return nil
            }
            var previous = CGFloat.nan
            var stableSamples = 0
            for _ in 0..<24 {
                let height = keyboardInputViewFrame(of: safari)?.height ?? 0
                let clearedThreshold = baseline.map { height > $0 + 1 } ?? true
                if height > 1, clearedThreshold {
                    if previous.isFinite, abs(height - previous) < 0.5 {
                        stableSamples += 1
                        if stableSamples >= 2 { return height }
                    } else {
                        stableSamples = 0
                    }
                    previous = height
                } else {
                    stableSamples = 0
                    previous = CGFloat.nan
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            }
            dump(safari, "48-\(evidence)-height-not-stable")
            shot("48-\(evidence)-height-not-stable")
            if let baseline {
                XCTFail("F-05 setting changed but keyboard height never grew beyond the hidden baseline \(baseline)")
            } else {
                XCTFail("F-05 keyboard height did not settle to a measurable non-zero value")
            }
            return nil
        }

        func enterEmptyLatinField(evidence: String) -> XCUIElement? {
            let field = activatePreNavigatedField("plain-text")
            switchToCopaky(in: safari)
            dismissCopakyNotice(in: safari)
            guard switchToLatinQwertyTab(in: safari) else {
                dump(safari, "48-\(evidence)-latin-tab-missing")
                shot("48-\(evidence)-latin-tab-missing")
                XCTFail("Could not establish an empty Latin QWERTY for the F-05 \(evidence) phase")
                return nil
            }
            clearFocusedField(field, placeholder: "plain-text", in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            return field
        }

        guard enterEmptyLatinField(evidence: "hidden") != nil,
              let hiddenHeight = stableKeyboardHeight(evidence: "hidden") else { return }
        shot("48-hidden-empty-candidate-bar")

        // Use a fresh Safari/extension presentation after the shared setting changes. Re-tapping an
        // already-focused field after a MainApp round-trip is unreliable on iOS 26 (see test46).
        safari.terminate()
        mainApp.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        openSettingsTab()
        guard driveSwitch(L.hideEmptyCandidateBarToggle, to: false) else {
            dump(mainApp, "48-hide-empty-setting-not-off")
            XCTFail("Could not switch hide_empty_candidate_bar_on_latin to FALSE for the visible baseline")
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        guard enterEmptyLatinField(evidence: "visible") != nil,
              let visibleHeight = stableKeyboardHeight(evidence: "visible", greaterThan: hiddenHeight) else { return }
        XCTAssertGreaterThan(visibleHeight, hiddenHeight + 1,
                             "F-05: reserving the empty candidate bar must make the same Latin keyboard taller")
        note("48-height-comparison", "hidden=\(hiddenHeight) visible=\(visibleHeight) delta=\(visibleHeight - hiddenHeight)")
        shot("48-visible-empty-candidate-bar")
    }

    // MARK: - 49 · Apple-proportioned Latin bottom row + image-key accessibility

    /// F-07 geometric gate on the new-default Latin layout: Space occupies at least 45% of the
    /// keyboard width and no period key remains immediately to its right. E-18 is checked on the
    /// same stable tree: explicit localized labels plus unchanged SF-Symbol identifiers.
    /// F-07の幅とピリオド除去、E-18のlabel/identifier契約を同じラテンタブで検証する。
    func test49_appleLatinBottomRowGeometryAndImageAccessibility() throws {
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "49-latin-tab-missing")
            shot("49-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY; seed keyboard_type_en=roman")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))

        // Custom keyboards vend no XCUI `Keyboard` element on this project (30/08): measure the
        // UIKit inputView container frame and scope every query by frame containment instead.
        // カスタムキーボードはKeyboard要素を持たないため、inputViewのframeで包含判定する。
        guard let keyboardFrame = waitForKeyboardInputViewFrame(of: safari, timeout: 6),
              keyboardFrame.width > 1 else {
            dump(safari, "49-keyboard-root-missing")
            shot("49-keyboard-root-missing")
            XCTFail("F-07 geometry gate requires the keyboard inputView frame to measure total width")
            return
        }

        let spaces = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", L.spaceKey))
        var space: XCUIElement?
        var widest = CGFloat.zero
        for index in 0..<min(spaces.count, 12) {
            let candidate = spaces.element(boundBy: index)
            guard candidate.exists, candidate.isHittable else { continue }
            let frame = candidate.frame
            guard keyboardFrame.intersection(frame).height >= frame.height * 0.5,
                  frame.width > widest else { continue }
            space = candidate
            widest = frame.width
        }
        guard let space else {
            dump(safari, "49-space-missing")
            shot("49-space-missing")
            XCTFail("F-07 Latin space key is missing")
            return
        }
        XCTAssertGreaterThanOrEqual(
            space.frame.width,
            keyboardFrame.width * 0.45,
            "F-07: Latin Space must occupy at least 45% of the keyboard width"
        )

        // A page may contain punctuation, so admit only dots inside the keyboard frame and
        // overlapping Space's row. The old base-row dot abutted Space (zero horizontal gap).
        // ページ文字は除外し、キーボード内でSpace行と重なるドットキーだけを検査する。
        let dots = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR identifier == %@ OR title == %@", ".", ".", "."))
        var adjacentDots: [CGRect] = []
        for index in 0..<min(dots.count, 20) {
            let dot = dots.element(boundBy: index)
            guard dot.exists else { continue }
            let frame = dot.frame
            guard keyboardFrame.intersection(frame).height >= frame.height * 0.5 else { continue }
            let verticalOverlap = frame.intersection(space.frame).height
            let isSameRow = verticalOverlap >= min(frame.height, space.frame.height) * 0.5
            let gap = frame.minX - space.frame.maxX
            let isAdjacentOnRight = frame.midX > space.frame.midX && gap >= -1 && gap <= keyboardFrame.width * 0.12
            if isSameRow, isAdjacentOnRight { adjacentDots.append(frame) }
        }
        XCTAssertTrue(adjacentDots.isEmpty,
                      "F-07: no '.' key may remain adjacent to Space's right edge; found frames \(adjacentDots)")

        assertLatinImageKeyAccessibility(in: safari)
        note("49-bottom-row-geometry", "keyboardWidth=\(keyboardFrame.width) spaceWidth=\(space.frame.width) ratio=\(space.frame.width / keyboardFrame.width)")
        shot("49-apple-latin-bottom-row")
    }

    // MARK: - 51 · Layout gallery capture (site asset pipeline, not a functional gate)

    /// F-08: captures ONLY the keyboard — the UIKit inputView element — for the site's layout
    /// gallery. The visual state comes entirely from the external seeds
    /// (scripts/layout_gallery_shots.sh); `TEST_RUNNER_COPAKY_GALLERY_NAME` names the attachment
    /// and `TEST_RUNNER_COPAKY_GALLERY_TYPE=ciao` first types «ciao» to fill the candidate bar.
    /// F-08: サイトのレイアウトギャラリー用にキーボード（inputView要素）だけを撮影する。
    func test51_layoutGalleryShot() throws {
        let env = ProcessInfo.processInfo.environment
        let name = env["COPAKY_GALLERY_NAME"] ?? "layout"
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "51-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY for the gallery shot")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)
        if env["COPAKY_GALLERY_TYPE"] == "ciao" {
            tapKeys(["c", "i", "a", "o"], in: safari)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))

        let query = safari.descendants(matching: .other)
            .matching(NSPredicate(format: "identifier == 'inputView'"))
        var best: XCUIElement?
        var bestHeight = CGFloat.zero
        for index in 0..<min(query.count, 6) {
            let element = query.element(boundBy: index)
            guard element.exists, element.frame.height > bestHeight, element.frame.width > 1 else { continue }
            best = element
            bestHeight = element.frame.height
        }
        guard let best else {
            dump(safari, "51-inputview-missing")
            XCTFail("F-08 gallery shot needs the keyboard inputView element")
            return
        }
        let attachment = XCTAttachment(screenshot: best.screenshot())
        attachment.name = "gallery-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 52 · Apple-like Shift cycle and Caps Lock

    /// Copaky [G-01]: one tap is one-shot Shift, a long press and double tap lock capitals, and the
    /// dynamic key resumes its 123 role after Shift is released.
    func test52_shiftKeyCycleAndCapsLock() throws {
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "52-latin-tab-missing")
            shot("52-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY for the Shift cycle")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)

        guard let shift = keyboardImageKey(identifier: "shift", in: safari), shift.isHittable else {
            dump(safari, "52-shift-off-missing")
            shot("52-shift-off-missing")
            XCTFail("Inactive Shift key with identifier 'shift' is missing")
            return
        }
        shift.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        guard keyboardImageKey(identifier: "shift.fill", in: safari) != nil else {
            dump(safari, "52-shift-active-missing")
            shot("52-shift-active-missing")
            XCTFail("One tap did not expose the active 'shift.fill' state")
            return
        }
        // Copaky [G-01]: query the StaticText, not `.any` — the key container `Other` reports an
        // invalid activation point ("Failed to determine hittability", measured 04/09), while the
        // StaticText is what every other key tap in this harness targets.
        let uppercaseQ = safari.staticTexts.matching(NSPredicate(format: "label == %@", "Q")).firstMatch
        guard uppercaseQ.waitForExistence(timeout: 4),
              uppercaseQ.frame.minY >= safari.frame.height * 0.45 else {
            dump(safari, "52-uppercase-q-missing")
            shot("52-uppercase-q-missing")
            XCTFail("One-shot Shift did not uppercase the Q key")
            return
        }
        uppercaseQ.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard waitForFieldValue(field, "Q"),
              keyboardImageKey(identifier: "shift", in: safari) != nil else {
            dump(safari, "52-one-shot-did-not-release")
            shot("52-one-shot-did-not-release")
            XCTFail("Typing Q must insert one uppercase letter and release one-shot Shift")
            return
        }

        guard let shiftForLongPress = keyboardImageKey(identifier: "shift", in: safari),
              shiftForLongPress.isHittable else {
            dump(safari, "52-shift-longpress-source-missing")
            shot("52-shift-longpress-source-missing")
            XCTFail("Shift key disappeared before the Caps Lock long press")
            return
        }
        shiftForLongPress.press(forDuration: 1.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard let capsLock = keyboardImageKey(identifier: "capslock.fill", in: safari),
              capsLock.isHittable else {
            dump(safari, "52-capslock-longpress-missing")
            shot("52-capslock-longpress-missing")
            XCTFail("Long-pressing Shift did not enable 'capslock.fill'")
            return
        }
        // Copaky [G-01]: "A" is ambiguous — the language key exposes a StaticText "A" (its
        // keyboard-language-switch-A-IT label) that the label lookup hits first (measured 05/09).
        // Copaky [G-01]: while Caps Lock is on, the dynamic key gives up its 123 role (upstream design:
        // shift/caps states hand the slot back to the globe/symbols role) — assert the contract explicitly.
        XCTAssertNil(keyboardImageKey(identifier: "textformat.123", in: safari, timeout: 1), "The dynamic key must not show 123 while Caps Lock is on")
        tapKeys(["K", "J"], in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard waitForFieldValue(field, "QKJ") else {
            dump(safari, "52-capslock-typing-wrong")
            shot("52-capslock-typing-wrong")
            XCTFail("Caps Lock must keep both following letters uppercase; got '\((field.value as? String) ?? "")'")
            return
        }

        capsLock.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let shiftForDoubleTap = keyboardImageKey(identifier: "shift", in: safari),
              shiftForDoubleTap.isHittable else {
            dump(safari, "52-shift-before-doubletap-missing")
            shot("52-shift-before-doubletap-missing")
            XCTFail("Tapping Caps Lock did not restore inactive Shift")
            return
        }
        // Copaky [G-01]: the double-tap → Caps Lock gesture is NOT reproducible with synthesized XCUI
        // taps (measured 05/09 ×3: two 0.05 s presses and the native doubleTap() both land outside the
        // product's double-press window). It stays a DEVICE check (build-9 what-to-test); here it is
        // best-effort: whatever state the two taps leave, the test restores Shift OFF and continues.
        doubleTapKey(shiftForDoubleTap, in: safari)
        if let doubleTapCaps = keyboardImageKey(identifier: "capslock.fill", in: safari, timeout: 2), doubleTapCaps.isHittable {
            doubleTapCaps.tap()
        } else {
            print("HARNESS-NOTE|test52|double-tap caps lock not reproducible via XCUI; verify on device")
            shot("52-capslock-doubletap-not-reproduced")
            if let stillActive = keyboardImageKey(identifier: "shift.fill", in: safari, timeout: 1), stillActive.isHittable {
                stillActive.tap()
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        guard let inactiveShift = keyboardImageKey(identifier: "shift", in: safari),
              let numbers = keyboardImageKey(identifier: "textformat.123", in: safari),
              let space = firstMatch(in: safari, labels: L.spaceKey, timeout: 4) else {
            dump(safari, "52-off-numbers-role-missing")
            shot("52-off-numbers-role-missing")
            XCTFail("Shift OFF must restore the dynamic 123 key beside Space")
            return
        }
        let bottomRowTolerance = max(4, numbers.frame.height * 0.2)
        guard abs(inactiveShift.frame.midY - numbers.frame.midY) <= bottomRowTolerance,
              numbers.frame.minX >= inactiveShift.frame.maxX - bottomRowTolerance,
              numbers.frame.maxX <= space.frame.minX + bottomRowTolerance,
              space.frame.minX - numbers.frame.maxX <= numbers.frame.width * 0.25 else {
            dump(safari, "52-numbers-not-left-of-space")
            shot("52-numbers-not-left-of-space")
            XCTFail("The dynamic 123 key must occupy the bottom-row slot between Shift and Latin Space")
            return
        }
        shot("52-shift-cycle-complete")
    }

    // MARK: - 54 · Language-key menu opens Copaky Settings

    /// Copaky [G-03]: the final held-menu item launches copaky://settings and selects Settings.
    func test54_languageKeyMenuOpensCopakySettings() throws {
        guard #available(iOS 18.0, *) else {
            throw XCTSkip("Opening a containing app through the keyboard responder chain requires iOS 18+")
        }
        mainApp.launch()
        if let close = firstMatch(in: mainApp, labels: L.closeOnboarding, timeout: 4) { close.tap() }
        mainApp.terminate()

        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "54-latin-tab-missing")
            shot("54-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY before opening the language menu")
            return
        }
        guard selectActiveLanguageMenuIndex(3, in: safari) else { return }
        guard mainApp.wait(for: .runningForeground, timeout: 8) else {
            dump(safari, "54-app-not-opened-safari")
            dump(mainApp, "54-app-not-opened-mainapp")
            shot("54-app-not-opened")
            XCTFail("The final language-menu item did not bring Copaky to the foreground")
            return
        }
        let settingsTab = mainApp.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "main-tab-settings")).firstMatch
        // [26th session: F-harness] The "Show all settings" switch sits below the fold in the short
        // settings list and never entered the accessibility tree without scrolling (26th-session UI dump), so we
        // verify the route selected the Settings tab instead — its own tab or nav bar, not that switch.
        // 「すべての設定を表示」は短い設定リストでは折り返し線の下にあり、スクロールしないとアクセシビリティツリーに現れない（第26セッションのUIダンプで確認）。
        // そのスイッチではなく、Settingsタブへの遷移自体（タブ選択またはナビゲーションバー）を検証する。
        let settingsTitles = ["Impostazioni", "Settings", "設定"]
        let settingsNavBar = mainApp.navigationBars
            .matching(NSPredicate(format: "identifier IN %@ OR label IN %@", settingsTitles, settingsTitles))
        let settingsRouteDeadline = Date().addingTimeInterval(8)
        var settingsRouteSelected = false
        repeat {
            if (settingsTab.exists && settingsTab.isSelected) || settingsNavBar.firstMatch.exists {
                settingsRouteSelected = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < settingsRouteDeadline
        guard settingsRouteSelected else {
            dump(mainApp, "54-settings-route-missing")
            shot("54-settings-route-missing")
            XCTFail("copaky://settings opened the app without selecting the Settings tab")
            return
        }
        shot("54-copaky-settings-open")
    }

    // MARK: - 55 · Clipboard history from Japanese flick ☆123

    /// Copaky [G-04]: the new default ☆123 slot opens Clipboard history with one long press.
    func test55_flickStar123LongPressOpensClipboardHistory() throws {
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        switchToJapaneseFlickTab(in: safari)

        let star123 = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "keyboard-flick-star-123")).firstMatch
        guard star123.waitForExistence(timeout: 4), star123.isHittable else {
            dump(safari, "55-star123-missing")
            shot("55-star123-missing")
            XCTFail("Japanese flick ☆123 key is missing stable identifier 'keyboard-flick-star-123'")
            return
        }

        // The small doc.badge.clock overlay is intentionally accessibilityHidden in the product, so
        // the observable contract is the panel itself rather than a synthetic badge query.
        func clipboardTabItem() -> XCUIElement? {
            let symbolPred = NSPredicate(format: "identifier CONTAINS 'doc.badge.clock' OR label CONTAINS 'doc.badge.clock'")
            let symbol = safari.descendants(matching: .any).matching(symbolPred).firstMatch
            if symbol.exists, symbol.isHittable { return symbol }
            return firstMatch(in: safari, labels: L.clipboardTab, timeout: 1)
        }
        if clipboardTabItem() == nil,
           let barButton = firstMatch(in: safari, labels: L.tabBarButton, timeout: 3),
           barButton.isHittable {
            barButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        }
        guard clipboardTabItem() != nil else {
            dump(safari, "55-clipboard-prerequisite-unavailable")
            shot("55-clipboard-prerequisite-unavailable")
            if ProcessInfo.processInfo.environment["COPAKY_CLIPBOARD_PRESEEDED"] == "1" {
                XCTFail("Clipboard tab is missing even though the harness successfully seeded its App Group files")
                return
            }
            throw XCTSkip("Clipboard tab not reachable on this build (App Group / Full Access / «Save clipboard history» off) — prerequisite, not a ☆123 long-press failure; on a signed build seed the setting and grant Full Access first.")
        }

        guard longPressClipboardShortcut(labels: [], identifiers: ["keyboard-flick-star-123"]) else {
            dump(safari, "55-star123-longpress-source-missing")
            shot("55-star123-longpress-source-missing")
            XCTFail("Japanese flick ☆123 key disappeared before its long press")
            return
        }
        let marker = firstMatch(
            in: safari,
            labels: L.backKey + ["ピン留め", "Pinned", "Fissati"],
            timeout: 4
        )
        guard marker != nil, clipboardPanelIsOpen(timeout: 2) else {
            dump(safari, "55-clipboard-not-open")
            shot("55-clipboard-not-open")
            XCTFail("Long-pressing Japanese flick ☆123 did not open Clipboard history")
            return
        }
        shot("55-flick-star123-clipboard-open")
    }

    // MARK: - 56 · Centered Latin second row without trailing period

    /// Copaky [G-40]: with the Apple-like bottom-left Shift layout, row two contains only a…l,
    /// centered by half a key. Query StaticText leaves so the key container cannot shadow labels.
    func test56_latinRowTwoHasNoTrailingDot() throws {
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "56-latin-tab-missing")
            shot("56-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY for the centered second-row gate")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        guard let keyboardFrame = waitForKeyboardInputViewFrame(of: safari, timeout: 6) else {
            dump(safari, "56-keyboard-root-missing")
            shot("56-keyboard-root-missing")
            XCTFail("G-40 geometry gate requires the keyboard inputView frame")
            return
        }
        func rowKey(_ label: String) -> XCUIElement? {
            let matches = safari.staticTexts.matching(NSPredicate(format: "label == %@", label))
            _ = matches.firstMatch.waitForExistence(timeout: 4)
            for index in 0..<min(matches.count, 12) {
                let candidate = matches.element(boundBy: index)
                guard candidate.exists else { continue }
                let frame = candidate.frame
                if keyboardFrame.intersection(frame).height >= frame.height * 0.5 {
                    return candidate
                }
            }
            return nil
        }
        guard let q = rowKey("q"), let a = rowKey("a"), let l = rowKey("l") else {
            dump(safari, "56-row-letters-missing")
            shot("56-row-letters-missing")
            XCTFail("Latin row anchors q/a/l are not all visible")
            return
        }

        let dots = safari.staticTexts.matching(NSPredicate(format: "label == %@", "."))
        var sameRowDots: [CGRect] = []
        for index in 0..<min(dots.count, 20) {
            let dot = dots.element(boundBy: index)
            guard dot.exists else { continue }
            if abs(dot.frame.midY - a.frame.midY) < a.frame.height / 2 {
                sameRowDots.append(dot.frame)
            }
        }
        XCTAssertTrue(sameRowDots.isEmpty,
                      "G-40: no '.' StaticText may share the a…l row; found frames \(sameRowDots)")
        XCTAssertGreaterThanOrEqual(
            a.frame.minX - q.frame.minX,
            q.frame.width * 0.25,
            "G-40: the 'a' key must begin at least one quarter-key to the right of 'q'"
        )
        XCTAssertGreaterThan(l.frame.midX, a.frame.midX, "G-40: the second row must retain a…l order")
        shot("g40_after")
    }

    // MARK: - 57 · Compact Clipboard history with relative timestamps

    /// Copaky [G-09]: the seeded Clipboard panel keeps touch targets at least 44 pt high, groups
    /// local-day history, exposes relative timestamps, and retains the back-key accessibility hook.
    func test57_clipboardPanelCompactWithTimestamps() throws {
        _ = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "57-latin-tab-missing")
            shot("57-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY before opening Clipboard history")
            return
        }
        try openClipboardTab()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        let language = Locale.preferredLanguages.first ?? "en"
        let today: String
        let yesterday: String
        switch language.prefix(2) {
        case "it":
            today = "Oggi"
            yesterday = "Ieri"
        case "ja":
            today = "今日"
            yesterday = "昨日"
        case "en":
            today = "Today"
            yesterday = "Yesterday"
        default:
            throw XCTSkip("Device language \(language) is not one Copaky localizes — nothing to assert")
        }

        let tiles = safari.buttons.matching(NSPredicate(format: "identifier == %@", "copaky_clipboard_text_tile"))
        XCTAssertGreaterThan(tiles.count, 0, "G-09: the seeded Clipboard history contains no text tiles")
        let relativePattern = ".*(ago|fa|前|now|adesso|ora|今).*"
        for index in 0..<tiles.count {
            let tile = tiles.element(boundBy: index)
            guard tile.exists else { continue }
            XCTAssertGreaterThanOrEqual(tile.frame.height, 44, "G-09: tile \(index) is below the 44 pt touch minimum")
            XCTAssertLessThanOrEqual(tile.frame.height, 56, "G-09: tile \(index) exceeds the compact 56 pt ceiling")
        }

        let todayHeader = safari.staticTexts.matching(NSPredicate(format: "label == %@", today)).firstMatch
        XCTAssertTrue(todayHeader.waitForExistence(timeout: 4), "G-09: localized Today header '\(today)' is missing")

        // Copaky [F05]: the tile is a single accessible element (children: .ignore, restored after the
        // counter-review), so the relative timestamp lives in the tile's own `value`, not in a separate
        // child StaticText.
        // Copaky [F05]: タイルは単一のアクセシビリティ要素（children: .ignore、レビュー後に復元）なので、
        // 相対タイムスタンプは子のStaticTextではなくタイル自身のvalueに含まれる。
        var timestampFound = false
        for index in 0..<tiles.count {
            let tile = tiles.element(boundBy: index)
            guard tile.exists, let value = tile.value as? String else { continue }
            if value.range(of: relativePattern, options: [.regularExpression, .caseInsensitive]) != nil {
                timestampFound = true
                break
            }
        }
        XCTAssertTrue(timestampFound,
                      "G-09: no Clipboard tile value exposes a relative timestamp matching \(relativePattern)")

        let back = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", "copaky_clipboard_back")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 4),
                      "G-09: Clipboard back key lost identifier copaky_clipboard_back")

        if ProcessInfo.processInfo.environment["COPAKY_CLIPBOARD_YESTERDAY_PRESEEDED"] == "1" {
            let yesterdayHeader = safari.staticTexts
                .matching(NSPredicate(format: "label == %@", yesterday)).firstMatch
            XCTAssertTrue(yesterdayHeader.waitForExistence(timeout: 4),
                          "G-09: seeded yesterday entry did not produce header '\(yesterday)'")
        }
        shot("g09_after")
    }

    // MARK: - 58 · Real number-row digit variations

    /// Copaky [G-05]: a held real-row 1 inserts its first superscript variation; a tap on 2 remains 2.
    func test58_numberRowDigitLongPressVariations() throws {
        let field = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        guard switchToLatinQwertyTab(in: safari) else {
            dump(safari, "58-latin-tab-missing")
            shot("58-latin-tab-missing")
            XCTFail("Could not establish Latin QWERTY for real-row digit variations")
            return
        }
        clearFocusedField(field, placeholder: "plain-text", in: safari)
        guard let keyboardFrame = waitForKeyboardInputViewFrame(of: safari, timeout: 6) else {
            dump(safari, "58-inputview-missing")
            shot("58-inputview-missing")
            XCTFail("The keyboard inputView is required to isolate real number-row keys")
            return
        }

        func digitKey(_ digit: String) -> XCUIElement? {
            let identifier = "keyboard-number-row-\(digit)"
            let matches = safari.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@", identifier))
            _ = matches.firstMatch.waitForExistence(timeout: 4)
            var topmost: XCUIElement?
            var topY = CGFloat.greatestFiniteMagnitude
            for index in 0..<min(matches.count, 12) {
                let candidate = matches.element(boundBy: index)
                guard candidate.exists, candidate.isHittable else { continue }
                let frame = candidate.frame
                guard keyboardFrame.intersection(frame).height >= frame.height * 0.5 else { continue }
                if frame.minY < topY {
                    topY = frame.minY
                    topmost = candidate
                }
            }
            return topmost
        }

        guard let one = digitKey("1") else {
            dump(safari, "58-one-key-missing")
            shot("58-one-key-missing")
            XCTFail("Real number-row key '1' is missing; seed enable_qwerty_number_row=true")
            return
        }
        let keyFrame = one.frame
        let appFrame = safari.frame
        let start = safari.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: keyFrame.midX - appFrame.minX,
            dy: keyFrame.midY - appFrame.minY
        ))
        let firstVariant = start.withOffset(CGVector(dx: 0, dy: -keyFrame.height))
        start.press(forDuration: 0.8, thenDragTo: firstVariant)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard (field.value as? String) == "¹" else {
            dump(safari, "58-superscript-one-not-inserted")
            shot("58-superscript-one-not-inserted")
            XCTFail("Long-pressing real-row 1 did not insert first variation '¹'; got '\((field.value as? String) ?? "")'")
            return
        }

        guard let two = digitKey("2") else {
            dump(safari, "58-two-key-missing")
            shot("58-two-key-missing")
            XCTFail("Real number-row key '2' is missing after the variation gesture")
            return
        }
        two.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard (field.value as? String) == "¹2" else {
            dump(safari, "58-plain-two-not-inserted")
            shot("58-plain-two-not-inserted")
            XCTFail("A simple tap on real-row 2 must remain plain '2'; got '\((field.value as? String) ?? "")'")
            return
        }
        shot("58-number-row-variations")
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
    /// shown, the OSS-license screen, the Contact screen, the Themes tab, and the Latin keyboard.
    /// Audit issues are RECORDED, never failed on — the closure always returns `true` — because that
    /// part is a census for human triage (reports/a11y_audit_*.md). E-18's explicit image-key labels
    /// are a separate exact regression contract and do fail when missing or OS-derived.
    /// 監査issueは一覧として収集するだけだが、E-18の画像キーlabelは厳密な回帰ゲートとする。
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

        // 3b · Clipboard long-press advanced options (Copaky [G-07]) — fail-closed: once the history toggle
        // is ON, the «詳しい設定» link must exist (counter-review 05/09: no silent A11Y-SKIP here).
        if driveSwitch(L.clipboardToggle, to: true) {
            guard softTapScrolling(L.clipboardAdvancedLink, in: mainApp) else {
                dump(mainApp, "50-clipboard-advanced-link-missing")
                shot("50-clipboard-advanced-link-missing")
                XCTFail("G-07: the clipboard advanced-options link is missing while the history toggle is ON")
                return
            }
            shot("50-clipboard-advanced")
            issues += auditScreen("Opzioni avanzate appunti", in: mainApp)
            softBack(mainApp)
        } else {
            print("A11Y-SKIP|Opzioni avanzate appunti|could not drive the clipboard toggle ON (Full Access prerequisite)")
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

        // 7 · Latin keyboard image keys (E-18). The audit inventory is supplemented by exact product-
        // label assertions because the OS-derived SF Symbol name is non-empty and can therefore evade
        // `.sufficientElementDescription` despite being wrong (e.g. it-IT "Ritorno Unitario").
        // E-18: OS派生名も空ではないため、監査に加えて製品翻訳labelを厳密検証する。
        let a11yField = activatePreNavigatedField("plain-text")
        switchToCopaky(in: safari)
        dismissCopakyNotice(in: safari)
        if switchToLatinQwertyTab(in: safari) {
            clearFocusedField(a11yField, placeholder: "plain-text", in: safari)
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            shot("50-latin-keyboard")
            issues += auditScreen("Tastiera latina", in: safari)
            assertLatinImageKeyAccessibility(in: safari)
        } else {
            dump(safari, "50-latin-keyboard-missing")
            XCTFail("E-18 accessibility gate could not establish the Latin QWERTY keyboard")
        }

        // 8 · "Appunti" (clipboard) — there is no such MainApp screen: clipboard history lives INSIDE
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
