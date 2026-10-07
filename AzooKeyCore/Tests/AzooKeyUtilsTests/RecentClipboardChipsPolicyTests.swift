// Copaky: synthetic saved-history metadata; no pasteboard, device, or clock dependency.
// Copaky: 保存履歴の合成メタデータのみを使い、ペーストボード・実機・実時計に依存しない。
import Foundation
import XCTest
@testable import KeyboardViews

final class RecentClipboardChipsPolicyTests: XCTestCase {
    private struct Item {
        let id: Int
        let created: Date
        let pinned: Bool
    }
    private let now = Date(timeIntervalSince1970: 10_000)

    func testEveryPermissionCombinationFailsClosed() {
        for enabled in [false, true] {
            for fullAccess in [false, true] {
                for secure in [false, true] {
                    XCTAssertEqual(RecentClipboardChipsPolicy.permits(historyEnabled: enabled, hasFullAccess: fullAccess, isSecureEntry: secure),
                                   enabled && fullAccess && !secure,
                                   "A chip must require history enabled, observed Full Access, and a non-secure field")
                }
            }
        }
    }

    func testNonPinnedExpiryIncludes120SecondsButRejectsFutureAndExpiredDates() {
        XCTAssertTrue(RecentClipboardChipsPolicy.isEligible(createdAt: now.addingTimeInterval(-120), isPinned: false, now: now))
        XCTAssertFalse(RecentClipboardChipsPolicy.isEligible(createdAt: now.addingTimeInterval(-120.001), isPinned: false, now: now))
        XCTAssertFalse(RecentClipboardChipsPolicy.isEligible(createdAt: now.addingTimeInterval(1), isPinned: false, now: now))
    }

    func testPinnedItemHasNoChipAgeLimitAndIsNotRankedAboveNewerItems() {
        let items = [Item(id: 1, created: now.addingTimeInterval(-3_600), pinned: true),
                     Item(id: 2, created: now.addingTimeInterval(-90), pinned: false),
                     Item(id: 3, created: now.addingTimeInterval(-121), pinned: false)]
        let selected = RecentClipboardChipsPolicy.select(items, now: now, createdAt: { $0.created }, isPinned: { $0.pinned })
        XCTAssertEqual(selected.map(\.id), [2, 1], "Sort by creation date, retain the old pin, and exclude the expired unpinned item")
    }

    func testSelectionKeepsOnlyThreeNewestItemsAndPreservesDateTies() {
        let items = [Item(id: 1, created: now.addingTimeInterval(-50), pinned: false),
                     Item(id: 2, created: now, pinned: false),
                     Item(id: 3, created: now, pinned: false),
                     Item(id: 4, created: now.addingTimeInterval(-10), pinned: false)]
        let selected = RecentClipboardChipsPolicy.select(items, now: now, createdAt: { $0.created }, isPinned: { $0.pinned })
        XCTAssertEqual(selected.map(\.id), [2, 3, 4], "Cap the row at three items without inventing an ordering for equal creation dates")
    }

    func testAChipThatWasVisibleCanExpireBeforeItsTap() {
        let created = now.addingTimeInterval(-119)
        XCTAssertTrue(RecentClipboardChipsPolicy.isEligible(createdAt: created, isPinned: false, now: now))
        XCTAssertFalse(RecentClipboardChipsPolicy.isEligible(createdAt: created, isPinned: false, now: now.addingTimeInterval(2)),
                       "The tap must re-evaluate eligibility using its current time")
    }

    func testPreviewLimitsGraphemesAndNormalizesOnlyTheBoundedPreview() {
        let grapheme = "👩🏽‍💻"
        let text = String(repeating: grapheme, count: 40)
        XCTAssertEqual(RecentClipboardChipsPolicy.preview(text), String(repeating: grapheme, count: 28))
        XCTAssertEqual(RecentClipboardChipsPolicy.preview("caffè\n日本\t"), "caffè 日本 ")
        XCTAssertEqual(text.count, 40, "Preview construction must preserve the full saved text for insertion")
    }
}
