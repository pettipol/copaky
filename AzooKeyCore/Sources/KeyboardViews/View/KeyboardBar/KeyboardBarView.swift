//
//  KeyboardBarView.swift
//  azooKey
//
//  Created by ensan on 2020/04/10.
//  Copyright © 2020 ensan. All rights reserved.
//

import Foundation
import SwiftUI
import SwiftUIUtils

@MainActor
struct KeyboardBarView<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    @EnvironmentObject private var variableStates: VariableStates
    @Binding private var isResultViewExpanded: Bool
    private let compactIdleBar: Bool
    @Environment(Extension.Theme.self) private var theme
    // CursorBarは操作がない場合に非表示にする。これをハンドルするためのタスク
    @State private var dismissTask: Task<(), any Error>?

    private var useReflectStyleCursorBar: Bool {
        Extension.SettingProvider.useReflectStyleCursorBar
    }

    private var displayCursorBarAutomatically: Bool {
        Extension.SettingProvider.displayCursorBarAutomatically
    }

    init(isResultViewExpanded: Binding<Bool>, compactIdleBar: Bool = false) {
        self._isResultViewExpanded = isResultViewExpanded
        self.compactIdleBar = compactIdleBar
    }

    var body: some View {
        switch variableStates.barState {
        case .cursor:
            Group {
                if useReflectStyleCursorBar {
                    ReflectStyleCursorBar<Extension>()
                } else {
                    SliderStyleCursorBar<Extension>()
                }
            }
            .onAppear {
                // 表示したタイミングでdismissTaskを開始
                self.restartCursorBarDismissTask()
            }
            .onChange(of: variableStates.textChangedCount) { (_, _) in
                // カーソルが動くたびにrestart
                self.restartCursorBarDismissTask()
            }
        case .tab:
            let tabBarData = if let data = try? variableStates.tabManager.config.custardManager.tabbar(identifier: 0),
                                data.items.count > 0 {
                data
            } else {
                TabBarData.default
            }
            TabBarView<Extension>(data: tabBarData)
        case .none:
            switch variableStates.tabManager.tab {
            case let .existential(.special(tab)) where tab == .emoji:
                EmojiTabResultBar<Extension>()
            default:
                ResultBar<Extension>(isResultViewExpanded: $isResultViewExpanded, compactIdleBar: compactIdleBar)
            }
        }
    }

    private func restartCursorBarDismissTask() {
        // 自動非表示はdisplayCursorBarAutomaticallyが有効の場合のみにする。
        guard self.displayCursorBarAutomatically else {
            return
        }
        self.dismissTask?.cancel()
        self.dismissTask = Task {
            // 10秒待つ
            try await Task.sleep(nanoseconds: 10_000_000_000)
            try Task.checkCancellation()
            withAnimation {
                variableStates.barState = .none
            }
        }
    }
}

@MainActor
struct KeyboardBarButton<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    enum LabelType {
        case copakyMark
        case systemImage(String)
    }
    @Environment(Extension.Theme.self) private var theme
    @EnvironmentObject private var variableStates: VariableStates
    private var action: () -> Void
    private let label: LabelType
    // Copaky: compact sizing is opt-in for the enabled idle toolbar only.
    // Copaky: コンパクト寸法は有効な待機時ツールバーだけで使用する。
    private let compact: Bool
    private let contentHeight: CGFloat?

    init(label: LabelType, compact: Bool = false, contentHeight: CGFloat? = nil, action: @escaping () -> Void) {
        self.label = label
        self.compact = compact
        self.contentHeight = contentHeight
        self.action = action
    }

    private var buttonBackgroundColor: Color {
        theme.tabBarButtonBackgroundColor
    }

    private var buttonLabelColor: Color {
        theme.tabBarButtonForegroundColor
    }

    private var circleSize: CGFloat {
        compact ? min(32, max(0, compactHeight - 6)) : Design.keyboardBarHeight(interfaceHeight: variableStates.interfaceSize.height, orientation: variableStates.keyboardOrientation) * 0.8
    }

    private var iconSize: CGFloat {
        compact ? min(24, max(0, compactHeight - 10)) : Design.keyboardBarHeight(interfaceHeight: variableStates.interfaceSize.height, orientation: variableStates.keyboardOrientation) * 0.6
    }

    private var compactHeight: CGFloat {
        if let contentHeight { return max(0, contentHeight) }
        return Design.keyboardBarCompactContentHeight(interfaceHeight: variableStates.interfaceSize.height,
                                               interfaceWidth: variableStates.interfaceSize.width,
                                               orientation: variableStates.keyboardOrientation)
    }

    private var button: some View {
        Button(action: self.action) {
            ZStack {
                Circle()
                    .strokeAndFill(fillContent: buttonBackgroundColor, strokeContent: theme.borderColor.color, lineWidth: theme.borderWidth)
                    .frame(width: circleSize, height: circleSize)
                switch label {
                case .copakyMark:
                    CopakyMark(fixedSize: iconSize, color: buttonLabelColor)
                case let .systemImage(name):
                    Image(systemName: name)
                        .frame(width: iconSize, height: iconSize)
                        .foregroundStyle(buttonLabelColor)
                }
            }
            .frame(width: compact ? 44 : nil, height: compact ? compactHeight : nil)
            .contentShape(Rectangle())
        }
    }

    var body: some View {
        if compact {
            // Copaky: constrain the actual control, not only its mark. The plain style avoids
            // inherited button expansion when it is the toolbar's only accessible child.
            // Copaky: ラベルだけでなく実ボタンを固定し、単独の操作要素でも行全体へ広げない。
            button
                .buttonStyle(.plain)
                .frame(width: 44, height: compactHeight)
                .contentShape(Rectangle())
        } else {
            button.padding(.all, 5)
        }
    }
}
