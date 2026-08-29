//
//  Action.swift
//  Keyboard
//
//  Created by ensan on 2020/04/11.
//  Copyright © 2020 ensan. All rights reserved.
//

import CustardKit
import Foundation

// Copaky: one-gesture clipboard access from the existing 123 / #+= / ☆123 slot.
// Copaky: 既存の 123 / #+= / ☆123 スロットから1ジェスチャーで履歴を開く。
enum NumbersSlotLongPressDecision {
    static func longPressActionsForNumbersSlot(clipboardHistoryEnabled: Bool) -> [ActionType] {
        clipboardHistoryEnabled
            ? [.moveTab(.system(.clipboard_history_tab))]
            : [.setTabBar(.toggle)]
    }
}

// Copaky [E-12]: pure policy for collapsing only an actually empty Latin QWERTY bar.
// Copaky [E-12]: 空のラテン文字QWERTY候補バーだけを折りたたむ純粋な判定。
enum CandidateBarVisibilityDecision {
    static func isVisible(
        isLatinQwertyTab: Bool,
        hasCandidates: Bool,
        hasPredictions: Bool,
        hasNoticeOrAlternateBarContent: Bool,
        copakyButtonVisible: Bool,
        hideEmptyLatinBarEnabled: Bool,
        hasMessageView: Bool = false,
        hasTemporalMessage: Bool = false
    ) -> Bool {
        !isLatinQwertyTab
            || !hideEmptyLatinBarEnabled
            || hasCandidates
            || hasPredictions
            || hasNoticeOrAlternateBarContent
            || copakyButtonVisible
            || hasMessageView
            || hasTemporalMessage
    }
}

// Copaky [A-12]: the visual affordance follows the same live opt-in as the gesture.
// Copaky [A-12]: ジェスチャーと同じライブ設定に従う視覚ヒント。
enum ClipboardHistoryKeyHintDecision {
    static func shouldShow(clipboardHistoryEnabled: Bool) -> Bool {
        clipboardHistoryEnabled
    }
}

// Copaky [E-09]: pure, width-derived quantization for space-bar cursor sliding.
// Copaky [E-09]: 通常QWERTYキー幅からカーソル移動量を量子化する純粋判定。
enum SpaceSlideCursorDecision {
    /// One cursor action per rendered ordinary QWERTY key width.
    static func stepThreshold(keyWidth: CGFloat) -> CGFloat {
        guard keyWidth > 0 else { return .infinity }
        return keyWidth
    }

    static func totalSteps(
        horizontalTranslation: CGFloat,
        keyWidth: CGFloat,
        isEnabled: Bool
    ) -> Int {
        guard isEnabled else { return 0 }
        let threshold = stepThreshold(keyWidth: keyWidth)
        guard threshold.isFinite else { return 0 }
        return Int(horizontalTranslation / threshold)
    }

    static func incrementalSteps(
        horizontalTranslation: CGFloat,
        keyWidth: CGFloat,
        emittedSteps: Int,
        isEnabled: Bool
    ) -> Int {
        guard isEnabled else { return 0 }
        return totalSteps(
            horizontalTranslation: horizontalTranslation,
            keyWidth: keyWidth,
            isEnabled: true
        ) - emittedSteps
    }
}

extension CodableActionData {
    var actionType: ActionType {
        switch self {
        case let .input(value):
            return .input(value)
        case let .directInput(value):
            return .input(value, simplyInsert: true)
        case let .replaceDefault(value):
            return .changeCharacterType(value)
        case let .replaceLastCharacters(value):
            return .replaceLastCharacters(value)
        case let .delete(value):
            return .delete(value)
        case .smartDeleteDefault:
            return .smoothDelete
        case let .smartDelete(value):
            return .smartDelete(value)
        case .selectCandidate(let selection):
            return .selectCandidate(selection)
        case .complete:
            return .enter
        case .completeCharacterForm(let forms):
            return .completeCharacterForm(forms)
        case let .moveCursor(value):
            return .moveCursor(value)
        case let .smartMoveCursor(value):
            return .smartMoveCursor(value)
        case let .moveTab(value):
            return .moveTab(value)
        case .enableResizingMode:
            return .enableResizingMode
        case .toggleCursorBar:
            return .setCursorBar(.toggle)
        case .toggleCapsLockState:
            return .setBoolState(VariableStates.BoolStates.isCapsLockedKey, .toggle)
        case .toggleTabBar:
            return .setTabBar(.toggle)
        case let .launchApplication(value):
            switch value.scheme {
            case .azooKey:
                return .openApp("copaky://" + value.target)
            case .shortcuts:
                return .openApp("shortcuts://" + value.target)
            }
        case .dismissKeyboard:
            return .dismissKeyboard
        case .paste:
            return .paste
        }
    }
}

extension CodableLongpressActionData {
    var longpressActionType: LongpressActionType {
        let duration: LongpressActionType.Duration = switch self.duration {
        case .normal: .normal
        case .light: .light
        }
        return .init(
            duration: duration,
            start: self.start.map {$0.actionType},
            repeat: self.repeat.map {$0.actionType}
        )
    }
}

public extension ActionType {
    @MainActor func feedback<Extension: ApplicationSpecificKeyboardViewExtension>(variableStates: VariableStates, extension _: Extension.Type) {
        switch self {
        case .input, .paste, .insertMainDisplay:
            KeyboardFeedback<Extension>.click()
        case .delete:
            KeyboardFeedback<Extension>.delete()
        case .smoothDelete, .smartDelete, .smartMoveCursor:
            KeyboardFeedback<Extension>.smoothDelete()
        case .moveTab, .setLatinKeyboardLanguage, .enter, .changeCharacterType, .completeCharacterForm, .setCursorBar, .moveCursor, .enableResizingMode, .replaceLastCharacters, .setTabBar, .setBoolState, .setUpsideComponent, .setSearchQuery, .selectCandidate:
            KeyboardFeedback<Extension>.tabOrOtherKey()
        case .openApp, .dismissKeyboard, .hideLearningMemory:
            return
        case let .boolSwitch(compiledExpression, trueAction, falseAction):
            if let condition = variableStates.boolStates.evaluateExpression(compiledExpression) {
                if condition {
                    trueAction.first?.feedback(variableStates: variableStates, extension: Extension.self)
                } else {
                    falseAction.first?.feedback(variableStates: variableStates, extension: Extension.self)
                }
            }
        }
    }
}
