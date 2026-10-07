//
//  ResultBar.swift
//  azooKey
//
//  Created by ensan on 2023/03/19.
//  Copyright © 2023 ensan. All rights reserved.
//

import SwiftUI
import SwiftUIUtils
import SwiftUtils

private struct EquatablePair<First: Equatable, Second: Equatable>: Equatable {
    var first: First
    var second: Second
}

private extension Equatable {
    func and<T: Equatable>(_ value: T) -> EquatablePair<Self, T> {
        .init(first: self, second: value)
    }
}

@MainActor
struct ResultBar<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    @Environment(Extension.Theme.self) private var theme
    @Environment(\.userActionManager) private var action
    @EnvironmentObject private var variableStates: VariableStates
    @Binding private var isResultViewExpanded: Bool
    private let compactIdleBar: Bool
    @State private var undoButtonAction: VariableStates.UndoAction?
    // Copaky: hiding a used chip is transient UI state; saved history is untouched.
    @State private var usedRecentClipboardItems: Set<ClipboardHistoryItem> = []
    private var displayTabBarButton: Bool {
        Extension.SettingProvider.displayTabBarButton
    }

    private var buttonWidth: CGFloat {
        Design.keyboardBarHeight(interfaceHeight: variableStates.interfaceSize.height, orientation: variableStates.keyboardOrientation) * 0.5
    }
    private var buttonHeight: CGFloat {
        Design.keyboardBarHeight(interfaceHeight: variableStates.interfaceSize.height, orientation: variableStates.keyboardOrientation) * 0.6
    }
    private var toolbarContentHeight: CGFloat {
        // Copaky: use the parent projection explicitly; full bars can be shorter than 44 pt.
        // Copaky: 親の表示方式を明示的に使い、通常バーが44pt未満でも子をはみ出させない。
        if compactIdleBar {
            return Design.keyboardBarCompactContentHeight(interfaceHeight: variableStates.interfaceSize.height,
                                                          interfaceWidth: variableStates.interfaceSize.width,
                                                          orientation: variableStates.keyboardOrientation)
        }
        return min(44, max(0, Design.keyboardBarHeight(interfaceHeight: variableStates.interfaceSize.height,
                                                     orientation: variableStates.keyboardOrientation)))
    }
    private var undoVerticalPadding: CGFloat {
        displayTabBarButton ? min(5, toolbarContentHeight / 2) : 5
    }
    private var compactButtonHeight: CGFloat {
        max(0, toolbarContentHeight - 2 * undoVerticalPadding)
    }

    init(isResultViewExpanded: Binding<Bool>, compactIdleBar: Bool = false) {
        self._isResultViewExpanded = isResultViewExpanded
        self.compactIdleBar = compactIdleBar
    }

    private var tabBarButton: some View {
        TabBarButton<Extension>()
            .zIndex(10)
    }

    private var idleToolbar: some View {
        HStack(spacing: 6) {
            if displayTabBarButton {
                // Copaky: privacy/empty history may produce EmptyView; retain a real flexible
                // slot so the menu remains at the right edge without a hit-testing surface.
                // Copaky: 履歴が表示されなくても、右端メニュー用の伸縮領域を確保する。
                ZStack(alignment: .leading) {
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    RecentClipboardChips<Extension>(usedItems: $usedRecentClipboardItems, contentHeight: toolbarContentHeight)
                }
                    .frame(height: toolbarContentHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            if let undoButtonAction {
                Button("取り消す", systemImage: "arrow.uturn.backward") {
                    // Copaky: revalidate and consume the current token at the tap, rather
                    // than executing a stale action captured by the rendered button.
                    // Copaky: タップ時にも現在の復元トークンを確認し、一度だけ消費する。
                    guard let current = variableStates.undoAction, current == undoButtonAction,
                          current.textChangedCount == variableStates.textChangedCount else { return }
                    variableStates.undoAction = nil
                    self.undoButtonAction = nil
                    KeyboardFeedback<Extension>.click()
                    self.action.registerAction(current.action, variableStates: variableStates)
                }
                .buttonStyle(ResultButtonStyle<Extension>(height: displayTabBarButton ? compactButtonHeight : buttonHeight,
                                                         verticalPadding: undoVerticalPadding))
                .fixedSize(horizontal: true, vertical: false)
            }
            if displayTabBarButton {
                TabBarButton<Extension>(compact: true, contentHeight: toolbarContentHeight)
            } else {
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            if variableStates.undoAction?.textChangedCount == variableStates.textChangedCount {
                self.undoButtonAction = variableStates.undoAction
            } else {
                self.undoButtonAction = nil
            }
        }
        .onChange(of: variableStates.undoAction.and(variableStates.textChangedCount)) { (_, newValue) in
            withAnimation(.easeInOut(duration: 0.2)) {
                if newValue.first?.textChangedCount == newValue.second {
                    self.undoButtonAction = newValue.first
                } else {
                    self.undoButtonAction = nil
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        Group {
            if variableStates.resultModel.displayState == .nothing {
                // Copaky: explicit controls own the enabled toolbar. Keep the legacy
                // full-row gesture and its hit surface only in the menu-OFF branch.
                // Copaky: ONでは個別の操作領域を使い、行全体の長押しはOFF側に保つ。
                if displayTabBarButton {
                    idleToolbar
                } else {
                    idleToolbar
                        .background(Color(.sRGB, white: 1, opacity: 0.001))
                        .onLongPressGesture {
                            self.action.registerAction(.setTabBar(.toggle), variableStates: variableStates)
                        }
                }
            } else {
                HStack {
                    if variableStates.resultModel.displayState == .predictions && displayTabBarButton {
                        tabBarButton
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        ScrollViewReader {scrollViewProxy in
                            LazyHStack(spacing: 10) {
                                ForEach(variableStates.resultModel.resultData, id: \.id) {(data: ResultData) in
                                    switch data.candidate.label {
                                    case .text(let value):
                                        if data.candidate.inputable {
                                            Button(action: {
                                                KeyboardFeedback<Extension>.click()
                                                self.pressed(data)
                                            }, label: {
                                                Text(
                                                    Design.fonts.forceJapaneseFont(
                                                        text: value,
                                                        theme: theme,
                                                        userSizePrefrerence: Extension.SettingProvider.resultViewFontSize
                                                    )
                                                )
                                            })
                                            .buttonStyle(ResultButtonStyle<Extension>(height: buttonHeight, selected: .init(selection: variableStates.resultModel.selection, index: data.id)))
                                            .contextMenu {
                                                ResultContextMenuView(candidate: data.candidate, displayResetLearningButton: Extension.SettingProvider.canResetLearningForCandidate, index: data.id)
                                            }
                                            .id(data.id)
                                        } else {
                                            Text(Design.fonts.forceJapaneseFont(text: value, theme: theme, userSizePrefrerence: Extension.SettingProvider.resultViewFontSize))
                                                .underline(true, color: .accentColor)
                                        }
                                    case .systemImage(let name, let accessibilityLabel):
                                        Button {
                                            KeyboardFeedback<Extension>.click()
                                            self.pressed(data)
                                        } label: {
                                            Image(systemName: name)
                                                .accessibilityLabel(accessibilityLabel ?? name)
                                                .font(Design.fonts.resultViewFont(theme: theme, userSizePrefrerence: Extension.SettingProvider.resultViewFontSize))
                                        }
                                        .buttonStyle(ResultButtonStyle<Extension>(height: buttonHeight, selected: .init(selection: variableStates.resultModel.selection, index: data.id)))
                                        .id(data.id)
                                    }
                                }
                            }
                            .onChange(of: variableStates.resultModel.updateResult) { (_, _) in
                                scrollViewProxy.scrollTo(0, anchor: .trailing)
                            }
                            .onChange(of: variableStates.resultModel.selection) { (_, newValue) in
                                if let newValue {
                                    withAnimation(.easeIn(duration: 0.05)) {
                                        scrollViewProxy.scrollTo(newValue, anchor: .center)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                    .zIndex(0)
                    if variableStates.resultModel.displayState == .results {
                        // 候補を展開するボタン
                        Button {
                            self.expand()
                        } label: {
                            ZStack {
                                Color(white: 1, opacity: 0.001)
                                    .frame(width: buttonWidth)
                                Image(systemName: "chevron.down")
                                    .font(Design.fonts.iconImageFont(keyViewFontSizePreference: Extension.SettingProvider.keyViewFontSize, theme: theme))
                                    .frame(height: 18)
                            }
                        }
                        .buttonStyle(ResultButtonStyle<Extension>(height: buttonHeight))
                        .padding(.trailing, 10)
                    }
                }
            }
        }
        .onChange(of: variableStates.clipboardHistoryManager.items) { _, items in
            usedRecentClipboardItems.formIntersection(items)
        }
        .animation(.easeIn(duration: 0.2), value: variableStates.resultModel.displayState == .nothing)
    }

    private func pressed(_ data: ResultData) {
        self.action.notifyComplete(data.candidate, variableStates: variableStates)
    }

    private func expand() {
        self.isResultViewExpanded = true
    }
}

struct ResultContextMenuView: View {
    @EnvironmentObject private var variableStates: VariableStates
    @Environment(\.userActionManager) private var action
    private let candidate: any ResultViewItemData
    private let index: Int?
    private let displayResetLearningButton: Bool

    init(candidate: any ResultViewItemData, displayResetLearningButton: Bool, index: Int? = nil) {
        self.candidate = candidate
        self.index = index
        self.displayResetLearningButton = displayResetLearningButton
    }

    var body: some View {
        Button("大きな文字で表示", systemImage: "plus.magnifyingglass") {
            if let labelText = candidate.textualRepresentation {
                variableStates.magnifyingText = labelText
                variableStates.boolStates.isTextMagnifying = true
            }
        }
        if displayResetLearningButton {
            Button("この候補の学習をリセットする", systemImage: "clear") {
                action.notifyForgetCandidate(candidate, variableStates: variableStates)
            }
        }
        #if DEBUG
        Button("デバッグ情報を表示する", systemImage: "ladybug.fill") {
            debug(self.candidate.getDebugInformation())
        }
        #endif
    }
}

struct ResultButtonStyle<Extension: ApplicationSpecificKeyboardViewExtension>: ButtonStyle {
    enum SelectionState: Sendable {
        case nothing
        case this
        case other
        init(selection: Int?, index: Int) {
            if let selection {
                if selection == index {
                    self = .this
                } else {
                    self = .other
                }
            } else {
                self = .nothing
            }
        }
    }
    private let height: CGFloat
    private let userSizePreference: Double
    private let selected: SelectionState
    private let verticalPadding: CGFloat

    @Environment(Extension.Theme.self) private var theme

    @MainActor init(height: CGFloat, selected: SelectionState = .nothing, verticalPadding: CGFloat = 5) {
        self.userSizePreference = Extension.SettingProvider.resultViewFontSize
        self.height = height
        self.selected = selected
        self.verticalPadding = verticalPadding
    }

    private func background(configuration: Configuration) -> any ShapeStyle {
        if configuration.isPressed {
            theme.pushedKeyFillColor.color.opacity(0.5)
        } else {
            switch self.selected {
            case .nothing: theme.resultBackgroundColor.color
            case .this: Material.thin
            case .other: theme.resultBackgroundColor.color.opacity(0.5)
            }
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Design.fonts.resultViewFont(theme: theme, userSizePrefrerence: self.userSizePreference))
            .frame(height: height)
            .padding(.horizontal, 5)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(theme.resultTextColor.color) // 文字色は常に不透明度1で描画する
            .background(AnyShapeStyle(background(configuration: configuration)))
            .cornerRadius(5.0)
            .compositingGroup()
            .contentShape(Rectangle())
            .animation(nil, value: configuration.isPressed)
    }
}
