//
//  BuiltInCustardLocalization.swift
//  Copaky
//
//  Localizes the functional labels of the custards WE ship, at the point where they are built.
//  組み込みカスタードの機能ラベルを、生成時にUI言語へ解決する。
//

import CustardKit
import Foundation

public extension Custard {
    /// Copaky: resolve the Japanese functional labels of a BUILT-IN custard against the string catalog.
    ///
    /// CustardKit bakes 「空白」 and 「全角」 into `flickSpace()`, and our own ErrorCustard is written in
    /// Japanese; those are words the user READS, so they must follow the UI language like every other
    /// functional label. The translation happens HERE, on the custards we ship, and deliberately not at
    /// the `CustardKeyLabelStyle → KeyLabelType` boundary: doing it there would also rename a key that a
    /// user authored or imported — a custom key labelled 「戻る」 that types 「戻る」 would read "Back"
    /// while still typing Japanese. Author-supplied labels stay exactly as authored.
    ///
    /// Only labels in `functionalLabels` are touched, and only when the catalog actually has a
    /// translation: if a language is missing, the Japanese source text is kept.
    ///
    /// Copaky: 組み込みカスタードの日本語の機能ラベルのみをUI言語に解決する。
    /// ユーザーが作成・読み込んだカスタードのラベルは一切変更しない。
    func localizingFunctionalLabels() -> Custard {
        var custard = self
        var interface = custard.interface
        for (position, key) in interface.keys {
            guard case .custom(var customKey) = key else {
                continue
            }
            var changed = false
            if case let .text(label) = customKey.design.label, let localized = Self.localizedFunctionalLabel(label) {
                customKey.design.label = .text(localized)
                changed = true
            }
            for index in customKey.variations.indices {
                if case let .text(label) = customKey.variations[index].key.design.label,
                   let localized = Self.localizedFunctionalLabel(label) {
                    customKey.variations[index].key.design.label = .text(localized)
                    changed = true
                }
            }
            if changed {
                interface.keys[position] = .custom(customKey)
            }
        }
        custard.interface = interface
        return custard
    }

    /// The Japanese functional labels our built-in custards can carry. Characters a key TYPES are not
    /// here and must never be: this list holds words, not input.
    /// 組み込みカスタードが持つ機能ラベル（打鍵される文字は含めない）。
    private static var functionalLabels: Set<String> {
        [
            // CustardKit: flickSpace()
            "空白", "全角", "次候補",
            // Copaky: ErrorCustard
            "カスタードファイルが見つかりません\n正しく読み込めているか確認してください",
            "アプリで確認する", "前のタブに戻る", "ひらがなタブに移動",
        ]
    }

    private static func localizedFunctionalLabel(_ label: String) -> String? {
        guard functionalLabels.contains(label) else {
            return nil
        }
        let localized = String(localized: String.LocalizationValue(label), bundle: .main)
        return localized == label ? nil : localized
    }
}
