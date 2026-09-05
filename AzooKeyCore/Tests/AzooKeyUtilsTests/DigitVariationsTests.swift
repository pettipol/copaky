import enum KanaKanjiConverterModule.KeyboardLanguage
import XCTest
@testable import AzooKeyUtils
@testable import KeyboardViews

// Copaky [G-05]: verify the production layouts instead of exposing the private variation table.
final class DigitVariationsTests: XCTestCase {
    @MainActor
    private func variationTexts(for language: KeyboardLanguage) -> [String: [String]] {
        let suiteName = "DigitVariationsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let states = VariableStates(
            clipboardHistoryManagerConfig: ClipboardHistoryManagerConfig(),
            tabManagerConfig: TabManagerConfig(),
            userDefaults: defaults
        )
        states.keyboardLanguage = language
        let layout = QwertyLayoutProvider<AzooKeyKeyboardViewExtension>.abcKeyboard(language: language)

        return Dictionary(uniqueKeysWithValues: QwertyNumberRowLayoutDecision.digits.enumerated().map { index, digit in
            let position = UnifiedPositionSpecifier(x: CGFloat(index), y: 0)
            guard let model = layout[position] else {
                XCTFail("Missing real digit key \(digit) for \(language)")
                return (digit, [])
            }
            let labels = model.getLinearVariations(variableStates: states).arr.compactMap { element in
                if case let .text(text) = element.label {
                    return text
                }
                return nil
            }
            return (digit, labels)
        })
    }

    @MainActor
    func testEveryLanguageExposesTenUniqueDigitVariationSets() {
        let previousValue = EnableQwertyNumberRow.get()
        defer {
            if let previousValue {
                EnableQwertyNumberRow.value = previousValue
            } else {
                SharedStore.userDefaults.removeObject(forKey: EnableQwertyNumberRow.key)
            }
        }
        EnableQwertyNumberRow.value = true

        let expectedCommon = [
            "1": ["¹", "½", "⅓", "¼"],
            "2": ["²", "⅔"],
            "3": ["³", "¾"],
            "4": ["⁴"],
            "5": ["⁵"],
            "6": ["⁶"],
            "7": ["⁷"],
            "8": ["⁸"],
            "9": ["⁹"],
            "0": ["°", "⁰"],
        ]
        let commonLanguages: [KeyboardLanguage] = [.en_US, .it_IT, .el_GR, .none]
        for language in commonLanguages {
            let variations = variationTexts(for: language)
            XCTAssertEqual(Set(variations.keys), Set(QwertyNumberRowLayoutDecision.digits))
            XCTAssertEqual(variations, expectedCommon, "\(language) must expose the exact common digit-variation table")
            for (digit, labels) in variations {
                XCTAssertFalse(labels.isEmpty, "\(language) digit \(digit) must expose at least one variant")
                XCTAssertEqual(Set(labels).count, labels.count, "\(language) digit \(digit) has duplicate variants")
            }
            XCTAssertTrue(variations["1", default: []].contains("½"))
        }

        let japanese = variationTexts(for: .ja_JP)
        XCTAssertEqual(Set(japanese.keys), Set(QwertyNumberRowLayoutDecision.digits))
        for (index, digit) in QwertyNumberRowLayoutDecision.digits.enumerated() {
            let labels = japanese[digit, default: []]
            XCTAssertFalse(labels.isEmpty, "Japanese digit \(digit) must expose at least one variant")
            XCTAssertEqual(Set(labels).count, labels.count, "Japanese digit \(digit) has duplicate variants")
            XCTAssertEqual(labels.first, ["１", "２", "３", "４", "５", "６", "７", "８", "９", "０"][index])
            XCTAssertEqual(
                Array(labels.dropFirst()),
                expectedCommon[digit, default: []],
                "Japanese digit \(digit) must prepend its full-width form to the exact common variants"
            )
        }
    }
}
