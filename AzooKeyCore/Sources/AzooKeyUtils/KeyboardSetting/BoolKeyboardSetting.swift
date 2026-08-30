//
//  BoolKeyboardSetting.swift
//  BoolKeyboardSetting
//
//  Created by ensan on 2021/08/10.
//  Copyright © 2021 ensan. All rights reserved.
//

import Foundation
import enum KanaKanjiConverterModule.KeyboardLanguage
import KeyboardViews
import SwiftUI
import SwiftUtils

public protocol BoolKeyboardSettingKey: KeyboardSettingKey, StoredInUserDefault where Value == Bool {
    /// 有効化時に実行される処理
    static func onEnabled() -> LocalizedStringKey?
    /// 無効化時に実行される処理
    static func onDisabled()
}
public extension StoredInUserDefault where Value == Bool {
    @MainActor
    static func get() -> Value? {
        let object = SharedStore.userDefaults.object(forKey: key)
        return object as? Bool
    }
    @MainActor
    static func set(newValue: Value) {
        SharedStore.userDefaults.set(newValue, forKey: key)
    }
}

public extension BoolKeyboardSettingKey {
    static func onEnabled() -> LocalizedStringKey? { nil }
    static func onDisabled() {}

    @MainActor static var value: Value {
        get {
            get() ?? defaultValue
        }
        set {
            set(newValue: newValue)
        }
    }
}

public struct LiveConversionInputMode: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "ライブ変換"
    public static let explanation: LocalizedStringKey = "入力中の文字列を自動的に変換します。"
    public static let defaultValue = true
    public static let key: String = "live_conversion"
}

public extension KeyboardSettingKey where Self == LiveConversionInputMode {
    static var liveConversion: Self { .init() }
}

public struct TypographyLetter: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "装飾英字変換"
    public static let explanation: LocalizedStringKey = "英字入力の際に\n「𝕥𝕪𝕡𝕠𝕘𝕣𝕒𝕡𝕙𝕪」のような装飾字体を候補に表示します。"
    public static let defaultValue = true
    public static let key: String = "typography_roman_candidate"
}

public extension KeyboardSettingKey where Self == TypographyLetter {
    static var typographyLetter: Self { .init() }
}

public struct EnglishCandidate: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "日本語入力中の英単語変換"
    public static let explanation: LocalizedStringKey = "「いんてれsちんg」→「interesting」のように、ローマ字日本語入力中も英語への変換候補を表示します。"
    public static let defaultValue = true
    public static let key: String = "roman_english_candidate"
}

public extension KeyboardSettingKey where Self == EnglishCandidate {
    static var englishCandidate: Self { .init() }
}

public struct MemoryResetFlag: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "学習のリセット"
    public static let explanation: LocalizedStringKey = "学習履歴を全て消去します。この操作は取り消せません。"
    public static let defaultValue = false
    public static let key: String = "memory_reset_setting"
}

public extension KeyboardSettingKey where Self == MemoryResetFlag {
    static var memoryResetFlag: Self { .init() }
}

public struct EnableKeySound: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "キーの音"
    public static let explanation: LocalizedStringKey = "キーを押した際に音を鳴らします♪"
    public static let defaultValue = false
    public static let key: String = "sound_enable_setting"
}

public extension KeyboardSettingKey where Self == EnableKeySound {
    static var enableKeySound: Self { .init() }
}

/// キーボードの触覚フィードバックを有効化する設定
/// - note: この機能はフルアクセスがないと実現できない
public struct EnableKeyHaptics: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "振動フィードバック"
    public static let explanation: LocalizedStringKey = "キーを押した際に端末を振動させます。"
    public static let defaultValue = false
    public static let key: String = "enable_key_haptics"
    public static let requireFullAccess: Bool = true
}

public extension KeyboardSettingKey where Self == EnableKeyHaptics {
    static var enableKeyHaptics: Self { .init() }
}

public struct UseOSUserDict: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "OSのユーザ辞書の利用"
    public static let explanation: LocalizedStringKey = "OS標準のユーザ辞書を利用します。"
    public static let defaultValue = true
    public static let key: String = "use_OS_user_dict"
}

public extension KeyboardSettingKey where Self == UseOSUserDict {
    static var useOSUserDict: Self { .init() }
}

public struct UseReflectStyleCursorBar: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "新しいカーソルバーを使う"
    public static let explanation: LocalizedStringKey = "操作性が向上した新しいカーソルバーを有効化します。"
    public static let defaultValue = true
    // MARK: This setting is originally introduced as 'beta cursor bar'
    public static let key: String = "use_move_cursor_bar_beta"
}

