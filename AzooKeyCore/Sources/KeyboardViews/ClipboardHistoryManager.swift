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

    static func < (lhs: ClipboardHistoryItem, rhs: ClipboardHistoryItem) -> Bool {
        if let rPinnedDate = rhs.pinnedDate {
            if let lPinnedDate = lhs.pinnedDate {
                return lPinnedDate < rPinnedDate
            }
            return true
        }
        return lhs.createdData < rhs.createdData
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
        // Cap dimensione del singolo elemento: non memorizzare blob enormi nel container condiviso.
        guard string.count <= Self.maxItemCharacterCount else {
            self.previousChangedCount = currentCount
            self.hasPendingClipboard = false
            return
        }
        self.previousChangedCount = currentCount

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
        let items = try JSONDecoder().decode([ClipboardHistoryItem].self, from: encoded)
        return items
    }

    enum IOError: Error {
        /// フルアクセスが存在しない
        case lackFullAccess
        /// 共有ディレクトリにアクセスできない
        case sharedDirectoryInaccessible
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
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(items)

        try encoded.write(to: historyFileURL)
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
