//
//  ClipboardHistoryTab.swift
//  azooKey
//
//  Created by ensan on 2023/02/26.
//  Copyright © 2023 ensan. All rights reserved.
//

import SwiftUI
import SwiftUIUtils
import SwiftUtils

private final class ClipboardHistory: ObservableObject {
    @Published private(set) var pinnedItems: [ClipboardHistoryItem] = []
    @Published private(set) var notPinnedItems: [ClipboardHistoryItem] = []

    func updatePinnedItems(manager: inout ClipboardHistoryManager, _ process: (inout [ClipboardHistoryItem]) -> Void) {
        var copied = self.pinnedItems
        process(&copied)
        manager.items = copied + self.notPinnedItems
    }

    func updateNotPinnedItems(manager: inout ClipboardHistoryManager, _ process: (inout [ClipboardHistoryItem]) -> Void) {
        var copied = self.notPinnedItems
        process(&copied)
        manager.items = self.pinnedItems + copied
    }

    func updateBothItems(manager: inout ClipboardHistoryManager, _ process: (inout [ClipboardHistoryItem], inout [ClipboardHistoryItem]) -> Void) {
        var pinnedItems = self.pinnedItems
        var notPinnedItems = self.notPinnedItems
        process(&pinnedItems, &notPinnedItems)
        manager.items = pinnedItems + notPinnedItems
    }

    func reload(manager: ClipboardHistoryManager) {
        self.pinnedItems = []
        self.notPinnedItems = []
        for item in manager.items {
            if item.pinnedDate != nil {
                self.pinnedItems.append(item)
            } else {
                self.notPinnedItems.append(item)
            }
        }
        self.pinnedItems.sort(by: >)
        self.notPinnedItems.sort(by: >)
        debug("reload", manager.items)
    }
}

