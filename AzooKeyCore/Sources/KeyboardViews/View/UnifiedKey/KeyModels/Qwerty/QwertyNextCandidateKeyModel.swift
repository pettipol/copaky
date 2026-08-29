import Foundation
import KeyboardThemes
import SwiftUI

struct QwertyNextCandidateKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    private let supportsSpaceSlideCursor: Bool

    init(supportsSpaceSlideCursor: Bool = false) {
        self.supportsSpaceSlideCursor = supportsSpaceSlideCursor
    }

    /// The "next candidate" role belongs to the CONVERSION metaphor, which is Japanese.
    ///
    /// On a Latin tab the space bar must insert a space, always: Latin typists reach for a
    /// candidate by tapping it, never by pressing space. This distinction did not bite before
    /// Copaky shipped an Italian lexicon, because the Latin tab produced almost no candidates —
    /// so the key behaved as a space bar by accident. With Italian on, nearly every word raises
    /// candidates, and the space bar stopped inserting spaces: the user's own report
    /// («la barra spazio italiana non funziona»), reproduced on the phone 2026-08-14 (the field
    /// read "perchéciao"). Gate the conversion behaviour on the Japanese language.
    /// 「次候補」は日本語の変換の概念。ラテン文字タブでは空白キーは常に空白を入力する。
    private func convertsCandidates(_ states: VariableStates) -> Bool {
        states.keyboardLanguage == .ja_JP && !states.resultModel.results.isEmpty
    }

    func pressActions(variableStates: VariableStates) -> [ActionType] {
        if convertsCandidates(variableStates) {
            [.selectCandidate(.offset(1))]
        } else {
            [.input(" ")]
        }
    }
    func longPressActions(variableStates: VariableStates) -> LongpressActionType {
        if convertsCandidates(variableStates) {
            .init(start: [.input(" ")])
        } else {
            .init(start: [.setCursorBar(.toggle)])
        }
    }
    func variationSpace(variableStates _: VariableStates) -> UnifiedVariationSpace {
        .none
    }

    func enablesSpaceSlideCursor(variableStates _: VariableStates) -> Bool {
        supportsSpaceSlideCursor && Extension.SettingProvider.enableSpaceSlideCursor
    }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        // Same rule as QwertySpaceKeyModel: Japanese tab keeps Japanese caps, Latin tabs localize.
        // The label must state what the key WILL do, so it follows the same gate as pressActions:
        // on a Latin tab it always reads as a space bar, because that is what it now inserts.
        // 日本語タブは日本語表記のまま、ラテン文字タブはUI言語に追従。表記は実際の動作に一致させる。
        if !convertsCandidates(states) {
            switch states.keyboardLanguage {
            case .ja_JP:
                return KeyLabel(.text("空白"), width: width, textSize: .small, textColor: color)
            case .el_GR:
                return KeyLabel(.text("διάστημα"), width: width, textSize: .small, textColor: color)
            default:
                return KeyLabel(.localizedText("空白"), width: width, textSize: .small, textColor: color)
            }
        } else {
            if states.keyboardLanguage == .ja_JP {
                return KeyLabel(.text("次候補"), width: width, textSize: .small, textColor: color)
            }
            return KeyLabel(.localizedText("次候補"), width: width, textSize: .small, textColor: color)
        }
    }

    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        // QwertyNextCandidateKeyModel uses normal background by default
        (theme.normalKeyFillColor.color, theme.normalKeyFillColor.blendMode)
    }

    func feedback(variableStates: VariableStates) {
        if convertsCandidates(variableStates) { KeyboardFeedback<Extension>.tabOrOtherKey() } else { KeyboardFeedback<Extension>.click() }
    }
}
