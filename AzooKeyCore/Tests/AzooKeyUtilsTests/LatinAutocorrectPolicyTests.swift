import AzooKeyUtils
import UIKit
import XCTest

// Copaky: exhaustive pure gates/ranking plus the permanent Campaign 4 corpus. The UIKit-backed
// corpus gate runs only when both dictionaries exist on the selected iOS runtime.
// Copaky: 純粋判定・順位付けと恒久コーパスを検証。実辞書テストは伊英辞書がある時だけ実行する。
final class LatinAutocorrectPolicyTests: XCTestCase {
    private func context(
        enabled: Bool = true,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocorrectionType: UITextAutocorrectionType? = .yes,
        isSecureField: Bool = false,
        beforeWord: String? = "I wrote ",
        preferredItalianAccent: String? = nil,
        italianAccentCandidateExists: Bool = false
    ) -> LatinAutocorrectPolicy.Context {
        .init(
            isEnabled: enabled,
            keyboardType: keyboardType,
            textContentType: textContentType,
            autocorrectionType: autocorrectionType,
            isSecureField: isSecureField,
            documentContextBeforeWord: beforeWord,
            preferredItalianAutoAccentCorrection: preferredItalianAccent,
            italianAutoAccentCandidateExists: italianAccentCandidateExists
        )
    }

    private func correction(
        _ typed: String,
        _ expectedGuess: String,
        language: LatinAutocorrectPolicy.Language,
        context: LatinAutocorrectPolicy.Context? = nil,
        guesses: [String]? = nil
    ) -> String? {
        LatinAutocorrectPolicy.correction(
            forTypedWord: typed,
            language: language,
            context: context ?? self.context(),
            spellCheckResult: .init(isMisspelled: true, guesses: guesses ?? [expectedGuess])
        )
    }

    func testSettingContractDefaultsOff() {
        XCTAssertFalse(EnableLatinAutocorrect.defaultValue)
        XCTAssertEqual(EnableLatinAutocorrect.key, "enable_latin_autocorrect")
        XCTAssertEqual(LatinAutocorrectPolicy.Language.italian.rawValue, "it-IT")
        XCTAssertEqual(LatinAutocorrectPolicy.Language.english.rawValue, "en-US")
    }

    func testCanonicalEnglishCorrections() {
        XCTAssertEqual(correction("teh", "the", language: .english), "the")
        XCTAssertEqual(correction("adn", "and", language: .english), "and")
    }

    func testCanonicalItalianCorrections() {
        XCTAssertEqual(correction("qundo", "quando", language: .italian), "quando")
        XCTAssertEqual(correction("anhce", "anche", language: .italian), "anche")
    }

    func testSettingAndHostTraitGatesFailClosed() {
        let oracle = LatinAutocorrectPolicy.SpellCheckResult(isMisspelled: true, guesses: ["the"])
        XCTAssertNil(LatinAutocorrectPolicy.correction(
            forTypedWord: "teh", language: .english, context: context(enabled: false), spellCheckResult: oracle
        ))
        XCTAssertNil(LatinAutocorrectPolicy.correction(
            forTypedWord: "teh", language: .english, context: context(autocorrectionType: .no), spellCheckResult: oracle
        ))
        XCTAssertNil(LatinAutocorrectPolicy.correction(
            forTypedWord: "teh", language: .english, context: context(isSecureField: true), spellCheckResult: oracle
        ))
        for keyboardType: UIKeyboardType in [
            .URL, .emailAddress, .twitter, .namePhonePad, .asciiCapableNumberPad,
            .numberPad, .phonePad, .decimalPad,
        ] {
            XCTAssertNil(
                LatinAutocorrectPolicy.correction(
                    forTypedWord: "teh",
                    language: .english,
                    context: context(keyboardType: keyboardType),
                    spellCheckResult: oracle
                ),
                "\(keyboardType) must be blocked"
            )
        }
        for contentType: UITextContentType in [.name, .URL, .emailAddress, .password, .oneTimeCode, .creditCardNumber] {
            XCTAssertNil(
                LatinAutocorrectPolicy.correction(
                    forTypedWord: "teh",
                    language: .english,
                    context: context(textContentType: contentType),
                    spellCheckResult: oracle
                ),
                "\(contentType) must be blocked"
            )
        }
    }

    func testNamesCapitalizationCodesSymbolsAndElisionsAreUntouched() {
        for (typed, beforeWord, nearbyGuess) in [
            ("Sara", "Ciao ", "Sarà"),
            ("ASAP", "Invia ", "ASAPs"),
            ("iPhone", "Uso ", "iPhobe"),
            ("b2b", "modello ", "bob"),
            ("example.com", "visita ", "examplecom"),
            ("un'ora", "tra ", "unora"),
            ("l’acqua", "bevo ", "lacqua"),
        ] {
            XCTAssertNil(
                LatinAutocorrectPolicy.correction(
                    forTypedWord: typed,
                    language: .italian,
                    context: context(beforeWord: beforeWord),
                    spellCheckResult: .init(isMisspelled: true, guesses: [nearbyGuess])
                ),
                "\(typed) must be preserved"
            )
        }
    }

