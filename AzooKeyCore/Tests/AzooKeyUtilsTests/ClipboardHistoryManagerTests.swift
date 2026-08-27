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

/// Spy a riferimento: verifica che il valore della pasteboard venga letto una volta sola.
/// 参照型 spy：pasteboard の値を一度だけ読むことを検証する。
@MainActor
private final class CountingClipboardSource: ClipboardSource {
    let changeCount: Int
    let hasStrings: Bool
    private let storedString: String?
    private(set) var stringReadCount = 0

    init(changeCount: Int = 1, hasStrings: Bool = true, string: String?) {
        self.changeCount = changeCount
        self.hasStrings = hasStrings
        self.storedString = string
    }

    var string: String? {
        self.stringReadCount += 1
        return self.storedString
    }
}

final class ClipboardHistoryManagerTests: XCTestCase {

    @MainActor
    private func makeManager(maxCount: Int = 100, clipboard: any ClipboardSource = FakeClipboardSource(hasStrings: false, string: nil)) -> ClipboardHistoryManager {
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
        let result = manager.captureCurrentClipboard(isSecureEntry: true)
        XCTAssertEqual(result, .rejected)
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

        let result = manager.captureCurrentClipboard(isSecureEntry: false)

        XCTAssertEqual(result, .captured)
        XCTAssertTrue(texts(manager).contains(unique), "La cattura esplicita deve memorizzare il contenuto corrente")
        XCTAssertFalse(manager.hasPendingClipboard, "Dopo la cattura non deve restare contenuto pendente")
    }

    @MainActor
    func testCaptureSkipsOversizedItem() {
        let huge = String(repeating: "a", count: ClipboardHistoryManager.maxItemCharacterCount + 1)
        var manager = makeManager(clipboard: FakeClipboardSource(changeCount: 1, hasStrings: true, string: huge))

        let result = manager.captureCurrentClipboard(isSecureEntry: false)

        XCTAssertEqual(result, .rejectedOversized)
        XCTAssertTrue(manager.items.isEmpty, "Gli elementi oltre il cap dimensione non devono essere memorizzati")
    }

    @MainActor
    func testCaptureAcceptsExactCharacterCap() {
        let exact = String(repeating: "a", count: ClipboardHistoryManager.maxItemCharacterCount)
        var manager = makeManager(clipboard: FakeClipboardSource(string: exact))

        let result = manager.captureCurrentClipboard(isSecureEntry: false)

        XCTAssertEqual(result, .captured)
        XCTAssertEqual(texts(manager), [exact], "Il confine esatto di 50k caratteri deve restare accettato")
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
        let result = manager.captureCurrentClipboard(isSecureEntry: false)
        XCTAssertEqual(result, .rejectedOversized)
        XCTAssertTrue(manager.items.isEmpty, "Entro il cap caratteri ma oltre il cap byte → l'elemento va rifiutato")
    }

    @MainActor
    func testCaptureHonorsExactByteCapBoundaryWithinCharacterCap() {
        let family = "👨‍👩‍👧‍👦"
        let familyCount = ClipboardHistoryManager.maxItemByteCount / family.utf8.count
        let remainder = ClipboardHistoryManager.maxItemByteCount % family.utf8.count
        let exact = String(repeating: family, count: familyCount) + String(repeating: "a", count: remainder)
        XCTAssertEqual(exact.utf8.count, ClipboardHistoryManager.maxItemByteCount)
        XCTAssertLessThanOrEqual(exact.count, ClipboardHistoryManager.maxItemCharacterCount)
        var manager = makeManager(clipboard: FakeClipboardSource(string: exact))

        let result = manager.captureCurrentClipboard(isSecureEntry: false)

        XCTAssertEqual(result, .captured)
        XCTAssertEqual(texts(manager), [exact], "Il confine esatto di 256 KiB deve restare accettato")

        let plusOne = exact + "a"
        XCTAssertEqual(plusOne.utf8.count, ClipboardHistoryManager.maxItemByteCount + 1)
        XCTAssertLessThanOrEqual(plusOne.count, ClipboardHistoryManager.maxItemCharacterCount)
        var rejectingManager = makeManager(clipboard: FakeClipboardSource(string: plusOne))
        let rejected = rejectingManager.captureCurrentClipboard(isSecureEntry: false)
        XCTAssertEqual(rejected, .rejectedOversized)
        XCTAssertTrue(rejectingManager.items.isEmpty, "256 KiB + 1 byte deve essere rifiutato")
    }

    func testRawUTF8PreflightIgnoresLeadingBOMAtByteCapBoundary() {
        let bom = Data([0xEF, 0xBB, 0xBF])
        let exact = bom + Data(repeating: 0x61, count: ClipboardHistoryManager.maxItemByteCount)
        let plusOne = exact + Data([0x61])

        XCTAssertFalse(
            SystemClipboardSource.exceedsDecodedUTF8ByteLimit(exact, maxByteCount: ClipboardHistoryManager.maxItemByteCount),
            "Il BOM rimosso dalla decodifica non deve far rifiutare un testo di esatti 256 KiB"
        )
        XCTAssertTrue(
            SystemClipboardSource.exceedsDecodedUTF8ByteLimit(plusOne, maxByteCount: ClipboardHistoryManager.maxItemByteCount),
            "BOM + testo decodificato di 256 KiB + 1 byte deve essere rifiutato"
        )
    }

