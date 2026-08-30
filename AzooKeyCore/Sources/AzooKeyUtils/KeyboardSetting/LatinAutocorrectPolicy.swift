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
        /// Exact guesses that UIKit reports as user-learned words. Learned English guesses and
        /// unattested learned Italian guesses are never eligible for correction.
        public let learnedGuesses: Set<String>
        /// Guesses known to pass a same-language second oracle query. Production populates this
        /// only for the selected winner; deterministic callers may inject validity for every guess.
        public let oracleAcceptedGuesses: Set<String>

        public init(
            isMisspelled: Bool,
            guesses: [String],
            learnedGuesses: Set<String> = [],
            oracleAcceptedGuesses: Set<String>? = nil
        ) {
            self.isMisspelled = isMisspelled
            self.guesses = guesses
            self.learnedGuesses = learnedGuesses
            // Backwards-compatible deterministic seam: an omitted validity set means that the
            // injected oracle accepts its own guesses. Production always passes an explicit set.
            self.oracleAcceptedGuesses = oracleAcceptedGuesses ?? Set(guesses)
        }
    }

    /// Stable fail-closed reasons intended for DEBUG diagnostics and deterministic tests.
    public enum RejectionReason: String, Equatable, Sendable {
        case preflightRejected
        case attestedItalianWord
        case spellCheckUnavailable
        case typedWordAccepted
        case noEligibleGuess
        case candidateRejectedByOracle
    }

    /// A single policy pass, including only the typed-word spell-check snapshot needed for DEBUG
    /// diagnostics. It intentionally carries no surrounding host text.
    public struct Evaluation: Equatable, Sendable {
        public let correction: String?
        public let rejectionReason: RejectionReason?
        public let spellCheckResult: SpellCheckResult?
        /// Winner before case adaptation. Present even when the second oracle query rejects it.
        public let selectedCandidate: String?

        private init(
            correction: String?,
            rejectionReason: RejectionReason?,
            spellCheckResult: SpellCheckResult?,
            selectedCandidate: String?
        ) {
            self.correction = correction
            self.rejectionReason = rejectionReason
            self.spellCheckResult = spellCheckResult
            self.selectedCandidate = selectedCandidate
        }

        fileprivate static func accepted(
            _ correction: String,
            spellCheckResult: SpellCheckResult?,
            selectedCandidate: String
        ) -> Self {
            .init(
                correction: correction,
                rejectionReason: nil,
                spellCheckResult: spellCheckResult,
                selectedCandidate: selectedCandidate
            )
        }

        fileprivate static func rejected(
            _ reason: RejectionReason,
            spellCheckResult: SpellCheckResult? = nil,
            selectedCandidate: String? = nil
        ) -> Self {
            .init(
                correction: nil,
                rejectionReason: reason,
                spellCheckResult: spellCheckResult,
                selectedCandidate: selectedCandidate
            )
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

    private struct SystemSpellCheckSnapshot {
        let result: SpellCheckResult
        let languageIdentifier: String
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
        evaluate(forTypedWord: typed, language: language, context: context).correction
    }

    /// Production evaluation performs one typed-word oracle path, then revalidates only its winner.
    @MainActor public static func evaluate(
        forTypedWord typed: String,
        language: Language,
        context: Context
    ) -> Evaluation {
        switch preflight(forTypedWord: typed, language: language, context: context) {
        case .reject:
            return .rejected(.preflightRejected)
        case let .preferred(correction):
            return .accepted(correction, spellCheckResult: nil, selectedCandidate: correction)
        case .requiresSpellCheck:
            // A frequency-attested Italian word is positive evidence and must never reach a
            // potentially polluted dynamic UIKit lexicon. / 頻度辞書にある入力語は照会前に保持する。
            guard !isAttestedItalianWord(typed, language: language) else {
                return .rejected(.attestedItalianWord)
            }
            guard let snapshot = systemSpellCheck(forTypedWord: typed, language: language) else {
                return .rejected(.spellCheckUnavailable)
            }
            guard snapshot.result.isMisspelled else {
                return .rejected(.typedWordAccepted, spellCheckResult: snapshot.result)
            }
            guard let candidate = rankedCandidate(
                forTypedWord: typed,
                language: language,
                result: snapshot.result
            ) else {
                return .rejected(.noEligibleGuess, spellCheckResult: snapshot.result)
            }

            let candidateIsAccepted = systemOracleAccepts(
                candidate.text,
                languageIdentifier: snapshot.languageIdentifier
            )
            let diagnosedResult = SpellCheckResult(
                isMisspelled: snapshot.result.isMisspelled,
                guesses: snapshot.result.guesses,
                learnedGuesses: snapshot.result.learnedGuesses,
                oracleAcceptedGuesses: candidateIsAccepted ? [candidate.text] : []
            )
            guard candidateIsAccepted else {
                return .rejected(
                    .candidateRejectedByOracle,
                    spellCheckResult: diagnosedResult,
                    selectedCandidate: candidate.text
                )
            }
            return .accepted(
                adaptCase(of: candidate.text, to: typed),
                spellCheckResult: diagnosedResult,
                selectedCandidate: candidate.text
            )
        }
    }

    /// Deterministic seam for exhaustive policy and corpus tests. Production never injects guesses.
    public static func correction(
        forTypedWord typed: String,
        language: Language,
        context: Context,
        spellCheckResult: SpellCheckResult?
    ) -> String? {
        evaluate(
            forTypedWord: typed,
            language: language,
            context: context,
            spellCheckResult: spellCheckResult
        ).correction
    }

    /// Deterministic seam: learned status and same-language candidate validity are injectable.
    public static func evaluate(
        forTypedWord typed: String,
        language: Language,
        context: Context,
        spellCheckResult: SpellCheckResult?
    ) -> Evaluation {
        switch preflight(forTypedWord: typed, language: language, context: context) {
        case .reject:
            return .rejected(.preflightRejected)
        case let .preferred(correction):
            return .accepted(correction, spellCheckResult: nil, selectedCandidate: correction)
        case .requiresSpellCheck:
            guard !isAttestedItalianWord(typed, language: language) else {
                return .rejected(.attestedItalianWord)
            }
            guard let spellCheckResult else {
                return .rejected(.spellCheckUnavailable)
            }
            guard spellCheckResult.isMisspelled else {
                return .rejected(.typedWordAccepted, spellCheckResult: spellCheckResult)
            }
            guard let candidate = rankedCandidate(
                forTypedWord: typed,
                language: language,
                result: spellCheckResult
            ) else {
                return .rejected(.noEligibleGuess, spellCheckResult: spellCheckResult)
            }
            guard spellCheckResult.oracleAcceptedGuesses.contains(candidate.text) else {
                return .rejected(
                    .candidateRejectedByOracle,
                    spellCheckResult: spellCheckResult,
                    selectedCandidate: candidate.text
                )
            }
            return .accepted(
                adaptCase(of: candidate.text, to: typed),
                spellCheckResult: spellCheckResult,
                selectedCandidate: candidate.text
            )
        }
    }

    private static func isAttestedItalianWord(_ typed: String, language: Language) -> Bool {
        language == .italian
            && ItalianAutocorrectFrequencyLexicon.rank(ofLowercased: typed.lowercased()) != nil
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
    ) -> SystemSpellCheckSnapshot? {
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
            return SystemSpellCheckSnapshot(
                result: SpellCheckResult(
                    isMisspelled: false,
                    guesses: [],
                    oracleAcceptedGuesses: []
                ),
                languageIdentifier: identifier
            )
        }
        // The input is one composing word. A partial-range diagnosis is ambiguous, so do not ask
        // for or apply guesses unless the checker rejected that whole word.
        // 単語全体が誤字と判定された場合だけ候補を利用し、部分範囲なら fail-closed とする。
        guard misspelledRange == range else {
            return nil
        }
        let guesses = checker.guesses(
            forWordRange: misspelledRange,
            in: typed,
            language: identifier
        ) ?? []
        let learnedGuesses = Set(guesses.filter { UITextChecker.hasLearnedWord($0) })
        return SystemSpellCheckSnapshot(
            result: SpellCheckResult(
                isMisspelled: true,
                guesses: guesses,
                learnedGuesses: learnedGuesses,
                // Unknown until the selected winner receives its same-language second query.
                oracleAcceptedGuesses: []
            ),
            languageIdentifier: identifier
        )
    }

    @MainActor private static func systemOracleAccepts(
        _ candidate: String,
        languageIdentifier: String
    ) -> Bool {
        let range = NSRange(location: 0, length: (candidate as NSString).length)
        let misspelledRange = checker.rangeOfMisspelledWord(
            in: candidate,
            range: range,
            startingAt: 0,
            wrap: false,
            language: languageIdentifier
        )
        return misspelledRange.location == NSNotFound
    }

    private static func normalizedLanguageIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func rankedCandidate(
        forTypedWord typed: String,
        language: Language,
        result: SpellCheckResult
    ) -> RankedCandidate? {
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
            let italianFrequencyRank = language == .italian
                ? ItalianAutocorrectFrequencyLexicon.rank(ofLowercased: guessLowercased)
                : nil
            if result.learnedGuesses.contains(guess) {
                // Dynamic learned words are untrusted. Italian makes the sole exception when the
                // pinned frequency lexicon independently attests the candidate; English has no
                // equivalent embedded oracle. / 学習語は伊語頻度辞書に載る場合だけ許可する。
                guard language == .italian, italianFrequencyRank != nil else {
                    return nil
                }
            }
            return RankedCandidate(
                text: guess,
                distance: distance,
                italianFrequencyRank: italianFrequencyRank,
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
        return best
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
