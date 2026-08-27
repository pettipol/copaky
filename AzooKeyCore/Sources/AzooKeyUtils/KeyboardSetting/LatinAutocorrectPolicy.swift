//
//  LatinAutocorrectPolicy.swift
//  AzooKeyUtils
//

import Foundation
import UIKit

// Copaky: fail-closed typo correction policy shared by the Italian and English Latin tabs. Host
// traits and the spell-check snapshot are explicit inputs, so every decision except the UIKit
// oracle itself remains deterministic and unit-testable.
// Copaky: 伊英ラテン文字タブ共通の fail-closed 誤字補正。入力欄属性と校正結果を明示入力にする。
public enum LatinAutocorrectPolicy {
    public enum Language: String, CaseIterable, Sendable {
        case italian = "it-IT"
        case english = "en-US"
    }

    public struct Context {
        public let isEnabled: Bool
        public let keyboardType: UIKeyboardType
        public let textContentType: UITextContentType?
        public let autocorrectionType: UITextAutocorrectionType?
        public let isSecureField: Bool
        /// Text immediately before the typed word, not including the word itself.
        public let documentContextBeforeWord: String?
        /// A-01c's already-confirmed answer. It wins without invoking the general oracle again.
        public let preferredItalianAutoAccentCorrection: String?
        /// True when A-01c recognizes this as its domain, even if its own setting/oracle blocks it.
        /// This prevents missing-accent words from silently falling through the general path.
        public let italianAutoAccentCandidateExists: Bool

        public init(
            isEnabled: Bool,
            keyboardType: UIKeyboardType,
            textContentType: UITextContentType?,
            autocorrectionType: UITextAutocorrectionType?,
            isSecureField: Bool,
            documentContextBeforeWord: String?,
            preferredItalianAutoAccentCorrection: String? = nil,
            italianAutoAccentCandidateExists: Bool = false
        ) {
            self.isEnabled = isEnabled
            self.keyboardType = keyboardType
            self.textContentType = textContentType
            self.autocorrectionType = autocorrectionType
            self.isSecureField = isSecureField
            self.documentContextBeforeWord = documentContextBeforeWord
            self.preferredItalianAutoAccentCorrection = preferredItalianAutoAccentCorrection
            self.italianAutoAccentCandidateExists = italianAutoAccentCandidateExists
        }
    }

    public struct SpellCheckResult: Equatable, Sendable {
        public let isMisspelled: Bool
        public let guesses: [String]

        public init(isMisspelled: Bool, guesses: [String]) {
            self.isMisspelled = isMisspelled
            self.guesses = guesses
        }
    }

    private enum Preflight {
        case reject
        case preferred(String)
        case requiresSpellCheck
    }

    private struct RankedCandidate {
        let text: String
        let distance: Int
        let italianFrequencyRank: UInt16?
        let lengthDelta: Int
        let length: Int
        let oracleIndex: Int
    }

    // Long identifier-like runs are not prose words and must never create unbounded work inside
    // the extension. Thirty characters also keep non-marked commit + space within the 32-edit host
    // tracker, preserving immediate undo; edit distance is linear-memory as a second safety layer.
    // 長大な識別子風入力は語として扱わず、32編集の追跡内で復元できる30文字までに制限する。
    private static let maximumWordLength = 30

    // One checker instance serves both range and guesses for a word. A-01c is resolved before this
    // path, so a space never pays the general oracle after an accent answer.
    // 1語につき同じ checker で誤字範囲と候補を取得し、アクセント回答後の二重照会を避ける。
    @MainActor private static let checker = UITextChecker()

    /// Production entry point: word + Latin language + explicit host context -> correction or nil.
    @MainActor public static func correction(
        forTypedWord typed: String,
        language: Language,
        context: Context
    ) -> String? {
        switch preflight(forTypedWord: typed, language: language, context: context) {
        case .reject:
            return nil
        case let .preferred(correction):
            return correction
        case .requiresSpellCheck:
            guard let result = systemSpellCheck(forTypedWord: typed, language: language) else {
                return nil
            }
            return rankedCorrection(forTypedWord: typed, language: language, result: result)
        }
    }

    /// Deterministic seam for exhaustive policy and corpus tests. Production never injects guesses.
    public static func correction(
        forTypedWord typed: String,
        language: Language,
        context: Context,
        spellCheckResult: SpellCheckResult?
    ) -> String? {
        switch preflight(forTypedWord: typed, language: language, context: context) {
        case .reject:
            return nil
        case let .preferred(correction):
            return correction
        case .requiresSpellCheck:
            guard let spellCheckResult else {
                return nil
            }
            return rankedCorrection(forTypedWord: typed, language: language, result: spellCheckResult)
        }
    }

    private static func preflight(
        forTypedWord typed: String,
        language: Language,
        context: Context
    ) -> Preflight {
        guard context.isEnabled,
              context.autocorrectionType != .no,
              !context.isSecureField,
              ItalianAutoAccentPolicy.allowsKeyboardType(context.keyboardType),
              ItalianAutoAccentPolicy.allowsTextContentType(context.textContentType),
              allowsWord(typed, documentContextBeforeWord: context.documentContextBeforeWord) else {
            return .reject
        }

        // A-01c owns missing-accent words. A confirmed fix wins; an unconfirmed/disabled A-01c
        // candidate stays untouched instead of being reinterpreted by the general guess ranking.
        if language == .italian, context.italianAutoAccentCandidateExists {
            guard let correction = context.preferredItalianAutoAccentCorrection,
                  correction != typed,
                  correction.allSatisfy(\.isLetter) else {
                return .reject
            }
            return .preferred(adaptCase(of: correction, to: typed))
        }
        return .requiresSpellCheck
    }

