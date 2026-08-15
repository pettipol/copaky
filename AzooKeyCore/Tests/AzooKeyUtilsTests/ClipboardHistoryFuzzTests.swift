import XCTest
@testable import KeyboardViews
@testable import AzooKeyUtils

/// PRNG deterministico xorshift64* — MAI `SystemRandomNumberGenerator`: la campagna deve essere
/// riproducibile bit-per-bit tra run diversi (macchine, CI, giorni diversi). Il seme è una costante
/// (`ClipboardHistoryFuzzTests.seed`), stampata nel log a inizio campagna.
private struct XorShift64Star {
    private var state: UInt64

    init(seed: UInt64) {
        // xorshift richiede stato non-zero.
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }

    mutating func nextByte() -> UInt8 {
        UInt8(next() & 0xFF)
    }

    /// Intero uniforme in `range`. Se `range` è vuoto ritorna `lowerBound` (no-op difensivo: la
    /// campagna non deve mai crashare per colpa del PROPRIO generatore di input).
    mutating func nextInt(in range: Range<Int>) -> Int {
        guard range.count > 0 else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(range.count))
    }

    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
}

/// Fuzz/property test sul parser di input NON FIDATO di `ClipboardHistoryManager.load(config:)`:
/// il file `clipboard_history.json` vive nel container condiviso app↔estensione tastiera e può
/// essere scritto da un build precedente, da un bug di un'altra app col medesimo App Group, o essere
/// manomesso — va trattato come input ostile. Proprietà verificate a ogni caso (P1..P5), vedi
/// `loadAndCheck`.
final class ClipboardHistoryFuzzTests: XCTestCase {

    /// Seme fisso della campagna: ripetibilità bit-per-bit.
    static let seed: UInt64 = 0x5EED_C0FF_EE

    // MARK: - esito e istogramma

    private enum Outcome: Hashable, CustomStringConvertible {
        case items(Int)
        case malformedHistoryFile
        case unsupportedSchemaVersion
        case otherError(String)

        var description: String {
            switch self {
            case .items(let n): return "items(\(n))"
            case .malformedHistoryFile: return "malformedHistoryFile"
            case .unsupportedSchemaVersion: return "unsupportedSchemaVersion"
            case .otherError(let detail): return "altroErrore(\(detail))"
            }
        }
    }

    private func printHistogram(_ histogram: [Outcome: Int], maxDuration: (name: String, seconds: Double), label: String) {
        print("=== FUZZ HISTOGRAM (\(label)) ===")
        for (outcome, count) in histogram.sorted(by: { $0.key.description < $1.key.description }) {
            print("  \(outcome.description): \(count)")
        }
        print("=== FUZZ MAX DURATION (\(label)) === caso=\(maxDuration.name) secondi=\(maxDuration.seconds)")
    }

    // MARK: - fixture helpers (stesso pattern di ClipboardHistoryManagerTests.swift, duplicato qui:
    // gli helper `private` di quella classe non sono visibili da questo file).

