//
//  ClipboardHistoryManager.swift
//  azooKey
//
//  Created by ensan on 2023/02/26.
//  Copyright © 2023 ensan. All rights reserved.
//

import class UIKit.UIPasteboard
import Foundation
import SwiftUtils
import UniformTypeIdentifiers
#if DEBUG
import os

private let clipboardProbeLog = OSLog(
    subsystem: "com.pettipol.copaky.keyboard",
    category: "ClipboardProbe"
)
#endif

struct ClipboardHistoryItem: Equatable, Comparable, Hashable, Codable, Identifiable {
    var content: Content
    var createdData: Date
    var pinnedDate: Date?

    /// Pinned items sort above unpinned ones; within each group, by date. This must be a strict weak
    /// ordering: the previous version compared a PINNED lhs against an UNPINNED rhs by creation date,
    /// so `a < b` and `b < a` could both be true and `sort(by: >)` produced an order that depended on
    /// the algorithm's comparison sequence (found by the fuzz/property test P4, 2026-08-15).
    /// ピン留めは常に上、同じ群の中では日付順。以前は「ピン留め lhs 対 未ピン rhs」を作成日で比べていたため
    /// 厳密弱順序が壊れ、並び順がアルゴリズム依存になっていた（fuzz テスト P4 で検出）。
    static func < (lhs: ClipboardHistoryItem, rhs: ClipboardHistoryItem) -> Bool {
        switch (lhs.pinnedDate, rhs.pinnedDate) {
        case let (lPinned?, rPinned?):
            return lPinned < rPinned
        case (nil, .some):
            return true
        case (.some, nil):
            return false
        case (nil, nil):
            return lhs.createdData < rhs.createdData
        }
    }

    var id: Int {
        self.createdData.hashValue
    }
    enum Content: Hashable, Codable {
        case text(String)
    }
}

/// Sorgente appunti di sistema, astratta per (a) isolare l'UNICO punto di lettura della pasteboard
/// e (b) rendere i test deterministici: la `UIPasteboard.general` reale, in un contesto di test
/// headless su Simulatore iOS 16+, può bloccarsi sul servizio `com.apple.pasteboard.pasted` in attesa
/// del permesso di incolla. I test iniettano una sorgente fittizia.
public enum ClipboardTextReadResult: Sendable {
    case text(String)
    case unavailable
    case rejectedOversized
}

public protocol ClipboardSource {
    @MainActor var changeCount: Int { get }
    @MainActor var hasStrings: Bool { get }
    @MainActor var string: String? { get }
    @MainActor func readText(maxUTF8ByteCount: Int) -> ClipboardTextReadResult
}

public extension ClipboardSource {
    /// Default/test path: read the value once. The manager keeps final authority over both caps.
    /// 既定・テスト経路：値を一度だけ読む。最終的な上限判定は manager が行う。
    @MainActor func readText(maxUTF8ByteCount _: Int) -> ClipboardTextReadResult {
        guard let string = self.string else {
            return .unavailable
        }
        return .text(string)
    }
}

/// Implementazione di produzione: legge la `UIPasteboard.general` reale.
public struct SystemClipboardSource: ClipboardSource {
    private static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    public init() {}
    @MainActor public var changeCount: Int { UIPasteboard.general.changeCount }
    @MainActor public var hasStrings: Bool { UIPasteboard.general.hasStrings }
    @MainActor public var string: String? { UIPasteboard.general.string }

    @MainActor public func readText(maxUTF8ByteCount: Int) -> ClipboardTextReadResult {
        let pasteboard = UIPasteboard.general
        let utf8Type = UTType.utf8PlainText.identifier
        if pasteboard.types.contains(utf8Type) {
            // UIPasteboard has no size-only query. Read the raw representation ONCE, reject by its
            // O(1) byte count, and only then decode a String (which would be a second allocation).
            // size-only API はないため raw Data を一度だけ読み、count 後にだけ String 化する。
            guard let data = pasteboard.data(forPasteboardType: utf8Type) else {
                return .unavailable
            }
            guard !Self.exceedsDecodedUTF8ByteLimit(data, maxByteCount: maxUTF8ByteCount) else {
                return .rejectedOversized
            }
            guard let string = String(data: data, encoding: .utf8) else {
                return .unavailable
            }
            return .text(string)
        }

        // Preserve support for other text representations. This is still exactly one value read;
        // the bounded UTF-8 walk happens before grapheme counting or any history mutation.
        // UTF-8 以外の表現も維持する。値の読み取りは一度だけで、その後 bounded guard を行う。
        guard let string = self.string else {
            return .unavailable
        }
        return .text(string)
    }