    func testCapitalizedTypoIsAllowedOnlyAtSentenceStartAndCaseIsPreserved() {
        XCTAssertEqual(
            correction("Teh", "the", language: .english, context: context(beforeWord: "Hello. ")),
            "The"
        )
        XCTAssertNil(correction("Teh", "the", language: .english, context: context(beforeWord: "Hello ")))
        XCTAssertEqual(
            correction("iphnoe", "iPhone", language: .english),
            "iPhone",
            "internal capitalization proposed by the oracle must not be rewritten"
        )
    }

    func testValidAmbiguousItalianWordsAreUntouchedWhenOracleAcceptsThem() {
        for word in ["Sara", "meta", "faro", "pero", "cosi"] {
            let result = LatinAutocorrectPolicy.correction(
                forTypedWord: word,
                language: .italian,
                context: context(beforeWord: word == "Sara" ? nil : "Vedo "),
                spellCheckResult: .init(isMisspelled: false, guesses: [])
            )
            XCTAssertNil(result, "\(word) is accepted by the oracle and must remain unchanged")
        }
    }

    func testItalianAutoAccentHasPrecedenceAndCanBlockGeneralFallback() {
        let generalGuess = LatinAutocorrectPolicy.SpellCheckResult(isMisspelled: true, guesses: ["perché"])
        XCTAssertEqual(
            LatinAutocorrectPolicy.correction(
                forTypedWord: "perche",
                language: .italian,
                context: context(
                    preferredItalianAccent: "perché",
                    italianAccentCandidateExists: true
                ),
                spellCheckResult: generalGuess
            ),
            "perché"
        )
        XCTAssertNil(
            LatinAutocorrectPolicy.correction(
                forTypedWord: "perche",
                language: .italian,
                context: context(italianAccentCandidateExists: true),
                spellCheckResult: generalGuess
            ),
            "an A-01c-owned word must not fall through the general ranking"
        )
    }

