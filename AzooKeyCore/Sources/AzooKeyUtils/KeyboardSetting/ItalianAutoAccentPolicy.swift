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
