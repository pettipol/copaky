import Foundation

struct HotfixDictionaryV1: Codable {
    /// Metadata about the file itself (status, version, etc.)
    let metadata: Metadata
    /// Array of dictionary entries.
    let data: [Entry]

    // MARK: - Nested Types

    /// Corresponds to the `"metadata"` object.
    struct Metadata: Codable {
        let status: Status
        let name: String
        let description: String
        let version: String
        let lastUpdate: String  // ISO‑8601 文字列 (例: "2025-05-04T12:00:00.00")

        enum Status: String, Codable {
            case active
            case disabled
        }

        enum CodingKeys: String, CodingKey {
            case status, name, description, version
            case lastUpdate = "last_update"
        }

        var lastUpdateDate: Date? {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SS"
            return formatter.date(from: self.lastUpdate)
        }
    }

    /// One element of the `"data"` array (a single vocabulary entry).
    struct Entry: Codable {
        let word: String
        let ruby: String
        let wordWeight: Double     // 負の値ほど優先度が高い
        let lcid: Int
        let rcid: Int
        let mid: Int
        let date: String        // "YYYY-MM-DD"
        let author: String

        enum CodingKeys: String, CodingKey {
            case word, ruby
            case wordWeight = "word_weight"
            case lcid, rcid, mid, date, author
        }
    }
}

// MARK: - Convenience Loading Helpers
extension HotfixDictionaryV1 {
    /// Decode `HotfixDictionaryV1` from raw JSON `Data`.
    static func load(from jsonData: Data) throws -> HotfixDictionaryV1 {
        let decoder = JSONDecoder()
        // `.convertFromSnakeCase` would work, but CodingKeys give us explicit control
        return try decoder.decode(HotfixDictionaryV1.self, from: jsonData)
    }

    // Copaky: offline-true (v0.1). The remote hotfix-dictionary update path (GitHub REST API +
    // release download via URLSession) has been removed — Copaky performs no network I/O. Any entries
    // previously cached in UserDefaults are still decoded locally by `load(from:Data)` above.
    // Copaky: オフライン徹底（v0.1）。GitHub からのホットフィックス辞書更新（ネットワーク取得）は削除。
}
