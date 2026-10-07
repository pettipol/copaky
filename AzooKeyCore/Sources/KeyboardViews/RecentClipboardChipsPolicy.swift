// Copaky: bounded, read-only selection of saved clipboard items for the enabled idle toolbar.
// Copaky: 有効な待機時ツールバー用の保存済み履歴を、変更せずに限定選択する。
import Foundation

enum RecentClipboardChipsPolicy {
    static let lifetime: TimeInterval = 120
    static let maximumCount = 3
    static let previewLimit = 28

    static func permits(historyEnabled: Bool, hasFullAccess: Bool, isSecureEntry: Bool) -> Bool {
        historyEnabled && hasFullAccess && !isSecureEntry
    }

    static func isEligible(createdAt: Date, isPinned: Bool, now: Date) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return isPinned || (age >= 0 && age <= lifetime)
    }

    static func select<Item>(_ items: [Item], now: Date, createdAt: (Item) -> Date, isPinned: (Item) -> Bool) -> [Item] {
        items.enumerated().filter {
            isEligible(createdAt: createdAt($0.element), isPinned: isPinned($0.element), now: now)
        }.sorted {
            let lhs = createdAt($0.element)
            let rhs = createdAt($1.element)
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.prefix(maximumCount).map(\.element)
    }

    static func preview(_ text: String) -> String {
        String(text.prefix(previewLimit)).replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\t", with: " ")
    }
}
