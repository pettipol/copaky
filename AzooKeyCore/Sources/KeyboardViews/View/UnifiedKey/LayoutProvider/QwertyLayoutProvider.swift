import CustardKit
import Foundation
import enum KanaKanjiConverterModule.KeyboardLanguage

// Copaky: optional number hints on the QWERTY top row / QWERTY最上段の数字ヒント（長押しで入力）
private let qwertyTopRowDigits: [String: String] = [
    "q": "1", "w": "2", "e": "3", "r": "4", "t": "5",
    "y": "6", "u": "7", "i": "8", "o": "9", "p": "0",
]

struct QwertyLayoutProvider<Extension: ApplicationSpecificKeyboardViewExtension> {
    typealias Layout = [UnifiedPositionSpecifier: any UnifiedKeyModelProtocol<Extension>]

    enum ShiftBehaviorPreference {
        case left
        case leftbottom
        case off
    }
    @MainActor private static func spaceKey() -> any UnifiedKeyModelProtocol<Extension> {
        Extension.SettingProvider.useNextCandidateKey
            ? QwertyNextCandidateKeyModel<Extension>()
            : QwertySpaceKeyModel<Extension>()
    }
    @MainActor static func shiftBehaviorPreference() -> ShiftBehaviorPreference {
        if #available(iOS 18, *) {
            // iOS 18+ uses new behavior: bottom-left shift when enabled
            return Extension.SettingProvider.useShiftKey ? .leftbottom : .off
        } else {
            if Extension.SettingProvider.useShiftKey {
                return Extension.SettingProvider.keepDeprecatedShiftKeyBehavior ? .left : .leftbottom
            } else {
                return .off
            }
        }
    }
    @MainActor private static func tabKeys() -> (
        languageKey: any UnifiedKeyModelProtocol<Extension>,
        numbersKey: any UnifiedKeyModelProtocol<Extension>,
        symbolsKey: any UnifiedKeyModelProtocol<Extension>,
        changeKeyboardKey: any UnifiedKeyModelProtocol<Extension>
    ) {
        // language key
        let languageKey: any UnifiedKeyModelProtocol<Extension> = QwertyLanguageSwitchKeyModel<Extension>(languages: (.ja_JP, .en_US))
        // numbers key
        let numbersKey: any UnifiedKeyModelProtocol<Extension> = QwertyGeneralKeyModel(
            labelType: .image("textformat.123"),
            pressActions: { _ in [.moveTab(.system(.qwerty_numbers))] },
            longPressActions: { states in
                .init(start: NumbersSlotLongPressDecision.longPressActionsForNumbersSlot(
                    clipboardHistoryEnabled: states.keyboardLanguage.usesLatinScript
                        && states.clipboardHistoryManager.isEnabled
                ))
            },
            variations: [], direction: .right, showsTapBubble: false, role: .special
        )
        // symbols key
        let symbolsKey: any UnifiedKeyModelProtocol<Extension> = QwertyGeneralKeyModel(
            labelType: .text("#+="),
            pressActions: { _ in [.moveTab(.system(.qwerty_symbols))] },
            longPressActions: { states in
                .init(start: NumbersSlotLongPressDecision.longPressActionsForNumbersSlot(
                    clipboardHistoryEnabled: states.keyboardLanguage.usesLatinScript
                        && states.clipboardHistoryManager.isEnabled
                ))
            },
            variations: [], direction: .right, showsTapBubble: false, role: .special
        )
        // change keyboard key (dynamic)
        let changeKeyboardKey: any UnifiedKeyModelProtocol<Extension> = QwertyDynamicChangeKeyModel<Extension>()
        return (languageKey, numbersKey, symbolsKey, changeKeyboardKey)
    }

    // Copaky: Latin symbol tabs use verbatim labels whose tap action inputs the same character.
    // Copaky: ラテン記号タブは表示文字とタップ入力を必ず一致させる。
    @MainActor private static func latinInputKey(
        _ label: String,
        variations: [String] = [],
        direction: VariationsViewDirection = .right
    ) -> any UnifiedKeyModelProtocol<Extension> {
        let variationModels = variations.map {
            QwertyVariationsModel.VariationElement(label: .text($0), actions: [.input($0)])
        }
        return QwertyGeneralKeyModel(
            labelType: .text(label),
            pressActions: { _ in [.input(label)] },
            longPressActions: { _ in .none },
            variations: variationModels,
            direction: direction,
            showsTapBubble: !variationModels.isEmpty,
            role: .normal
        )
    }

    @MainActor private static func latinDeleteKey() -> any UnifiedKeyModelProtocol<Extension> {
        QwertyGeneralKeyModel(
            labelType: .image("delete.left"),
            pressActions: { _ in [.delete(1)] },
            longPressActions: { _ in .init(repeat: [.delete(1)]) },
            variations: [], direction: .right, showsTapBubble: false, role: .special
        )
    }

    @MainActor private static func appendLatinPunctuationRow(
        to dict: inout Layout,
        leadingKey: any UnifiedKeyModelProtocol<Extension>
    ) {
        dict[.init(x: 0, y: 2, width: 1.4)] = leadingKey
        let punctuation: [(label: String, variations: [String])] = [
            (".", [".", "…"]),
            (",", [",", "‚"]),
            ("?", ["?", "¿"]),
            ("!", ["!", "¡"]),
            ("'", ["'", "‘", "’", "‚"]),
        ]
        for (index, key) in punctuation.enumerated() {
            dict[.init(x: 1.5 + Double(index) * 1.4, y: 2, width: 1.4)] = latinInputKey(
                key.label,
                variations: key.variations,
                direction: .center
            )
        }
        dict[.init(x: 8.6, y: 2, width: 1.4)] = latinDeleteKey()
    }

    @MainActor private static func appendLatinBottomRow(
        to dict: inout Layout,
        enterKey: any UnifiedKeyModelProtocol<Extension>
    ) {
        let tabs = tabKeys()
        dict[.init(x: 0, y: 3, width: 1.4)] = tabs.languageKey
        dict[.init(x: 1.4, y: 3, width: 1.4)] = tabs.changeKeyboardKey
        dict[.init(x: 2.8, y: 3, width: 4.4)] = spaceKey()
        dict[.init(x: 7.2, y: 3, width: 2.8)] = enterKey
    }

    // Copaky: Build language-less number tabs on demand from the preserved typing language.
    // Copaky: 言語なし数字タブを保持中の入力言語から動的に構築する。
    @MainActor static func numberKeyboard(language: KeyboardLanguage) -> Layout {
        if language.usesLatinScript {
            return latinNumberKeyboard(language: language)
        }
        return japaneseNumberKeyboard
    }

    @MainActor private static var japaneseNumberKeyboard: Layout {
        func uniKey(label: KeyLabelType, press: [ActionType], vars: [QwertyVariationsModel.VariationElement], dir: VariationsViewDirection = .center, showsBubble: Bool = true, role: QwertyGeneralKeyModel<Extension>.UnpressedRole = .normal) -> any UnifiedKeyModelProtocol<Extension> {
            QwertyGeneralKeyModel<Extension>(
                labelType: label,
                pressActions: { _ in press },
                longPressActions: { _ in .none },
                variations: vars,
                direction: dir,
                showsTapBubble: showsBubble,
                role: role
            )
        }
        func v(_ s: String) -> QwertyVariationsModel.VariationElement { .init(label: .text(s), actions: [.input(s)]) }
        var dict: [UnifiedPositionSpecifier: any UnifiedKeyModelProtocol<Extension>] = [:]
        // Top row: 1..0 with common variations
        dict[.init(x: 0, y: 0)] = uniKey(label: .text("1"), press: [.input("1")], vars: [v("1"), v("１"), v("一"), v("①")], dir: .right)
        dict[.init(x: 1, y: 0)] = uniKey(label: .text("2"), press: [.input("2")], vars: [v("2"), v("２"), v("二"), v("②")], dir: .right)
        dict[.init(x: 2, y: 0)] = uniKey(label: .text("3"), press: [.input("3")], vars: [v("3"), v("３"), v("三"), v("③")])
        dict[.init(x: 3, y: 0)] = uniKey(label: .text("4"), press: [.input("4")], vars: [v("4"), v("４"), v("四"), v("④")])
        dict[.init(x: 4, y: 0)] = uniKey(label: .text("5"), press: [.input("5")], vars: [v("5"), v("５"), v("五"), v("⑤")])
        dict[.init(x: 5, y: 0)] = uniKey(label: .text("6"), press: [.input("6")], vars: [v("6"), v("６"), v("六"), v("⑥")])
        dict[.init(x: 6, y: 0)] = uniKey(label: .text("7"), press: [.input("7")], vars: [v("7"), v("７"), v("七"), v("⑦")])
        dict[.init(x: 7, y: 0)] = uniKey(label: .text("8"), press: [.input("8")], vars: [v("8"), v("８"), v("八"), v("⑧")])
        dict[.init(x: 8, y: 0)] = uniKey(label: .text("9"), press: [.input("9")], vars: [v("9"), v("９"), v("九"), v("⑨")], dir: .left)
        dict[.init(x: 9, y: 0)] = uniKey(label: .text("0"), press: [.input("0")], vars: [v("0"), v("０"), v("〇"), v("⓪")], dir: .left)

        // 2nd row (legacy parity)
        dict[.init(x: 0, y: 1)] = uniKey(label: .text("-"), press: [.input("-")], vars: [])
        dict[.init(x: 1, y: 1)] = uniKey(label: .text("/"), press: [.input("/")], vars: [v("/"), v("\\")])
        dict[.init(x: 2, y: 1)] = uniKey(label: .text(":"), press: [.input(":")], vars: [v(":"), v("："), v(";"), v("；")])
        dict[.init(x: 3, y: 1)] = uniKey(label: .text("@"), press: [.input("@")], vars: [v("@"), v("＠")])
        dict[.init(x: 4, y: 1)] = uniKey(label: .text("("), press: [.input("(")], vars: [])
        dict[.init(x: 5, y: 1)] = uniKey(label: .text(")"), press: [.input(")")], vars: [])
        dict[.init(x: 6, y: 1)] = uniKey(label: .text("「"), press: [.input("「")], vars: [v("「"), v("『"), v("【"), v("（"), v("《")])
        dict[.init(x: 7, y: 1)] = uniKey(label: .text("」"), press: [.input("」")], vars: [v("」"), v("』"), v("】"), v("）"), v("》")])
        dict[.init(x: 8, y: 1)] = uniKey(label: .text("¥"), press: [.input("¥")], vars: [v("¥"), v("￥"), v("$"), v("＄"), v("€"), v("₿"), v("£"), v("¤")], dir: .left)
        dict[.init(x: 9, y: 1)] = uniKey(label: .text("&"), press: [.input("&")], vars: [v("&"), v("＆")], dir: .left)

        // 3rd row: symbols key + punctuation cluster + delete
        dict[.init(x: 0, y: 2, width: 1.4)] = tabKeys().symbolsKey
        // Middle cluster: custom keys if provided (variable count), otherwise fixed 5-slot defaults
        do {
            let defaults = [
                (name: ".", actions: [ActionType.input(".")], vars: [".", ",", "!", "?", "'", "\""] as [String]),
                (name: ",", actions: [ActionType.input(",")], vars: [] as [String]),
                (name: "?", actions: [ActionType.input("?")], vars: [] as [String]),
                (name: "!", actions: [ActionType.input("!")], vars: [] as [String]),
                (name: "…", actions: [ActionType.input("…")], vars: [] as [String]),
            ]
            let custom = Extension.SettingProvider.numberTabCustomKeysSetting.keys
            if !custom.isEmpty {
                let count = custom.count
                let w = 7.0 / Double(count)
                for (i, k) in custom.enumerated() {
                    let x = 1.5 + Double(i) * w
                    let vars = k.longpresses.map { QwertyVariationsModel.VariationElement(label: .text($0.name), actions: $0.actions.map { $0.actionType }) }
                    dict[.init(x: x, y: 2, width: w)] = QwertyGeneralKeyModel(
                        labelType: .text(k.name),
                        pressActions: { _ in k.actions.map { $0.actionType } },
                        longPressActions: { _ in .none },
                        variations: vars,
                        direction: .center,
                        showsTapBubble: !vars.isEmpty,
                        role: .normal
                    )
                }
            } else {
                for (i, d) in defaults.enumerated() {
                    let x = 1.5 + Double(i) * (7.0 / 5.0)
                    let vars = d.vars.map { QwertyVariationsModel.VariationElement(label: .text($0), actions: [.input($0)]) }
                    dict[.init(x: x, y: 2, width: 7.0 / 5.0)] = QwertyGeneralKeyModel(
                        labelType: .text(d.name),
                        pressActions: { _ in d.actions },
                        longPressActions: { _ in .none },
                        variations: vars,
                        direction: .center,
                        showsTapBubble: !vars.isEmpty,
                        role: .normal
                    )
                }
            }
        }
        dict[.init(x: 8.6, y: 2, width: 1.4, height: 1)] = QwertyGeneralKeyModel<Extension>(
            labelType: .image("delete.left"),
            pressActions: { _ in [.delete(1)] },
            longPressActions: { _ in .init(repeat: [.delete(1)]) },
            variations: [], direction: .right, showsTapBubble: false, role: .special
        )

        // 4th row: bottom controls (language and dynamic change)
        let tabs = tabKeys()
        dict[.init(x: 0, y: 3, width: 1.4)] = tabs.languageKey
        dict[.init(x: 1.4, y: 3, width: 1.4)] = tabs.changeKeyboardKey
        dict[.init(x: 2.8, y: 3, width: 4.4)] = spaceKey()
        dict[.init(x: 7.2, y: 3, width: 2.8)] = UnifiedEnterKeyModel<Extension>(textSize: .small)

        return dict
    }

    // Copaky: Match the system keyboard's Latin number layout; EN uses $, IT uses €.
    // Copaky: システム配列に合わせ、英語は$、イタリア語は€を表示する。
    @MainActor private static func latinNumberKeyboard(language: KeyboardLanguage) -> Layout {
        var dict: Layout = [:]
        for (index, label) in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].enumerated() {
            dict[.init(x: Double(index), y: 0)] = latinInputKey(
                label,
                direction: index < 8 ? .right : .left
            )
        }

        let currency = language == .it_IT ? "€" : "$"
        let secondRow: [(label: String, variations: [String])] = [
            ("-", ["-", "–", "—", "•"]),
            ("/", ["/", "\\"]),
            (":", []),
            (";", []),
            ("(", []),
            (")", []),
            (currency, [currency, currency == "€" ? "$" : "€", "£", "¥"]),
            ("&", []),
            ("@", []),
            ("\"", ["\"", "“", "”", "„"]),
        ]
        for (index, key) in secondRow.enumerated() {
            dict[.init(x: Double(index), y: 1)] = latinInputKey(
                key.label,
                variations: key.variations,
                direction: index < 8 ? .right : .left
            )
        }

        appendLatinPunctuationRow(to: &dict, leadingKey: tabKeys().symbolsKey)
        appendLatinBottomRow(
            to: &dict,
            enterKey: UnifiedEnterKeyModel<Extension>(textSize: .small)
        )
        return dict
    }

    @MainActor static func hiraKeyboard() -> [UnifiedPositionSpecifier: any UnifiedKeyModelProtocol<Extension>] {
        func key(_ x: Double, _ y: Double, _ t: String) -> (UnifiedPositionSpecifier, any UnifiedKeyModelProtocol<Extension>) {
            (.init(x: x, y: y), QwertyGeneralKeyModel(labelType: .text(t), pressActions: { _ in [.input(t)] }, longPressActions: { _ in .none }, variations: [], direction: .right, showsTapBubble: true, role: .normal))
        }
        func barKey() -> any UnifiedKeyModelProtocol<Extension> {
            QwertyGeneralKeyModel(
                labelType: .text("ー"),
                pressActions: { _ in [.input("ー")] },
                longPressActions: { _ in .none },
                variations: [
                    .init(label: .text("ー"), actions: [.input("ー")]),
                    .init(label: .text("。"), actions: [.input("。")]),
                    .init(label: .text("、"), actions: [.input("、")]),
                    .init(label: .text("！"), actions: [.input("！")]),
                    .init(label: .text("？"), actions: [.input("？")]),
                    .init(label: .text("・"), actions: [.input("・")]),
                ],
                direction: .left,
                showsTapBubble: true,
                role: .normal
            )
        }
        var dict: [UnifiedPositionSpecifier: any UnifiedKeyModelProtocol<Extension>] = [:]
        // Row 0 (digit leads the long-press variations when number hints are on)
        let numberHints = Extension.SettingProvider.enableNumberRowHints
        for (i, c) in ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"].enumerated() {
            if numberHints, let digit = qwertyTopRowDigits[c] {
                let direction: VariationsViewDirection = i < 5 ? .right : .left
                dict[.init(x: Double(i), y: 0)] = QwertyGeneralKeyModel(
                    labelType: .textWithUpperHint(c, digit),
                    pressActions: { _ in [.input(c)] },
                    longPressActions: { _ in .none },
                    variations: [.init(label: .text(digit), actions: [.input(digit)])],
                    direction: direction,
                    showsTapBubble: true,
                    role: .normal
                )
            } else {
                let (pos, mdl) = key(Double(i), 0, c)
                dict[pos] = mdl
            }
        }
        // Row 1 letters + bar key at end
        for (i, c) in ["a", "s", "d", "f", "g", "h", "j", "k", "l"].enumerated() {
            let (pos, mdl) = key(Double(i), 1, c)
            dict[pos] = mdl
        }
        dict[.init(x: 9, y: 1)] = barKey()

        // Row 2: language key at left, then letters, and delete
        let tabs = tabKeys()
        dict[.init(x: 0, y: 2, width: 1.4)] = tabs.languageKey
        for (i, c) in ["z", "x", "c", "v", "b", "n", "m"].enumerated() {
            let (pos, mdl) = key(1.5 + Double(i), 2, c)
            dict[pos] = mdl
        }
        dict[.init(x: 8.6, y: 2, width: 1.4)] = QwertyGeneralKeyModel(
            labelType: .image("delete.left"), pressActions: { _ in [.delete(1)] }, longPressActions: { _ in .init(repeat: [.delete(1)]) }, variations: [], direction: .right, showsTapBubble: false, role: .special
        )

        // Row 3: hiragana layout never shows Shift; always numbers key at left
        dict[.init(x: 0, y: 3, width: 1.4)] = tabs.numbersKey
        dict[.init(x: 1.4, y: 3, width: 1.4)] = tabs.changeKeyboardKey
        dict[.init(x: 2.8, y: 3, width: 4.4)] = spaceKey()
        dict[.init(x: 7.2, y: 3, width: 2.8)] = UnifiedEnterKeyModel<Extension>(textSize: .small)
        return dict
    }

    @MainActor static func abcKeyboard() -> [UnifiedPositionSpecifier: any UnifiedKeyModelProtocol<Extension>] {
        func key(_ x: Double, _ y: Double, _ t: String) -> (UnifiedPositionSpecifier, any UnifiedKeyModelProtocol<Extension>) {
            (.init(x: x, y: y), QwertyGeneralKeyModel(labelType: .text(t), pressActions: { _ in [.input(t)] }, longPressActions: { _ in .none }, variations: [], direction: .right, showsTapBubble: true, role: .normal))
        }
        // Copaky: Western-European accent variations on long-press / 長押しでアクセント記号入力（Copaky 拡張）
        func v(_ s: String) -> QwertyVariationsModel.VariationElement { .init(label: .text(s), actions: [.input(s)]) }
        func keyWithVariations(_ x: Double, _ y: Double, _ t: String, variations: [String], direction: VariationsViewDirection) -> (UnifiedPositionSpecifier, any UnifiedKeyModelProtocol<Extension>) {
            (.init(x: x, y: y), QwertyGeneralKeyModel(labelType: .text(t), pressActions: { _ in [.input(t)] }, longPressActions: { _ in .none }, variations: variations.map(v), direction: direction, showsTapBubble: true, role: .normal))
        }
        let accentVariations: [String: (variations: [String], direction: VariationsViewDirection)] = [
            "e": (["è", "é", "ê", "ë"], .right),
            "u": (["ù", "ú", "û", "ü"], .left),
            "i": (["ì", "í", "î", "ï"], .left),
            "o": (["ò", "ó", "ô", "ö", "õ"], .left),
            "a": (["à", "á", "â", "ä", "ã"], .right),
            "n": (["ñ"], .left),
            "c": (["ç"], .right),
        ]
        func accentKey(_ x: Double, _ y: Double, _ t: String) -> (UnifiedPositionSpecifier, any UnifiedKeyModelProtocol<Extension>) {
            if let accent = accentVariations[t] {
                return keyWithVariations(x, y, t, variations: accent.variations, direction: accent.direction)
            }
            return key(x, y, t)
        }
        // Copaky: with number hints on, the digit leads the long-press variations and shows above the letter
        // 数字ヒントON時は長押しバリエーションの先頭に数字を置き、キー上部に小さく表示する（アクセント記号は数字の後ろに残る）
        func topRowKey(_ x: Double, _ t: String) -> (UnifiedPositionSpecifier, any UnifiedKeyModelProtocol<Extension>) {
            guard Extension.SettingProvider.enableNumberRowHints, let digit = qwertyTopRowDigits[t] else {
                return accentKey(x, 0, t)
            }
            let accent = accentVariations[t]
            let direction = accent?.direction ?? (x < 5 ? VariationsViewDirection.right : .left)
            let variations = [digit] + (accent?.variations ?? [])
            return (.init(x: x, y: 0), QwertyGeneralKeyModel(labelType: .textWithUpperHint(t, digit), pressActions: { _ in [.input(t)] }, longPressActions: { _ in .none }, variations: variations.map(v), direction: direction, showsTapBubble: true, role: .normal))
        }
        func dotKey() -> any UnifiedKeyModelProtocol<Extension> {
            QwertyGeneralKeyModel(
                labelType: .text("."),
                pressActions: { _ in [.input(".")] },
                longPressActions: { _ in .none },
                variations: [
                    .init(label: .text("."), actions: [.input(".")]),
                    .init(label: .text(","), actions: [.input(",")]),
                    .init(label: .text("!"), actions: [.input("!")]),
                    .init(label: .text("?"), actions: [.input("?")]),
                    .init(label: .text("'"), actions: [.input("'")]),
                    .init(label: .text("\""), actions: [.input("\"")]),
                ],
                direction: .left,
                showsTapBubble: true,
                role: .normal
            )
        }
        var dict: [UnifiedPositionSpecifier: any UnifiedKeyModelProtocol<Extension>] = [:]
        // Row 0
        for (i, c) in ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"].enumerated() {
            let (pos, mdl) = topRowKey(Double(i), c)
            dict[pos] = mdl
        }
        // Row 1 core letters
        let core = ["a", "s", "d", "f", "g", "h", "j", "k", "l"].enumerated()
        let shiftBehavior = shiftBehaviorPreference()
        switch shiftBehavior {
        case .leftbottom:
            // No shift on row1; place core letters and dot key at end
            for (i, c) in core {
                let (pos, mdl) = accentKey(Double(i), 1, c)
                dict[pos] = mdl
            }
            dict[.init(x: 9, y: 1)] = dotKey()
        case .left:
            dict[.init(x: 0, y: 1)] = QwertyShiftKeyModel<Extension>()
            for (i, c) in core {
                let (pos, mdl) = accentKey(Double(i + 1), 1, c)
                dict[pos] = mdl
            }
        case .off:
            for (i, c) in core {
                let (pos, mdl) = accentKey(Double(i), 1, c)
                dict[pos] = mdl
            }
            dict[.init(x: 9, y: 1)] = QwertyAaKeyModel<Extension>()
        }
        // Row 2: language key at left, then letters, and delete
        let tabsAbc = tabKeys()
        dict[.init(x: 0, y: 2, width: 1.4)] = tabsAbc.languageKey
        for (i, c) in ["z", "x", "c", "v", "b", "n", "m"].enumerated() {
            let (pos, mdl) = accentKey(1.5 + Double(i), 2, c)
            dict[pos] = mdl
        }
        dict[.init(x: 8.6, y: 2, width: 1.4)] = QwertyGeneralKeyModel(
            labelType: .image("delete.left"),
            pressActions: { _ in [.delete(1)] },
            longPressActions: { _ in .init(repeat: [.delete(1)]) },
            variations: [], direction: .right, showsTapBubble: false, role: .special
        )
        // Row 3: numbers or shift at left, and dynamic change key next
        switch shiftBehavior {
        case .leftbottom:
            dict[.init(x: 0, y: 3, width: 1.4)] = QwertyShiftKeyModel<Extension>()
        default:
            dict[.init(x: 0, y: 3, width: 1.4)] = tabsAbc.numbersKey
        }
        dict[.init(x: 1.4, y: 3, width: 1.4)] = tabsAbc.changeKeyboardKey
        switch shiftBehavior {
        case .leftbottom:
            dict[.init(x: 2.8, y: 3, width: 4.4)] = spaceKey()
        case .left, .off:
            // Copaky: Shift/Aa occupies row 1, so keep punctuation beside Return and narrow Space.
            // Copaky: Shift/Aa使用時は句点をReturn左に置き、Spaceを狭める。
            dict[.init(x: 2.8, y: 3, width: 3.4)] = spaceKey()
            dict[.init(x: 6.2, y: 3)] = dotKey()
        }
        dict[.init(x: 7.2, y: 3, width: 2.8)] = UnifiedEnterKeyModel<Extension>(textSize: .small)
        return dict
    }

    // Copaky: Build language-less symbol tabs on demand from the preserved typing language.
    // Copaky: 言語なし記号タブを保持中の入力言語から動的に構築する。
    @MainActor static func symbolsKeyboard(language: KeyboardLanguage) -> Layout {
        if language.usesLatinScript {
            return latinSymbolsKeyboard(language: language)
        }
        return japaneseSymbolsKeyboard()
    }

    @MainActor private static func japaneseSymbolsKeyboard() -> Layout {
        func uni(_ x: Double, _ y: Double, _ label: String, vars: [String] = [], dir: VariationsViewDirection = .right) -> (UnifiedPositionSpecifier, any UnifiedKeyModelProtocol<Extension>) {
            let v = vars.map { QwertyVariationsModel.VariationElement(label: .text($0), actions: [.input($0)]) }
            return (.init(x: x, y: y), QwertyGeneralKeyModel(labelType: .text(label), pressActions: { _ in [.input(label)] }, longPressActions: { _ in .none }, variations: v, direction: dir, showsTapBubble: !v.isEmpty, role: .normal))
        }
        var dict: [UnifiedPositionSpecifier: any UnifiedKeyModelProtocol<Extension>] = [:]
        // Row 0
        for (i, spec) in [
            ("[", ["［"]), ("]", ["］"]), ("{", ["｛"]), ("}", ["｝"]), ("#", ["＃"]), ("%", ["％"]), ("^", ["＾"]), ("*", ["＊"]), ("+", ["＋", "±"]), ("=", ["＝", "≡", "≒", "≠"])].enumerated() {
            let (pos, mdl) = uni(Double(i), 0, spec.0, vars: spec.1, dir: i == 9 ? .left : .right)
            dict[pos] = mdl
        }
        // Row 1
        let row1 = [
            (0.0, "_", []), (1.0, "\\", ["/", "\\"]), (2.0, ";", [":", "：", ";", "；"]), (3.0, "|", ["｜"]), (4.0, "<", ["＜"]), (5.0, ">", ["＞"]), (6.0, "\"", ["＂", "“", "”"]), (7.0, "'", ["`"]), (8.0, "$", ["＄"]), (9.0, "€", ["¥", "￥", "$", "＄", "€", "₿", "£", "¤"]) ]
        for item in row1 {
            let (pos, mdl) = uni(item.0, 1, item.1, vars: item.2, dir: item.0 == 9.0 ? .left : .right)
            dict[pos] = mdl
        }
        // Row 2: numbers key at left, then fixed 5-slot punctuation cluster with width 7/5
        let tabs = tabKeys()
        dict[.init(x: 0, y: 2, width: 1.4)] = tabs.numbersKey
        let punctSpecs: [(String, [String])] = [
            (".", ["。", "."]),
            (",", ["、", ","]),
            ("?", ["？", "?"]),
            ("!", ["！", "!"]),
            ("…", []),
        ]
        for (i, spec) in punctSpecs.enumerated() {
            let x = 1.5 + Double(i) * (7.0 / 5.0)
            let vars = spec.1.map { QwertyVariationsModel.VariationElement(label: .text($0), actions: [.input($0)]) }
            dict[.init(x: x, y: 2, width: 7.0 / 5.0)] = QwertyGeneralKeyModel(labelType: .text(spec.0), pressActions: { _ in [.input(spec.0)] }, longPressActions: { _ in .none }, variations: vars, direction: .center, showsTapBubble: !vars.isEmpty, role: .normal)
        }
        dict[.init(x: 8.6, y: 2, width: 1.4)] = QwertyGeneralKeyModel(labelType: .image("delete.left"), pressActions: { _ in [.delete(1)] }, longPressActions: { _ in .init(repeat: [.delete(1)]) }, variations: [], direction: .right, showsTapBubble: false, role: .special)
        // Row 3
        dict[.init(x: 0, y: 3, width: 1.4)] = tabs.languageKey
        dict[.init(x: 1.4, y: 3, width: 1.4)] = tabs.changeKeyboardKey
        dict[.init(x: 2.8, y: 3, width: 4.4)] = spaceKey()
        dict[.init(x: 7.2, y: 3, width: 2.8)] = UnifiedEnterKeyModel<Extension>()
        return dict
    }

    // Copaky: The system keyboard's symbol row uses $ for EN and € for IT, then £ and ¥.
    // Copaky: システム記号配列は英語で$、イタリア語で€、続いて£と¥を置く。
    @MainActor private static func latinSymbolsKeyboard(language: KeyboardLanguage) -> Layout {
        var dict: Layout = [:]
        let firstRow: [(label: String, variations: [String])] = [
            ("[", []),
            ("]", []),
            ("{", []),
            ("}", []),
            ("#", []),
            ("%", []),
            ("^", []),
            ("*", []),
            ("+", ["+", "±"]),
            ("=", ["=", "≠", "≈"]),
        ]
        for (index, key) in firstRow.enumerated() {
            dict[.init(x: Double(index), y: 0)] = latinInputKey(
                key.label,
                variations: key.variations,
                direction: index < 8 ? .right : .left
            )
        }

        let currency = language == .it_IT ? "€" : "$"
        let secondRow: [(label: String, variations: [String])] = [
            ("_", []),
            ("\\", ["\\", "/"]),
            ("|", []),
            ("~", []),
            ("<", ["<", "≤"]),
            (">", [">", "≥"]),
            (currency, [currency, currency == "€" ? "$" : "€"]),
            ("£", []),
            ("¥", []),
            ("•", ["•", "·"]),
        ]
        for (index, key) in secondRow.enumerated() {
            dict[.init(x: Double(index), y: 1)] = latinInputKey(
                key.label,
                variations: key.variations,
                direction: index < 8 ? .right : .left
            )
        }

        appendLatinPunctuationRow(to: &dict, leadingKey: tabKeys().numbersKey)
        appendLatinBottomRow(to: &dict, enterKey: UnifiedEnterKeyModel<Extension>())
        return dict
    }
}
