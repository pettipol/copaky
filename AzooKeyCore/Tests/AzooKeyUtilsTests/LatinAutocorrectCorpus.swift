import AzooKeyUtils
import Foundation

// Copaky: loader for the permanent, reviewable Campaign 4 TSV resource. #filePath keeps the corpus
// source-bound without changing Package.swift outside B-04's authorized file set.
// Copaky: 恒久的でレビュー可能な Campagna 4 TSV を読み込み、Package.swift は変更しない。
enum LatinAutocorrectCorpus {
    enum Kind: String, Equatable {
        case typo
        case control
    }

    struct Entry {
        let kind: Kind
        let language: LatinAutocorrectPolicy.Language
        let typed: String
        let expected: String?
        let contextBeforeWord: String?
        let spellCheckResult: LatinAutocorrectPolicy.SpellCheckResult
    }

    enum LoadError: Error {
        case invalidRow(line: Int, reason: String)
    }

    static func load() throws -> [Entry] {
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let resourceURL = sourceDirectory.deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("LatinAutocorrectCorpus.tsv", isDirectory: false)
        let contents = try String(contentsOf: resourceURL, encoding: .utf8)
        var entries: [Entry] = []

        for (offset, rawLine) in contents.split(whereSeparator: \.isNewline).enumerated() {
            guard !rawLine.hasPrefix("#") else {
                continue
            }
            let lineNumber = offset + 1
            let fields = rawLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7 else {
                throw LoadError.invalidRow(line: lineNumber, reason: "expected 7 TSV fields, got \(fields.count)")
            }
            guard let kind = Kind(rawValue: fields[0]) else {
                throw LoadError.invalidRow(line: lineNumber, reason: "unknown kind \(fields[0])")
            }
            guard let language = LatinAutocorrectPolicy.Language(rawValue: fields[1]) else {
                throw LoadError.invalidRow(line: lineNumber, reason: "unknown language \(fields[1])")
            }
            guard fields[5] == "0" || fields[5] == "1" else {
                throw LoadError.invalidRow(line: lineNumber, reason: "misspelled must be 0 or 1")
            }
            let expected = fields[3].isEmpty ? nil : fields[3]
            if kind == .typo, expected == nil {
                throw LoadError.invalidRow(line: lineNumber, reason: "typo row needs an expected target")
            }
            let context = fields[4] == "<nil>"
                ? nil
                : fields[4].replacingOccurrences(of: "\\s", with: " ")
            let guesses = fields[6].isEmpty
                ? []
                : fields[6].split(separator: "|", omittingEmptySubsequences: false).map(String.init)

            entries.append(Entry(
                kind: kind,
                language: language,
                typed: fields[2],
                expected: expected,
                contextBeforeWord: context,
                spellCheckResult: .init(isMisspelled: fields[5] == "1", guesses: guesses)
            ))
        }
        return entries
    }
}