@MainActor
struct ClipboardHistoryTab<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    @EnvironmentObject private var variableStates: VariableStates
    @StateObject private var target = ClipboardHistory()
    @Environment(Extension.Theme.self) private var theme
    @Environment(\.userActionManager) private var action

    init() {}
    // キーボードのキーと同じ配色を使用
    private var keyBackgroundColor: Extension.Theme.ColorData {
        theme.normalKeyFillColor
    }

    private var keyTextColor: Color {
        theme.textColor.color
    }

    @ViewBuilder
    private func tileView(_ item: ClipboardHistoryItem, index: Int?, pinned: Bool = false) -> some View {
        ClipboardTileView<Extension>(
            item: item,
            index: index,
            pinned: pinned,
            background: keyBackgroundColor,
            textColor: keyTextColor,
            onTap: { handleTileInput(item) },
            onPin: { pinItem(item: item, at: $0) },
            onUnpin: { unpinItem(item: item, at: $0) },
            onDelete: { deleteItem(at: $0, pinned: pinned) }
        )
    }

    private func handleTileInput(_ item: ClipboardHistoryItem) {
        switch item.content {
        case .text(let string):
            // simplyInsert: true → inserimento diretto come paste(), SENZA passare per la conversione
            // kana-kanji (che costruirebbe un lattice su tutta la stringa, fino a 50k → hang/OOM
            // nell'estensione). Sicurezza/robustezza: vedi Sec1.
            action.registerAction(.input(string, simplyInsert: true), variableStates: variableStates)
            variableStates.undoAction = .init(action: .replaceLastCharacters([string: ""]), textChangedCount: variableStates.textChangedCount)
            KeyboardFeedback<Extension>.click()
        }
    }

    private func deleteItem(at index: Int, pinned: Bool) {
        if pinned {
            self.target.updatePinnedItems(manager: &variableStates.clipboardHistoryManager) {
                $0.remove(at: index)
            }
        } else {
            self.target.updateNotPinnedItems(manager: &variableStates.clipboardHistoryManager) {
                $0.remove(at: index)
            }
        }
    }

    /// Cattura user-initiated: legge gli appunti SOLO quando l'utente tocca questo bottone (intento).
    /// Disabilitato nei campi sicuri. La label cambia se ci sono nuovi appunti rilevati (solo metadati).
    @ViewBuilder
    private var captureBar: some View {
        // Copaky prototype: with the setting on, capture goes through Apple's own paste button, which
        // hands us the text instead of letting us read the pasteboard — so iOS raises no banner.
        // Off by default and NOT verifiable on the Simulator (the paste dialog does not exist there):
        // the device round decides whether this becomes the only path.
        // Copaky試験実装: 設定オン時はシステムのペーストボタン経由で取り込む（バナーなし）。
        if #available(iOS 16.0, *), Extension.SettingProvider.useSystemPasteControl, !variableStates.isSecureEntry {
            SystemPasteControl(
                onPaste: { text in
                    variableStates.capturePastedText(text)
                    self.target.reload(manager: variableStates.clipboardHistoryManager)
                    KeyboardFeedback<Extension>.click()
                }
            )
            .frame(height: 34)
            .padding(.horizontal, 12)
            .accessibilityHint(Text("クリップボードの内容を履歴に追加します"))
        } else {
            legacyCaptureBar
        }
    }

    @ViewBuilder
    private var legacyCaptureBar: some View {
        Button {
            variableStates.captureClipboard()
            self.target.reload(manager: variableStates.clipboardHistoryManager)
            KeyboardFeedback<Extension>.click()
        } label: {
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .accessibilityHidden(true)
                Text(variableStates.clipboardHistoryManager.hasPendingClipboard ? "コピーした内容を追加" : "現在のクリップボードを追加")
            }
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .disabled(variableStates.isSecureEntry)
        .opacity(variableStates.isSecureEntry ? 0.4 : 1)
        .accessibilityHint(variableStates.isSecureEntry ? Text("パスワード入力中は使用できません") : Text(""))
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var tileGridView: some View {
        // ピン留めがない場合は縦スクロールを無効にする
        let scrollAxes: Axis.Set = self.target.pinnedItems.isEmpty ? [] : .vertical

        ScrollView(scrollAxes) {
            VStack(spacing: 12) {
                captureBar
                if !self.target.pinnedItems.isEmpty {
                    ClipboardSection(
                        title: "ピン留め",
                        items: self.target.pinnedItems,
                        isPinned: true,
                        tileView: tileView,
                        menuView: {
                            Menu("詳細", systemImage: "ellipsis") {
                                Button("全て解除", systemImage: "pin.slash", role: .destructive) {
                                    self.target.updatePinnedItems(manager: &variableStates.clipboardHistoryManager) {
                                        $0.mutatingForEach {
                                            $0.pinnedDate = nil
                                        }
                                    }
                                }
                                Button("全て削除", systemImage: "trash", role: .destructive) {
                                    self.target.updatePinnedItems(manager: &variableStates.clipboardHistoryManager) {
                                        $0.removeAll()
                                    }
                                }
                            }
                            .labelStyle(.iconOnly)
                        }
                    )
                }

                if self.target.notPinnedItems.isEmpty {
                    EmptyHistoryView()
                } else {
                    ClipboardSection(
                        title: "履歴",
                        items: self.target.notPinnedItems,
                        isPinned: false,
                        tileView: tileView,
                        menuView: {
                            Menu("詳細", systemImage: "ellipsis") {
                                Button("全て削除", systemImage: "trash", role: .destructive) {
                                    self.target.updateNotPinnedItems(manager: &variableStates.clipboardHistoryManager) {
                                        $0.removeAll()
                                    }
                                }
                            }
                            .labelStyle(.iconOnly)
                        }
                    )
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func enterKey(_ design: TabDependentDesign) -> some View {
        SimpleKeyView<Extension>(model: SimpleEnterKeyModel<Extension>(), tabDesign: design)
    }
    private func deleteKey(_ design: TabDependentDesign) -> some View {
        SimpleKeyView<Extension>(model: SimpleKeyModel<Extension>(keyLabelType: .image("delete.left"), unpressedKeyColorType: .special, pressActions: [.delete(1)], longPressActions: .init(repeat: [.delete(1)])), tabDesign: design)
            .accessibilityLabel(Text("削除キー"))
    }
    private func backTabKey(_ design: TabDependentDesign) -> some View {
        SimpleKeyView<Extension>(model: SimpleKeyModel<Extension>(keyLabelType: .localizedText("戻る"), unpressedKeyColorType: .special, pressActions: [.moveTab(.system(.last_tab))], longPressActions: .init(start: [.setTabBar(.toggle)])), tabDesign: design)
            .accessibilityLabel(Text("戻る"))
    }

    var body: some View {
        Group {
            switch variableStates.keyboardOrientation {
            case .vertical:
                VStack {
                    tileGridView
                    HStack {
                        let design = TabDependentDesign(width: 3, height: 7, interfaceSize: variableStates.interfaceSize, orientation: .vertical)
                        backTabKey(design)
                        enterKey(design)
                        deleteKey(design)
                    }
                }
            case .horizontal:
                HStack {
                    tileGridView
                    VStack {
                        let design = TabDependentDesign(width: 8, height: 3, interfaceSize: variableStates.interfaceSize, orientation: .horizontal)
                        backTabKey(design)
                        deleteKey(design)
                        enterKey(design)
                    }
                }
            }
        }
        .font(Design.fonts.resultViewFont(theme: theme, userSizePrefrerence: Extension.SettingProvider.resultViewFontSize))
        .foregroundStyle(theme.resultTextColor.color)
        .onAppear {
            self.target.reload(manager: variableStates.clipboardHistoryManager)
        }
        .onChange(of: variableStates.clipboardHistoryManager.items) { (_, _) in
            self.target.reload(manager: variableStates.clipboardHistoryManager)
        }
    }

    private func unpinItem(item: ClipboardHistoryItem, at index: Int) {
        self.target.updateBothItems(manager: &variableStates.clipboardHistoryManager) { (pinned, notPinned) in
            pinned.remove(at: index)
            var item = item
            item.pinnedDate = nil
            notPinned.append(item)
            notPinned.sort(by: >)
        }
    }
    private func pinItem(item: ClipboardHistoryItem, at index: Int) {
        self.target.updateBothItems(manager: &variableStates.clipboardHistoryManager) { (pinned, notPinned) in
            notPinned.remove(at: index)
            var item = item
            item.pinnedDate = .now
            pinned.append(item)
            pinned.sort(by: >)
        }
    }
}

private struct ClipboardTileView<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    let item: ClipboardHistoryItem
    let index: Int?
    let pinned: Bool
    let background: Extension.Theme.ColorData
    let textColor: Color
    let onTap: () -> Void
    let onPin: (Int) -> Void
    let onUnpin: (Int) -> Void
    let onDelete: (Int) -> Void

    /// アクセシビリティラベルに使うプレビュー文字列。表示中の`TextTileContent`と同じ切り詰めロジックを使う
    /// （最大50kにもなる`item.content`全体をVoiceOverに読ませない）。
    private var accessibilityPreviewText: String {
        switch item.content {
        case .text(let string):
            return String(string.prefix(TextTileContent.displayPreviewLimit))
        }
    }

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: 8)
            .strokeAndFill(
                fillContent: self.background.color.blendMode(self.background.blendMode),
                strokeContent: pinned ? Color.orange : Color.clear,
                lineWidth: pinned ? 2 : 0
            )
            .padding(2)
            .overlay {
                switch item.content {
                case .text(let string):
                    TextTileContent(string: string, textColor: textColor)
                }
            }
            .frame(width: 140, height: 80)
            .onTapGesture {
                onTap()
            }
            .contextMenu {
                if pinned {
                    Button {
                        guard let index else {
                            return
                        }
                        onUnpin(index)
                    } label: {
                        Label("固定解除", systemImage: "pin.slash")
                    }
                } else {
                    Button {
                        guard let index else {
                            return
                        }
                        onPin(index)
                    } label: {
                        Label("固定", systemImage: "pin")
                    }
                }
                Button(role: .destructive) {
                    guard let index else {
                        return
                    }
                    onDelete(index)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(verbatim: accessibilityPreviewText))
            .accessibilityAction(named: pinned ? Text("固定解除") : Text("固定")) {
                guard let index else {
                    return
                }
                if pinned {
                    onUnpin(index)
                } else {
                    onPin(index)
                }
            }
            .accessibilityAction(named: Text("削除")) {
                guard let index else {
                    return
                }
                onDelete(index)
            }

        if pinned {
            tile.accessibilityValue(Text("固定済み"))
        } else {
            tile
        }
    }
}

private struct TextTileContent: View {
    /// Solo i primi N caratteri vengono renderizzati: il costo di layout di SwiftUI `Text` non deve
    /// scalare con la lunghezza memorizzata (fino a 50k). L'input alla pressione usa `item.content` intero.
    static let displayPreviewLimit = 280
    let string: String
    let textColor: Color

    var body: some View {
        Text(String(string.prefix(Self.displayPreviewLimit)))
            .font(.system(size: 12))
            .foregroundStyle(textColor)
            .lineLimit(5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .frame(height: 80)
    }
}

private struct ClipboardSection<TileView: View, MenuView: View>: View {
    let title: LocalizedStringKey
    let items: [ClipboardHistoryItem]
    let isPinned: Bool
    let tileView: (ClipboardHistoryItem, Int?, Bool) -> TileView
    let menuView: () -> MenuView

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                menuView()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        tileView(item, index, isPinned)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

private struct EmptyHistoryView: View {
    var body: some View {
        VStack {
            Text("コピーした後、上の「追加」ボタンを押すとここに保存されます")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }
}
