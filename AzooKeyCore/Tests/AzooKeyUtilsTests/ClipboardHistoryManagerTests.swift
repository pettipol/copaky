import XCTest
@testable import KeyboardViews
@testable import AzooKeyUtils

struct MockClipboardHistoryManagerConfiguration: ClipboardHistoryManagerConfiguration {
    var enabled: Bool = true
    var saveDirectory: URL? = FileManager.default.temporaryDirectory
    var maxCount: Int = 100
}

/// Sorgente appunti fittizia: rende i test deterministici e veloci, senza toccare la
/// `UIPasteboard.general` reale (che su Simulatore headless si blocca sul servizio pasteboard).
@MainActor
struct FakeClipboardSource: ClipboardSource {
    var changeCount: Int = 1
    var hasStrings: Bool = true
    var string: String?
}

final class ClipboardHistoryManagerTests: XCTestCase {

    @MainActor
    private func makeManager(maxCount: Int = 100, clipboard: FakeClipboardSource = FakeClipboardSource(hasStrings: false, string: nil)) -> ClipboardHistoryManager {
        var manager = ClipboardHistoryManager(config: MockClipboardHistoryManagerConfiguration(maxCount: maxCount), clipboardSource: clipboard)
        manager.items = []
        return manager
    }

    private func texts(_ manager: ClipboardHistoryManager) -> [String] {
        manager.items.compactMap { item -> String? in
            if case .text(let t) = item.content { return t }
            return nil
        }
    }

    // MARK: - pruneExpired (clock iniettato)

    @MainActor
    func testPruneExpiredRemovesOldUnpinnedKeepsRecentAndPinned() {
        var manager = makeManager()
        let now = Date()
        let recent = ClipboardHistoryItem(content: .text("recent"), createdData: now.addingTimeInterval(-1 * 24 * 60 * 60))
        let oldUnpinned = ClipboardHistoryItem(content: .text("old-unpinned"), createdData: now.addingTimeInterval(-8 * 24 * 60 * 60))
        let oldPinned = ClipboardHistoryItem(content: .text("old-pinned"), createdData: now.addingTimeInterval(-8 * 24 * 60 * 60), pinnedDate: now)
        manager.items = [recent, oldUnpinned, oldPinned]

        manager.pruneExpired(now: now)

        let result = texts(manager)
        XCTAssertTrue(result.contains("recent"), "L'elemento recente non deve essere rimosso")
        XCTAssertTrue(result.contains("old-pinned"), "Un elemento scaduto ma pinnato non deve essere rimosso")
        XCTAssertFalse(result.contains("old-unpinned"), "Un elemento non pinnato scaduto (>7gg) deve essere rimosso")
    }

    @MainActor
    func testPruneExpiredBoundaryKeepsExactlySevenDays() {
        var manager = makeManager()
        let now = Date()
        // Esattamente 7 giorni: createdData == expirationLimit → mantenuto (confronto strettamente `<`).
        let exactlySevenDays = ClipboardHistoryItem(content: .text("edge"), createdData: now.addingTimeInterval(-7 * 24 * 60 * 60))
        // Appena oltre i 7 giorni → rimosso.
        let justOver = ClipboardHistoryItem(content: .text("over"), createdData: now.addingTimeInterval(-7 * 24 * 60 * 60 - 1))
        manager.items = [exactlySevenDays, justOver]

        manager.pruneExpired(now: now)

        let result = texts(manager)
        XCTAssertTrue(result.contains("edge"), "Esattamente a 7 giorni l'elemento deve essere mantenuto")
        XCTAssertFalse(result.contains("over"), "Appena oltre i 7 giorni l'elemento deve essere rimosso")
    }

    // MARK: - guardia secure-field (ritorna prima di leggere la pasteboard)

    @MainActor
    func testCaptureIsSkippedInSecureField() {
        var manager = makeManager(clipboard: FakeClipboardSource(changeCount: 1, hasStrings: true, string: "secret"))
        manager.captureCurrentClipboard(isSecureEntry: true)
        XCTAssertTrue(manager.items.isEmpty, "Nei campi sicuri non deve avvenire alcuna cattura")
    }

    // MARK: - detect non legge mai il valore

    @MainActor
    func testDetectDoesNotCaptureValueButSignalsPending() {
        var manager = makeManager(clipboard: FakeClipboardSource(changeCount: 1, hasStrings: true, string: "detect-should-not-store"))
        manager.detectClipboardChange()

        XCTAssertTrue(manager.items.isEmpty, "detectClipboardChange non deve mai aggiungere elementi (non legge il valore)")
        XCTAssertTrue(manager.hasPendingClipboard, "detect deve segnalare contenuto pendente quando la pasteboard ha stringhe")
    }

    @MainActor
    func testDetectDoesNotSignalPendingWhenNoStrings() {
        var manager = makeManager(clipboard: FakeClipboardSource(changeCount: 1, hasStrings: false, string: nil))
        manager.detectClipboardChange()
        XCTAssertFalse(manager.hasPendingClipboard, "Senza stringhe sugli appunti non deve esserci contenuto pendente")
    }

    // MARK: - capture su intento + cap dimensione

    @MainActor
    func testCaptureStoresCurrentClipboardOnIntent() {
        let unique = "capture-\(UUID().uuidString)"
        var manager = makeManager(clipboard: FakeClipboardSource(changeCount: 1, hasStrings: true, string: unique))

        manager.captureCurrentClipboard(isSecureEntry: false)

        XCTAssertTrue(texts(manager).contains(unique), "La cattura esplicita deve memorizzare il contenuto corrente")
        XCTAssertFalse(manager.hasPendingClipboard, "Dopo la cattura non deve restare contenuto pendente")
    }

    @MainActor
    func testCaptureSkipsOversizedItem() {
        let huge = String(repeating: "a", count: ClipboardHistoryManager.maxItemCharacterCount + 1)
        var manager = makeManager(clipboard: FakeClipboardSource(changeCount: 1, hasStrings: true, string: huge))

        manager.captureCurrentClipboard(isSecureEntry: false)

        XCTAssertTrue(manager.items.isEmpty, "Gli elementi oltre il cap dimensione non devono essere memorizzati")
    }

    @MainActor
    func testCaptureSkipsBytewiseHugeItemWithinCharCap() {
        // "Bomb" ZWJ/emoji: pochi grapheme cluster (entro il cap caratteri) ma molti byte UTF-8.
        let family = "👨‍👩‍👧‍👦" // 1 grapheme cluster, ~25 byte
        let bomb = String(repeating: family, count: 11_000)
        XCTAssertLessThanOrEqual(bomb.count, ClipboardHistoryManager.maxItemCharacterCount,
                                 "Il cap a CARATTERI non deve scattare: dev'essere il cap a BYTE a fermare")
        XCTAssertGreaterThan(bomb.utf8.count, ClipboardHistoryManager.maxItemByteCount)
        var manager = makeManager(clipboard: FakeClipboardSource(changeCount: 1, hasStrings: true, string: bomb))
        manager.captureCurrentClipboard(isSecureEntry: false)
        XCTAssertTrue(manager.items.isEmpty, "Entro il cap caratteri ma oltre il cap byte → l'elemento va rifiutato")
    }
}
