import Foundation
import KeyboardThemes
import SwiftUI

struct QwertyGeneralKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    enum UnpressedRole {
        case normal
        case special
        case selected
        case unimportant
    }

    private let showsBubbleFlag: Bool
    private let labelType: KeyLabelType
    private let press: (VariableStates) -> [ActionType]
    private let longpress: (VariableStates) -> LongpressActionType
    private let variations: [QwertyVariationsModel.VariationElement]
    private let direction: VariationsViewDirection
    private let role: UnpressedRole
    private let clipboardLongPressSite: ClipboardLongPressSite?
    // 文字キー等で英語時シフト・Capsで大文字化するか（カスタムキー等では無効にしたい）
    private let shouldUppercaseForEnglish: Bool

    init(labelType: KeyLabelType,
         pressActions: @escaping (VariableStates) -> [ActionType],
         longPressActions: @escaping (VariableStates) -> LongpressActionType,
         variations: [QwertyVariationsModel.VariationElement],
         direction: VariationsViewDirection,
         showsTapBubble: Bool,
         role: UnpressedRole,
         shouldUppercaseForEnglish: Bool = true,
         clipboardLongPressSite: ClipboardLongPressSite? = nil
    ) {
        self.labelType = labelType
        self.press = pressActions
        self.longpress = longPressActions
        self.variations = variations
        self.direction = direction
        self.showsBubbleFlag = showsTapBubble
        self.role = role
        self.shouldUppercaseForEnglish = shouldUppercaseForEnglish
        self.clipboardLongPressSite = clipboardLongPressSite
    }

    // 静的アクション版（LinearCustomの置き換え用）
    init(labelType: KeyLabelType,
         pressActions: [ActionType],
         longPressActions: LongpressActionType,
         variations: [QwertyVariationsModel.VariationElement],
         direction: VariationsViewDirection = .center,
         showsTapBubble: Bool,
         role: UnpressedRole,
         shouldUppercaseForEnglish: Bool = true,
         clipboardLongPressSite: ClipboardLongPressSite? = nil
    ) {
        self.init(
            labelType: labelType,
            pressActions: { _ in pressActions },
            longPressActions: { _ in longPressActions },
            variations: variations,
            direction: direction,
            showsTapBubble: showsTapBubble,
            role: role,
            shouldUppercaseForEnglish: shouldUppercaseForEnglish,
            clipboardLongPressSite: clipboardLongPressSite
        )
    }

    func pressActions(variableStates: VariableStates) -> [ActionType] { press(variableStates) }
    func longPressActions(variableStates: VariableStates) -> LongpressActionType { longpress(variableStates) }
    func variationSpace(variableStates: VariableStates) -> UnifiedVariationSpace {
        // Copaky: 長押しバリエーションのラベルも英語シフト・Caps時は大文字化（actionsはdoAction側で大文字化済み）
        // Counter-review major (30/08): the INSERTED case follows every Latin-script language
        // (doAction), so the shown label must too — with Italian active a shifted key otherwise
        // shows "c" but types "C". / 挿入はラテン文字言語全体が大文字化されるため表示も揃える。
        if shouldUppercaseForEnglish,
           variableStates.boolStates.isCapsLocked || variableStates.boolStates.isShifted,
           variableStates.keyboardLanguage.usesLatinScript {
            let uppercased = variations.map { element -> QwertyVariationsModel.VariationElement in
                if case let .text(text) = element.label {
                    return QwertyVariationsModel.VariationElement(label: .text(text.uppercased()), actions: element.actions)
                }
                return element
            }
            return .linear(uppercased, direction: direction)
        }
        return .linear(variations, direction: direction)
    }
    @MainActor func showsTapBubble(variableStates _: VariableStates) -> Bool { showsBubbleFlag }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        // Emulate QwertyKeyModel: uppercase for en_US when shifted or caps（必要時のみ）
        if shouldUppercaseForEnglish,
           states.boolStates.isCapsLocked || states.boolStates.isShifted,
           states.keyboardLanguage.usesLatinScript {
            switch labelType {
            case let .text(text):
                return KeyLabel(.text(text.uppercased()), width: width, textColor: color)
            case let .textWithUpperHint(main, hint):
                return KeyLabel(.textWithUpperHint(main.uppercased(), hint), width: width, textColor: color)
            default:
                break
            }
        }
        return KeyLabel(labelType, width: width, textColor: color)
    }

    @MainActor func labelCornerHintSystemImage(variableStates: VariableStates) -> String? {
        guard let clipboardLongPressSite,
              ClipboardHistoryKeyHintDecision.shouldShow(
                  clipboardHistoryEnabled: ClipboardLongPressSlotDecision.isEnabled(
                      for: clipboardLongPressSite,
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
        switch role {
        case .normal: (theme.normalKeyFillColor.color, theme.normalKeyFillColor.blendMode)
        case .special: (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
        case .selected: (theme.pushedKeyFillColor.color, theme.pushedKeyFillColor.blendMode)
        case .unimportant: (Color(white: 0, opacity: 0.001), .normal)
        }
    }

    func feedback(variableStates: VariableStates) {
        press(variableStates).first?.feedback(variableStates: variableStates, extension: Extension.self)
    }
}
