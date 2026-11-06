import Foundation
import XCTest
@testable import KeyboardViews

/// Copaky: isolated, synthetic qualification of the production history persistence boundary.
/// Copaky: 実際の履歴保存を合成データと専用ディレクトリで検証する。
/// This does not exercise UIPasteboard, UI pin/delete handlers, App Groups, or process termination.
final class ClipboardLifecycleQualificationTests: XCTestCase {
    @MainActor
    private final class SyntheticSource: ClipboardSource {
        var changeCount = 1
        var hasStrings = true
        var value: String
        private(set) var valueReads = 0

        init(value: String) { self.value = value }

        var string: String? {
            valueReads += 1
            return value
        }
    }

    @MainActor
    func testExplicitCapturePinReloadSelectiveDeletePreservesOtherEntries() throws {
        try qualifyLifecycle(systemProvidedText: false)
    }

    @MainActor
    func testProvidedTextPinReloadSelectiveDeletePreservesOtherEntries() throws {
        try qualifyLifecycle(systemProvidedText: true)
    }

    @MainActor
    private func qualifyLifecycle(systemProvidedText: Bool) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("copaky-clipboard-lifecycle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let previousFullAccess = SemiStaticStates.shared.hasFullAccess
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(previousFullAccess) }

        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: directory)
        let run = UUID().uuidString
        let survivor = "copaky-synthetic-survivor-\(run)-日本語-à"
        let pinnedMarker = "copaky-synthetic-pin-\(run)-日本語-à"
        let deleteMarker = "copaky-synthetic-delete-\(run)-日本語-à"
        let source = SyntheticSource(value: survivor)
        let now = Date()
        var manager = ClipboardHistoryManager(config: config, clipboardSource: source)
        XCTAssertTrue(manager.items.isEmpty, "A new isolated directory must not expose any history")

        // Establish an unrelated, existing entry through the same production capture pipeline.
        XCTAssertEqual(manager.captureProvidedText(survivor, isSecureEntry: false, now: now), .captured)
        XCTAssertTrue(manager.save(), "The survivor fixture must reach the real history file")
        let originalSurvivor = try XCTUnwrap(manager.items.first)

        source.changeCount += 1
        source.value = pinnedMarker
        manager.detectClipboardChange(now: now.addingTimeInterval(1))
        XCTAssertTrue(manager.hasPendingClipboard)
        XCTAssertEqual(source.valueReads, 0, "Detection must inspect metadata only")
        XCTAssertFalse(manager.items.contains { $0.content == .text(pinnedMarker) },
                       "The unique marker must be absent before explicit capture")
        let capture: ClipboardHistoryManager.CaptureResult
        if systemProvidedText {
            capture = manager.captureProvidedText(pinnedMarker, isSecureEntry: false, now: now.addingTimeInterval(1))
        } else {
            capture = manager.captureCurrentClipboard(isSecureEntry: false, now: now.addingTimeInterval(1))
        }
        XCTAssertEqual(capture, .captured, "The production capture path must accept the fresh synthetic marker")
        XCTAssertFalse(manager.hasPendingClipboard)
        XCTAssertEqual(source.valueReads, systemProvidedText ? 0 : 1,
                       "Provided text must not read the clipboard; explicit capture must read once")
        let pinnedIndex = try XCTUnwrap(manager.items.firstIndex { $0.content == .text(pinnedMarker) })
        XCTAssertNil(manager.items[pinnedIndex].pinnedDate, "A new capture starts unpinned")

        // The UI's private mutation handler changes pinnedDate then calls manager.save().
        // This exercises that persisted state contract, not the gesture or private handler itself.
        let pinDate = now.addingTimeInterval(2)
        manager.items[pinnedIndex].pinnedDate = pinDate
        XCTAssertTrue(manager.save(), "Pinning must be persisted, not retained only in memory")
        let expectedPinned = try XCTUnwrap(manager.items.first { $0.content == .text(pinnedMarker) })
        let savedAfterPin = try ClipboardHistoryManager.load(config: config)
        XCTAssertEqual(Set(savedAfterPin), Set([originalSurvivor, expectedPinned]))

        // A fresh manager reopens the file; it does not inherit the previous instance's array.
        var reopened = ClipboardHistoryManager(config: config, clipboardSource: source)
        XCTAssertEqual(Set(reopened.items), Set([originalSurvivor, expectedPinned]))
        XCTAssertEqual(reopened.items.first?.content, .text(pinnedMarker), "The persisted pin must sort first")
        XCTAssertEqual(reopened.items.first?.pinnedDate, pinDate)
        XCTAssertEqual(reopened.captureProvidedText(deleteMarker, isSecureEntry: false,
                                                    now: now.addingTimeInterval(3)), .captured)
        XCTAssertTrue(reopened.save())
        XCTAssertEqual(reopened.items.count, 3, "Selective deletion needs a distinct victim and two survivors")
        XCTAssertEqual(try ClipboardHistoryManager.load(config: config).count, 3,
                       "The victim must exist on disk before deletion")

        // Delete one exact, run-unique entry. Never clear history or match by position/prefix.
        let victim = try XCTUnwrap(reopened.items.first { $0.content == .text(deleteMarker) })
        XCTAssertEqual(reopened.items.filter { $0.content == victim.content }.count, 1)
        reopened.items.removeAll { $0.content == victim.content }
        XCTAssertTrue(reopened.save(), "The selective deletion must reach disk")
        let final = ClipboardHistoryManager(config: config, clipboardSource: source)
        XCTAssertFalse(final.items.contains { $0.content == victim.content }, "Deleted marker must stay absent after reload")
        XCTAssertEqual(Set(final.items), Set([originalSurvivor, expectedPinned]),
                       "Selective deletion must preserve unrelated content, timestamps and pin state exactly")

        // Also delete the exact pinned fixture and prove the unrelated entry survives a final reload.
        var deletingPin = final
        deletingPin.items.removeAll { $0.content == .text(pinnedMarker) }
        XCTAssertTrue(deletingPin.save())
        XCTAssertEqual(ClipboardHistoryManager(config: config, clipboardSource: source).items, [originalSurvivor])
        XCTAssertEqual(source.valueReads, systemProvidedText ? 0 : 1,
                       "Saving/reloading/deleting must not read the live clipboard")
    }
}
