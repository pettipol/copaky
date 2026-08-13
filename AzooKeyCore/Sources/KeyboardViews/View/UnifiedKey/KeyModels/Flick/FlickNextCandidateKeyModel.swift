import CustardKit
import Foundation
import KeyboardThemes
import SwiftUI

struct FlickNextCandidateKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: UnifiedKeyModelProtocol {
    func pressActions(variableStates: VariableStates) -> [ActionType] {
        if variableStates.resultModel.results.isEmpty {
            [.input(" ")]
        } else {
            [.selectCandidate(.offset(1))]
        }
    }
    func longPressActions(variableStates: VariableStates) -> LongpressActionType {
        if variableStates.resultModel.results.isEmpty {
            .init(start: [.setCursorBar(.toggle)])
        } else {
            .init(repeat: [.selectCandidate(.offset(1))])
        }
    }
    func variationSpace(variableStates: VariableStates) -> UnifiedVariationSpace {
        let left: UnifiedVariation = if variableStates.resultModel.selection != nil {
            UnifiedVariation(label: .text("前候補"), pressActions: [.selectCandidate(.offset(-1))], longPressActions: .init(repeat: [.selectCandidate(.offset(-1))]))
        } else {
            UnifiedVariation(label: .text("←"), pressActions: [.moveCursor(-1)], longPressActions: .init(repeat: [.moveCursor(-1)]))
        }
        return .fourWay([
            .left: left,
            .top: UnifiedVariation(label: .text("全角"), pressActions: [.input("　")]),
            .bottom: UnifiedVariation(label: .text("Tab"), pressActions: [.input("\u{0009}")]),
        ])
    }
    func isFlickAble(to direction: FlickDirection, variableStates _: VariableStates) -> Bool {
        switch direction {
        case .left, .top, .bottom: true
        case .right: false
        }
    }

    func label<ThemeExtension>(width: CGFloat, theme _: ThemeData<ThemeExtension>, states: VariableStates, color _: Color?) -> KeyLabel<Extension> where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        // Copaky: same rule as the QWERTY models — the JAPANESE tab keeps Japanese caps whatever
        // the UI language (this key replaces the flick space when 次候補キー is enabled).
        // 日本語タブでは常に日本語表記（QWERTY側と同じ規則）。
        let text = states.resultModel.results.isEmpty ? "空白" : "次候補"
        if states.keyboardLanguage == .ja_JP {
            return KeyLabel(.text(text), width: width)
        }
        return KeyLabel(.localizedText(text), width: width)
    }
    func backgroundStyleWhenUnpressed<ThemeExtension>(states _: VariableStates, theme: ThemeData<ThemeExtension>) -> UnifiedKeyBackgroundStyleValue where ThemeExtension: ApplicationSpecificKeyboardViewExtensionLayoutDependentDefaultThemeProvidable {
        (theme.specialKeyFillColor.color, theme.specialKeyFillColor.blendMode)
    }
    func feedback(variableStates: VariableStates) {
        if variableStates.resultModel.results.isEmpty {
            KeyboardFeedback<Extension>.click()
        } else {
            KeyboardFeedback<Extension>.tabOrOtherKey()
        }
    }
}