    @MainActor
    func testCaptureRejectsDeviceByteCapPayloadOnceWithoutMutatingHistory() {
        // Stessa fixture di test13: oltre sia 256 KiB sia 50k caratteri. La guardia byte-first deve
        // rifiutarla senza consegnarla a insert/save e senza una seconda lettura della pasteboard.
        // test13 と同じ fixture。byte-first で拒否し、insert/save と二度目の読み取りを行わない。
        let payload = String(repeating: "あ", count: 120_000)
        XCTAssertGreaterThan(payload.utf8.count, ClipboardHistoryManager.maxItemByteCount)
        XCTAssertGreaterThan(payload.count, ClipboardHistoryManager.maxItemCharacterCount)

        let clipboard = CountingClipboardSource(changeCount: 17, string: payload)
        var manager = makeManager(clipboard: clipboard)
        let now = Date()
        manager.detectClipboardChange(now: now)
        XCTAssertTrue(manager.hasPendingClipboard)
        let sentinel = ClipboardHistoryItem(
            content: .text("expired-sentinel"),
            createdData: now.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        manager.items = [sentinel]

        let result = manager.captureCurrentClipboard(isSecureEntry: false, now: now)

        XCTAssertEqual(result, .rejectedOversized)
        XCTAssertEqual(clipboard.stringReadCount, 1, "Il valore degli appunti deve essere letto una volta sola")
        XCTAssertEqual(manager.items, [sentinel], "Il rifiuto non deve mutare o potare la cronologia")
        XCTAssertFalse(manager.hasPendingClipboard, "Il contenuto rifiutato deve risultare gestito, non riproposto")
    }

    @MainActor
    func testCaptureProvidedTextRejectsBytewiseHugeItemWithoutMutatingHistory() {
        let family = "👨‍👩‍👧‍👦"
        let bomb = String(repeating: family, count: 11_000)
        var manager = makeManager()
        let sentinel = ClipboardHistoryItem(content: .text("sentinel"), createdData: .now)
        manager.items = [sentinel]

        let result = manager.captureProvidedText(bomb, isSecureEntry: false)

        XCTAssertEqual(result, .rejectedOversized)
        XCTAssertEqual(manager.items, [sentinel], "Anche il testo consegnato dal sistema deve essere rifiutato senza mutazioni")
        XCTAssertFalse(manager.hasPendingClipboard)
    }

    @MainActor
    func testSourceSideOversizedRejectionClearsPendingWithoutReadingValue() {
        let clipboard = CountingClipboardSource(changeCount: 23, string: "must-not-be-read")
        var manager = makeManager(clipboard: clipboard)
        manager.detectClipboardChange()
        XCTAssertTrue(manager.hasPendingClipboard)

        manager.markCurrentClipboardRejectedOversized()

        XCTAssertFalse(manager.hasPendingClipboard)
        XCTAssertEqual(clipboard.stringReadCount, 0, "Un rifiuto raw-Data già deciso non deve rileggere il valore")
        XCTAssertTrue(manager.items.isEmpty)
    }

    // MARK: - persistence (envelope versionato, decode tollerante) / persistence (versioned envelope, tolerant decode)

    private func makeTempSaveDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func historyFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("clipboard_history.json", isDirectory: false)
    }

    private func texts(_ items: [ClipboardHistoryItem]) -> [String] {
        items.compactMap { item -> String? in
            if case .text(let t) = item.content { return t }
            return nil
        }
    }

    @MainActor
    func testRoundTripEnvelopeFormat() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let now = Date()
        let item1 = ClipboardHistoryItem(content: .text("alpha"), createdData: now, pinnedDate: now)
        let item2 = ClipboardHistoryItem(content: .text("beta"), createdData: now.addingTimeInterval(-10))
        let item3 = ClipboardHistoryItem(content: .text("gamma"), createdData: now.addingTimeInterval(-20))

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        try ClipboardHistoryManager.save([item1, item2, item3], config: config)

        let encoded = try Data(contentsOf: historyFileURL(in: dir))
        let topLevel = try JSONSerialization.jsonObject(with: encoded)
        let dict = try XCTUnwrap(topLevel as? [String: Any], "Il formato su disco deve essere un envelope (dizionario), non un array nudo")
        XCTAssertEqual(dict["schemaVersion"] as? Int, 1)
        XCTAssertEqual((dict["items"] as? [Any])?.count, 3)

