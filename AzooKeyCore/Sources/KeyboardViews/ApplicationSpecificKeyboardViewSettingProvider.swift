//
//  ApplicationSpecificKeyboardViewSettingProvider.swift
//
//
//  Created by ensan on 2023/07/22.
//

import Foundation
import enum KanaKanjiConverterModule.KeyboardLanguage

@MainActor public protocol ApplicationSpecificKeyboardViewSettingProvider {
    static var koganaFlickCustomKey: KeyFlickSetting { get }
    static var kanaSymbolsFlickCustomKey: KeyFlickSetting { get }
    static var hiraTabFlickCustomKey: KeyFlickSetting { get }
    static var abcTabFlickCustomKey: KeyFlickSetting { get }
    static var symbolsTabFlickCustomKey: KeyFlickSetting { get }

    static var numberTabCustomKeysSetting: QwertyCustomKeysValue { get }

    static var japaneseKeyboardLayout: LanguageLayout { get }
    static var englishKeyboardLayout: LanguageLayout { get }

    static var flickSensitivity: Double { get }
    static var resultViewFontSize: Double { get }
    static var keyViewFontSize: Double { get }

    static var enableSound: Bool { get }
    static var enableHaptics: Bool { get }
    static var enablePasteButton: Bool { get }
    /// 削除キーの左フリックで文頭まで削除する / Flick-left "delete to line start" on the delete key
    static var enableSmoothDelete: Bool { get }
    /// QWERTY最上段に数字ヒントを表示し、長押しで入力できるようにする / Number hints + long-press digits on the QWERTY top row
    static var enableNumberRowHints: Bool { get }
    /// QWERTY最上部に実際の数字キーを1行追加する / Add a real digit-key row above QWERTY
    static var enableQwertyNumberRow: Bool { get }
    /// アルファベットQWERTYの空白スライドでカーソルを移動する / Slide alphabetic QWERTY space to move the cursor
    static var enableSpaceSlideCursor: Bool { get }
    /// 空白スライドの移動閾値 / Movement threshold for space-bar cursor sliding
    static var spaceSlideCursorSensitivity: SpaceSlideCursorSensitivity { get }
    /// イタリア語をキーボードの言語として使う / Italian as a keyboard language: it joins the language-switch cycle
    /// and the Latin tab predicts from the Italian dictionary instead of the English one.
    static var enableItalianKeyboardLanguage: Bool { get }
    /// Internal keyboard languages in tap-cycle order. Japanese and English are always present.
    static var activeKeyboardLanguages: [KeyboardLanguage] { get }
    /// クリップボード取り込みにシステムのペーストボタンを使う（試験的） / Experimental: capture through
    /// `UIPasteControl` instead of reading the pasteboard ourselves — no system banner.
    static var useSystemPasteControl: Bool { get }
    /// 履歴を直接開く長押しスロット / Long-press slots that open Clipboard history directly
    static var clipboardLongPressSlots: ClipboardLongPressSlots { get }
    static var hideResetButtonInOneHandedMode: Bool { get }
    static var useShiftKey: Bool { get }
    static var keepDeprecatedShiftKeyBehavior: Bool { get }
    static var useNextCandidateKey: Bool { get }

    /// タブバーボタンを表示する
    static var displayTabBarButton: Bool { get }
    /// ラテン文字QWERTYで空の候補バーを隠す
    static var hideEmptyCandidateBarOnLatin: Bool { get }
    /// 反射スタイルのカーソルバーを利用する
    static var useReflectStyleCursorBar: Bool { get }
    /// カーソルバーを自動表示する（実験的機能）
    ///  - note: この機能は実験的に導入しているが、仕様に議論がある。[#346](https://github.com/azooKey/azooKey/issues/346)も参照。
    static var displayCursorBarAutomatically: Bool { get }

    static var canResetLearningForCandidate: Bool { get }

    static func get(_: CustomizableFlickKey) -> KeyFlickSetting.SettingData
}

public extension ApplicationSpecificKeyboardViewSettingProvider {
    static var activeKeyboardLanguages: [KeyboardLanguage] {
        var languages: [KeyboardLanguage] = [.ja_JP, .en_US]
        if enableItalianKeyboardLanguage {
            languages.append(.it_IT)
        }
        return languages
    }
}
