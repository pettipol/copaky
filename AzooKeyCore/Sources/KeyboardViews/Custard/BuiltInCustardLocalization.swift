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
        // Copaky: JAPANESE tabs keep their Japanese layout labels (空白/全角/次候補) whatever the
        // UI language — Apple's own JP layouts do the same, and on the space key it is the visual
        // cue that the key CONVERTS instead of inserting a space (the Latin tabs look identical
        // otherwise). Error/navigation messages still follow the UI language everywhere.
        // 日本語タブの空白・次候補などは常に日本語（変換動作の目印）。案内文はUI言語に追従。
        let keepLayoutLabels = self.language == .ja_JP
        var custard = self
        var interface = custard.interface
        for (position, key) in interface.keys {
            guard case .custom(var customKey) = key else {
                continue
            }
            var changed = false
            if case let .text(label) = customKey.design.label,
               let localized = Self.localizedFunctionalLabel(label, keepLayoutLabels: keepLayoutLabels) {
                customKey.design.label = .text(localized)
                changed = true
            }
            for index in customKey.variations.indices {
                if case let .text(label) = customKey.variations[index].key.design.label,
                   let localized = Self.localizedFunctionalLabel(label, keepLayoutLabels: keepLayoutLabels) {
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

    /// Layout labels from CustardKit's `flickSpace()` — kept Japanese on Japanese tabs.
    /// 配列ラベル（日本語タブでは日本語のまま）。
    private static var layoutLabels: Set<String> {
        ["空白", "全角", "次候補"]
    }

    /// The Japanese functional labels our built-in custards can carry. Characters a key TYPES are not
    /// here and must never be: this list holds words, not input.
    /// 組み込みカスタードが持つ機能ラベル（打鍵される文字は含めない）。
    private static var functionalLabels: Set<String> {
        layoutLabels.union([
            // Copaky: ErrorCustard
            "カスタードファイルが見つかりません\n正しく読み込めているか確認してください",
            "アプリで確認する", "前のタブに戻る", "ひらがなタブに移動",
        ])
    }

    private static func localizedFunctionalLabel(_ label: String, keepLayoutLabels: Bool) -> String? {
        guard functionalLabels.contains(label) else {
            return nil
        }
        if keepLayoutLabels && layoutLabels.contains(label) {
            return nil
        }
        let localized = String(localized: String.LocalizationValue(label), bundle: .main)
        return localized == label ? nil : localized
    }
}