    private static func allowsWord(_ typed: String, documentContextBeforeWord: String?) -> Bool {
        guard !typed.isEmpty,
              typed.count <= maximumWordLength,
              typed.allSatisfy(\.isLetter) else {
            return false
        }

        let hasUppercase = typed.contains(where: \.isUppercase)
        let hasLowercase = typed.contains(where: \.isLowercase)
        guard !(hasUppercase && !hasLowercase) else {
            return false
        }

        // Mixed/internal capitals look like names or identifiers. A single initial capital is
        // accepted only at a sentence boundary, matching the A-01c proper-name protection.
        if hasUppercase {
            guard typed.first?.isUppercase == true,
                  typed.dropFirst().allSatisfy(\.isLowercase),
                  ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: documentContextBeforeWord) else {
                return false
            }
        }
        return true
    }

    @MainActor private static func systemSpellCheck(
        forTypedWord typed: String,
        language: Language
    ) -> SpellCheckResult? {
        let available = UITextChecker.availableLanguages
        let requiredIdentifier = normalizedLanguageIdentifier(language.rawValue)
        let identifier = available.first {
            normalizedLanguageIdentifier($0) == requiredIdentifier
        }
        guard let identifier else {
            return nil
        }

        let range = NSRange(location: 0, length: (typed as NSString).length)
        let misspelledRange = checker.rangeOfMisspelledWord(
            in: typed,
            range: range,
            startingAt: 0,
            wrap: false,
            language: identifier
        )
        guard misspelledRange.location != NSNotFound else {
            return SpellCheckResult(isMisspelled: false, guesses: [])
        }
        // The input is one composing word. A partial-range diagnosis is ambiguous, so do not ask
        // for or apply guesses unless the checker rejected that whole word.
        // 単語全体が誤字と判定された場合だけ候補を利用し、部分範囲なら fail-closed とする。
        guard misspelledRange == range else {
            return nil
        }
        return SpellCheckResult(
            isMisspelled: true,
            guesses: checker.guesses(forWordRange: misspelledRange, in: typed, language: identifier) ?? []
        )
    }

    private static func normalizedLanguageIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func rankedCorrection(
        forTypedWord typed: String,
        language: Language,
        result: SpellCheckResult
    ) -> String? {
        guard result.isMisspelled else {
            return nil
        }

        let threshold = typed.count <= 4 ? 1 : 2
        let typedLowercased = typed.lowercased()
        let ranked = result.guesses.enumerated().compactMap { index, guess -> RankedCandidate? in
            let guessLowercased = guess.lowercased()
            guard !guess.isEmpty,
                  guess.allSatisfy(\.isLetter),
                  guessLowercased != typedLowercased else {
                return nil
            }
            let lengthDelta = abs(guess.count - typed.count)
            guard lengthDelta <= threshold else {
                return nil
            }
            let distance = editDistance(typedLowercased, guessLowercased)
            guard distance <= threshold else {
                return nil
            }
            return RankedCandidate(
                text: guess,
                distance: distance,
                italianFrequencyRank: language == .italian
                    ? ItalianAutocorrectFrequencyLexicon.rank(ofLowercased: guessLowercased)
                    : nil,
                lengthDelta: lengthDelta,
                length: guess.count,
                oracleIndex: index
            )
        }
        let best = ranked.min { lhs, rhs in
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            // Frequency is deliberately an exact-distance tie-break only. It can overturn the
            // system oracle's alphabetical order (and its length bias), but never a closer edit.
            // The English path has no ranks and therefore retains its previous comparator.
            if language == .italian {
                let lhsRank = lhs.italianFrequencyRank ?? .max
                let rhsRank = rhs.italianFrequencyRank ?? .max
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
            }
            if lhs.lengthDelta != rhs.lengthDelta {
                return lhs.lengthDelta < rhs.lengthDelta
            }
            if lhs.length != rhs.length {
                return lhs.length < rhs.length
            }
            // Preserve the system oracle order as the final deterministic tie-break.
            return lhs.oracleIndex < rhs.oracleIndex
        }
        return best.map { adaptCase(of: $0.text, to: typed) }
    }

    private static func adaptCase(of candidate: String, to typed: String) -> String {
        guard typed.first?.isUppercase == true,
              candidate.first?.isLowercase == true,
              candidate.dropFirst().allSatisfy({ !$0.isUppercase }),
              let first = candidate.first else {
            return candidate
        }
        return first.uppercased() + String(candidate.dropFirst())
    }

    /// Optimal-string-alignment Damerau-Levenshtein distance. Adjacent transpositions count as one
    /// edit, which is required for canonical typos such as "teh" and "adn" under the short-word cap.
    public static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty else {
            return right.count
        }
        guard !right.isEmpty else {
            return left.count
        }

        var previousPrevious: [Int]?
        var previous = Array(0...right.count)

        for leftIndex in 1...left.count {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                let substitutionCost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    min(
                        current[rightIndex - 1] + 1,
                        previous[rightIndex - 1] + substitutionCost
                    )
                )
                if leftIndex > 1,
                   rightIndex > 1,
                   left[leftIndex - 1] == right[rightIndex - 2],
                   left[leftIndex - 2] == right[rightIndex - 1],
                   let previousPrevious {
                    current[rightIndex] = min(
                        current[rightIndex],
                        previousPrevious[rightIndex - 2] + 1
                    )
                }
            }
            previousPrevious = previous
            previous = current
        }
        return previous[right.count]
    }
}