public extension KeyboardSettingKey where Self == UseReflectStyleCursorBar {
    static var useReflectStyleCursorBar: Self { .init() }
}

public struct DisplayCursorBarAutomatically: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "カーソルバーを自動表示"
    public static let explanation: LocalizedStringKey = "カーソル移動の際にカーソルバーを自動表示します"
    public static let defaultValue = false
    public static let key: String = "display_cursor_bar_automatically"
}

public extension KeyboardSettingKey where Self == DisplayCursorBarAutomatically {
    static var displayCursorBarAutomatically: Self { .init() }
}

public struct UseShiftKey: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "シフトキーを使う"
    public static let explanation: LocalizedStringKey = "QwertyキーボードでAaキーの代わりにシフトキーを利用します。"
    public static let defaultValue = false
    public static let key: String = "use_shift_key"
}

public extension KeyboardSettingKey where Self == UseShiftKey {
    static var useShiftKey: Self { .init() }
}

public struct KeepDeprecatedShiftKeyBehavior: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "シフトキーの古い挙動を使う"
    public static let explanation: LocalizedStringKey = "シフトキーの以前の挙動を利用します。iOS 18以降では廃止されます。"
    public static let defaultValue: Bool = true
    public static let key: String = "keep_deprecated_shift_key_behavior"
}

public extension KeyboardSettingKey where Self == KeepDeprecatedShiftKeyBehavior {
    static var keepDeprecatedShiftKeyBehavior: Self { .init() }
}

public struct UseNextCandidateKey: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "次候補キーを使う"
    public static let explanation: LocalizedStringKey = "キーボードで入力中、空白キーに「次候補」機能を表示します"
    public static let defaultValue = false
    public static let key: String = "use_next_candidate_key"
}

public extension KeyboardSettingKey where Self == UseNextCandidateKey {
    static var useNextCandidateKey: Self { .init() }
}

public struct HideResetButtonInOneHandedMode: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "片手モードで解除ボタンを表示しない"
    public static let explanation: LocalizedStringKey = "片手モードの際に表示される解除ボタンを非表示にします。片手モードの調整はタブバーのボタンから行えます。"
    public static let defaultValue = false
    public static let key: String = "hide_reset_button_in_one_handed_mode"
}

public extension KeyboardSettingKey where Self == HideResetButtonInOneHandedMode {
    static var hideResetButtonInOneHandedMode: Self { .init() }
}

public struct StopLearningWhenSearch: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "検索時は学習を停止"
    public static let explanation: LocalizedStringKey = "web検索などで入力した単語を学習しません。"
    public static let defaultValue = false
    public static let key: String = "stop_learning_when_search"
}

public extension KeyboardSettingKey where Self == StopLearningWhenSearch {
    static var stopLearningWhenSearch: Self { .init() }
}

/// ペーストボタンを追加する設定
/// - note: この機能はフリックのキーボードのみで提供する
/// - note: この機能はフルアクセスがないと実現できない
public struct EnablePasteButton: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "ペーストボタン"
    public static let explanation: LocalizedStringKey = "左下のカーソル移動キーの上フリックにペーストボタンを追加します"
    public static let defaultValue = false
    public static let key: String = "enable_paste_button_on_flick_cursorbar_key"
    public static let requireFullAccess: Bool = true
}

public extension KeyboardSettingKey where Self == EnablePasteButton {
    static var enablePasteButton: Self { .init() }
}

/// 削除キーの左フリックで文頭まで削除する設定 / Toggle for the flick-left "delete to line start" gesture
/// - note: フリックレイアウトのみ対象。オフにすると左フリックでも1文字削除になる。
public struct EnableSmoothDelete: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "フリックで文頭まで削除"
    public static let explanation: LocalizedStringKey = "削除キーを左にフリックすると文頭まで一括削除します。オフにすると1文字ずつ削除します。"
    public static let defaultValue = true
    public static let key: String = "enable_smooth_delete_flick"
}

public extension KeyboardSettingKey where Self == EnableSmoothDelete {
    static var enableSmoothDelete: Self { .init() }
}

/// QWERTY最上段に数字ヒントを表示する設定 / Optional number hints on the QWERTY top row
/// - note: 基本入力の一部でありフルアクセス不要。ラベルに数字を小さく表示し、長押しバリエーションの先頭に数字を追加する。
public struct EnableNumberRowHints: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "上段に数字を表示"
    public static let explanation: LocalizedStringKey = "QWERTYの最上段に数字を小さく表示し、長押しで入力できます。オフにすると通常のキー表示になります。"
    public static let defaultValue = false
    public static let key: String = "enable_qwerty_number_row_hints"
}

