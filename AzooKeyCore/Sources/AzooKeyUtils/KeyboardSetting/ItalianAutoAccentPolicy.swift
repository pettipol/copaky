//
//  ItalianAutoAccentPolicy.swift
//  AzooKeyUtils
//

import UIKit

// Copaky: pure host-field and capitalization gates for Italian auto-accent, kept outside the
// keyboard extension so the safety decisions have focused unit coverage.
// Copaky: イタリア語アクセント自動補正の入力欄・大文字判定を純粋関数としてテスト可能にする。
public enum ItalianAutoAccentPolicy {
    // Copaky: one checker instance per keyboard process; each confirmation uses it for both the
    // misspelling range and guesses, avoiding the former double allocation/query on every space.
    // Copaky: 1回の空白確定で同じ checker を誤字判定と候補取得に再利用する。
    @MainActor private static let checker = UITextChecker()

    public static func allowsKeyboardType(_ keyboardType: UIKeyboardType) -> Bool {
        switch keyboardType {
        case .URL, .emailAddress, .twitter, .namePhonePad, .asciiCapableNumberPad,
             .numberPad, .phonePad, .decimalPad:
            return false
        default:
            return true
        }
    }

    // Copaky: FAIL-CLOSED — any structured textContentType (URL, email, codes, dates, card fields,
    // names, flight numbers, …) means the host expects the text verbatim, so auto-accent stays off;
    // free prose fields leave the trait nil. A denylist proved fail-open (re-review 2026-08-19).
    // Copaky: textContentType が設定された欄はすべて除外（fail-closed）。自由文の欄は nil。
    public static func allowsTextContentType(_ contentType: UITextContentType?) -> Bool {
        contentType == nil
    }

    // Copaky: fail-closed oracle — the fix is applied only when the SYSTEM Italian spell checker
    // flags the plain word as misspelled. The bundled 50k-word lexicon cannot tell a valid plain word
    // it simply lacks ("meta", "faro", "pero", "Sara") from a missing accent ("perche", "piu"); the
    // device dictionary can, which is exactly how the system keyboard avoids these corrections.
    // Without an Italian checker on the device nothing is corrected. (counter-review 2026-08-19)
    // Copaky: 端末のイタリア語スペルチェッカーが誤りと判定した語だけ補正する（fail-closed）。
    @MainActor public static func systemFlagsAsMisspelledItalian(_ typed: String) -> Bool {
        guard !typed.isEmpty, UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("it") }) else {
            return false
        }
        let range = checker.rangeOfMisspelledWord(
            in: typed,
            range: NSRange(location: 0, length: (typed as NSString).length),
            startingAt: 0,
            wrap: false,
            language: "it_IT"
        )
        return range.location != NSNotFound
    }

    // Copaky: second half of the fail-closed oracle — the fix is applied only when the system
    // checker not only rejects the plain word but itself SUGGESTS the accented form we would
    // insert. A valid name merely missing from the device dictionary never gets guesses equal to
    // our candidate, which closes the residual path of the 2026-08-19 re-review.
    // Copaky: 端末の校正候補にこちらの補正形が含まれる場合のみ適用（fail-closed の後段）。
    @MainActor public static func systemConfirmsAccentFix(forTyped typed: String, fix: String) -> Bool {
        guard !typed.isEmpty, UITextChecker.availableLanguages.contains(where: { $0.hasPrefix("it") }) else {
            return false
        }
        let range = NSRange(location: 0, length: (typed as NSString).length)
        let misspelledRange = checker.rangeOfMisspelledWord(
            in: typed,
            range: range,
            startingAt: 0,
            wrap: false,
            language: "it_IT"
        )
        guard misspelledRange.location != NSNotFound else {
            return false
        }
        let guesses = checker.guesses(forWordRange: range, in: typed, language: "it_IT") ?? []
        let locale = Locale(identifier: "it_IT")
        return guesses.contains { $0.compare(fix, options: [.caseInsensitive], range: nil, locale: locale) == .orderedSame }
    }

    public static func isSentenceStart(documentContextBeforeInput context: String?) -> Bool {
        guard let context else {
            return true
        }

        var trimmedTail = context[...]
        var trailingWhitespaceContainsNewline = false
        while let last = trimmedTail.last, last.isWhitespace {
            trailingWhitespaceContainsNewline = trailingWhitespaceContainsNewline || last == "\n" || last == "\r"
            trimmedTail.removeLast()
        }
        if trailingWhitespaceContainsNewline || trimmedTail.isEmpty {
            return true
        }
        return trimmedTail.last.map { ".!?…".contains($0) } ?? true
    }

    public static func allowsCapitalization(of typed: String, documentContextBeforeInput context: String?) -> Bool {
        guard typed.first?.isUppercase == true, typed.contains(where: \.isLowercase) else {
            return true
        }
        return isSentenceStart(documentContextBeforeInput: context)
    }
}