    func testEditDistanceThresholdsAndRanking() {
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("teh", "the"), 1)
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("adn", "and"), 1)
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("kitten", "sitting"), 3)

        // Short words permit only one edit.
        XCTAssertNil(correction("cat", "cost", language: .english))
        XCTAssertEqual(correction("cta", "cat", language: .english), "cat")

        // Longer words permit exactly two edits, never three.
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("abcdef", "abxyef"), 2)
        XCTAssertEqual(correction("abcdef", "abxyef", language: .english), "abxyef")
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("abcdef", "abxyeg"), 3)
        XCTAssertNil(correction("abcdef", "abxyeg", language: .english))

        let oversized = String(repeating: "a", count: 31)
        let nearbyOversized = String(repeating: "a", count: 30) + "b"
        XCTAssertNil(correction(oversized, nearbyOversized, language: .english))

        // Distance wins first; English equal-distance candidates retain the closer length tie-break.
        XCTAssertEqual(
            correction("qusto", "questo", language: .italian, guesses: ["costo", "questo"]),
            "questo"
        )
        XCTAssertEqual(
            correction("abcde", "abxde", language: .english, guesses: ["abcdee", "abxde"]),
            "abxde"
        )
    }

    func testItalianFrequencyRankBreaksOnlyExactDistanceTiesBeforeLengthDelta() {
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("crdere", "cedere"), 1)
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("crdere", "credere"), 1)
        XCTAssertEqual(
            correction("crdere", "credere", language: .italian, guesses: ["cedere", "credere"]),
            "credere",
            "frequency rank must precede the smaller length delta at an exact distance tie"
        )

        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("qundo", "fundo"), 1)
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("qundo", "quando"), 1)
        XCTAssertEqual(
            correction("qundo", "quando", language: .italian, guesses: ["fundo", "quando"]),
            "quando",
            "an in-list Italian word must beat an unranked candidate at an exact distance tie"
        )

        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("qundo", "quanto"), 2)
        XCTAssertEqual(
            correction("qundo", "fundo", language: .italian, guesses: ["quanto", "fundo"]),
            "fundo",
            "frequency must never overturn a strictly smaller edit distance"
        )
    }

    func testItalianFrequencyRankOrdersKnownWordsWithinTheList() {
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("caas", "caos"), 1)
        XCTAssertEqual(LatinAutocorrectPolicy.editDistance("caas", "casa"), 1)
        XCTAssertEqual(
            correction("caas", "casa", language: .italian, guesses: ["caos", "casa"]),
            "casa",
            "the better Italian frequency rank must resolve an otherwise equal tie"
        )
    }

    func testItalianFrequencyRankResolvesMeasuredSystemSpellCheckerMisses() {
        let cases = [
            (typed: "qundo", wrong: "fundo", expected: "quando"),
            (typed: "qusto", wrong: "quoto", expected: "questo"),
            (typed: "motlo", wrong: "motto", expected: "molto"),
            (typed: "tnto", wrong: "toto", expected: "tanto"),
            (typed: "dobve", wrong: "doble", expected: "dove"),
            (typed: "priima", wrong: "prisma", expected: "prima"),
            (typed: "doop", wrong: "coop", expected: "dopo"),
            (typed: "lavro", wrong: "ladro", expected: "lavoro"),
            (typed: "annoo", wrong: "annoi", expected: "anno"),
            (typed: "crdere", wrong: "cedere", expected: "credere"),
            (typed: "satto", wrong: "setto", expected: "stato"),
            (typed: "prate", wrong: "orate", expected: "parte"),
            (typed: "propro", wrong: "propor", expected: "proprio"),
            (typed: "caas", wrong: "caos", expected: "casa"),
            (typed: "insime", wrong: "insite", expected: "insieme"),
            (typed: "macchian", wrong: "macchiai", expected: "macchina"),
        ]

        for item in cases {
            XCTAssertEqual(LatinAutocorrectPolicy.editDistance(item.typed, item.wrong), 1)
            XCTAssertEqual(LatinAutocorrectPolicy.editDistance(item.typed, item.expected), 1)
            XCTAssertEqual(
                correction(item.typed, item.expected, language: .italian, guesses: [item.wrong, item.expected]),
                item.expected,
                "frequency rank failed to resolve the measured tie for \(item.typed)"
            )
        }
    }

    func testEnglishRankingRemainsOracleBasedWithoutItalianFrequencyRanks() {
        XCTAssertEqual(
            correction("caas", "caos", language: .english, guesses: ["caos", "casa"]),
            "caos"
        )
    }

    func testPermanentCorpusInventoryTargetsAndNegativeControls() throws {
        let entries = try LatinAutocorrectCorpus.load()
        let italianTypos = entries.filter { $0.kind == .typo && $0.language == .italian }
        let englishTypos = entries.filter { $0.kind == .typo && $0.language == .english }
        let controls = entries.filter { $0.kind == .control }
        XCTAssertGreaterThanOrEqual(italianTypos.count, 60)
        XCTAssertGreaterThanOrEqual(englishTypos.count, 40)
        XCTAssertGreaterThanOrEqual(controls.count, 40)

        for (language, typoEntries) in [
            (LatinAutocorrectPolicy.Language.italian, italianTypos),
            (.english, englishTypos),
        ] {
            var exactCorrections = 0
            for entry in typoEntries {
                let actual = LatinAutocorrectPolicy.correction(
                    forTypedWord: entry.typed,
                    language: entry.language,
                    context: context(beforeWord: entry.contextBeforeWord),
                    spellCheckResult: entry.spellCheckResult
                )
                XCTAssertEqual(actual, entry.expected, "corpus target failed for \(language.rawValue):\(entry.typed)")
                if actual == entry.expected {
                    exactCorrections += 1
                }
            }
            let accuracy = Double(exactCorrections) / Double(typoEntries.count)
            XCTAssertGreaterThanOrEqual(accuracy, 0.80, "\(language.rawValue) deterministic accuracy was \(accuracy)")
        }

        for entry in controls {
            let actual = LatinAutocorrectPolicy.correction(
                forTypedWord: entry.typed,
                language: entry.language,
                context: context(beforeWord: entry.contextBeforeWord),
                spellCheckResult: entry.spellCheckResult
            )
            XCTAssertNil(actual, "negative control \(entry.language.rawValue):\(entry.typed) was changed to \(actual ?? "nil")")
        }
    }

    @MainActor func testSystemSpellCheckerCorpusCampaignGate() throws {
        let available = UITextChecker.availableLanguages
        let normalizedLanguages = Set(available.map {
            $0.replacingOccurrences(of: "_", with: "-").lowercased()
        })
        try XCTSkipUnless(
            normalizedLanguages.contains("it-it") && normalizedLanguages.contains("en-us"),
            "exact it-IT and en-US spell-check dictionaries are both required"
        )

        let entries = try LatinAutocorrectCorpus.load()
        let controls = entries.filter { $0.kind == .control }
        for language in LatinAutocorrectPolicy.Language.allCases {
            let typoEntries = entries.filter { $0.kind == .typo && $0.language == language }
            var exactCorrections = 0
            var misses: [String] = []
            for entry in typoEntries {
                let actual = LatinAutocorrectPolicy.correction(
                    forTypedWord: entry.typed,
                    language: entry.language,
                    context: context(beforeWord: entry.contextBeforeWord)
                )
                if actual == entry.expected {
                    exactCorrections += 1
                } else {
                    misses.append("\(entry.typed)->\(actual ?? "nil") expected \(entry.expected ?? "nil")")
                }
            }
            let accuracy = Double(exactCorrections) / Double(typoEntries.count)
            XCTAssertGreaterThanOrEqual(
                accuracy,
                0.80,
                "\(language.rawValue) system accuracy was \(accuracy); misses: \(misses.joined(separator: ", "))"
            )
        }

        for entry in controls {
            let actual = LatinAutocorrectPolicy.correction(
                forTypedWord: entry.typed,
                language: entry.language,
                context: context(beforeWord: entry.contextBeforeWord)
            )
            XCTAssertNil(actual, "system checker changed negative control \(entry.language.rawValue):\(entry.typed) to \(actual ?? "nil")")
        }
    }
}