public extension KeyboardSettingKey where Self == EnableNumberRowHints {
    static var enableNumberRowHints: Self { .init() }
}

/// QWERTY最上部に実際の数字キー列を追加する設定 / Optional real digit-key row above QWERTY
/// - note: 既存の4行を圧縮せず、キー1行と行間の分だけキーボードを高くする。
public struct EnableQwertyNumberRow: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "QWERTYに数字行を追加"
    public static let explanation: LocalizedStringKey = "QWERTYの最上部に数字キーの行を追加します。有効にすると、既存のキーの大きさを保つためキーボードが1行分高くなります。"
    public static let defaultValue = false
    public static let key: String = "enable_qwerty_number_row"
}

public extension KeyboardSettingKey where Self == EnableQwertyNumberRow {
    static var enableQwertyNumberRow: Self { .init() }
}

/// Copaky [E-09]: opt-in cursor movement by sliding the space bar on alphabetic QWERTY tabs.
/// Copaky [E-09]: アルファベットQWERTYの空白スライドによるカーソル移動（既定オフ）。
public struct EnableSpaceSlideCursor: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "スペースをスライドしてカーソルを移動"
    public static let explanation: LocalizedStringKey = "英語・イタリア語とローマ字日本語のQWERTYでスペースキーを左右にスライドすると、カーソルを1文字ずつ移動します。英語・イタリア語ではタップで通常どおりスペースを入力し、ローマ字日本語のタップ・変換動作も変わりません。日本語フリックには影響しません。"
    public static let defaultValue = false
    public static let key: String = "enable_space_slide_cursor"
}

public extension KeyboardSettingKey where Self == EnableSpaceSlideCursor {
    static var enableSpaceSlideCursor: Self { .init() }
}

/// イタリア語をキーボードの言語として使う設定 / Italian as a keyboard language.
/// Defaults on only when the system's first preferred language is Italian, so Italian users get
/// accented-word predictions on first launch; other locales retain the existing opt-in behavior.
/// システムの第一優先言語がイタリア語の場合だけ既定でオンにし、イタリア語利用者が初回から
/// アクセント付き単語の予測を得られるようにする。他言語では従来どおりオプトイン。
public struct EnableItalianKeyboardLanguage: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "イタリア語を使う"
    public static let explanation: LocalizedStringKey = "言語切替キーにイタリア語を加え、ラテン文字タブの予測変換をイタリア語の辞書から行います。キー配列は変わりません。"
    public static var defaultValue: Bool {
        isItalianSystemLanguage(preferredLanguages: Locale.preferredLanguages)
    }
    public static func isItalianSystemLanguage(preferredLanguages: [String]) -> Bool {
        preferredLanguages.first?.hasPrefix("it") == true
    }
    @MainActor public static var value: Bool {
        get {
            ActiveKeyboardLanguagesSetting.value.contains(.it_IT)
        }
        set {
            ActiveKeyboardLanguagesSetting.setItalianEnabled(newValue, in: SharedStore.userDefaults)
        }
    }
    public static let key: String = "enable_italian_keyboard_language"
}

public extension KeyboardSettingKey where Self == EnableItalianKeyboardLanguage {
    static var enableItalianKeyboardLanguage: Self { .init() }
}

// Copaky: optionally replace a plain Italian word with its dictionary-backed accented form when
// space commits it. The setting is independent from enabling the Italian keyboard language.
// Copaky: 空白で確定するとき、辞書に基づくアクセント付き語への補正を個別に切り替える。
public struct ItalianAutoAccentOnSpace: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "スペースでアクセントを自動補正（イタリア語）"
    public static let explanation: LocalizedStringKey = "イタリア語タブで「perche」のようにアクセントを付け忘れた語の後にスペースを押すと、辞書にあるアクセント付きの形（perché）に自動で置き換えます。「si」「da」のようにアクセントなしでも正しい語には触れません。"
    public static let defaultValue = true
    public static let key: String = "italian_auto_accent_on_space"
}

public extension KeyboardSettingKey where Self == ItalianAutoAccentOnSpace {
    static var italianAutoAccentOnSpace: Self { .init() }
}