        let loaded = try ClipboardHistoryManager.load(config: config)
        XCTAssertEqual(Set(texts(loaded)), Set(["alpha", "beta", "gamma"]))
    }

    @MainActor
    func testLoadLegacyBareArrayMigrates() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let now = Date()
        let item1 = ClipboardHistoryItem(content: .text("legacy-one"), createdData: now)
        let item2 = ClipboardHistoryItem(content: .text("legacy-two"), createdData: now.addingTimeInterval(-5))

        // Wire format legacy pre-versioning: array nudo, senza envelope.
        let legacyEncoded = try JSONEncoder().encode([item1, item2])
        try legacyEncoded.write(to: historyFileURL(in: dir))

        let loaded = try ClipboardHistoryManager.load(config: config)
        XCTAssertEqual(Set(texts(loaded)), Set(["legacy-one", "legacy-two"]), "Il formato legacy (array nudo) deve continuare a essere leggibile")

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        try ClipboardHistoryManager.save(loaded, config: config)

        let migratedEncoded = try Data(contentsOf: historyFileURL(in: dir))
        let migratedTopLevel = try JSONSerialization.jsonObject(with: migratedEncoded)
        XCTAssertNotNil(migratedTopLevel as? [String: Any], "Dopo un save il file deve migrare all'envelope (dizionario), non restare un array nudo")
    }

    @MainActor
    func testLoadDropsCorruptedItemKeepsGood() throws {
        let now = Date().timeIntervalSinceReferenceDate
        func itemJSON(_ text: String) -> String {
            "{\"content\":{\"text\":{\"_0\":\"\(text)\"}},\"createdData\":\(now)}"
        }

        // Variante A: envelope versionato con un item corrotto (42) in mezzo a due validi.
        let envelopeDir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: envelopeDir) }
        let envelopeConfig = MockClipboardHistoryManagerConfiguration(saveDirectory: envelopeDir)
        let envelopeJSON = "{\"schemaVersion\":1,\"items\":[\(itemJSON("good1")),42,\(itemJSON("good2"))]}"
        try envelopeJSON.data(using: .utf8)!.write(to: historyFileURL(in: envelopeDir))
        let envelopeItems = try ClipboardHistoryManager.load(config: envelopeConfig)
        XCTAssertEqual(Set(texts(envelopeItems)), Set(["good1", "good2"]), "L'item corrotto deve decadere a nil, i due validi restano")

        // Variante B: array nudo legacy con un item corrotto in mezzo a due validi.
        let legacyDir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: legacyDir) }
        let legacyConfig = MockClipboardHistoryManagerConfiguration(saveDirectory: legacyDir)
        let legacyJSON = "[\(itemJSON("good3")),42,\(itemJSON("good4"))]"
        try legacyJSON.data(using: .utf8)!.write(to: historyFileURL(in: legacyDir))
        let legacyItems = try ClipboardHistoryManager.load(config: legacyConfig)
        XCTAssertEqual(Set(texts(legacyItems)), Set(["good3", "good4"]), "Anche nel formato legacy l'item corrotto decade, i validi restano")
    }

    @MainActor
    func testCorruptTopLevelYieldsEmptyNoCrashNoClobber() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let originalBytes = "not json".data(using: .utf8)!
        try originalBytes.write(to: historyFileURL(in: dir))

        XCTAssertThrowsError(try ClipboardHistoryManager.load(config: config), "Un file corrotto/non-JSON deve far fallire load, non crashare")

        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        XCTAssertTrue(manager.items.isEmpty, "Con un file corrotto init deve produrre una history vuota, senza crash")

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        manager.save()

        let bytesAfterSaveAttempt = try Data(contentsOf: historyFileURL(in: dir))
        XCTAssertEqual(bytesAfterSaveAttempt, originalBytes, "Con history collassata, save() deve essere no-op: il file corrotto non va sovrascritto (anti-clobber)")
    }

    @MainActor
    func testNewerSchemaVersionPreserved() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let originalBytes = "{\"schemaVersion\":99,\"items\":[]}".data(using: .utf8)!
        try originalBytes.write(to: historyFileURL(in: dir))

        XCTAssertThrowsError(try ClipboardHistoryManager.load(config: config)) { error in
            guard case ClipboardHistoryManager.IOError.unsupportedSchemaVersion(let version) = error else {
                XCTFail("Atteso IOError.unsupportedSchemaVersion, trovato \(error)")
                return
            }
            XCTAssertEqual(version, 99)
        }

        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        XCTAssertTrue(manager.items.isEmpty, "Uno schema più nuovo del build corrente non va letto: history vuota")

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        manager.save()

        let bytesAfterSaveAttempt = try Data(contentsOf: historyFileURL(in: dir))
        XCTAssertEqual(bytesAfterSaveAttempt, originalBytes, "save() deve essere no-op: non sovrascrivere un file di schema futuro")
    }

    @MainActor
    func testOversizedRawFileYieldsEmpty() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        // La guardia anti-tamper controlla la size dei byte grezzi PRIMA del decode: non serve JSON valido.
        let oversizedBytes = Data(repeating: 0x20, count: ClipboardHistoryManager.maxRawFileBytes + 1)
        try oversizedBytes.write(to: historyFileURL(in: dir))

        let loaded = try ClipboardHistoryManager.load(config: config)
        XCTAssertTrue(loaded.isEmpty, "Un file oltre maxRawFileBytes deve restituire [] senza lanciare")
    }
}
