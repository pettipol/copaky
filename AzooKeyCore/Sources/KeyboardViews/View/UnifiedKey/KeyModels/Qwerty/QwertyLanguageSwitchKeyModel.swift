import Foundation
import KanaKanjiConverterModule
import KeyboardThemes
import SwiftUI

struct QwertyLanguageSwitchKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    let languages: (KeyboardLanguage, KeyboardLanguage)

    /// The language the keyboard is really typing right now. A tab that declares itself English is
    /// the LATIN tab: which Latin language is active lives in `latinKeyboardLanguage`.
    /// 実際に入力中の言語。英語を宣言するタブはラテン文字タブであり、実際の言語は状態側にある。
    @MainActor func currentTabLanguage(variableStates: VariableStates) -> KeyboardLanguage? {
        let declared = variableStates.tabManager.existentialTab().language
        return declared == .en_US ? variableStates.latinKeyboardLanguage : declared
    }

    /// Copaky: the languages this key cycles through, in order. Italian joins the cycle only when the
    /// user turned it on in Settings, so a two-language user keeps exactly today's behaviour.
    /// Copaky: このキーが巡回する言語。イタリア語は設定でオンにした場合のみ加わる。
    @MainActor private var cycle: [KeyboardLanguage] {
        var cycle = [languages.0, languages.1]
        if Extension.SettingProvider.enableItalianKeyboardLanguage, !cycle.contains(.it_IT) {
            cycle.append(.it_IT)
        }
        return cycle
    }

    /// The language one tap moves to, given what is active now.
    @MainActor private func nextLanguage(variableStates: VariableStates) -> KeyboardLanguage {
        let cycle = self.cycle
        if let current = currentTabLanguage(variableStates: variableStates),
           let index = cycle.firstIndex(of: current) {
            return cycle[(index + 1) % cycle.count]
        }
        // Not on a tab that carries a language (numbers, symbols, clipboard…): go back to the
        // language the keyboard was last typing, or to the first of the cycle.
        if SemiStaticStates.shared.needsInputModeSwitchKey, cycle.contains(variableStates.keyboardLanguage) {
            return variableStates.keyboardLanguage
        }
        return cycle.first ?? .ja_JP
    }

    @MainActor private func actions(for target: KeyboardLanguage) -> [ActionType] {
        switch target {
        case .ja_JP:
            return [.moveTab(.system(.user_japanese))]
        case .en_US, .it_IT:
            // Set the Latin language FIRST: the tab move reads it while updating the states.
            // タブ移動より先に言語を確定させる。
            return [.setLatinKeyboardLanguage(target), .moveTab(.system(.user_english))]
        case .none, .el_GR:
            return []
        }
    }

    func pressActions(variableStates: VariableStates) -> [ActionType] {
        actions(for: nextLanguage(variableStates: variableStates))
    }

    func longPressActions(variableStates _: VariableStates) -> LongpressActionType {
        .none
    }
    /// Copaky: with three languages in the cycle, long-pressing the key opens a direct-pick menu
    /// (あ / A / IT) — tapping still cycles. With two languages a tap already toggles, so no menu.
    /// Copaky: 3言語のときは長押しで直接選択メニューを表示（タップは従来どおり巡回）。
    func variationSpace(variableStates: VariableStates) -> UnifiedVariationSpace {
        let cycle = self.cycle
        guard cycle.count > 2 else {
            return .none
        }
        let elements = cycle.map { language in
            QwertyVariationsModel.VariationElement(
                label: .text(language.shortSymbol),
                actions: actions(for: language)
            )
        }
        return .linear(elements, direction: .right)
    }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        if let current = currentTabLanguage(variableStates: states), cycle.contains(current) {
            // "current / next": the key shows where you are and where one tap takes you.
            return KeyLabel(.selectable(current.shortSymbol, nextLanguage(variableStates: states).shortSymbol), width: width, textColor: color)
        }
        if SemiStaticStates.shared.needsInputModeSwitchKey, cycle.contains(states.keyboardLanguage) {
            return KeyLabel(.text(states.keyboardLanguage.symbol), width: width, textColor: color)
        }
        return KeyLabel(.text(KeyboardLanguage.ja_JP.symbol), width: width, textColor: color)
    }

    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
    }
    func feedback(variableStates _: VariableStates) {
        KeyboardFeedback<Extension>.tabOrOtherKey()
    }
}