// Copaky: conservative IT/EN typo correction when a Latin word is committed with space. It is
// opt-in until the permanent corpus and device campaign meet their accuracy and memory gates.
// Copaky: ラテン文字（伊英）の空白確定時誤字補正。検証完了までは既定オフ。
public struct EnableLatinAutocorrect: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "ラテン文字の自動修正"
    public static let explanation: LocalizedStringKey = "ラテン文字キーボードで単語の後にスペースを押すと、イタリア語・英語のよくある入力ミスを自動で修正します。修正直後に削除キーを押すと元の単語に戻せます。"
    public static let defaultValue = false
    public static let key: String = "enable_latin_autocorrect"
}

public extension KeyboardSettingKey where Self == EnableLatinAutocorrect {
    static var enableLatinAutocorrect: Self { .init() }
}

// Copaky [F-07]: Apple-style period shortcut for safe Latin prose fields.
// Copaky [F-07]: 安全なラテン文字の文章欄で、空白2回をピリオドへ置換する。
public struct EnableDoubleSpacePeriod: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "スペース2回でピリオド"
    public static let explanation: LocalizedStringKey = "ラテン文字キーボードでスペースを素早く2回押すと、「. 」を入力します。URL・メール・パスワードなどの保護された入力欄では動作しません。"
    public static let defaultValue = true
    public static let key: String = "double_space_period"
}

public extension KeyboardSettingKey where Self == EnableDoubleSpacePeriod {
    static var enableDoubleSpacePeriod: Self { .init() }
}

// Copaky [F-04b]: one-shot Shift at the start of safe Latin prose sentences.
// Copaky [F-04b]: 安全なラテン文字の文章欄で、文頭だけ Shift を1回有効にする。
public struct EnableLatinAutoCapitalization: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "文頭を自動で大文字に"
    public static let explanation: LocalizedStringKey = "ラテン文字キーボードで、入力欄の先頭や文末記号の後を自動的に大文字で始めます。URL・メール・パスワードなどの保護された入力欄では動作しません。"
    public static let defaultValue = true
    public static let key: String = "enable_latin_auto_capitalization"
}

public extension KeyboardSettingKey where Self == EnableLatinAutoCapitalization {
    static var enableLatinAutoCapitalization: Self { .init() }
}

/// クリップボード履歴の取り込みにシステムのペーストボタンを使う設定（試験的） / Experimental: use Apple's
/// system paste button (`UIPasteControl`) to add to the clipboard history. iOS treats a tap on its own
/// control as consent, so the text is handed over without us reading the pasteboard and no
/// "pasted from…" banner appears. Off by default until it is validated on a real device — the paste
/// dialog does not exist on the Simulator, so nothing about this can be proven there.
public struct UseSystemPasteControl: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "システムのペーストボタンを使う"
    // 断定しないこと: バナーが消えるかどうかは実機でしか確かめられない仮説であり、結果ではない。
    // Do not assert it: whether the banner disappears is our hypothesis, testable only on a device.
    public static let explanation: LocalizedStringKey = "クリップボード履歴への追加を、iOS標準のペーストボタンで行います。確認バナーが出なくなることを狙った試験的な機能で、実機での確認が必要です。"
    public static let defaultValue = false
    public static let key: String = "use_system_paste_control"
    public static let requireFullAccess: Bool = true
}

public extension KeyboardSettingKey where Self == UseSystemPasteControl {
    static var useSystemPasteControl: Self { .init() }
}

/// 「連絡先」アプリの名前情報を読み込む設定
/// - note: この機能はフルアクセスがないと実現できない
public struct EnableContactImport: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "変換に連絡先データを利用"
    public static let explanation: LocalizedStringKey = "「連絡先」アプリに登録された氏名のデータを変換に利用します"
    public static let defaultValue = false
    public static let key: String = "enable_contact_import"
    public static let requireFullAccess: Bool = true
}

public extension KeyboardSettingKey where Self == EnableContactImport {
    static var enableContactImport: Self { .init() }
}

