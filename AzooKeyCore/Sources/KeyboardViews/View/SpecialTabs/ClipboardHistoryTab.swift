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

private enum ClipboardHistoryDayGroup: CaseIterable, Hashable, Identifiable {
    case today
    case yesterday
    case earlier

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .today: "今日"
        case .yesterday: "昨日"
        case .earlier: "以前"
        }
    }

    func contains(_ date: Date, calendar: Calendar, now: Date) -> Bool {
        switch self {
        case .today:
            calendar.isDate(date, inSameDayAs: now)
        case .yesterday:
            calendar.isDateInYesterday(date)
        case .earlier:
            !calendar.isDate(date, inSameDayAs: now) && !calendar.isDateInYesterday(date)
        }
    }
}

private struct IndexedClipboardHistoryItem: Identifiable {
    let index: Int
    let item: ClipboardHistoryItem

    var id: Int { index }
}

private struct ClipboardHistoryDaySection: Identifiable {
    let group: ClipboardHistoryDayGroup
    let items: [IndexedClipboardHistoryItem]

    var id: ClipboardHistoryDayGroup { group }
}

private enum ClipboardHistoryDateFormatting {
    /// SwiftUI's localized keys resolve through the main bundle. Use that same selected language
    /// for relative dates instead of independently guessing from the keyboard typing language.
    static var uiLocale: Locale {
        guard let localization = Bundle.main.preferredLocalizations.first else {
            return .current
        }
        return Locale(identifier: localization)
    }

