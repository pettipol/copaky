//
//  ItalianAutoAccentPolicy.swift
//  AzooKeyUtils
//

import UIKit

// Copaky: pure host-field and capitalization gates for Italian auto-accent, kept outside the
// keyboard extension so the safety decisions have focused unit coverage.
// Copaky: イタリア語アクセント自動補正の入力欄・大文字判定を純粋関数としてテスト可能にする。
public enum ItalianAutoAccentPolicy {
    public static func allowsKeyboardType(_ keyboardType: UIKeyboardType) -> Bool {
        switch keyboardType {
        case .URL, .emailAddress, .twitter, .namePhonePad, .asciiCapableNumberPad,
             .numberPad, .phonePad, .decimalPad:
            return false
        default:
            return true
        }
    }

    // Copaky: content types where an "accent fix" would corrupt data the host expects verbatim —
    // the keyboardType gate alone misses hosts that set only textContentType (counter-review 2026-08-19).
    // Copaky: keyboardType だけでは漏れる URL/メール等の textContentType も除外する。
    public static func allowsTextContentType(_ contentType: UITextContentType?) -> Bool {
        guard let contentType else {
            return true
        }
        let blocked: [UITextContentType] = [
            .URL, .emailAddress, .telephoneNumber, .username, .password, .newPassword, .oneTimeCode,
            .creditCardNumber, .postalCode, .nickname,
        ]
        return !blocked.contains(contentType)
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
        let checker = UITextChecker()
        let range = checker.rangeOfMisspelledWord(
            in: typed,
            range: NSRange(location: 0, length: (typed as NSString).length),
            startingAt: 0,
            wrap: false,
            language: "it_IT"
        )
        return range.location != NSNotFound
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
