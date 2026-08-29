import Foundation
import KeyboardThemes
import SwiftUI

struct QwertySpaceKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    private let supportsSpaceSlideCursor: Bool

    init(supportsSpaceSlideCursor: Bool = false) {
        self.supportsSpaceSlideCursor = supportsSpaceSlideCursor
    }

    func pressActions(variableStates _: VariableStates) -> [ActionType] {
        [.input(" ")]
    }
    func longPressActions(variableStates _: VariableStates) -> LongpressActionType {
        .init(start: [.setCursorBar(.toggle)])
    }
    func variationSpace(variableStates _: VariableStates) -> UnifiedVariationSpace {
        .none
    }

    func enablesSpaceSlideCursor(variableStates _: VariableStates) -> Bool {
        supportsSpaceSlideCursor && Extension.SettingProvider.enableSpaceSlideCursor
    }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        // Copaky: the space key cap follows the UI language on LATIN tabs, but stays Japanese on
        // the JAPANESE tab (Apple does the same) — on the JP QWERTY the space key CONVERTS, and
        // 空白 is the visual cue that distinguishes it from the identical-looking Latin QWERTY,
        // where space really inserts a space. Greek keeps its upstream hard-coded cap because the
        // app ships no Greek localization to fall back on.
        // 日本語タブの空白キーは常に「空白」（変換動作の目印）。ラテン文字タブはUI言語に追従。
        switch states.keyboardLanguage {
        case .ja_JP:
            return KeyLabel(.text("空白"), width: width, textSize: .small, textColor: color)
        case .el_GR:
            return KeyLabel(.text("διάστημα"), width: width, textSize: .small, textColor: color)
        default:
            return KeyLabel(.localizedText("空白"), width: width, textSize: .small, textColor: color)
        }
    }

    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        (theme.normalKeyFillColor.color, theme.normalKeyFillColor.blendMode)
    }
    func feedback(variableStates _: VariableStates) {
        KeyboardFeedback<Extension>.click()
    }
}
