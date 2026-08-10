import Foundation
import KeyboardThemes
import SwiftUI

struct QwertySpaceKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    func pressActions(variableStates _: VariableStates) -> [ActionType] {
        [.input(" ")]
    }
    func longPressActions(variableStates _: VariableStates) -> LongpressActionType {
        .init(start: [.setCursorBar(.toggle)])
    }
    func variationSpace(variableStates _: VariableStates) -> UnifiedVariationSpace {
        .none
    }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        // Copaky: the space key cap is a WORD the user reads, so it follows the UI language via the
        // string catalog — not the keyboard language, which is what used to leave 「空白」 on an
        // English phone. Greek keeps its upstream hard-coded cap because the app ships no Greek
        // localization to fall back on.
        // スペースキーの表記はUI言語に追従させる（ギリシャ語のみ上位互換のため据え置き）。
        if states.keyboardLanguage == .el_GR {
            return KeyLabel(.text("διάστημα"), width: width, textSize: .small, textColor: color)
        }
        return KeyLabel(.localizedText("空白"), width: width, textSize: .small, textColor: color)
    }

    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        (theme.normalKeyFillColor.color, theme.normalKeyFillColor.blendMode)
    }
    func feedback(variableStates _: VariableStates) {
        KeyboardFeedback<Extension>.click()
    }
}
