//
//  TabNavigationView.swift
//  azooKey
//
//  Created by ensan on 2021/02/21.
//  Copyright © 2021 ensan. All rights reserved.
//

import Foundation
import SwiftUI

struct TabBarView<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    private let data: TabBarData
    @Environment(\.userActionManager) private var action
    @EnvironmentObject private var variableStates: VariableStates

    init(data: TabBarData) {
        self.data = data
    }

    private var pinnedItems: [TabBarItem] {
        self.data.items.filter {$0.pinned == true}
    }

    private var nonPinnedItems: [TabBarItem] {
        self.data.items.filter {$0.pinned != true}
    }

    private func itemView(_ item: TabBarItem) -> some View {
        Button {
            self.action.registerActions(item.actions.map {$0.actionType}, variableStates: variableStates)
        } label: {
            switch item.label {
            case let .text(text):
                Text(text)
            case let .image(image):
                Image(systemName: image)
                    .accessibilityLabel(tabItemAccessibilityLabel(for: item, symbolName: image))
            }
        }
        .buttonStyle(ResultButtonStyle<Extension>(height: Design.keyboardBarHeight(interfaceHeight: variableStates.interfaceSize.height, orientation: variableStates.keyboardOrientation) * 0.6))
    }

    /// タブバーの画像アイテムに付与するアクセシビリティラベル。アクションから意味のある説明を導出し、
    /// マッチしない場合はSF Symbol名にフォールバックする。
    private func tabItemAccessibilityLabel(for item: TabBarItem, symbolName: String) -> Text {
        for action in item.actions {
            switch action {
            case .moveTab(.system(.clipboard_history_tab)):
                return Text("クリップボードの履歴")
            case .moveTab(.system(.emoji_tab)):
                return Text("絵文字")
            case .dismissKeyboard:
                return Text("キーボードを閉じる")
            case .enableResizingMode:
                return Text("キーボードのサイズを変更")
            default:
                continue
            }
        }
        return Text(verbatim: symbolName)
    }

    var body: some View {
        HStack {
            if !self.pinnedItems.isEmpty {
                ForEach(self.pinnedItems.indices, id: \.self) {i in
                    let item = self.pinnedItems[i]
                    self.itemView(item)
                }
                Divider()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(self.nonPinnedItems.indices, id: \.self) {i in
                        let item = self.nonPinnedItems[i]
                        self.itemView(item)
                    }
                }
            }
        }.frame(height: Design.keyboardBarHeight(interfaceHeight: variableStates.interfaceSize.height, orientation: variableStates.keyboardOrientation))
    }
}