    /// `String(data:encoding:.utf8)` consumes one leading UTF-8 BOM. Mirror that O(1) adjustment so
    /// a decoded payload exactly at the cap remains accepted without allocating the String first.
    /// UTF-8 BOM は String 化で除かれるため、割り当て前の判定でも先頭の3 byte を除外する。
    static func exceedsDecodedUTF8ByteLimit(_ data: Data, maxByteCount: Int) -> Bool {
        let bomByteCount = data.starts(with: Self.utf8ByteOrderMark) ? Self.utf8ByteOrderMark.count : 0
        return data.count - bomByteCount > maxByteCount
    }
}

public struct ClipboardHistoryManager {

    public enum CaptureResult: Equatable, Sendable {
        case captured
        case rejected
        case rejectedOversized
    }

    var items: [ClipboardHistoryItem] = []
    var config: any ClipboardHistoryManagerConfiguration
    private var collapsed = false
    private var previousChangedCount = 0
    /// Sorgente appunti (iniettabile per i test). In produzione è `SystemClipboardSource`.
    private var clipboardSource: any ClipboardSource
    /// true se sugli appunti c'è nuovo contenuto testuale non ancora aggiunto alla cronologia.
    /// Calcolato SOLO dai metadati (`changeCount` + `hasStrings`): non legge mai il valore, quindi
    /// non innesca il banner di sistema "incollato da…". Usato dalla UI per l'affordance di cattura.
    public internal(set) var hasPendingClipboard = false

    /// Lunghezza massima (in caratteri) di un singolo elemento, per non saturare il container condiviso.
    static let maxItemCharacterCount = 50_000
    /// Cap in byte UTF-8 del singolo elemento: difende dai "bomb" ZWJ/combining (pochi grapheme
    /// cluster ma molti scalari/byte), che il solo cap a caratteri non fermerebbe.
    static let maxItemByteCount = 256 * 1024
    /// Tetto sui byte grezzi del file di cronologia: non deserializzare blob enormi (anti-tamper)
    /// nella memoria stretta dell'estensione tastiera.
    static let maxRawFileBytes = 4 * 1024 * 1024
    /// Versione corrente dello schema di clipboard_history.json. / Current schema version of clipboard_history.json.
    static let currentSchemaVersion = 1

    /// Reads the live setting through the injected configuration; key models use this at gesture time.
    @MainActor var isEnabled: Bool {
        config.enabled
    }

    init(config: any ClipboardHistoryManagerConfiguration, clipboardSource: any ClipboardSource = SystemClipboardSource()) {
        self.config = config
        self.clipboardSource = clipboardSource
        // TODO: メモリ対策をやる必要がある。
        do {
            self.items = try Self.load(config: config)
            self.collapsed = false
        } catch {
            debug("ClipboardHistoryManager.init: load failed", error)
            self.items = []
            self.collapsed = true
        }
        self.sort()
    }

    public mutating func reload() {
        do {
            let newItems = try Self.load(config: config)
            self.items = newItems
            self.collapsed = false
        } catch {
            debug("ClipboardHistoryManager.reload: load failed", error)
            self.collapsed = true
        }
    }

    @MainActor func save() {
        // 読み込みに失敗している場合は上書きを行わない
        guard !self.collapsed else {
            return
        }
        // 有効化されていなければ上書きしない
        guard self.isEnabled else {
            return
        }
        do {
            try Self.save(self.items, config: config)
        } catch {
            debug("ClipboardHistoryManager.init: save failed", error)
        }
    }

    private mutating func sort() {
        self.items.sort(by: >)
    }

