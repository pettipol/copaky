// Copaky: saved recent items only. No pasteboard reads, capture, writes or new settings.
// Copaky: 保存済みの最近の項目だけを使い、ペーストボードの読み取り・取得・書き込みは行わない。
import SwiftUI

@MainActor
struct RecentClipboardChips<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    @EnvironmentObject private var variableStates: VariableStates
    @Environment(Extension.Theme.self) private var theme
    @Environment(\.userActionManager) private var action
    @Binding var usedItems: Set<ClipboardHistoryItem>
    private let contentHeight: CGFloat

    init(usedItems: Binding<Set<ClipboardHistoryItem>>, contentHeight: CGFloat) {
        self._usedItems = usedItems
        self.contentHeight = max(0, contentHeight)
    }

    private var permitted: Bool {
        Extension.SettingProvider.displayTabBarButton && variableStates.resultModel.displayState == .nothing
            && RecentClipboardChipsPolicy.permits(historyEnabled: variableStates.clipboardHistoryManager.isEnabled,
                                           hasFullAccess: variableStates.hasFullAccess,
                                           isSecureEntry: variableStates.isSecureEntry)
    }

    var body: some View {
        if permitted {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let items = RecentClipboardChipsPolicy.select(
                    variableStates.clipboardHistoryManager.items.filter { !usedItems.contains($0) },
                    now: context.date, createdAt: { $0.createdData }, isPinned: { $0.pinnedDate != nil }
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element) { index, item in
                            if case let .text(text) = item.content {
                                Button { insert(item) } label: {
                                    Text(verbatim: RecentClipboardChipsPolicy.preview(text))
                                        .font(.system(size: 13))
                                        .foregroundStyle(theme.textColor.color)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .frame(minWidth: 44, maxWidth: 140)
                                        .frame(height: contentHeight)
                                        .background(theme.normalKeyFillColor.color, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("copaky-recent-clipboard-\(index)")
                                .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    if admittedNow(item) {
                                        action.registerAction(.moveTab(.system(.clipboard_history_tab)), variableStates: variableStates)
                                        KeyboardFeedback<Extension>.tabOrOtherKey()
                                    }
                                })
                            }
                        }
                    }
                }
            }
        }
    }

    private func admittedNow(_ item: ClipboardHistoryItem) -> Bool {
        permitted && !usedItems.contains(item) && variableStates.clipboardHistoryManager.items.contains(item)
            && RecentClipboardChipsPolicy.isEligible(createdAt: item.createdData, isPinned: item.pinnedDate != nil, now: .now)
    }

    private func insert(_ item: ClipboardHistoryItem) {
        guard admittedNow(item), case let .text(text) = item.content else { return }
        action.registerAction(.input(text, simplyInsert: true), variableStates: variableStates)
        // Copaky: simplyInsert leaves no composition. Native delete works in IT/EN/JP, while
        // replaceLastCharacters only edits an empty composition when keyboardLanguage is .none.
        // Copaky: 直接挿入後は未確定文字列がないため、言語に依存しない削除で戻す。
        variableStates.undoAction = .init(action: .delete(text.count), textChangedCount: variableStates.textChangedCount)
        usedItems.insert(item)
        KeyboardFeedback<Extension>.click()
    }
}
