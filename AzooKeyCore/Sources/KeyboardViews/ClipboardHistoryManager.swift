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
        /// Copaky [G-38]: the entry cannot be persisted next to the pinned ones (raw-file budget saturated).
        case rejectedHistoryFull
        /// Copaky [G-38]: the history file could not be read (oversized/locked/corrupt): nothing is captured.
        case rejectedHistoryUnavailable
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
    /// Copaky [G-38]: raw-file cap of the history. It stays SMALL on purpose: the keyboard extension
    /// decodes and re-encodes this file inside a 50 MB memory ceiling (AGENTS §4). Coherence with
    /// `maxCount × maxItemByteCount` (12.8 MiB) is guaranteed by prune-on-save (`save(_:config:)`),
    /// never by a larger cap; an oversized file collapses the load instead of being overwritten.
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

    /// Returns false when nothing could be persisted (collapsed, disabled, write or backup-exclusion
    /// failure): the capture flow surfaces it instead of pretending the entry is safe on disk.
    @MainActor @discardableResult mutating func save() -> Bool {
        // 読み込みに失敗している場合は上書きを行わない
        guard !self.collapsed else {
            return false
        }
        // 有効化されていなければ上書きしない
        guard self.isEnabled else {
            return false
        }
        do {
            // Copaky [G-38]: nil means nothing was written (pinned data alone exceeds the raw budget, the
            // existing file is preserved) — report it, do not pretend the history is safe on disk.
            guard let persistedItems = try Self.save(self.items, config: config) else {
                return false
            }
            // Copaky [G-38]: keep memory aligned with the exact pruned state written to disk.
            self.items = persistedItems
            return true
        } catch {
            debug("ClipboardHistoryManager.init: save failed", error)
            return false
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
        // Copaky [G-38]: a collapsed manager never persists — do not report a capture that would be volatile.
        guard !self.collapsed else {
            return .rejectedHistoryUnavailable
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
            return self.insert(text: string, now: now) ? .captured : .rejectedHistoryFull
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
        guard !self.collapsed else {
            return .rejectedHistoryUnavailable
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
        return self.insert(text: string, now: now) ? .captured : .rejectedHistoryFull
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
    /// Copaky [G-38/G-39]: fully TRANSACTIONAL — every step runs on a copy and `self.items` changes only
    /// when the new entry survives count AND byte policy; otherwise nothing pre-existing is touched and
    /// the caller must NOT report `.captured`.
    /// Copaky: 取り込みはコピー上で判定し、新規項目が生き残る場合だけ確定する（既存項目を巻き添えにしない）。
    @MainActor private mutating func insert(text string: String, now: Date) -> Bool {
        self.hasPendingClipboard = false
        var item = ClipboardHistoryItem(content: .text(string), createdData: now)
        var candidate = self.items
        Self.removeExpired(from: &candidate, now: now)
        if let index = candidate.firstIndex(where: { item.content == $0.content }) {
            let oldItem = candidate.remove(at: index)
            if oldItem.pinnedDate != nil {
                item.pinnedDate = now
            }
        }
        candidate.append(item)
        // Normalize the order BEFORE any policy: an «unpin all» from the tab concatenates groups without
        // re-sorting, and the count policy keeps the first unpinned entries it meets.
        candidate.sort(by: >)
        Self.applyCountPolicy(to: &candidate, maxCount: config.maxCount, protecting: item)
        guard Self.pruneToRawFileBudget(&candidate, protecting: item),
              candidate.contains(where: { $0.content == item.content }) else {
            return false
        }
        self.items = candidate
        return true
    }

    /// Pulizia temporale: gli elementi non pinnati scadono dopo 7 giorni (privacy).
    /// Il clock è iniettabile (`now`) per rendere i test deterministici.
    @MainActor mutating func pruneExpired(now: Date = Date()) {
        Self.removeExpired(from: &self.items, now: now)
    }

    /// Retention window (7 days) for unpinned entries — shared by the manager and the transactional insert.
    static func removeExpired(from items: inout [ClipboardHistoryItem], now: Date) {
        let expirationLimit = now.addingTimeInterval(-7 * 24 * 60 * 60)
        items.removeAll { item in
            item.pinnedDate == nil && item.createdData < expirationLimit
        }
    }

    private static func historyFileURL(config: any ClipboardHistoryManagerConfiguration) -> URL? {
        config.saveDirectory?.appendingPathComponent("clipboard_history.json", isDirectory: false)
    }

    // MARK: - Copaky [G-38/G-39]: ONE capacity policy for insert(), load() and save()

    /// Unpinned entries keep at least one slot, so a fresh capture always survives next to `maxCount` pins.
    static func unpinnedBudget(pinnedCount: Int, maxCount: Int) -> Int {
        max(1, maxCount - pinnedCount)
    }

    /// Keeps every pinned item and only the newest unpinned ones within the budget (`items` sorted by `>`).
    /// `protected` (the entry being captured) always keeps its slot, even when its date sorts it last
    /// (clock moved backwards): it consumes one unit of the unpinned budget first.
    static func applyCountPolicy(to items: inout [ClipboardHistoryItem], maxCount: Int, protecting protected: ClipboardHistoryItem? = nil) {
        let pinnedCount = items.filter { $0.pinnedDate != nil }.count
        var budget = unpinnedBudget(pinnedCount: pinnedCount, maxCount: maxCount)
        let isProtected: (ClipboardHistoryItem) -> Bool = { item in
            guard let protected, protected.pinnedDate == nil else { return false }
            return item.pinnedDate == nil && item.content == protected.content
        }
        if items.contains(where: isProtected) {
            budget -= 1
        }
        var seenUnpinned = 0
        items.removeAll { item in
            guard item.pinnedDate == nil, !isProtected(item) else { return false }
            seenUnpinned += 1
            return seenUnpinned > budget
        }
    }

    static func encodedByteCount(_ items: [ClipboardHistoryItem]) -> Int? {
        try? JSONEncoder().encode(HistoryFile(schemaVersion: currentSchemaVersion, items: items)).count
    }

    /// Rough per-entry cost in the encoded envelope (UTF-8 text + keys/dates); used to size prune batches.
    static func estimatedEncodedBytes(_ item: ClipboardHistoryItem) -> Int {
        switch item.content {
        case .text(let string):
            return string.utf8.count + 96
        }
    }

    /// Prunes the oldest unpinned entries (never `protected`) until the envelope fits `maxRawFileBytes`.
    /// Linear, not quadratic: each pass removes a BATCH sized from the estimated overshoot, then re-encodes
    /// once; a history of thousands of tiny entries converges in a handful of passes.
    /// Returns false when the remaining (pinned or protected) entries alone exceed the budget.
    static func pruneToRawFileBudget(
        _ items: inout [ClipboardHistoryItem],
        protecting protected: ClipboardHistoryItem? = nil,
        evictingPinnedAsLastResort: Bool = false
    ) -> Bool {
        while let size = encodedByteCount(items), size > maxRawFileBytes {
            let overshoot = size - maxRawFileBytes
            // Non-lazy on purpose: a lazy filter would capture the inout `items` in an escaping closure.
            var candidates = items.indices
                .filter { items[$0].pinnedDate == nil && items[$0].content != protected?.content }
                .sorted { items[$0].createdData < items[$1].createdData }
            if candidates.isEmpty {
                // Only the container-app repair may touch pinned entries, oldest first, so that a history
                // saturated by pins becomes usable again instead of staying unreadable forever.
                guard evictingPinnedAsLastResort else {
                    return false
                }
                candidates = items.indices
                    .filter { items[$0].content != protected?.content }
                    .sorted { items[$0].createdData < items[$1].createdData }
                guard !candidates.isEmpty else {
                    return false
                }
            }
            var freed = 0
            var removed = Set<Int>()
            for index in candidates {
                removed.insert(index)
                freed += estimatedEncodedBytes(items[index])
                if freed >= overshoot + overshoot / 10 + 1 {
                    break
                }
            }
            items = items.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        }
        return true
    }

    /// Copaky [G-22]: atomic replacement with data protection, then backup exclusion re-applied to the NEW
    /// inode and verified by reading it back (one retry); a persistent failure is logged, never hidden.
    static func writeHistoryFile(_ encoded: Data, to url: URL) throws {
        try encoded.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        for _ in 0..<2 {
            excludeFromBackup(url)
            if (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup == true {
                return
            }
        }
        // Fail closed: the bytes are on disk, but the caller must know the exclusion is not confirmed.
        throw IOError.backupExclusionNotConfirmed
    }

    public enum RepairOutcome: Equatable, Sendable {
        case notNeeded
        case shrunk
        case movedAside
        case failed
    }

    /// Files larger than this are not a history at all (16× the budget): moved aside without decoding.
    static let repairReadLimit = 16 * maxRawFileBytes

    /// Where the history lives for `config` (nil when the App Group container is unavailable).
    public static func historyFileLocation(config: any ClipboardHistoryManagerConfiguration) -> URL? {
        historyFileURL(config: config)
    }

    /// Copaky [G-38]: BOUNDED repair for the container app (no 50 MB ceiling), so a history the keyboard
    /// extension cannot read stops being unreadable forever: an oversized VALID file (build-8 growth) is
    /// shrunk with the shared capacity policy — unpinned first, then, as a last resort, the oldest pinned
    /// entries; a malformed file, or one beyond `repairReadLimit`, is MOVED ASIDE (never deleted) so the
    /// keyboard starts from an empty history. Runs off the main actor; nothing is decoded above the limit.
    /// Copaky [G-38]: 本体アプリ側の有界な修復。上限超過の正当なファイルは縮小（最後の手段として古いピン留めも）、
    /// 壊れたファイルや極端に大きいファイルは削除せず退避して空の履歴から再開する。
    public static func repairUnreadableHistory(at url: URL, maxCount: Int) -> RepairOutcome {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue else {
            return .notNeeded
        }
        // Copaky [G-22]: the container app can run before the extension's next load() — harden the file
        // here too, so a valid build-8 history never stays backup-eligible until the keyboard reads it.
        // Copaky [G-22]: 本体アプリが先に起動しても、既存ファイルをここで保護・バックアップ除外する。
        applyLegacyFileProtection(to: url)
        excludeFromBackup(url)
        guard size <= repairReadLimit else {
            return moveAside(url) ? .movedAside : .failed
        }
        guard let encoded = try? Data(contentsOf: url) else {
            return .failed
        }
        var items: [ClipboardHistoryItem]
        do {
            items = try decodeItems(from: encoded)
        } catch IOError.unsupportedSchemaVersion {
            // A newer build wrote it: not ours to touch (the extension keeps it collapsed, unmodified).
            return .notNeeded
        } catch {
            return moveAside(url) ? .movedAside : .failed
        }
        guard size > maxRawFileBytes else {
            return .notNeeded
        }
        items.sort(by: >)
        applyCountPolicy(to: &items, maxCount: maxCount)
        guard pruneToRawFileBudget(&items, evictingPinnedAsLastResort: true),
              let data = try? JSONEncoder().encode(HistoryFile(schemaVersion: currentSchemaVersion, items: items)) else {
            return .failed
        }
        do {
            try writeHistoryFile(data, to: url)
            return .shrunk
        } catch {
            return .failed
        }
    }

    @MainActor public static func repairUnreadableHistory(config: any ClipboardHistoryManagerConfiguration) -> RepairOutcome {
        guard let url = historyFileURL(config: config) else {
            return .notNeeded
        }
        return repairUnreadableHistory(at: url, maxCount: config.maxCount)
    }

    /// Renames the file next to itself with a timestamp; the bytes are preserved for a later look.
    private static func moveAside(_ url: URL) -> Bool {
        // Timestamp + random suffix: two repairs within the same second must not collide.
        let stamp = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        let target = url.deletingLastPathComponent().appendingPathComponent("clipboard_history.unreadable-\(stamp).json", isDirectory: false)
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            return false
        }
        // The aside still holds clipboard text: same at-rest protection and backup exclusion as the history.
        applyLegacyFileProtection(to: target)
        excludeFromBackup(target)
        return true
    }

    private static func applyLegacyFileProtection(to url: URL) {
        // Copaky [G-22]: existing histories need the same at-rest protection as newly written files.
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: url.path
            )
        } catch {
            debug("ClipboardHistoryManager: could not apply file protection", error)
        }
    }

    private static func excludeFromBackup(_ url: URL) {
        // Copaky [G-22]: clipboard history is device-local and must not enter iCloud/computer backups.
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedURL = url
        do {
            try protectedURL.setResourceValues(resourceValues)
        } catch {
            debug("ClipboardHistoryManager: could not exclude history from backup", error)
        }
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

    /// Only the version: a newer build may change the shape of `items`, and that must still read as
    /// «newer schema», never as «malformed». / 新しいビルドが items の形を変えても「壊れたファイル」と誤認しない。
    private struct SchemaProbe: Decodable {
        var schemaVersion: Int
    }

    static func load(config: any ClipboardHistoryManagerConfiguration) throws -> [ClipboardHistoryItem] {
        guard let historyFileURL = historyFileURL(config: config) else {
            throw IOError.sharedDirectoryInaccessible
        }
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else {
            return []
        }
        // Copaky [G-22]: harden the file BEFORE any size gate or read, so an oversized legacy history is
        // protected and excluded from backups too (it stays untouched while the manager is collapsed).
        Self.applyLegacyFileProtection(to: historyFileURL)
        Self.excludeFromBackup(historyFileURL)
        // Copaky [G-38]: check the on-disk size BEFORE materializing the file, so an oversized or
        // tampered history is never read whole into the extension's memory. An oversized file is a
        // collapsed load, not an empty valid history: throwing keeps the bytes (save() becomes a no-op)
        // until the container app repairs it (`repairOversizedHistory`).
        if let size = (try? FileManager.default.attributesOfItem(atPath: historyFileURL.path)[.size] as? NSNumber)?.intValue,
           size > Self.maxRawFileBytes {
            throw IOError.rawFileOversized(bytes: size, limit: Self.maxRawFileBytes)
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
        guard encoded.count <= Self.maxRawFileBytes else {
            throw IOError.rawFileOversized(bytes: encoded.count, limit: Self.maxRawFileBytes)
        }
        var items = try Self.decodeItems(from: encoded)
        items.sort(by: >)
        // Copaky [G-38/G-39]: same capacity policy as insert()/save(): every pinned entry survives and the
        // newest unpinned keep at least one slot (a fresh capture next to `maxCount` pins is not lost).
        Self.applyCountPolicy(to: &items, maxCount: config.maxCount)
        return items
    }

    /// Tolerant decode shared by `load()` and `repairOversizedHistory()`: envelope or legacy bare array,
    /// corrupted items dropped one by one, per-item caps re-applied.
    static func decodeItems(from encoded: Data) throws -> [ClipboardHistoryItem] {
        let decoder = JSONDecoder()
        var items: [ClipboardHistoryItem]
        // Copaky [G-38]: version check BEFORE the shape-dependent decode (counter-review n.4, N4).
        if let probe = try? decoder.decode(SchemaProbe.self, from: encoded), probe.schemaVersion > Self.currentSchemaVersion {
            throw IOError.unsupportedSchemaVersion(probe.schemaVersion)
        }
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
        /// Copaky [G-38]: the raw file exceeds the pre-decode memory guard and must be preserved.
        case rawFileOversized(bytes: Int, limit: Int)
        /// Copaky [G-22]: the file was written, but `isExcludedFromBackup` could not be confirmed on it.
        case backupExclusionNotConfirmed
    }

    @MainActor static func save(_ items: [ClipboardHistoryItem], config: any ClipboardHistoryManagerConfiguration) throws -> [ClipboardHistoryItem]? {
        // jsonファイルとして共有空間に保存する
        // FullAccessがない場合は不可能なので`fail`にする
        guard SemiStaticStates.shared.hasFullAccess else {
            throw IOError.lackFullAccess
        }
        guard let historyFileURL = historyFileURL(config: config) else {
            throw IOError.sharedDirectoryInaccessible
        }
        var persistedItems = items.sorted(by: >)
        // Copaky [G-38]: same capacity policy as insert()/load() — including the count policy (an unpin
        // can leave maxCount + 1 entries in memory). Pinned data is never discarded automatically; if it
        // alone exceeds the cap, preserve the existing file (nil = nothing written).
        Self.applyCountPolicy(to: &persistedItems, maxCount: config.maxCount)
        guard Self.pruneToRawFileBudget(&persistedItems) else {
            debug("ClipboardHistoryManager.save: pinned history exceeds raw file limit")
            return nil
        }
        let encoded = try JSONEncoder().encode(HistoryFile(schemaVersion: Self.currentSchemaVersion, items: persistedItems))
        try Self.writeHistoryFile(encoded, to: historyFileURL)
        return persistedItems
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
