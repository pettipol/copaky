import AzooKeyUtils
import UIKit
import XCTest

// Copaky: cover the pure safety gates used before the converter's accent-fix lookup.
// Copaky: 変換器を呼ぶ前の安全判定を純粋な単体テストで確認する。
final class ItalianAutoAccentPolicyTests: XCTestCase {
    func testSettingContract() {
        XCTAssertTrue(ItalianAutoAccentOnSpace.defaultValue)
        XCTAssertEqual(ItalianAutoAccentOnSpace.key, "italian_auto_accent_on_space")
    }

    func testSentenceStartDetection() {
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: nil))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: ""))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "   "))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao. "))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao!\n"))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao? "))
        XCTAssertTrue(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao… "))
        XCTAssertFalse(ItalianAutoAccentPolicy.isSentenceStart(documentContextBeforeInput: "Ciao "))
    }

    func testCapitalizedWordIsLimitedToSentenceStart() {
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "Sara", documentContextBeforeInput: nil))
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "Sara", documentContextBeforeInput: "Ciao. "))
        XCTAssertFalse(ItalianAutoAccentPolicy.allowsCapitalization(of: "Sara", documentContextBeforeInput: "Ciao "))
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "sara", documentContextBeforeInput: "Ciao "))
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsCapitalization(of: "SARA", documentContextBeforeInput: "Ciao "))
    }

    func testKeyboardTypeGate() {
        for keyboardType: UIKeyboardType in [
            .URL, .emailAddress, .twitter, .namePhonePad, .asciiCapableNumberPad,
            .numberPad, .phonePad, .decimalPad,
        ] {
            XCTAssertFalse(ItalianAutoAccentPolicy.allowsKeyboardType(keyboardType), "Expected \(keyboardType) to be blocked")
        }
        for keyboardType: UIKeyboardType in [.default, .asciiCapable, .numbersAndPunctuation, .webSearch] {
            XCTAssertTrue(ItalianAutoAccentPolicy.allowsKeyboardType(keyboardType), "Expected \(keyboardType) to be allowed")
        }
    }

    // Copaky: fail-closed — ANY declared textContentType disables auto-accent (re-review 2026-08-19).
    func testTextContentTypeGate() {
        XCTAssertTrue(ItalianAutoAccentPolicy.allowsTextContentType(nil))
        for contentType: UITextContentType in [.name, .URL, .emailAddress, .password, .oneTimeCode, .creditCardNumber] {
            XCTAssertFalse(ItalianAutoAccentPolicy.allowsTextContentType(contentType), "\(contentType) must be blocked")
        }
    }

    // Copaky: the fail-closed oracle — valid plain words the bundled lexicon lacks must NOT be flagged,
    // genuine missing-accent misspellings must. Depends on the simulator's Italian dictionary.
    @MainActor func testSystemSpellCheckerOracle() throws {
        try XCTSkipUnless(
            UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("it") }),
            "no Italian spell-check dictionary on this runtime"
        )
        // Copaky: UIKit's treatment of "cosi" varies; H-46 tests its preservation separately.
        // This raw observer must keep reporting the dictionary's actual answer.
        // Copaky:「cosi」のUIKit判定は環境に依存するため、H-46の保持テストと生の辞書判定を分ける。
        for word in ["perche", "piu", "citta", "puo"] {
            XCTAssertTrue(ItalianAutoAccentPolicy.systemFlagsAsMisspelledItalian(word), "\(word) must be flagged")
        }
        for word in ["Sara", "meta", "faro", "pero", "si", "da", "ciao", "perché"] {
            XCTAssertFalse(ItalianAutoAccentPolicy.systemFlagsAsMisspelledItalian(word), "\(word) must not be flagged")
        }
    }

    // Copaky: the second oracle stage — the system's own guesses must contain the exact fix.
    @MainActor func testSystemConfirmsAccentFix() throws {
        try XCTSkipUnless(
            UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("it") }),
            "no Italian spell-check dictionary on this runtime"
        )
        XCTAssertTrue(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "perche", fix: "perché"))
        XCTAssertTrue(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "citta", fix: "città"))
        // Valid words and names are already accepted by the checker → first stage says no.
        XCTAssertFalse(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "Sara", fix: "Sarà"))
        XCTAssertFalse(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "meta", fix: "metà"))
        // A flagged word whose guesses do not contain our candidate must not be replaced.
        XCTAssertFalse(ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: "perche", fix: "città"))
    }

    // Copaky: H-46 preserves the valid plain word even when UIKit proposes an accent.
    // Copaky: H-46ではUIKitがアクセントを提案しても、有効な無アクセント語を保持する。
    @MainActor func testH46DoesNotConfirmAccentForCosi() {
        for (typed, fix) in [("cosi", "così"), ("Cosi", "Così")] {
            XCTAssertFalse(
                ItalianAutoAccentPolicy.systemConfirmsAccentFix(forTyped: typed, fix: fix),
                "H-46: \(typed) must remain unchanged independently of the system dictionary"
            )
        }
    }

    func testH46PlainWordGuardMatchesOnlyCosiIgnoringCase() {
        for word in ["cosi", "Cosi", "COSI", "cOsI"] {
            XCTAssertTrue(ItalianAutoAccentPolicy.shouldPreservePlainWord(word), "\(word) must be preserved")
        }
        for word in ["", "così", "COSÌ", "cósi", " cosi", "cosi ", "cosiddetto", "scosi", "perche", "citta"] {
            XCTAssertFalse(
                ItalianAutoAccentPolicy.shouldPreservePlainWord(word),
                "H-46 must not extend preservation to \(word)"
            )
        }
    }
}
