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

    private func validLargeText(identifier: String, byteCount: Int) -> String {
        let unit = "👨‍👩‍👧‍👦"
        let prefix = "\(identifier)-"
        let remainingBytes = byteCount - prefix.utf8.count
        let unitCount = remainingBytes / unit.utf8.count
        let remainder = remainingBytes % unit.utf8.count
        return prefix + String(repeating: unit, count: unitCount) + String(repeating: "x", count: remainder)
    }

    private func protectionType(at url: URL) throws -> FileProtectionType? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
    }

    private func writeLegacyHistory(to url: URL) throws {
        let item = ClipboardHistoryItem(content: .text("legacy-protected"), createdData: Date())
        try JSONEncoder().encode([item]).write(to: url)
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
        _ = try ClipboardHistoryManager.save([item1, item2, item3], config: config)

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
        _ = try ClipboardHistoryManager.save(loaded, config: config)

        let migratedEncoded = try Data(contentsOf: historyFileURL(in: dir))
        let migratedTopLevel = try JSONSerialization.jsonObject(with: migratedEncoded)
        XCTAssertNotNil(migratedTopLevel as? [String: Any], "Dopo un save il file deve migrare all'envelope (dizionario), non restare un array nudo")
    }

    @MainActor
    func testSaveExcludesHistoryFromBackup() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let item = ClipboardHistoryItem(content: .text("device-only"), createdData: Date())

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        _ = try ClipboardHistoryManager.save([item], config: config)

        let values = try historyFileURL(in: dir).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "Clipboard history must be excluded from backups")
    }

    @MainActor
    func testSaveAppliesCompleteUnlessOpenProtection() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let item = ClipboardHistoryItem(content: .text("protected"), createdData: Date())

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        _ = try ClipboardHistoryManager.save([item], config: config)

        guard let protection = try protectionType(at: historyFileURL(in: dir)) else {
            throw XCTSkip("This test platform does not report FileAttributeKey.protectionKey")
        }
        XCTAssertEqual(protection, .completeUnlessOpen)
    }

    @MainActor
    func testLoadExcludesLegacyHistoryFromBackup() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        var legacyURL = historyFileURL(in: dir)
        try writeLegacyHistory(to: legacyURL)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try legacyURL.setResourceValues(values)

        _ = try ClipboardHistoryManager.load(config: config)

        let hardenedValues = try legacyURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(hardenedValues.isExcludedFromBackup, true, "A successfully read legacy history must be excluded from backups")
    }

    @MainActor
    func testLoadAppliesProtectionToLegacyHistory() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let legacyURL = historyFileURL(in: dir)
        try writeLegacyHistory(to: legacyURL)

        _ = try ClipboardHistoryManager.load(config: config)

        guard let protection = try protectionType(at: legacyURL) else {
            throw XCTSkip("This test platform does not report FileAttributeKey.protectionKey")
        }
        XCTAssertEqual(protection, .completeUnlessOpen)
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
    func testRawFileCapStaysWithinExtensionMemoryBudget() {
        // Copaky [G-38]: the keyboard extension lives under a 50 MB ceiling (AGENTS §4) and decodes +
        // re-encodes this file in-process, so the raw cap stays at 4 MiB. maxCount × maxItemByteCount
        // exceeds it ON PURPOSE: coherence comes from prune-on-save, never from a larger cap.
        XCTAssertEqual(ClipboardHistoryManager.maxRawFileBytes, 4 * 1024 * 1024)
        XCTAssertGreaterThan(
            ClipboardHistoryManagerConfig().maxCount * ClipboardHistoryManager.maxItemByteCount,
            ClipboardHistoryManager.maxRawFileBytes,
            "If this ever flips, re-check testSavePrunesOldestUnpinnedAndSynchronizesMemory: prune-on-save is the coherence mechanism"
        )
    }

    @MainActor
    func testLegitimateHistoryNearTheCapLoadsCompletely() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let base = Date()
        let items = (0..<14).map { index in
            ClipboardHistoryItem(
                content: .text(validLargeText(identifier: "large-\(index)", byteCount: 250 * 1024)),
                createdData: base.addingTimeInterval(Double(index))
            )
        }

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        _ = try ClipboardHistoryManager.save(items, config: config)

        let fileBytes = try Data(contentsOf: historyFileURL(in: dir)).count
        XCTAssertGreaterThan(fileBytes, 3 * 1024 * 1024, "The fixture must sit just under the cap so the guard is exercised, not skipped")
        XCTAssertLessThanOrEqual(fileBytes, ClipboardHistoryManager.maxRawFileBytes)
        XCTAssertEqual(Set(try ClipboardHistoryManager.load(config: config)), Set(items), "Every valid item in a near-cap history must load intact")
    }

    @MainActor
    func testOversizedRawFileCollapsesAndIsPreserved() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        // Copaky [G-38]: the raw-byte guard runs before decoding, so valid JSON is unnecessary here.
        let oversizedBytes = Data(repeating: 0x20, count: ClipboardHistoryManager.maxRawFileBytes + 1)
        try oversizedBytes.write(to: historyFileURL(in: dir))

        XCTAssertThrowsError(try ClipboardHistoryManager.load(config: config)) { error in
            guard case ClipboardHistoryManager.IOError.rawFileOversized(let bytes, let limit) = error else {
                XCTFail("Expected IOError.rawFileOversized, got \(error)")
                return
            }
            XCTAssertEqual(bytes, oversizedBytes.count)
            XCTAssertEqual(limit, ClipboardHistoryManager.maxRawFileBytes)
        }

        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        XCTAssertTrue(manager.items.isEmpty)
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        manager.save()
        XCTAssertEqual(manager.captureProvidedText("volatile", isSecureEntry: false), .rejectedHistoryUnavailable)

        XCTAssertEqual(try Data(contentsOf: historyFileURL(in: dir)), oversizedBytes, "A collapsed manager must not clobber an oversized file")
    }

    @MainActor
    func testFreshCaptureSurvivesAFullyPinnedHistory() {
        // Copaky [G-38]: with maxCount pinned entries, a new capture used to be evicted on the spot.
        var manager = makeManager(maxCount: 3)
        let base = Date()
        manager.items = (0..<3).map { index in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text("pinned-\(index)"), createdData: created, pinnedDate: created)
        }

        XCTAssertEqual(manager.captureProvidedText("fresh-1", isSecureEntry: false, now: base.addingTimeInterval(10)), .captured)
        XCTAssertTrue(texts(manager.items).contains("fresh-1"), "The capture that was just reported must be in the history")
        XCTAssertEqual(manager.items.count, 4, "Only one unpinned item may exceed maxCount when everything else is pinned")

        XCTAssertEqual(manager.captureProvidedText("fresh-2", isSecureEntry: false, now: base.addingTimeInterval(20)), .captured)
        XCTAssertTrue(texts(manager.items).contains("fresh-2"))
        XCTAssertFalse(texts(manager.items).contains("fresh-1"), "The previous unpinned capture is the one evicted")
        XCTAssertEqual(manager.items.count, 4)
        XCTAssertEqual(manager.items.filter { $0.pinnedDate != nil }.count, 3, "Pinned entries are never evicted automatically")

        // The reported capture must also survive persistence and the next launch (counter-review BLOCKER, 05/09).
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir, maxCount: 3)
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        _ = try? ClipboardHistoryManager.save(manager.items, config: config)
        let reloaded = try? ClipboardHistoryManager.load(config: config)
        XCTAssertEqual(reloaded.map(texts)?.contains("fresh-2"), true, "load() must keep the unpinned slot next to maxCount pins")
        XCTAssertEqual(reloaded?.filter { $0.pinnedDate != nil }.count, 3)
    }

    @MainActor
    func testCaptureIsRejectedWhenPinsSaturateTheFileBudget() throws {
        // Copaky [G-38]: pins close to the 4 MiB budget — a fresh 250 KiB capture cannot be persisted, so the
        // manager must say so instead of reporting `.captured` and dropping it at save time.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        let base = Date()
        // 16 × 250 KiB ≈ 4.10 MB of pins: just under the 4 MiB budget; one more 250 KiB entry cannot fit.
        manager.items = (0..<16).map { index in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text(validLargeText(identifier: "pin-\(index)", byteCount: 250 * 1024)), createdData: created, pinnedDate: created)
        }
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        manager.save()
        let bytesBefore = try Data(contentsOf: historyFileURL(in: dir))
        XCTAssertLessThanOrEqual(bytesBefore.count, ClipboardHistoryManager.maxRawFileBytes)
        XCTAssertGreaterThan(bytesBefore.count, ClipboardHistoryManager.maxRawFileBytes - 300 * 1024, "fixture must sit just under the budget")

        let result = manager.captureProvidedText(validLargeText(identifier: "fresh", byteCount: 250 * 1024), isSecureEntry: false, now: base.addingTimeInterval(100))
        XCTAssertEqual(result, .rejectedHistoryFull)
        XCTAssertEqual(manager.items.count, 16, "A rejected capture must not linger in memory")
        XCTAssertFalse(texts(manager.items).contains(where: { $0.hasPrefix("fresh-") }))
        manager.save()
        // save() re-sorts, so compare content, not bytes: the pins on disk are exactly the ones from before.
        XCTAssertEqual(Set(try ClipboardHistoryManager.load(config: config)), Set(manager.items), "Nothing changes on disk after a rejected capture")
        XCTAssertLessThanOrEqual(try Data(contentsOf: historyFileURL(in: dir)).count, ClipboardHistoryManager.maxRawFileBytes)
    }

    @MainActor
    func testCollapsedManagerRejectsCapturesInsteadOfFakingThem() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let oversizedBytes = Data(repeating: 0x20, count: ClipboardHistoryManager.maxRawFileBytes + 1)
        try oversizedBytes.write(to: historyFileURL(in: dir))
        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        XCTAssertEqual(manager.captureProvidedText("volatile", isSecureEntry: false), .rejectedHistoryUnavailable)
        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: historyFileURL(in: dir)), oversizedBytes)
    }

    @MainActor
    func testRepairOversizedHistoryShrinksAValidBuild8File() throws {
        // Copaky [G-38]: a VALID envelope above the budget (build-8 growth) collapses the extension's load;
        // the container app repairs it with the shared capacity policy and the extension can read it again.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let base = Date()
        let items = (0..<18).map { index -> ClipboardHistoryItem in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text(validLargeText(identifier: "big-\(index)", byteCount: 250 * 1024)), createdData: created, pinnedDate: index < 2 ? created : nil)
        }
        let envelope = try JSONEncoder().encode(ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: items))
        XCTAssertGreaterThan(envelope.count, ClipboardHistoryManager.maxRawFileBytes, "fixture must exceed the budget")
        try envelope.write(to: historyFileURL(in: dir))

        XCTAssertThrowsError(try ClipboardHistoryManager.load(config: config)) { error in
            guard case ClipboardHistoryManager.IOError.rawFileOversized = error else { return XCTFail("expected rawFileOversized, got \(error)") }
        }
        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .shrunk)
        let repaired = try ClipboardHistoryManager.load(config: config)
        XCTAssertLessThanOrEqual(try Data(contentsOf: historyFileURL(in: dir)).count, ClipboardHistoryManager.maxRawFileBytes)
        XCTAssertEqual(repaired.filter { $0.pinnedDate != nil }.count, 2, "Pinned entries survive the repair")
        XCTAssertTrue(texts(repaired).contains(where: { $0.hasPrefix("big-17-") }), "The newest unpinned entry survives")
        XCTAssertFalse(texts(repaired).contains(where: { $0.hasPrefix("big-2-") }), "The oldest unpinned entry is pruned first")
        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .notNeeded, "A fitting file is a no-op")
    }

    @MainActor
    func testLegacyOversizedFileIsProtectedAndExcludedBeforeTheSizeGate() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        var url = historyFileURL(in: dir)
        try Data(repeating: 0x20, count: ClipboardHistoryManager.maxRawFileBytes + 1).write(to: url)
        var values = URLResourceValues(); values.isExcludedFromBackup = false
        try url.setResourceValues(values)
        XCTAssertThrowsError(try ClipboardHistoryManager.load(config: config))
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true, "Hardening must happen before the size gate")
    }

    @MainActor
    func testCaptureOlderThanTheExistingEntrySurvivesWithMaxCountOne() {
        // Counter-review N1 (05/09): a clock moved backwards sorts the fresh entry last; the count policy
        // must still keep the entry that was just reported as captured.
        var manager = makeManager(maxCount: 1)
        let base = Date()
        manager.items = [ClipboardHistoryItem(content: .text("future"), createdData: base.addingTimeInterval(100))]
        XCTAssertEqual(manager.captureProvidedText("fresh", isSecureEntry: false, now: base), .captured)
        XCTAssertEqual(texts(manager.items), ["fresh"], "The captured entry keeps its slot; the older unpinned one is evicted")
    }

    @MainActor
    func testRejectedCaptureLeavesPreexistingHistoryUntouched() throws {
        // Counter-review N2 (05/09): a capture rejected by the byte budget must be a no-op — the count
        // policy alone would have evicted the old unpinned entry.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir, maxCount: 17)
        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        let base = Date()
        var items = (0..<16).map { index -> ClipboardHistoryItem in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text(validLargeText(identifier: "pin-\(index)", byteCount: 250 * 1024)), createdData: created, pinnedDate: created)
        }
        items.append(ClipboardHistoryItem(content: .text("old-unpinned"), createdData: base.addingTimeInterval(-1000)))
        items.sort(by: >)
        manager.items = items
        let before = manager.items
        XCTAssertEqual(manager.captureProvidedText(validLargeText(identifier: "fresh", byteCount: 250 * 1024), isSecureEntry: false, now: base.addingTimeInterval(100)), .rejectedHistoryFull)
        XCTAssertEqual(manager.items, before, "A rejected capture must not touch the pre-existing history")
        XCTAssertTrue(texts(manager.items).contains("old-unpinned"))
    }

    @MainActor
    func testSaveAppliesTheCountPolicy() throws {
        // Counter-review N3 (05/09): an unpin can leave maxCount + 1 entries in memory; save() must apply
        // the same count policy as load() so the next launch does not silently drop one.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir, maxCount: 3)
        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        let base = Date()
        manager.items = [
            ClipboardHistoryItem(content: .text("pin-a"), createdData: base, pinnedDate: base),
            ClipboardHistoryItem(content: .text("pin-b"), createdData: base.addingTimeInterval(1), pinnedDate: base.addingTimeInterval(1)),
            ClipboardHistoryItem(content: .text("pin-c"), createdData: base.addingTimeInterval(2), pinnedDate: base.addingTimeInterval(2)),
            ClipboardHistoryItem(content: .text("new-unpinned"), createdData: base.addingTimeInterval(10)),
            ClipboardHistoryItem(content: .text("old-unpinned"), createdData: base.addingTimeInterval(-10)),
        ]
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        manager.save()
        XCTAssertEqual(manager.items.count, 4, "3 pins + the one unpinned slot")
        XCTAssertTrue(texts(manager.items).contains("new-unpinned"))
        XCTAssertFalse(texts(manager.items).contains("old-unpinned"))
        XCTAssertEqual(Set(try ClipboardHistoryManager.load(config: config)), Set(manager.items), "Disk and memory agree after save()")
    }

    @MainActor
    func testRepairDropsOldestPinsOnlyAsLastResort() throws {
        // Counter-review N4 (05/09): pins alone above the budget must not leave the history unreadable forever.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let base = Date()
        let items = (0..<18).map { index -> ClipboardHistoryItem in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text(validLargeText(identifier: "pin-\(index)", byteCount: 250 * 1024)), createdData: created, pinnedDate: created)
        }
        try JSONEncoder().encode(ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: items)).write(to: historyFileURL(in: dir))
        XCTAssertThrowsError(try ClipboardHistoryManager.load(config: config))
        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .shrunk)
        let repaired = try ClipboardHistoryManager.load(config: config)
        XCTAssertTrue(repaired.allSatisfy { $0.pinnedDate != nil })
        XCTAssertTrue(texts(repaired).contains(where: { $0.hasPrefix("pin-17-") }), "The newest pins survive")
        XCTAssertFalse(texts(repaired).contains(where: { $0.hasPrefix("pin-0-") }), "The oldest pin is the one sacrificed")
    }

    @MainActor
    func testRepairMovesAsideAMalformedOrAbsurdlyLargeFile() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        try Data("{not json".utf8).write(to: historyFileURL(in: dir))
        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .movedAside)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFileURL(in: dir).path))
        let asides = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("clipboard_history.unreadable-") }
        XCTAssertEqual(asides.count, 1, "The unreadable bytes are preserved next to the history")
        XCTAssertEqual(try ClipboardHistoryManager.load(config: config), [], "The keyboard restarts from an empty history")

        try Data(repeating: 0x20, count: ClipboardHistoryManager.repairReadLimit + 1).write(to: historyFileURL(in: dir))
        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .movedAside, "Beyond the read limit nothing is decoded")
    }

    @MainActor
    func testCaptureAfterUnpinAllKeepsTheNewestUnpinnedEntry() {
        // Counter-review N3 (05/09): «unpin all» concatenates groups without re-sorting; the count policy
        // must see a normalized order or it evicts the newest unpinned entry.
        var manager = makeManager(maxCount: 3)
        let base = Date()
        manager.items = [
            ClipboardHistoryItem(content: .text("older-ex-pin"), createdData: base.addingTimeInterval(-50)),
            ClipboardHistoryItem(content: .text("newest-ex-pin"), createdData: base.addingTimeInterval(-10)),
            ClipboardHistoryItem(content: .text("oldest"), createdData: base.addingTimeInterval(-500)),
        ]
        XCTAssertEqual(manager.captureProvidedText("fresh", isSecureEntry: false, now: base), .captured)
        XCTAssertEqual(texts(manager.items), ["fresh", "newest-ex-pin", "older-ex-pin"], "Sorted newest-first; the oldest is the one evicted")
    }

    @MainActor
    func testRepairLeavesAFutureSchemaUntouched() throws {
        // Counter-review N4 (05/09): a newer build's file is not malformed — it must not be moved aside.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let future = Data(#"{"schemaVersion":99,"items":[]}"#.utf8)
        try future.write(to: historyFileURL(in: dir))
        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .notNeeded)
        XCTAssertEqual(try Data(contentsOf: historyFileURL(in: dir)), future, "A future-schema file is preserved byte for byte")
    }

    @MainActor
    func testRepairLeavesAFutureSchemaWithADifferentShapeUntouched() throws {
        // Counter-review n.4, N4 (05/09): a newer build may change the shape of `items`; only the version matters.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let future = Data(#"{"schemaVersion":99,"items":{"newFormat":[]}}"#.utf8)
        try future.write(to: historyFileURL(in: dir))
        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .notNeeded)
        XCTAssertEqual(try Data(contentsOf: historyFileURL(in: dir)), future, "A future-schema file is preserved byte for byte")
        let asides = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("clipboard_history.unreadable-") }
        XCTAssertTrue(asides.isEmpty, "Nothing is moved aside")
        XCTAssertThrowsError(try ClipboardHistoryManager.load(config: config)) { error in
            guard case ClipboardHistoryManager.IOError.unsupportedSchemaVersion(99) = error else {
                return XCTFail("Expected unsupportedSchemaVersion(99), got \(error)")
            }
        }
    }

    @MainActor
    func testRepairHardensAValidFileItLeavesInPlace() throws {
        // Counter-review n.4, G-22 (05/09): the container app can run before the extension's next load();
        // a valid build-8 history must not stay backup-eligible until then.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        var url = historyFileURL(in: dir)
        let item = ClipboardHistoryItem(content: .text("build-8"), createdData: Date())
        try JSONEncoder().encode(ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: [item])).write(to: url)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try url.setResourceValues(values)

        XCTAssertEqual(ClipboardHistoryManager.repairUnreadableHistory(config: config), .notNeeded)

        let hardened = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(hardened.isExcludedFromBackup, true, "A valid history left in place is excluded from backups by the repair itself")
        if let protection = try protectionType(at: url) {
            XCTAssertEqual(protection, .completeUnlessOpen)
        }
        XCTAssertEqual(texts(try ClipboardHistoryManager.load(config: config)), ["build-8"], "The file content is untouched")
    }

    @MainActor
    func testSaveReportsFailureWhenPinsAloneExceedTheBudget() throws {
        // Counter-review n.4 (05/09): nil from the static save means nothing was written — not a success.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let base = Date()
        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        manager.items = (0..<18).map { index in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text(validLargeText(identifier: "pin-\(index)", byteCount: 250 * 1024)), createdData: created, pinnedDate: created)
        }
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        XCTAssertFalse(manager.save(), "Nothing was written: the caller must not be told the history is safe on disk")
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFileURL(in: dir).path), "No file is created when nothing can be persisted")
        XCTAssertEqual(manager.items.count, 18, "Memory is untouched when nothing is persisted")
    }

    @MainActor
    func testPinningAtTheExactBudgetKeepsThePreviousFileAndReportsFailure() throws {
        // Counter-review n. 5 (05/09): 15 pins + 1 unpinned entry filling the budget to the byte; pinning the
        // last one exceeds it with nothing left to prune. Nothing is written, the previous file survives and the
        // caller is told — the tab now persists every pin/unpin/delete and shows the toast.
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let base = Date()
        var items = (0..<15).map { index -> ClipboardHistoryItem in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text(validLargeText(identifier: "pin-\(index)", byteCount: 262_120)), createdData: created, pinnedDate: created)
        }
        let probeBytes = 100
        let probe = ClipboardHistoryItem(content: .text(validLargeText(identifier: "last", byteCount: probeBytes)), createdData: base.addingTimeInterval(15))
        let overhead = try XCTUnwrap(ClipboardHistoryManager.encodedByteCount(items + [probe]))
        let lastBytes = probeBytes + (ClipboardHistoryManager.maxRawFileBytes - 4 - overhead)
        XCTAssertLessThan(lastBytes, ClipboardHistoryManager.maxItemByteCount, "The filler must stay under the per-item cap")
        let last = ClipboardHistoryItem(content: .text(validLargeText(identifier: "last", byteCount: lastBytes)), createdData: base.addingTimeInterval(15))
        items.append(last)
        let total = try XCTUnwrap(ClipboardHistoryManager.encodedByteCount(items))
        XCTAssertLessThanOrEqual(total, ClipboardHistoryManager.maxRawFileBytes, "The fixture fits the budget")
        XCTAssertGreaterThan(total + 20, ClipboardHistoryManager.maxRawFileBytes, "The fixture sits right under the budget")

        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        manager.items = items
        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        XCTAssertTrue(manager.save(), "The exact-budget history is written")

        let index = try XCTUnwrap(manager.items.firstIndex(where: { $0.content == last.content }))
        manager.items[index].pinnedDate = base.addingTimeInterval(16)
        XCTAssertFalse(manager.save(), "All pinned and over the budget: nothing can be written, and that is reported")

        let onDisk = try ClipboardHistoryManager.load(config: config)
        XCTAssertEqual(onDisk.count, 16, "The previous file is preserved")
        XCTAssertNil(onDisk.first(where: { $0.content == last.content })?.pinnedDate, "The unpersisted pin is not on disk")
    }

    func testPruneToRawFileBudgetIsLinearOnManyTinyEntries() {
        // Counter-review N5 (05/09): thousands of tiny pinned entries must prune in a few passes.
        let base = Date()
        var items = (0..<40_000).map { index -> ClipboardHistoryItem in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(content: .text("pin-\(index)-" + String(repeating: "x", count: 100)), createdData: created, pinnedDate: created)
        }
        let start = Date()
        XCTAssertTrue(ClipboardHistoryManager.pruneToRawFileBudget(&items, evictingPinnedAsLastResort: true))
        XCTAssertLessThan(Date().timeIntervalSince(start), 10, "Pruning must not be quadratic")
        XCTAssertLessThanOrEqual(ClipboardHistoryManager.encodedByteCount(items) ?? .max, ClipboardHistoryManager.maxRawFileBytes)
        XCTAssertTrue(items.contains(where: { $0.createdData == base.addingTimeInterval(39_999) }), "The newest pin survives")
    }

    @MainActor
    func testSavePrunesOldestUnpinnedAndSynchronizesMemory() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let base = Date()
        let originalItems = (0..<70).reversed().map { index in
            let created = base.addingTimeInterval(Double(index))
            return ClipboardHistoryItem(
                content: .text(validLargeText(identifier: "item-\(index)", byteCount: ClipboardHistoryManager.maxItemByteCount - 1_024)),
                createdData: created,
                pinnedDate: index < 2 ? created : nil
            )
        }
        var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
        manager.items = originalItems

        SemiStaticStates.shared.setHasFullAccess(true)
        defer { SemiStaticStates.shared.setHasFullAccess(false) }
        manager.save()

        let writtenBytes = try Data(contentsOf: historyFileURL(in: dir)).count
        XCTAssertLessThanOrEqual(writtenBytes, ClipboardHistoryManager.maxRawFileBytes)
        XCTAssertLessThan(manager.items.count, originalItems.count, "The oversized state must be pruned before persistence")
        XCTAssertTrue(texts(manager.items).contains(where: { $0.hasPrefix("item-0-") }), "Pinned oldest item 0 must remain")
        XCTAssertTrue(texts(manager.items).contains(where: { $0.hasPrefix("item-1-") }), "Pinned oldest item 1 must remain")
        XCTAssertFalse(texts(manager.items).contains(where: { $0.hasPrefix("item-2-") }), "The oldest unpinned item must be pruned first")
        XCTAssertTrue(texts(manager.items).contains(where: { $0.hasPrefix("item-69-") }), "The newest unpinned item must remain")
        XCTAssertEqual(Set(try ClipboardHistoryManager.load(config: config)), Set(manager.items), "Memory must match the persisted pruned state")

        let sentinelBytes = Data("existing-history-must-survive".utf8)
        try sentinelBytes.write(to: historyFileURL(in: dir))
        manager.items = originalItems.map { item in
            var pinnedItem = item
            pinnedItem.pinnedDate = item.createdData
            return pinnedItem
        }
        manager.save()
        XCTAssertEqual(manager.items.count, originalItems.count, "An all-pinned oversized state must remain intact in memory")
        XCTAssertEqual(try Data(contentsOf: historyFileURL(in: dir)), sentinelBytes, "An all-pinned oversized state must not clobber the existing file")
    }
}