/// クリップボード履歴マネージャを有効化する設定
/// - note: この機能はフルアクセスがないと実現できない
public struct EnableClipboardHistoryManagerTab: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "クリップボードの履歴を保存"
    public static let explanation: LocalizedStringKey = "コピーした文字列の履歴を保存し、専用のタブから入力できるようにします。"
    // 既定でオフ（オプトイン）。フルアクセスが必要な付加機能であり、基本入力はこれ無しで動作する（App Review 4.4.1）。
    public static let defaultValue = false
    public static let key: String = "enable_clipboard_history_manager_tab"
    public static let requireFullAccess: Bool = true
    public static func onEnabled() -> LocalizedStringKey? {
        do {
            var manager = CustardManager.load()
            var tabBarData = (try? manager.tabbar(identifier: 0)) ?? .default
            if !tabBarData.items.contains(where: {$0.actions == [.moveTab(.system(.clipboard_history_tab))]}) {
                tabBarData.items.append(TabBarItem(label: .image("doc.badge.clock"), pinned: true, actions: [.moveTab(.system(.clipboard_history_tab))]))
            }
            tabBarData.lastUpdateDate = Date()
            try manager.saveTabBarData(tabBarData: tabBarData)
            return "クリップボードの履歴がオンになりました。既定では文字タブの123キーを長押しすると履歴タブが開きます。設定で #+= / ☆123 キーも追加できます。「ペーストの許可」を求めるダイアログが繰り返し出る場合は、設定アプリ ▸ Copaky ▸「ほかの App からペースト」を「許可」にしてください。"
        } catch {
            debug("EnableClipboardHistoryManagerTab onEnabled", error)
            return nil
        }
    }
    public static func onDisabled() {
        do {
            var manager = CustardManager.load()
            var tabBarData = (try? manager.tabbar(identifier: 0)) ?? .default
            tabBarData.items.removeAll {
                $0.actions == [.moveTab(.system(.clipboard_history_tab))]
            }
            tabBarData.lastUpdateDate = Date()
            try manager.saveTabBarData(tabBarData: tabBarData)
        } catch {
            debug("EnableClipboardHistoryManagerTab onEnabled", error)
        }
    }
}

public extension KeyboardSettingKey where Self == EnableClipboardHistoryManagerTab {
    static var enableClipboardHistoryManagerTab: Self { .init() }
}

/// Copaky: optional candidate-bar shortcut, off by default.
/// Copaky: 候補バーのショートカットは任意表示で、既定ではオフ。
public struct DisplayTabBarButton: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "Copaky ボタンを候補バーに表示"
    public static let explanation: LocalizedStringKey = "オンにすると候補バーに Copaky ボタンを表示します。長押しは既定で文字タブの123キーを使い、設定で #+= / ☆123 キーも追加できます。クリップボード履歴がオンなら、設定したキーから履歴を直接開きます。"
    public static let defaultValue = false
    public static let key: String = "display_tab_bar_button"
}

public extension KeyboardSettingKey where Self == DisplayTabBarButton {
    static var displayTabBarButton: Self { .init() }
}

/// Copaky: collapse an empty candidate bar only on the English/Italian QWERTY family.
/// Copaky: 英語・イタリア語のQWERTYに限り、空の候補バーを折りたたむ。
public struct HideEmptyCandidateBarOnLatin: BoolKeyboardSettingKey {
    public static let title: LocalizedStringKey = "候補がないとき候補バーを隠す（ラテン文字キーボード）"
    public static let explanation: LocalizedStringKey = "既定でオンです。英語・イタリア語のQWERTYで、候補・予測・お知らせがなく、Copaky ボタンも非表示のときに候補バーを隠して、キーボードを低くします。日本語キーボードには影響しません。"
    public static let defaultValue = true
    public static let key: String = "hide_empty_candidate_bar_on_latin"
}

public extension KeyboardSettingKey where Self == HideEmptyCandidateBarOnLatin {
    static var hideEmptyCandidateBarOnLatin: Self { .init() }
}

/// 削除した設定を記録するためのenum。おもに`key`の情報を残すため、ソースに維持している。
private enum DeprecatedSetting {
    public struct HalfKanaCandidate: BoolKeyboardSettingKey {
        public static let title: LocalizedStringKey = "半角カナ変換"
        public static let explanation: LocalizedStringKey = "半角ｶﾀｶﾅへの変換を候補に表示します。"
        public static let defaultValue = true
        public static let key: String = "half_kana_candidate"
    }

    public struct FullRomanCandidate: BoolKeyboardSettingKey {
        public static let title: LocalizedStringKey = "全角英数字変換"
        public static let explanation: LocalizedStringKey = "全角英数字(ａｂｃ１２３)への変換候補を表示します。"
        public static let defaultValue = true
        public static let key: String = "full_roman_candidate"
    }

    public struct UnicodeCandidate: BoolKeyboardSettingKey {
        public static let title: LocalizedStringKey = "unicode変換"
        public static let explanation: LocalizedStringKey = "「u3042→あ」のように、入力されたunicode番号に対応する文字に変換します。接頭辞にはu, u+, U, U+が使えます。"
        public static let defaultValue = true
        public static let key: String = "unicode_candidate"
    }
}