    /// DETECT — fase automatica, eseguita a ogni apparizione/aggiornamento della tastiera.
    /// Usa SOLO metadati (`changeCount`, `hasStrings`): **non legge mai il valore degli appunti**,
    /// quindi non mostra il banner di sistema. Aggiorna `hasPendingClipboard` per l'affordance UI
    /// ed esegue la pulizia temporale. La cattura del valore avviene solo in `captureCurrentClipboard`,
    /// su intento esplicito dell'utente.
    @MainActor public mutating func detectClipboardChange(now: Date = Date()) {
        #if DEBUG
        let b02ProbeEnabled = ProcessInfo.processInfo.environment["COPAKY_B02_PROBE"] == "1"
        if b02ProbeEnabled {
            // Copaky [B-02]: measure whether metadata is readable without Full Access; never log content.
            // Copaky [B-02]: フルアクセスなしでメタデータを読めるか測定し、内容は絶対に記録しない。
            let pasteboard = UIPasteboard.general
            os_log(
                .info,
                log: clipboardProbeLog,
                "B-02 metadata changeCount=%{public}ld hasStrings=%{public}d",
                pasteboard.changeCount,
                pasteboard.hasStrings ? 1 : 0
            )
            guard self.isEnabled else {
                self.hasPendingClipboard = false
                return
            }
        }
        #endif
        guard self.isEnabled else {
            self.hasPendingClipboard = false
            return
        }
        let currentCount = self.clipboardSource.changeCount
        // Solo metadati: c'è nuovo contenuto stringa non ancora acquisito? (nessuna lettura del valore)
        self.hasPendingClipboard = (currentCount != self.previousChangedCount) && self.clipboardSource.hasStrings
        self.pruneExpired(now: now)
    }

    /// CAPTURE — UNICO punto in cui si legge il valore degli appunti (raw UTF-8 quando disponibile,
    /// fallback `UIPasteboard.general.string` per le altre rappresentazioni).
    /// Da invocare SOLO in risposta a un'azione esplicita dell'utente (intento). Saltata nei campi
    /// sicuri (`isSecureEntry`) e per stringhe oltre i cap di caratteri o byte.
    @discardableResult
    @MainActor public mutating func captureCurrentClipboard(isSecureEntry: Bool, now: Date = Date()) -> CaptureResult {
        guard self.isEnabled, !isSecureEntry else {
            return .rejected
        }
        let currentCount = self.clipboardSource.changeCount
        guard self.clipboardSource.hasStrings else {
            self.previousChangedCount = currentCount
            self.hasPendingClipboard = false
            return .rejected
        }

        // La sorgente legge una volta sola. Quella di sistema usa raw Data quando è UTF-8 e controlla
        // `count` prima di creare String; i fallback fanno una scansione bounded. Sul rifiuto nessun
        // payload esce dall'autorelease pool e non parte altro lavoro.
        // source は一度だけ読み、UTF-8 は String 化前に Data.count、fallback は bounded scan。
        // 拒否 payload は autorelease pool の外へ出さず、後続処理を行わない。
        let readResult: ClipboardTextReadResult = autoreleasepool {
            let result = self.clipboardSource.readText(maxUTF8ByteCount: Self.maxItemByteCount)
            guard case .text(let string) = result else {
                return result
            }
            // The manager remains the invariant owner even for custom/public ClipboardSource
            // implementations: never trust an override to have enforced the requested byte cap.
            guard !Self.exceedsItemByteLimit(string), !Self.exceedsItemCharacterLimit(string) else {
                return .rejectedOversized
            }
            return .text(string)
        }
        self.previousChangedCount = currentCount
        self.hasPendingClipboard = false
        switch readResult {
        case .text(let string):
            self.insert(text: string, now: now)
            return .captured
        case .unavailable:
            return .rejected
        case .rejectedOversized:
            return .rejectedOversized
        }
    }

