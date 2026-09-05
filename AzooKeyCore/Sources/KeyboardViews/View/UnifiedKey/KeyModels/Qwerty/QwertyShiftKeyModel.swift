import Foundation
import KeyboardThemes
import SwiftUI

struct QwertyShiftKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    func pressActions(variableStates: VariableStates) -> [ActionType] {
        if variableStates.boolStates.isCapsLocked {
            return [.setBoolState(VariableStates.BoolStates.isCapsLockedKey, .off)]
        } else if variableStates.boolStates.isShifted {
            return [.setBoolState(VariableStates.BoolStates.isShiftedKey, .off)]
        } else {
            return [.setBoolState(VariableStates.BoolStates.isShiftedKey, .on)]
        }
    }

    func longPressActions(variableStates _: VariableStates) -> LongpressActionType {
        .init(start: [.setBoolState(VariableStates.BoolStates.isCapsLockedKey, .toggle)])
    }

    func doublePressActions(variableStates: VariableStates) -> [ActionType] {
        if variableStates.boolStates.isCapsLocked {
            return []
        } else {
            return [.setBoolState(VariableStates.BoolStates.isCapsLockedKey, .on)]
        }
    }

    func variationSpace(variableStates _: VariableStates) -> UnifiedVariationSpace {
        .none
    }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        if states.boolStates.isCapsLocked {
            // Copaky [G-01]: explicit tri-state value for VoiceOver (off / active / locked).
            return KeyLabel(.image("capslock.fill", accessibilityLabel: "大文字に固定する"), width: width, textColor: color, accessibilityValue: "大文字に固定中")
        } else if states.boolStates.isShifted {
            // Copaky [G-01]: VoiceOver distinguishes one-shot Shift from the inactive state.
            return KeyLabel(
                .image("shift.fill", accessibilityLabel: "大文字"),
                width: width,
                textColor: color,
                accessibilityValue: "有効"
            )
        } else {
            return KeyLabel(.image("shift", accessibilityLabel: "大文字"), width: width, textColor: color, accessibilityValue: "オフ")
        }
    }

    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
    }

    func feedback(variableStates _: VariableStates) {
        KeyboardFeedback<Extension>.tabOrOtherKey()
    }
}
