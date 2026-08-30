import CustardKit
import Foundation
import KeyboardThemes
import SwiftUI
import enum KanaKanjiConverterModule.KeyboardLanguage

struct QwertyDynamicChangeKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    @MainActor private func usesNumbersSlotLongPress(variableStates: VariableStates) -> Bool {
        let shiftRole = QwertyLayoutProvider<Extension>.shiftBehaviorPreference() != .leftbottom
            || variableStates.boolStates.isShifted
            || variableStates.boolStates.isCapsLocked
        let tab = variableStates.tabManager.existentialTab()
        let isLatinTab: Bool = switch tab {
        case .qwerty_abc, .qwerty_numbers, .qwerty_symbols: true
        default: false
        }
        let onAbcTab: Bool = switch tab {
        case .qwerty_abc: true
        default: false
        }
        let isGlobeRole = SemiStaticStates.shared.needsInputModeSwitchKey && (!onAbcTab || shiftRole)
        return isLatinTab && !isGlobeRole
    }

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
        // Copaky [F-06]: this dynamic numbers-access key follows qwertyNumbers even when its label
        // becomes #+= or ABC-back. It opens history unless the key currently IS the system globe.
        // system globe (needsInputModeSwitchKey), which has no Copaky long press. Counter-review fix:
        // the default «#+=» role (UseShiftKey off) was left without any long press.
        // Copaky [F-06]: 表示が #+= / ABC 戻るに変わっても数字アクセス用の動的キーは
        // qwertyNumbers スロットに従う。システムのグローブ役のときだけ対象外。
        if usesNumbersSlotLongPress(variableStates: variableStates) {
            return .init(start: NumbersSlotLongPressDecision.longPressActionsForNumbersSlot(
                clipboardHistoryEnabled: ClipboardLongPressSlotDecision.isEnabled(
                    for: .qwertyDynamicNumbers,
                    clipboardHistoryEnabled: variableStates.keyboardLanguage.usesLatinScript
                        && variableStates.clipboardHistoryManager.isEnabled,
                    enabledSlots: Extension.SettingProvider.clipboardLongPressSlots
                )
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
                    KeyLabel(.image("textformat.123", accessibilityLabel: "数字"), width: width, textColor: color)
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
                    KeyLabel(.image("textformat.123", accessibilityLabel: "数字"), width: width, textColor: color)
                }
            case .qwerty_numbers, .qwerty_symbols:
                KeyLabel(.text(KeyboardLanguage.en_US.symbol), width: width, textColor: color)
            default:
                KeyLabel(.image("arrowtriangle.left.and.line.vertical.and.arrowtriangle.right", accessibilityLabel: "カーソルバーの切り替え"), width: width, textColor: color)
            }
        }
    }

    @MainActor func labelCornerHintSystemImage(variableStates: VariableStates) -> String? {
        guard usesNumbersSlotLongPress(variableStates: variableStates),
              ClipboardHistoryKeyHintDecision.shouldShow(
                  clipboardHistoryEnabled: ClipboardLongPressSlotDecision.isEnabled(
                      for: .qwertyDynamicNumbers,
                      clipboardHistoryEnabled: variableStates.keyboardLanguage.usesLatinScript
                          && variableStates.clipboardHistoryManager.isEnabled,
                      enabledSlots: Extension.SettingProvider.clipboardLongPressSlots
                  )
              ) else {
            return nil
        }
        return "doc.badge.clock"
    }
    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
    }
    func feedback(variableStates _: VariableStates) {
        KeyboardFeedback<Extension>.tabOrOtherKey()
    }
}