    /// Copaky — capture of text HANDED to us by the system (`UIPasteControl`). It never reads the
    /// pasteboard VALUE — it only advances our copy of `changeCount`, which is metadata: iOS treats the
    /// tap on its own paste button as the user's intent and delivers the string directly, so no
    /// "pasted from…" banner appears. Same guards and same caps as `captureCurrentClipboard`; the only
    /// difference is where the string comes from.
    /// Copaky — システムのペーストボタン経由で渡されたテキストの取り込み。
    /// UIPasteboard を読まないためバナーが出ない。ガードと上限は通常の取り込みと同一。
    @discardableResult
    @MainActor public mutating func captureProvidedText(_ string: String, isSecureEntry: Bool, now: Date = Date()) -> CaptureResult {
        guard self.isEnabled, !isSecureEntry else {
            return .rejected
        }
        // Il testo è già stato consegnato dal sistema: nessuna copia, byte-first e lavoro limitato.
        // システムから受け取った String はコピーせず、byte-first で上限までだけ走査する。
        guard !Self.exceedsItemByteLimit(string), !Self.exceedsItemCharacterLimit(string) else {
            self.previousChangedCount = self.clipboardSource.changeCount
            self.hasPendingClipboard = false
            return .rejectedOversized
        }
        // The system handed us this text, so whatever is on the pasteboard is now accounted for.
        self.previousChangedCount = self.clipboardSource.changeCount
        self.insert(text: string, now: now)
        return .captured
    }

    /// Bounded byte preflight: unlike `utf8.count`, it never walks beyond cap+1 bytes.
    /// `utf8.count` と異なり、上限+1 byte より先は走査しない。
    private static func exceedsItemByteLimit(_ string: String) -> Bool {
        !string.utf8.dropFirst(Self.maxItemByteCount).isEmpty
    }

    /// Bounded grapheme preflight, evaluated only after the byte cap passes.
    /// byte 上限を通過した場合だけ、書記素を上限+1 まで確認する。
    private static func exceedsItemCharacterLimit(_ string: String) -> Bool {
        !string.dropFirst(Self.maxItemCharacterCount).isEmpty
    }

    /// Account for an oversized value rejected by a source before it could hand us a String
    /// (`UIPasteControl` raw-Data path). Metadata only: never reads or saves the clipboard value.
    /// String 化前に source が拒否した値を処理済みにする。metadata のみで、値の読み取り・保存はしない。
    @MainActor mutating func markCurrentClipboardRejectedOversized() {
        self.previousChangedCount = self.clipboardSource.changeCount
        self.hasPendingClipboard = false
    }

    /// Shared tail of both capture paths: dedupe, keep pins, order, prune, cap the list.
    @MainActor private mutating func insert(text string: String, now: Date) {
        var item = ClipboardHistoryItem(content: .text(string), createdData: now)
        if let index = self.items.firstIndex(where: { item.content == $0.content }) {
            let oldItem = self.items.remove(at: index)
            if oldItem.pinnedDate != nil {
                item.pinnedDate = now
            }
        }
        if self.items.isEmpty {
            self.items.append(item)
        } else if let index = self.items.firstIndex(where: { item > $0 }) {
            self.items.insert(item, at: index)
        } else {
            self.items.append(item)
        }

        self.pruneExpired(now: now)
        // 増えすぎないように削除する
        while self.items.count > config.maxCount {
            self.items.removeLast()
        }
        self.hasPendingClipboard = false
    }

    /// Pulizia temporale: gli elementi non pinnati scadono dopo 7 giorni (privacy).
    /// Il clock è iniettabile (`now`) per rendere i test deterministici.
    @MainActor mutating func pruneExpired(now: Date = Date()) {
        let expirationLimit = now.addingTimeInterval(-7 * 24 * 60 * 60)
        self.items.removeAll { item in
            item.pinnedDate == nil && item.createdData < expirationLimit
        }
    }

    private static func historyFileURL(config: any ClipboardHistoryManagerConfiguration) -> URL? {
        config.saveDirectory?.appendingPathComponent("clipboard_history.json", isDirectory: false)
    }

    /// Envelope versionato (formato v1+): {"schemaVersion": 1, "items": [...]}.
    struct HistoryFile: Codable {
        var schemaVersion: Int
        var items: [ClipboardHistoryItem]
    }

    /// Un item corrotto decade a nil invece di far fallire l'intero array. / A corrupted item decays to nil instead of failing the whole array.
    private struct FailableItem: Decodable {
        let item: ClipboardHistoryItem?
        init(from decoder: Decoder) throws { self.item = try? ClipboardHistoryItem(from: decoder) }
    }

