import CustardKit
import Foundation
import KeyboardThemes
import SwiftUI
import enum KanaKanjiConverterModule.KeyboardLanguage

struct QwertyDynamicChangeKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    func pressActions(variableStates states: VariableStates) -> [ActionType] {
        if SemiStaticStates.shared.needsInputModeSwitchKey {
            switch states.tabManager.existentialTab() {
            case .qwerty_abc:
                if QwertyLayoutProvider<Extension>.shiftBehaviorPreference() != .leftbottom || states.boolStates.isShifted || states.boolStates.isCapsLocked {
                    [] // system globe
                } else {
                    [.moveTab(.system(.qwerty_numbers))]
                }
            default:
                [] // system globe
            }
        } else {
            switch states.tabManager.existentialTab() {
            case .qwerty_hira:
                [.moveTab(.system(.qwerty_symbols))]
            case .qwerty_abc:
                if QwertyLayoutProvider<Extension>.shiftBehaviorPreference() != .leftbottom || states.boolStates.isShifted || states.boolStates.isCapsLocked {
                    [.moveTab(.system(.qwerty_symbols))]
                } else {
                    [.moveTab(.system(.qwerty_numbers))]
                }
            case .qwerty_numbers, .qwerty_symbols:
                [.moveTab(.system(.user_english))]
            default:
                [.setCursorBar(.toggle)]
            }
        }
    }

    func longPressActions(variableStates: VariableStates) -> LongpressActionType {
        let shiftRole = QwertyLayoutProvider<Extension>.shiftBehaviorPreference() != .leftbottom || variableStates.boolStates.isShifted || variableStates.boolStates.isCapsLocked
        let tab = variableStates.tabManager.existentialTab()
        let isLatinTab: Bool = switch tab {
        case .qwerty_abc, .qwerty_numbers, .qwerty_symbols: true
        default: false
        }
        let onAbcTab: Bool = switch tab {
        case .qwerty_abc: true
        default: false
        }
        // Copaky [A-11]: on the Latin tabs this slot (123 / #+= / ABC-back, in every Shift mode) opens
        // Clipboard history on long press when the history is on — unless the key currently IS the
        // system globe (needsInputModeSwitchKey), which has no Copaky long press. Counter-review fix:
        // the default «#+=» role (UseShiftKey off) was left without any long press.
        // Copaky [A-11]: ラテン文字タブではこのスロット（123 / #+= / ABC 戻る、全 Shift 状態）が長押しで
        // 履歴を開く。システムのグローブ役のときだけ対象外。
        let isGlobeRole = SemiStaticStates.shared.needsInputModeSwitchKey && (!onAbcTab || shiftRole)
        if isLatinTab && !isGlobeRole {
            return .init(start: NumbersSlotLongPressDecision.longPressActionsForNumbersSlot(
                clipboardHistoryEnabled: variableStates.keyboardLanguage.usesLatinScript
                    && variableStates.clipboardHistoryManager.isEnabled
            ))
        }
        return shiftRole ? .none : .init(start: [.setTabBar(.toggle)])
    }
    func variationSpace(variableStates _: VariableStates) -> UnifiedVariationSpace { .none }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        if SemiStaticStates.shared.needsInputModeSwitchKey {
            switch states.tabManager.existentialTab() {
            case .qwerty_abc:
                if QwertyLayoutProvider<Extension>.shiftBehaviorPreference() != .leftbottom || states.boolStates.isShifted || states.boolStates.isCapsLocked {
                    KeyLabel(.changeKeyboard, width: width, textColor: color)
                } else {
                    KeyLabel(.image("textformat.123"), width: width, textColor: color)
                }
            default:
                KeyLabel(.changeKeyboard, width: width, textColor: color)
            }
        } else {
            switch states.tabManager.existentialTab() {
            case .qwerty_hira:
                KeyLabel(.text("#+="), width: width, textColor: color)
            case .qwerty_abc:
                if QwertyLayoutProvider<Extension>.shiftBehaviorPreference() != .leftbottom || states.boolStates.isShifted || states.boolStates.isCapsLocked {
                    KeyLabel(.text("#+="), width: width, textColor: color)
                } else {
                    KeyLabel(.image("textformat.123"), width: width, textColor: color)
                }
            case .qwerty_numbers, .qwerty_symbols:
                KeyLabel(.text(KeyboardLanguage.en_US.symbol), width: width, textColor: color)
            default:
                KeyLabel(.image("arrowtriangle.left.and.line.vertical.and.arrowtriangle.right"), width: width, textColor: color)
            }
        }
    }
    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
    }
    func feedback(variableStates _: VariableStates) {
        KeyboardFeedback<Extension>.tabOrOtherKey()
    }
}
