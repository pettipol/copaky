import Foundation
import KeyboardThemes
import SwiftUI

struct UnifiedEnterKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    // Qwertyでは小さめの文字、Flickでは既定サイズを使う。nilの場合はデフォルトサイズ。
    private let textSize: Design.Fonts.LabelFontSizeStrategy

    init(textSize: Design.Fonts.LabelFontSizeStrategy = .small) {
        self.textSize = textSize
    }

    func pressActions(variableStates: VariableStates) -> [ActionType] {
        switch variableStates.enterKeyState {
        case .complete:
            return [.enter]
        case .return:
            return [.input("\n")]
        }
    }

    func longPressActions(variableStates _: VariableStates) -> LongpressActionType {
        .none
    }

    func variationSpace(variableStates _: VariableStates) -> UnifiedVariationSpace { .none }

    private func specialTextColor<ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable>(states: VariableStates, theme: ThemeData<ThemeExtension>) -> Color? {
        switch states.enterKeyState {
        case .complete:
            return nil
        case let .return(type):
            switch type {
            case .default:
                return nil
            default:
                if theme == ThemeExtension.native {
                    return .white
                } else {
                    return nil
                }
            }
        }
    }

    func label<ThemeExtension>(width: CGFloat, theme: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        let text = Design.language.getEnterKeyText(states.enterKeyState)
        let isLatinQwertyTab: Bool = switch states.tabManager.existentialTab() {
        case .qwerty_abc, .qwerty_numbers, .qwerty_symbols: true
        default: false
        }
        // Copaky [F-07]: only the plain newline state on Latin layouts uses Apple's return icon.
        // Search/Go/Done/Send and Japanese conversion states remain localized text.
        // Copaky [F-07]: ラテン配列の通常改行だけApple風アイコンにし、他の状態は文字表示を保つ。
        if isLatinQwertyTab,
           states.keyboardLanguage.usesLatinScript,
           case .return(.default) = states.enterKeyState {
            return KeyLabel(
                .image("arrow.turn.down.left", accessibilityLabel: "改行"),
                width: width,
                textSize: textSize,
                textColor: color ?? specialTextColor(states: states, theme: theme)
            )
        }
        // Copaky: on the JAPANESE tab the enter cap stays Japanese (確定/改行…) whatever the UI
        // language — Apple does the same on its JP layouts, and it is the one visual cue that
        // tells the Japanese QWERTY apart from the visually identical Latin QWERTY.
        // 日本語タブでは表示言語に関わらず日本語のまま（ラテン文字タブとの見分けの手がかり）。
        if states.keyboardLanguage == .ja_JP {
            return KeyLabel(.text(text), width: width, textSize: textSize, textColor: color ?? specialTextColor(states: states, theme: theme))
        }
        return KeyLabel(.localizedText(text), width: width, textSize: textSize, textColor: color ?? specialTextColor(states: states, theme: theme))
    }

    func backgroundStyleWhenUnpressed<ThemeExtension>(states: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        switch states.enterKeyState {
        case .complete:
            return (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
        case let .return(type):
            switch type {
            case .default:
                return (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
            default:
                if theme == ThemeExtension.default {
                    return (Design.colors.specialEnterKeyColor, .normal)
                } else if theme == ThemeExtension.native {
                    return (.accentColor, .normal)
                } else {
                    return (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
                }
            }
        }
    }

    func feedback(variableStates: VariableStates) {
        switch variableStates.enterKeyState {
        case .complete:
            KeyboardFeedback<Extension>.tabOrOtherKey()
        case let .return(type):
            switch type {
            case .default:
                KeyboardFeedback<Extension>.click()
            default:
                KeyboardFeedback<Extension>.tabOrOtherKey()
            }
        }
    }
}