    private struct TolerantHistoryFile: Decodable {
        var schemaVersion: Int
        var items: [FailableItem]
    }

    static func load(config: any ClipboardHistoryManagerConfiguration) throws -> [ClipboardHistoryItem] {
        guard let historyFileURL = historyFileURL(config: config) else {
            throw IOError.sharedDirectoryInaccessible
        }
        let encoded: Data
        do {
            encoded = try Data(contentsOf: historyFileURL)
        } catch let error as NSError {
            // "No such file or directory"
            if error.code != 260 {
                throw error
            }
            return []
        }
        // Guardia anti-tamper: un file manomesso/gonfiato non deve essere deserializzato per intero
        // nella memoria stretta dell'estensione.
        guard encoded.count <= Self.maxRawFileBytes else {
            debug("ClipboardHistoryManager.load: history file oversized, ignoring", encoded.count)
            return []
        }
        let decoder = JSONDecoder()
        var items: [ClipboardHistoryItem]
        if let envelope = try? decoder.decode(TolerantHistoryFile.self, from: encoded) {
            guard envelope.schemaVersion <= Self.currentSchemaVersion else {
                // File di un build più nuovo: non leggerlo e non sovrascriverlo (collapsed → save no-op).
                throw IOError.unsupportedSchemaVersion(envelope.schemaVersion)
            }
            let decoded = envelope.items.compactMap(\.item)
            if decoded.count != envelope.items.count {
                debug("ClipboardHistoryManager.load: dropped corrupted item(s)", envelope.items.count - decoded.count)
            }
            items = decoded
        } else if let legacy = try? decoder.decode([FailableItem].self, from: encoded) {
            // Formato legacy pre-versioning (array nudo): decode item-by-item tolerant.
            let decoded = legacy.compactMap(\.item)
            if decoded.count != legacy.count {
                debug("ClipboardHistoryManager.load: dropped corrupted legacy item(s)", legacy.count - decoded.count)
            }
            items = decoded
        } else {
            throw IOError.malformedHistoryFile
        }
        // I cap sono invarianti veri, indipendenti da come è stato prodotto il file: scarta gli item
        // sovradimensionati e applica `maxCount` anche in lettura (non solo in cattura).
        items.removeAll { item in
            switch item.content {
            case .text(let s):
                return s.count > Self.maxItemCharacterCount || s.utf8.count > Self.maxItemByteCount
            }
        }
        items.sort(by: >)
        if items.count > config.maxCount {
            items = Array(items.prefix(config.maxCount))
        }
        return items
    }

    enum IOError: Error {
        /// フルアクセスが存在しない
        case lackFullAccess
        /// 共有ディレクトリにアクセスできない
        case sharedDirectoryInaccessible
        /// ファイルのスキーマバージョンが現在のビルドより新しい / File's schema version is newer than the current build
        case unsupportedSchemaVersion(Int)
        /// ファイルの形式が不正で読み込めない / File format is malformed and cannot be read
        case malformedHistoryFile
    }

    @MainActor static func save(_ items: [ClipboardHistoryItem], config: any ClipboardHistoryManagerConfiguration) throws {
        // jsonファイルとして共有空間に保存する
        // FullAccessがない場合は不可能なので`fail`にする
        guard SemiStaticStates.shared.hasFullAccess else {
            throw IOError.lackFullAccess
        }
        guard let historyFileURL = historyFileURL(config: config) else {
            throw IOError.sharedDirectoryInaccessible
        }
        let encoded = try JSONEncoder().encode(HistoryFile(schemaVersion: Self.currentSchemaVersion, items: items))
        try encoded.write(to: historyFileURL, options: .atomic)
    }
}

#if DEBUG
extension ClipboardHistoryItem.Content: CustomDebugStringConvertible {
    var debugDescription: String {
        switch self {
        case .text(let string): return string
        }
    }
}
#endif

public protocol ClipboardHistoryManagerConfiguration {
    @MainActor var enabled: Bool { get }
    var saveDirectory: URL? { get }
    var maxCount: Int { get }
}