    private func makeTempSaveDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func historyFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("clipboard_history.json", isDirectory: false)
    }

    // MARK: - motore: scrive, carica, verifica le proprietà, ripulisce

    /// Scrive `data` nel file di history, chiama `ClipboardHistoryManager.load(config:)`, verifica:
    /// - P1: nessun crash (implicito — se il processo muore, il caso stampato PRIMA della load è il colpevole)
    /// - P2: ogni item restituito rispetta i cap (count ≤ 50.000 && utf8.count ≤ 256 KB)
    /// - P3: items.count ≤ config.maxCount
    /// - P4: ordinamento non-crescente secondo l'operatore `<` di ClipboardHistoryItem (coerente con `sort(by: >)`)
    /// - P5: tempo per input < 3s
    /// Ripulisce il file dopo il caso.
    @discardableResult
    private func loadAndCheck(
        _ data: Data,
        name: String,
        url: URL,
        config: any ClipboardHistoryManagerConfiguration,
        histogram: inout [Outcome: Int],
        maxDuration: inout (name: String, seconds: Double)
    ) -> Outcome {
        try? FileManager.default.removeItem(at: url)
        do {
            try data.write(to: url)
        } catch {
            XCTFail("scrittura fallita per il caso \(name): \(error)")
            return .otherError("write-failed")
        }
        // Stampato PRIMA della load: se il processo crasha, l'ultimo nome nel log è il colpevole.
        print("FUZZ_CASE:", name)
        let start = Date()
        var outcome: Outcome
        do {
            let items = try ClipboardHistoryManager.load(config: config)
            for item in items {
                if case .text(let s) = item.content {
                    XCTAssertLessThanOrEqual(s.count, ClipboardHistoryManager.maxItemCharacterCount, "P2 (cap caratteri) violato in \(name)")
                    XCTAssertLessThanOrEqual(s.utf8.count, ClipboardHistoryManager.maxItemByteCount, "P2 (cap byte) violato in \(name)")
                }
            }
            XCTAssertLessThanOrEqual(items.count, config.maxCount, "P3 (maxCount) violato in \(name)")
            if items.count > 1 {
                for i in 0..<(items.count - 1) {
                    XCTAssertFalse(items[i] < items[i + 1], "P4 (ordinamento non-crescente) violato in \(name)")
                }
            }
            outcome = .items(items.count)
        } catch ClipboardHistoryManager.IOError.malformedHistoryFile {
            outcome = .malformedHistoryFile
        } catch ClipboardHistoryManager.IOError.unsupportedSchemaVersion(_) {
            outcome = .unsupportedSchemaVersion
        } catch {
            outcome = .otherError(String(describing: error))
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "P5 (tempo < 3s) violato in \(name): \(elapsed)s")
        if elapsed > maxDuration.seconds {
            maxDuration = (name, elapsed)
        }
        histogram[outcome, default: 0] += 1
        try? FileManager.default.removeItem(at: url)
        return outcome
    }

    // MARK: - generatore di envelope VALIDO (tipo reale HistoryFile) per il fuzzing per-mutazione

    private func randomLowercaseString(length: Int, rng: inout XorShift64Star) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        var chars: [Character] = []
        chars.reserveCapacity(length)
        for _ in 0..<length {
            chars.append(alphabet[rng.nextInt(in: 0..<alphabet.count)])
        }
        return String(chars)
    }

    private func makeValidEnvelope(itemCount: Int, rng: inout XorShift64Star) -> Data {
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        var items: [ClipboardHistoryItem] = []
        items.reserveCapacity(itemCount)
        for i in 0..<itemCount {
            let length = 1 + rng.nextInt(in: 0..<20)
            let content = randomLowercaseString(length: length, rng: &rng)
            let created = base.addingTimeInterval(Double(i))
            let pinned: Date? = (rng.next() % 3 == 0) ? created : nil
            items.append(ClipboardHistoryItem(content: .text(content), createdData: created, pinnedDate: pinned))
        }
        let file = ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: items)
        return try! JSONEncoder().encode(file)
    }

    /// Applica UNA delle 5 mutazioni della campagna a una copia dei byte di `base`. Deterministico:
    /// dipende solo da `rng`.
    private func mutate(_ base: Data, rng: inout XorShift64Star) -> Data {
        var bytes = [UInt8](base)
        guard !bytes.isEmpty else { return Data(bytes) }
        let kind = rng.nextInt(in: 0..<5)
        switch kind {
        case 0: // troncamento a offset casuale
            let cut = rng.nextInt(in: 0..<bytes.count)
            bytes = Array(bytes[0..<cut])
        case 1: // 1-8 byte flippati
            let flips = 1 + rng.nextInt(in: 0..<8)
            for _ in 0..<flips {
                let idx = rng.nextInt(in: 0..<bytes.count)
                bytes[idx] ^= rng.nextByte()
            }
        case 2: // inserzione di 1-16 byte casuali
            let count = 1 + rng.nextInt(in: 0..<16)
            let at = rng.nextInt(in: 0...bytes.count)
            let insertion = (0..<count).map { _ in rng.nextByte() }
            bytes.insert(contentsOf: insertion, at: at)
        case 3: // sostituzione di un token strutturale
            let tokens: [UInt8] = [UInt8(ascii: "\""), UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "["), UInt8(ascii: "]"), UInt8(ascii: ","), UInt8(ascii: ":")]
            let positions = bytes.indices.filter { tokens.contains(bytes[$0]) }
            if !positions.isEmpty {
                let idx = positions[rng.nextInt(in: 0..<positions.count)]
                bytes[idx] = tokens[rng.nextInt(in: 0..<tokens.count)]
            }
        default: // duplicazione di una fetta
            guard bytes.count > 1 else { break }
            let start = rng.nextInt(in: 0..<bytes.count)
            let len = 1 + rng.nextInt(in: 0..<(bytes.count - start))
            let slice = Array(bytes[start..<(start + len)])
            let insertAt = rng.nextInt(in: 0...bytes.count)
            bytes.insert(contentsOf: slice, at: insertAt)
        }
        return Data(bytes)
    }

    // MARK: - fixture per il corpus patologico

    private func rawItemJSON(text: String, createdData: Double) -> String {
        "{\"content\":{\"text\":{\"_0\":\"\(text)\"}},\"createdData\":\(createdData)}"
    }

    private func singleItemEnvelope(content: String, createdData: Date = Date(timeIntervalSinceReferenceDate: 700_000_000)) -> Data {
        let item = ClipboardHistoryItem(content: .text(content), createdData: createdData)
        let file = ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: [item])
        return try! JSONEncoder().encode(file)
    }

    /// Stringa il cui `utf8.count` è ESATTAMENTE `totalBytes`, componendo unità grapheme-cluster a
    /// più byte ("famiglia" ZWJ, stesso trucco di `testCaptureSkipsBytewiseHugeItemWithinCharCap` in
    /// ClipboardHistoryManagerTests.swift) e completando il resto con caratteri ASCII da 1 byte: così
    /// il conteggio CARATTERI resta ben sotto il cap a 50.000, isolando il cap a BYTE come unica causa
    /// dell'esito.
    private func exactByteCountString(totalBytes: Int) -> String {
        let unit = "👨‍👩‍👧‍👦"
        let unitByteCount = unit.utf8.count
        let unitCount = totalBytes / unitByteCount
        let remainder = totalBytes - unitCount * unitByteCount
        return String(repeating: unit, count: unitCount) + String(repeating: "a", count: remainder)
    }

    /// Costruisce un envelope valido la cui dimensione su disco è ESATTAMENTE `targetBytes`, per
    /// testare il confine di `maxRawFileBytes`. Misura la dimensione con un item di riempimento
    /// vuoto, poi aggiusta il riempimento di 1 carattere ASCII per ogni byte mancante (nessun
    /// escaping JSON necessario per 'q', quindi l'aggiustamento è esatto).
    private func exactSizeEnvelope(targetBytes: Int) -> Data {
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let baselineCount = 20
        var items = (0..<baselineCount).map { i in
            ClipboardHistoryItem(content: .text("p"), createdData: base.addingTimeInterval(Double(i)))
        }
        items.append(ClipboardHistoryItem(content: .text(""), createdData: base))
        let zeroPadSize = try! JSONEncoder().encode(
            ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: items)
        ).count
        let padLength = max(0, targetBytes - zeroPadSize)
        items[items.count - 1].content = .text(String(repeating: "q", count: padLength))
        return try! JSONEncoder().encode(
            ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: items)
        )
    }

    private func makeMinimalEnvelope(itemCount: Int) -> Data {
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let items = (0..<itemCount).map { i in
            ClipboardHistoryItem(content: .text("x"), createdData: base.addingTimeInterval(Double(i)))
        }
        let file = ClipboardHistoryManager.HistoryFile(schemaVersion: ClipboardHistoryManager.currentSchemaVersion, items: items)
        return try! JSONEncoder().encode(file)
    }

    /// Deriva quanti item "minuscoli" (contenuto a 1 carattere) stanno in `targetBytes`, misurando
    /// due campioni reali invece di indovinare l'overhead esatto della codifica JSON.
    private func fittingItemCount(targetBytes: Int) -> Int {
        let n0 = 1_000
        let n1 = 2_000
        let size0 = makeMinimalEnvelope(itemCount: n0).count
        let size1 = makeMinimalEnvelope(itemCount: n1).count
        let perItem = Double(size1 - size0) / Double(n1 - n0)
        let overhead = Double(size0) - perItem * Double(n0)
        let margin = 4_096 // margine di sicurezza sotto il cap
        let count = Int((Double(targetBytes - margin) - overhead) / perItem)
        return max(0, count)
    }

    private func bomPrefixedCase() -> Data {
        let payload = singleItemEnvelope(content: "bom-test")
        var withBOM = Data([0xEF, 0xBB, 0xBF])
        withBOM.append(payload)
        return withBOM
    }

    private func invalidUTF8MidStringCase() -> Data {
        var data = singleItemEnvelope(content: "ZZZMARKERZZZ")
        guard let markerRange = data.range(of: Data("MARKER".utf8)) else {
            return data
        }
        data.insert(contentsOf: [0xFF, 0xFE], at: markerRange.upperBound)
        return data
    }

    private func legacyBareArrayValid() -> Data {
        let base = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let items = [
            ClipboardHistoryItem(content: .text("legacy-a"), createdData: base),
            ClipboardHistoryItem(content: .text("legacy-b"), createdData: base.addingTimeInterval(-5)),
        ]
        return try! JSONEncoder().encode(items)
    }

    private func legacyBareArrayWithCorruptedItem() -> Data {
        let now = Date(timeIntervalSinceReferenceDate: 700_000_000).timeIntervalSinceReferenceDate
        let json = "[\(rawItemJSON(text: "legacy-good1", createdData: now)),42,\(rawItemJSON(text: "legacy-good2", createdData: now))]"
        return Data(json.utf8)
    }

    // MARK: - campagna principale

    func testFuzzCampaign() throws {
        print("FUZZ SEED: 0x5EEDC0FFEE (\(Self.seed))")
        var rng = XorShift64Star(seed: Self.seed)
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let url = historyFileURL(in: dir)

        var histogram: [Outcome: Int] = [:]
        var maxDuration: (name: String, seconds: Double) = ("", 0)
        var outcomes: [String: Outcome] = [:]

        // MARK: corpus di casi patologici espliciti (nesting profondo escluso: vedi in fondo al metodo)
        var cases: [(name: String, data: Data)] = []
        cases.append(("empty-file", Data()))
        cases.append(("whitespace-only", Data(String(repeating: " ", count: 16).utf8)))
        cases.append(("json-null", Data("null".utf8)))
        cases.append(("json-empty-object", Data("{}".utf8)))
        cases.append(("json-empty-array", Data("[]".utf8)))
        cases.append(("schemaVersion-only-items-missing", Data(#"{"schemaVersion":1}"#.utf8)))
        cases.append(("schemaVersion-wrong-type-string", Data(#"{"schemaVersion":"1","items":[]}"#.utf8)))
        cases.append(("schemaVersion-negative", Data(#"{"schemaVersion":-1,"items":[]}"#.utf8)))
        cases.append(("schemaVersion-zero", Data(#"{"schemaVersion":0,"items":[]}"#.utf8)))
        cases.append(("schemaVersion-two", Data(#"{"schemaVersion":2,"items":[]}"#.utf8)))
        cases.append(("schemaVersion-2pow62", Data(#"{"schemaVersion":4611686018427387904,"items":[]}"#.utf8)))
        cases.append(("schemaVersion-1e999", Data(#"{"schemaVersion":1e999,"items":[]}"#.utf8)))
        cases.append(("schemaVersion-neg1e999", Data(#"{"schemaVersion":-1e999,"items":[]}"#.utf8)))
        cases.append(("items-is-object-not-array", Data(#"{"schemaVersion":1,"items":{}}"#.utf8)))
        cases.append(("item-content-unknown-case", Data(#"{"schemaVersion":1,"items":[{"content":{"unknownCase":{"_0":"x"}},"createdData":0}]}"#.utf8)))
        cases.append(("item-content-missing", Data(#"{"schemaVersion":1,"items":[{"createdData":0}]}"#.utf8)))
        cases.append(("item-content-null", Data(#"{"schemaVersion":1,"items":[{"content":null,"createdData":0}]}"#.utf8)))
        cases.append(("createdData-string", Data(#"{"schemaVersion":1,"items":[{"content":{"text":{"_0":"x"}},"createdData":"not-a-date"}]}"#.utf8)))
        cases.append(("createdData-1e999", Data(#"{"schemaVersion":1,"items":[{"content":{"text":{"_0":"x"}},"createdData":1e999}]}"#.utf8)))
        cases.append(("createdData-neg1e999", Data(#"{"schemaVersion":1,"items":[{"content":{"text":{"_0":"x"}},"createdData":-1e999}]}"#.utf8)))
        cases.append(("createdData-null", Data(#"{"schemaVersion":1,"items":[{"content":{"text":{"_0":"x"}},"createdData":null}]}"#.utf8)))
        cases.append(("pinnedDate-null", Data(#"{"schemaVersion":1,"items":[{"content":{"text":{"_0":"x"}},"createdData":0,"pinnedDate":null}]}"#.utf8)))
        cases.append(("pinnedDate-absent", Data(#"{"schemaVersion":1,"items":[{"content":{"text":{"_0":"x"}},"createdData":0}]}"#.utf8)))
        cases.append(("duplicate-keys-schemaVersion", Data(#"{"schemaVersion":1,"schemaVersion":2,"items":[]}"#.utf8)))
        cases.append(("unknown-extra-keys", Data(#"{"schemaVersion":1,"items":[],"unknownTopLevelKey":"value","another":[1,2,3]}"#.utf8)))
        cases.append(("utf8-bom-prefix", bomPrefixedCase()))
        cases.append(("invalid-utf8-mid-string", invalidUTF8MidStringCase()))
        cases.append(("legacy-bare-array-valid", legacyBareArrayValid()))
        cases.append(("legacy-bare-array-with-corrupted-item", legacyBareArrayWithCorruptedItem()))

        // Caso minimo (non un mutante casuale, costruito a mano) che dimostra che `ClipboardHistoryItem.<`
        // (righe ~18-26) NON è una strict weak ordering quando pinnati/non-pinnati sono mischiati:
        // A (non pinnato, createdData=10) < B (pinnato pinnedDate=5) è vero (regola "rhs pinnato, lhs no → true");
        // B < C (non pinnato, createdData=3) è vero (rhs non pinnato → confronto per createdData: 1 < 3);
        // ma A < C è FALSO (rhs non pinnato → confronto per createdData: 10 < 3 falso) — transitività rotta.
        // `sort(by: >)` su un comparatore non-transitivo ha comportamento non garantito da Swift.
        cases.append(("ordering-non-transitive-pinned-mix", Data(#"{"schemaVersion":1,"items":[{"content":{"text":{"_0":"A"}},"createdData":10},{"content":{"text":{"_0":"B"}},"createdData":1,"pinnedDate":5},{"content":{"text":{"_0":"C"}},"createdData":3}]}"#.utf8)))

        // Confine cap CARATTERI (50.000): isolato tenendo i byte ben sotto il cap byte.
        cases.append(("item-char-cap-exactly-50000-ascii-kept", singleItemEnvelope(content: String(repeating: "a", count: ClipboardHistoryManager.maxItemCharacterCount))))
        cases.append(("item-char-cap-50001-ascii-dropped", singleItemEnvelope(content: String(repeating: "a", count: ClipboardHistoryManager.maxItemCharacterCount + 1))))
        // 3 byte/carattere (es. 'あ'): 50.000 char = 150 KB (sotto entrambi i cap) / 100.000 char = 300 KB (oltre il cap byte).
        cases.append(("item-multibyte-3byte-50000-chars-150KB-kept", singleItemEnvelope(content: String(repeating: "\u{3042}", count: 50_000))))
        cases.append(("item-multibyte-3byte-100000-chars-300KB-dropped", singleItemEnvelope(content: String(repeating: "\u{3042}", count: 100_000))))

        // Confine cap BYTE (256*1024): isolato tenendo i caratteri ben sotto il cap caratteri.
        let exactByteContent = exactByteCountString(totalBytes: ClipboardHistoryManager.maxItemByteCount)
        XCTAssertEqual(exactByteContent.utf8.count, ClipboardHistoryManager.maxItemByteCount, "fixture al confine byte non calibrata")
        XCTAssertLessThanOrEqual(exactByteContent.count, ClipboardHistoryManager.maxItemCharacterCount, "la fixture al confine byte deve restare sotto il cap caratteri per isolare la causa")
        cases.append(("item-byte-cap-exactly-256KiB-kept", singleItemEnvelope(content: exactByteContent)))
        let overByteContent = exactByteCountString(totalBytes: ClipboardHistoryManager.maxItemByteCount + 1)
        XCTAssertEqual(overByteContent.utf8.count, ClipboardHistoryManager.maxItemByteCount + 1, "fixture al confine byte+1 non calibrata")
        cases.append(("item-byte-cap-256KiB-plus-1-dropped", singleItemEnvelope(content: overByteContent)))

        // Confine cap FILE GREZZO (maxRawFileBytes = 4 MiB).
        let exact4MiB = exactSizeEnvelope(targetBytes: ClipboardHistoryManager.maxRawFileBytes)
        XCTAssertEqual(exact4MiB.count, ClipboardHistoryManager.maxRawFileBytes, "fixture 4 MiB esatta non calibrata")
        cases.append(("raw-file-exactly-4MiB", exact4MiB))
        let over4MiB = exactSizeEnvelope(targetBytes: ClipboardHistoryManager.maxRawFileBytes + 1)
        XCTAssertEqual(over4MiB.count, ClipboardHistoryManager.maxRawFileBytes + 1, "fixture 4 MiB+1 non calibrata")
        cases.append(("raw-file-4MiB-plus-1", over4MiB))

        // Array con molti item minuscoli, sotto il cap file: 200.000 item minimi (~46 byte/item) non
        // ci stanno in 4 MiB (≈9.2 MB stimati) — riduco al conteggio che effettivamente ci sta.
        let requestedLargeArrayCount = 200_000
        let fittingLargeArrayCount = fittingItemCount(targetBytes: ClipboardHistoryManager.maxRawFileBytes)
        if fittingLargeArrayCount < requestedLargeArrayCount {
            print("FUZZ DEVIATION: large-array case ridotto da \(requestedLargeArrayCount) a \(fittingLargeArrayCount) item per rispettare maxRawFileBytes (\(ClipboardHistoryManager.maxRawFileBytes) byte)")
        }
        let largeArrayData = makeMinimalEnvelope(itemCount: fittingLargeArrayCount)
        XCTAssertLessThanOrEqual(largeArrayData.count, ClipboardHistoryManager.maxRawFileBytes, "large-array fixture supera maxRawFileBytes")
        cases.append(("large-array-\(fittingLargeArrayCount)-tiny-items", largeArrayData))

        for (name, data) in cases {
            let outcome = loadAndCheck(data, name: name, url: url, config: config, histogram: &histogram, maxDuration: &maxDuration)
            outcomes[name] = outcome
        }

        // Verifiche esplicite "deve restare" / "deve cadere" sui confini, oltre alle proprietà generiche P1-P5.
        XCTAssertEqual(outcomes["item-char-cap-exactly-50000-ascii-kept"], .items(1), "50.000 caratteri ASCII: al confine, deve restare")
        XCTAssertEqual(outcomes["item-char-cap-50001-ascii-dropped"], .items(0), "50.001 caratteri ASCII: oltre il cap caratteri, deve cadere")
        XCTAssertEqual(outcomes["item-multibyte-3byte-50000-chars-150KB-kept"], .items(1), "50.000 caratteri multibyte (150 KB): sotto entrambi i cap, deve restare")
        XCTAssertEqual(outcomes["item-multibyte-3byte-100000-chars-300KB-dropped"], .items(0), "100.000 caratteri multibyte (300 KB): oltre il cap byte, deve cadere")
        XCTAssertEqual(outcomes["item-byte-cap-exactly-256KiB-kept"], .items(1), "256*1024 byte esatti: al confine, deve restare")
        XCTAssertEqual(outcomes["item-byte-cap-256KiB-plus-1-dropped"], .items(0), "256*1024+1 byte: oltre il cap byte, deve cadere")
        XCTAssertEqual(outcomes["raw-file-4MiB-plus-1"], .items(0), "file oltre maxRawFileBytes: guardia anti-tamper, ritorna [] senza decodificare")
        XCTAssertEqual(outcomes["raw-file-exactly-4MiB"], .items(20), "file esattamente a maxRawFileBytes: la guardia non scatta, i 20 item baseline sopravvivono (il filler enorme viene scartato dal cap per-item)")
        XCTAssertEqual(outcomes["legacy-bare-array-valid"], .items(2), "array legacy nudo valido: entrambi gli item devono sopravvivere")
        XCTAssertEqual(outcomes["legacy-bare-array-with-corrupted-item"], .items(2), "array legacy con un item corrotto: l'item corrotto decade, i 2 validi restano")

        // MARK: fuzz casuale — 1.500 mutanti dell'envelope valido
        let baseValid = makeValidEnvelope(itemCount: 6, rng: &rng)
        let mutantCount = 1_500
        for i in 0..<mutantCount {
            let mutant = mutate(baseValid, rng: &rng)
            loadAndCheck(mutant, name: "mutant-\(i)", url: url, config: config, histogram: &histogram, maxDuration: &maxDuration)
        }

        printHistogram(histogram, maxDuration: maxDuration, label: "pre deep-nesting")

        // MARK: nesting profondo — per ultimo e deliberatamente isolato: se il parser sottostante
        // crasha lo stack qui, tutto il resto della campagna è già stato eseguito e stampato sopra.
        let nestedArrays = Data((String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)).utf8)
        loadAndCheck(nestedArrays, name: "deep-nesting-array-open-close-5000", url: url, config: config, histogram: &histogram, maxDuration: &maxDuration)
        let nestedObjectKeys = Data(String(repeating: "{\"a\":", count: 5_000).utf8)
        loadAndCheck(nestedObjectKeys, name: "deep-nesting-object-key-5000-unterminated", url: url, config: config, histogram: &histogram, maxDuration: &maxDuration)

        printHistogram(histogram, maxDuration: maxDuration, label: "finale")
    }

    // MARK: - percorso pubblico: reload() non deve mai lanciare né crashare

    @MainActor
    func testReloadNeverThrowsOnPathologicalInputs() throws {
        let dir = makeTempSaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = MockClipboardHistoryManagerConfiguration(saveDirectory: dir)
        let url = historyFileURL(in: dir)

        let selected: [(name: String, data: Data)] = [
            ("reload-deep-nesting-array-5000", Data((String(repeating: "[", count: 5_000) + String(repeating: "]", count: 5_000)).utf8)),
            ("reload-schemaVersion-1e999", Data(#"{"schemaVersion":1e999,"items":[]}"#.utf8)),
            ("reload-items-object-not-array", Data(#"{"schemaVersion":1,"items":{}}"#.utf8)),
            ("reload-invalid-utf8-mid-string", invalidUTF8MidStringCase()),
            ("reload-raw-file-4MiB-plus-1", exactSizeEnvelope(targetBytes: ClipboardHistoryManager.maxRawFileBytes + 1)),
        ]

        for (name, data) in selected {
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url)
            print("FUZZ_CASE (reload):", name)
            var manager = ClipboardHistoryManager(config: config, clipboardSource: FakeClipboardSource(hasStrings: false, string: nil))
            manager.reload()
            for item in manager.items {
                if case .text(let s) = item.content {
                    XCTAssertLessThanOrEqual(s.count, ClipboardHistoryManager.maxItemCharacterCount, "\(name): item oltre il cap caratteri sopravvissuto a reload()")
                    XCTAssertLessThanOrEqual(s.utf8.count, ClipboardHistoryManager.maxItemByteCount, "\(name): item oltre il cap byte sopravvissuto a reload()")
                }
            }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
