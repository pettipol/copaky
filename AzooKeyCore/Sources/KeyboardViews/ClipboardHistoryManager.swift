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
public protocol ClipboardSource {
    @MainActor var changeCount: Int { get }
    @MainActor var hasStrings: Bool { get }
    @MainActor var string: String? { get }
}

/// Implementazione di produzione: legge la `UIPasteboard.general` reale.
public struct SystemClipboardSource: ClipboardSource {
    public init() {}
    @MainActor public var changeCount: Int { UIPasteboard.general.changeCount }
    @MainActor public var hasStrings: Bool { UIPasteboard.general.hasStrings }
    @MainActor public var string: String? { UIPasteboard.general.string }
}

public struct ClipboardHistoryManager {

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

    @MainActor private var enabled: Bool {
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
        guard self.enabled else {
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
        guard self.enabled else {
            self.hasPendingClipboard = false
            return
        }
        let currentCount = self.clipboardSource.changeCount
        // Solo metadati: c'è nuovo contenuto stringa non ancora acquisito? (nessuna lettura del valore)
        self.hasPendingClipboard = (currentCount != self.previousChangedCount) && self.clipboardSource.hasStrings
        self.pruneExpired(now: now)
    }

    /// CAPTURE — UNICO punto in cui si legge il valore degli appunti (`UIPasteboard.general.string`).
    /// Da invocare SOLO in risposta a un'azione esplicita dell'utente (intento). Saltata nei campi
    /// sicuri (`isSecureEntry`) e per stringhe oltre `maxItemCharacterCount`.
    @MainActor public mutating func captureCurrentClipboard(isSecureEntry: Bool, now: Date = Date()) {
        guard self.enabled, !isSecureEntry else {
            return
        }
        let currentCount = self.clipboardSource.changeCount
        guard self.clipboardSource.hasStrings, let string = self.clipboardSource.string else {
            self.previousChangedCount = currentCount
            self.hasPendingClipboard = false
            return
        }
        // Cap dimensione del singolo elemento (caratteri E byte): non memorizzare blob enormi né
        // "bomb" ZWJ/combining nel container condiviso.
        guard string.count <= Self.maxItemCharacterCount, string.utf8.count <= Self.maxItemByteCount else {
            self.previousChangedCount = currentCount
            self.hasPendingClipboard = false
            return
        }
        self.previousChangedCount = currentCount
        self.insert(text: string, now: now)
    }

    /// Copaky — capture of text HANDED to us by the system (`UIPasteControl`). It never reads the
    /// pasteboard VALUE — it only advances our copy of `changeCount`, which is metadata: iOS treats the
    /// tap on its own paste button as the user's intent and delivers the string directly, so no
    /// "pasted from…" banner appears. Same guards and same caps as `captureCurrentClipboard`; the only
    /// difference is where the string comes from.
    /// Copaky — システムのペーストボタン経由で渡されたテキストの取り込み。
    /// UIPasteboard を読まないためバナーが出ない。ガードと上限は通常の取り込みと同一。
    @MainActor public mutating func captureProvidedText(_ string: String, isSecureEntry: Bool, now: Date = Date()) {
        guard self.enabled, !isSecureEntry else {
            return
        }
        guard string.count <= Self.maxItemCharacterCount, string.utf8.count <= Self.maxItemByteCount else {
            self.hasPendingClipboard = false
            return
        }
        // The system handed us this text, so whatever is on the pasteboard is now accounted for.
        self.previousChangedCount = self.clipboardSource.changeCount
        self.insert(text: string, now: now)
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
