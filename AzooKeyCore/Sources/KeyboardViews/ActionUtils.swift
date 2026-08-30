//
//  Action.swift
//  Keyboard
//
//  Created by ensan on 2020/04/11.
//  Copyright © 2020 ensan. All rights reserved.
//

import CustardKit
import Foundation

public enum ClipboardLongPressSlot: String, CaseIterable, Hashable, Sendable {
    case qwertyNumbers
    case qwertySymbols
    case flickStar123
}

public struct ClipboardLongPressSlots: Equatable, Sendable {
    public private(set) var slots: Set<ClipboardLongPressSlot>

    public init(slots: Set<ClipboardLongPressSlot>) {
        self.slots = slots.isEmpty ? [.qwertyNumbers] : slots
    }

    public func contains(_ slot: ClipboardLongPressSlot) -> Bool {
        slots.contains(slot)
    }

    public mutating func set(_ slot: ClipboardLongPressSlot, enabled: Bool) {
        if enabled {
            slots.insert(slot)
        } else if slots.count > 1 {
            slots.remove(slot)
        }
    }
}

enum ClipboardLongPressSite: CaseIterable {
    case qwertyNumbers
    case qwertySymbols
    case flickStar123
    case qwertyDynamicNumbers
}

// Copaky [F-06]: map four rendered sites onto the three persisted slots before action/hint policy.
// Copaky [F-06]: 4つの表示位置を3つの保存スロットへ写像してから、動作とヒントを判定する。
enum ClipboardLongPressSlotDecision {
    static func slot(for site: ClipboardLongPressSite) -> ClipboardLongPressSlot {
        switch site {
        case .qwertyNumbers, .qwertyDynamicNumbers: .qwertyNumbers
        case .qwertySymbols: .qwertySymbols
        case .flickStar123: .flickStar123
        }
    }

    static func isEnabled(
        for site: ClipboardLongPressSite,
        clipboardHistoryEnabled: Bool,
        enabledSlots: ClipboardLongPressSlots
    ) -> Bool {
        clipboardHistoryEnabled && enabledSlots.contains(slot(for: site))
    }
}

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

// Copaky [F-07]: pure gate for replacing a second Latin-space tap with ". ". Host traits are
// resolved by the keyboard extension and passed as one fail-closed boolean to avoid module cycles.
// Copaky [F-07]: 2回目の空白を「. 」へ置換する純粋判定。入力欄の安全判定は呼出側で閉じる。
public enum DoubleSpacePeriodDecision {
    public static let maximumInterval: TimeInterval = 0.6

    public static func shouldReplace(
        documentContextBeforeInput context: String?,
        elapsedSincePreviousSpace: TimeInterval?,
        isEnabled: Bool,
        isLatinQwertyTab: Bool,
        languageUsesLatinScript: Bool,
        fieldAllowsReplacement: Bool
    ) -> Bool {
        guard isEnabled,
              isLatinQwertyTab,
              languageUsesLatinScript,
              fieldAllowsReplacement,
              let elapsedSincePreviousSpace,
              (0 ... maximumInterval).contains(elapsedSincePreviousSpace),
              let context,
              context.last == " " else {
            return false
        }
        let characterBeforeFirstSpace = context.dropLast().last
        return characterBeforeFirstSpace?.isLetter == true || characterBeforeFirstSpace?.isNumber == true
    }
}

// Copaky [F-04b]: lexical/state-only auto-capitalization policy. Structured host fields are
// rejected before this helper is called, and nil document context remains fail-closed.
// Copaky [F-04b]: 文脈と状態だけで文頭シフトを判定する。取得不能な文脈は fail-closed。
public enum LatinAutoCapitalizationDecision {
    public static func shouldArmShift(
        documentContextBeforeInput context: String?,
        isEnabled: Bool,
        isLatinQwertyTab: Bool,
        languageUsesLatinScript: Bool,
        isShifted: Bool,
        isCapsLocked: Bool,
        isComposing: Bool,
        fieldAllowsAutoCapitalization: Bool,
        hostUsesSentenceCapitalization: Bool
    ) -> Bool {
        guard isEnabled,
              isLatinQwertyTab,
              languageUsesLatinScript,
              !isShifted,
              !isCapsLocked,
              !isComposing,
              fieldAllowsAutoCapitalization,
              hostUsesSentenceCapitalization,
              let context else {
            return false
        }
        if context.isEmpty {
            return true
        }
        var sentenceTail = context[...]
        var sawNewline = false
        while let last = sentenceTail.last, last.isWhitespace {
            if last.isNewline {
                sawNewline = true
            }
            sentenceTail.removeLast()
        }
        // Counter-review major (30/08): Return starts a new sentence too, and terminators can be
        // followed by closing quotes/brackets («Ciao!» …). The ellipsis also ends a sentence.
        // 改行後も文頭。終端記号の後の閉じ引用符・括弧も許容し、三点リーダーも文末扱い。
        if sentenceTail.isEmpty || sawNewline {
            return true
        }
        while let last = sentenceTail.last, "\"'»”’』」)]".contains(last) {
            sentenceTail.removeLast()
        }
        return sentenceTail.last.map { ".!?…".contains($0) } ?? false
    }
}

// Copaky [E-09]: pure, width-derived quantization for space-bar cursor sliding.
// Copaky [E-09]: 通常QWERTYキー幅からカーソル移動量を量子化する純粋判定。
public enum SpaceSlideCursorSensitivity: String, CaseIterable, Sendable {
    case slow
    case medium
    case fast

    public var thresholdMultiplier: CGFloat {
        switch self {
        case .slow: 1.0
        case .medium: 0.7
        case .fast: 0.45
        }
    }
}

enum SpaceSlideCursorDecision {
    /// Scale the rendered ordinary QWERTY key width without introducing an absolute device constant.
    /// 描画済みQWERTYキー幅に倍率を掛け、端末依存の固定値を持ち込まない。
    static func stepThreshold(
        keyWidth: CGFloat,
        sensitivity: SpaceSlideCursorSensitivity
    ) -> CGFloat {
        guard keyWidth > 0 else { return .infinity }
        return keyWidth * sensitivity.thresholdMultiplier
    }

    static func totalSteps(
        horizontalTranslation: CGFloat,
        keyWidth: CGFloat,
        sensitivity: SpaceSlideCursorSensitivity,
        isEnabled: Bool
    ) -> Int {
        guard isEnabled else { return 0 }
        let threshold = stepThreshold(keyWidth: keyWidth, sensitivity: sensitivity)
        guard threshold.isFinite else { return 0 }
        return Int(horizontalTranslation / threshold)
    }

    static func incrementalSteps(
        horizontalTranslation: CGFloat,
        keyWidth: CGFloat,
        sensitivity: SpaceSlideCursorSensitivity,
        emittedSteps: Int,
        isEnabled: Bool
    ) -> Int {
        guard isEnabled else { return 0 }
        return totalSteps(
            horizontalTranslation: horizontalTranslation,
            keyWidth: keyWidth,
            sensitivity: sensitivity,
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
