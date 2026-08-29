import Foundation

/// Pure policy for Copaky's optional real QWERTY number row.
///
/// `standardInterfaceHeight` remains the canonical value owned by the existing resize pipeline.
/// The projected height adds exactly one key plus one inter-row spacing while the candidate bar
/// keeps its standard height. This prevents the original four rows from being compressed.
public enum QwertyNumberRowLayoutDecision {
    public static let standardRowCount = 4
    public static let expandedRowCount = 5
    public static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

    public struct Layout: Equatable, Sendable {
        public let rowCount: Int
        public let interfaceHeight: CGFloat
        public let keysHeight: CGFloat
        public let keyHeight: CGFloat
        public let additionalHeight: CGFloat
    }

    public static func supportsNumberRow(_ tab: KeyboardTab.ExistentialTab) -> Bool {
        switch tab {
        case .qwerty_hira, .qwerty_abc, .qwerty_numbers, .qwerty_symbols:
            true
        case .flick_hira, .flick_abc, .flick_numbersymbols, .custard, .special:
            false
        }
    }

    public static func rowCount(
        for tab: KeyboardTab.ExistentialTab,
        enabled: Bool
    ) -> Int {
        enabled && supportsNumberRow(tab) ? expandedRowCount : standardRowCount
    }

    public static func resolve(
        tab: KeyboardTab.ExistentialTab,
        enabled: Bool,
        standardInterfaceHeight: CGFloat,
        standardKeysHeight: CGFloat,
        verticalSpacing: CGFloat
    ) -> Layout {
        let spacing = max(0, verticalSpacing)
        let standardKeyHeight = max(
            0,
            (standardKeysHeight - CGFloat(standardRowCount - 1) * spacing)
                / CGFloat(standardRowCount)
        )
        let expands = enabled && supportsNumberRow(tab)
        let additionalHeight = expands ? standardKeyHeight + spacing : 0
        return Layout(
            rowCount: expands ? expandedRowCount : standardRowCount,
            interfaceHeight: standardInterfaceHeight + additionalHeight,
            keysHeight: standardKeysHeight + additionalHeight,
            keyHeight: standardKeyHeight,
            additionalHeight: additionalHeight
        )
    }
}