    static func relativeTimestamp(for date: Date, relativeTo referenceDate: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = uiLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: referenceDate)
    }
}

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

    func notPinnedDaySections(calendar: Calendar = .current, now: Date = .now) -> [ClipboardHistoryDaySection] {
        let indexedItems = self.notPinnedItems.enumerated().map {
            IndexedClipboardHistoryItem(index: $0.offset, item: $0.element)
        }
        return ClipboardHistoryDayGroup.allCases.compactMap { group in
            let items = indexedItems.filter { group.contains($0.item.createdData, calendar: calendar, now: now) }
            return items.isEmpty ? nil : ClipboardHistoryDaySection(group: group, items: items)
        }
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
        self.persistMutation()
    }

    /// Copaky [G-38]: pin/unpin/delete used to live in memory until `closeKeyboard()`, whose `save()` result
    /// is discarded — a pin that cannot be persisted (pinned data alone at the file budget) was lost silently
    /// at the next load. Persist here and say it when nothing could be written (counter-review n. 5).
    /// Copaky [G-38]: ピン留め・解除・削除は即座に保存し、書けなかった場合はその場で知らせる。
    private func persistMutation() {
        if !variableStates.clipboardHistoryManager.save() {
            variableStates.temporalMessage = .clipboardHistorySaveFailed
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
                    let result = variableStates.capturePastedText(text)
                    if case .rejectedOversized = result {
                        return
                    }
                    self.target.reload(manager: variableStates.clipboardHistoryManager)
                    KeyboardFeedback<Extension>.click()
                },
                onRejectOversized: {
                    variableStates.reportSourceRejectedOversizedClipboardCapture()
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
            let result = variableStates.captureClipboard()
            if case .rejectedOversized = result {
                return
            }
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
        let daySections = self.target.notPinnedDaySections()

        ScrollView(.vertical) {
            VStack(spacing: 8) {
                captureBar
                if !self.target.pinnedItems.isEmpty {
                    ClipboardSection(
                        title: "ピン留め",
                        items: self.target.pinnedItems.enumerated().map {
                            IndexedClipboardHistoryItem(index: $0.offset, item: $0.element)
                        },
                        isPinned: true,
                        showsMenu: true,
                        tileView: tileView,
                        menuView: {
                            Menu("詳細", systemImage: "ellipsis") {
                                Button("全て解除", systemImage: "pin.slash", role: .destructive) {
                                    self.target.updatePinnedItems(manager: &variableStates.clipboardHistoryManager) {
                                        $0.mutatingForEach {
                                            $0.pinnedDate = nil
                                        }
                                    }
                                    self.persistMutation()
                                }
                                Button("全て削除", systemImage: "trash", role: .destructive) {
                                    self.target.updatePinnedItems(manager: &variableStates.clipboardHistoryManager) {
                                        $0.removeAll()
                                    }
                                    self.persistMutation()
                                }
                            }
                            .labelStyle(.iconOnly)
                        }
                    )
                }

                if self.target.notPinnedItems.isEmpty {
                    EmptyHistoryView()
                } else {
                    ForEach(daySections) { section in
                        ClipboardSection(
                            title: section.group.title,
                            items: section.items,
                            isPinned: false,
                            showsMenu: section.id == daySections.first?.id,
                            tileView: tileView,
                            menuView: {
                                Menu("詳細", systemImage: "ellipsis") {
                                    Button("全て削除", systemImage: "trash", role: .destructive) {
                                        self.target.updateNotPinnedItems(manager: &variableStates.clipboardHistoryManager) {
                                            $0.removeAll()
                                        }
                                        self.persistMutation()
                                    }
                                }
                                .labelStyle(.iconOnly)
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func enterKey(width: CGFloat, height: CGFloat) -> some View {
        SimpleKeyView<Extension>(model: ClipboardEnterKeyModel<Extension>(), width: width, height: height)
    }
    private func deleteKey(width: CGFloat, height: CGFloat) -> some View {
        SimpleKeyView<Extension>(model: SimpleKeyModel<Extension>(keyLabelType: .image("delete.left", accessibilityLabel: "削除"), unpressedKeyColorType: .special, pressActions: [.delete(1)], longPressActions: .init(repeat: [.delete(1)])), width: width, height: height)
    }
    private func backTabKey(width: CGFloat, height: CGFloat) -> some View {
        SimpleKeyView<Extension>(model: SimpleKeyModel<Extension>(keyLabelType: .image("chevron.backward", accessibilityLabel: "戻る"), unpressedKeyColorType: .special, pressActions: [.moveTab(.system(.last_tab))], longPressActions: .init(start: [.setTabBar(.toggle)])), width: width, height: height)
            .accessibilityLabel(Text("戻る"))
            // Copaky-only hook for liveness probes: with the system paste control ON this panel
            // shows NO other Copaky-specific label (the capture bar becomes Apple's capsule and
            // the section header is a generic localized "History"). Leaf-level on purpose —
            // a container-level identifier propagates and clobbers children (paid in A-04).
            // 生存プローブ用のCopaky固有フック。コンテナに付けると子に伝播するのでキー単位で。
            .accessibilityIdentifier("copaky_clipboard_back")
    }

    private var compactToolbar: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 6
            let horizontalPadding: CGFloat = 6
            let keyHeight: CGFloat = 40
            let keyWidth = max(
                44,
                (geometry.size.width - horizontalPadding * 2 - spacing * 2) / 3
            )
            HStack(spacing: spacing) {
                backTabKey(width: keyWidth, height: keyHeight)
                deleteKey(width: keyWidth, height: keyHeight)
                enterKey(width: keyWidth, height: keyHeight)
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        }
        .frame(height: 40)
    }

    var body: some View {
        VStack(spacing: 0) {
            tileGridView
            compactToolbar
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
        self.persistMutation()
    }
    private func pinItem(item: ClipboardHistoryItem, at index: Int) {
        self.target.updateBothItems(manager: &variableStates.clipboardHistoryManager) { (pinned, notPinned) in
            notPinned.remove(at: index)
            var item = item
            item.pinnedDate = .now
            pinned.append(item)
            pinned.sort(by: >)
        }
        self.persistMutation()
    }
}

private struct ClipboardEnterKeyModel<Extension: ApplicationSpecificKeyboardViewExtension>: SimpleKeyModelProtocol {
    let unpressedKeyColorType: SimpleUnpressedKeyColorType = .enter

    func pressActions(variableStates: VariableStates) -> [ActionType] {
        switch variableStates.enterKeyState {
        case .complete:
            [.enter]
        case .return:
            [.input("\n")]
        }
    }

    func longPressActions(variableStates: VariableStates) -> LongpressActionType {
        .none
    }

    func label(width: CGFloat, states: VariableStates) -> KeyLabel<Extension> {
        KeyLabel(
            .image("arrow.turn.down.left", accessibilityLabel: Design.language.getEnterKeyText(states.enterKeyState)),
            width: width
        )
    }

    func feedback(variableStates: VariableStates) {
        switch variableStates.enterKeyState {
        case .complete:
            KeyboardFeedback<Extension>.tabOrOtherKey()
        case .return:
            KeyboardFeedback<Extension>.click()
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

    private var relativeTimestamp: String {
        ClipboardHistoryDateFormatting.relativeTimestamp(for: item.createdData)
    }

    private var accessibilityTimestamp: String {
        guard pinned else {
            return relativeTimestamp
        }
        let pinnedLabel = String(localized: "固定済み", bundle: .main)
        return "\(relativeTimestamp), \(pinnedLabel)"
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
                    TextTileContent(
                        string: string,
                        relativeTimestamp: relativeTimestamp,
                        pinned: pinned,
                        textColor: textColor
                    )
                }
            }
            .frame(width: 140, height: 52)
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
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(verbatim: accessibilityPreviewText))
            .accessibilityValue(Text(verbatim: accessibilityTimestamp))
            .accessibilityIdentifier("copaky_clipboard_text_tile")
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

        tile
    }
}

private struct TextTileContent: View {
    /// Solo i primi N caratteri vengono renderizzati: il costo di layout di SwiftUI `Text` non deve
    /// scalare con la lunghezza memorizzata (fino a 50k). L'input alla pressione usa `item.content` intero.
    static let displayPreviewLimit = 280
    let string: String
    let relativeTimestamp: String
    let pinned: Bool
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(string.prefix(Self.displayPreviewLimit)))
                .font(.system(size: 13))
                .foregroundStyle(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                Text(verbatim: relativeTimestamp)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 52)
    }
}

private struct ClipboardSection<TileView: View, MenuView: View>: View {
    let title: LocalizedStringKey
    let items: [IndexedClipboardHistoryItem]
    let isPinned: Bool
    let showsMenu: Bool
    let tileView: (ClipboardHistoryItem, Int?, Bool) -> TileView
    let menuView: () -> MenuView

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if showsMenu {
                    menuView()
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { indexedItem in
                        tileView(indexedItem.item, indexedItem.index, isPinned)
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
