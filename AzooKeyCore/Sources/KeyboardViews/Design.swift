//
//  Design.swift
//  Keyboard
//
//  Created by ensan on 2020/12/25.
//  Copyright © 2020 ensan. All rights reserved.
//

import Foundation
import KeyboardThemes
import SwiftUI
import SwiftUIUtils

/// タブに依存するデザイン上の数値を計算する構造体
public struct TabDependentDesign {
    let horizontalKeyCount: CGFloat
    let verticalKeyCount: CGFloat
    let orientation: KeyboardOrientation

    private var interfaceWidth: CGFloat
    private var interfaceHeight: CGFloat
    private var fixedKeysHeight: CGFloat?

    public init(width: Int, height: Int, interfaceSize: CGSize, orientation: KeyboardOrientation, keysHeight: CGFloat? = nil) {
        self.horizontalKeyCount = CGFloat(width)
        self.verticalKeyCount = CGFloat(height)
        self.orientation = orientation
        self.interfaceWidth = interfaceSize.width
        self.interfaceHeight = interfaceSize.height
        self.fixedKeysHeight = keysHeight
    }

    public init(width: CGFloat, height: CGFloat, interfaceSize: CGSize, orientation: KeyboardOrientation, keysHeight: CGFloat? = nil) {
        self.horizontalKeyCount = width
        self.verticalKeyCount = height
        self.orientation = orientation
        self.interfaceWidth = interfaceSize.width
        self.interfaceHeight = interfaceSize.height
        self.fixedKeysHeight = keysHeight
    }

    /// screenWidthとhorizontalKeyCountに依存
    var keyViewWidth: CGFloat {
        let coefficient: CGFloat
        switch orientation {
        case .vertical:
            coefficient = 5 / (5.1 + horizontalKeyCount / 10)
        case .horizontal:
            coefficient = 10 / (10.2 + horizontalKeyCount * 0.28)
        }
        return interfaceWidth / horizontalKeyCount * coefficient
    }

    /// This property calculate suitable height for normal keyView.
    @MainActor var keyViewHeight: CGFloat {
        let keyHeight = (keysHeight - (verticalKeyCount - 1) * verticalSpacing) / verticalKeyCount
        return keyHeight
    }

    var keysWidth: CGFloat {
        keyViewWidth * horizontalKeyCount + horizontalSpacing * (horizontalKeyCount - 1)
    }

    // resultViewの幅を全体から引いたもの。キーを配置して良い部分の高さ。
    @MainActor var keysHeight: CGFloat {
        fixedKeysHeight ?? Design.keyboardKeysHeight(interfaceHeight: interfaceHeight, orientation: orientation)
    }

    /// This property is equivarent to `CGSize(width: keyViewWidth, height: keyViewHeight)`. if you want to use only either of two, call `keyViewWidth` or `keyViewHeight` directly.
    @MainActor var keyViewSize: CGSize {
        CGSize(width: keyViewWidth, height: keyViewHeight)
    }

    var verticalSpacing: CGFloat {
        switch orientation {
        case .vertical:
            return interfaceWidth / 50
        case .horizontal:
            return interfaceWidth / 107
        }
    }

    /// screenWidthとhorizontalKeyCountとkeyViewWidthに依存
    var horizontalSpacing: CGFloat {
        if horizontalKeyCount <= 1 {
            return 0
        }
        let coefficient: CGFloat
        switch orientation {
        case .vertical:
            coefficient = (5 + horizontalKeyCount) / (7.5 + horizontalKeyCount)
        case .horizontal:
            coefficient = (8 + horizontalKeyCount) / (10 + horizontalKeyCount * 1.3)
        }
        return (interfaceWidth - keyViewWidth * horizontalKeyCount) / (horizontalKeyCount - 1) * coefficient
    }

    func keyViewWidth(widthCount: CGFloat) -> CGFloat {
        keyViewWidth * widthCount + horizontalSpacing * (widthCount - 1)
    }

    @MainActor func keyViewHeight(heightCount: CGFloat) -> CGFloat {
        keyViewHeight * heightCount + verticalSpacing * (heightCount - 1)
    }
}

/// タブに依存せず、キーボード全体で共通するデザイン上の数値を切り出した構造体。
public enum Design {
    public static let colors = Colors.default
    public static let fonts = Fonts.default
    public static let language = Language.default

    /// レイアウトのモード
    enum LayoutMode {
        case phoneVertical
        case phoneHorizontal
        case padVertical
        case padHorizontal
    }

    /// レイアウトモードを決定する
    /// 特に、iPadでフローティングキーボードを利用する場合は`phoneVertical`になる。
    @MainActor private static func layoutMode(orientation: KeyboardOrientation) -> LayoutMode {
        // TODO: この実装は検証される必要がある
        let usePadMode = UIDevice.current.userInterfaceIdiom == .pad
        // floating keyboardの場合
        if usePadMode, SemiStaticStates.shared.screenWidth < 400 {
            return .phoneVertical
        }
        switch (orientation, usePadMode) {
        case (.vertical, false):
            return .phoneVertical
        case (.vertical, true):
            return .padVertical
        case (.horizontal, false):
            return .phoneHorizontal
        case (.horizontal, true):
            return .padHorizontal
        }
    }
    public static var keyboardScreenBottomPadding: CGFloat {
        2
    }

    /// This property calculate suitable width for normal keyView.
    @MainActor public static func keyboardScreenHeight(upsideComponent: UpsideComponent?, orientation: KeyboardOrientation) -> CGFloat {
        keyboardHeight(screenWidth: SemiStaticStates.shared.screenWidth, orientation: orientation, upsideComponent: upsideComponent) + keyboardScreenBottomPadding
    }

    /// screenWidthに依存して決定する
    /// 12はresultViewのpadding
    @MainActor public static func keyboardHeight(screenWidth: CGFloat, orientation: KeyboardOrientation, upsideComponent: UpsideComponent? = nil) -> CGFloat {
        let scale: CGFloat
        if let upsideComponent {
            switch orientation {
            case .vertical:
                scale = min(2.2, 1.0 + upsideComponentScale(upsideComponent).vertical)
            case .horizontal:
                scale = min(2.2, 1.0 + upsideComponentScale(upsideComponent).horizontal)
            }
        } else {
            scale = 1
        }
        // 安全装置として、widthが本来のscreenWidthを超えないようにする。
        let width = min(screenWidth, SemiStaticStates.shared.screenWidth)
        switch layoutMode(orientation: orientation) {
        case .phoneVertical:
            return 51 / 74 * width * scale + 12
        case .padVertical:
            return 15 / 31 * width * scale + 12
        case .phoneHorizontal:
            return 17 / 56 * width * scale + 12
        case .padHorizontal:
            return 5 / 18 * width * scale + 12
        }
    }

    private static func upsideComponentScale(_ component: UpsideComponent) -> (vertical: CGFloat, horizontal: CGFloat) {
        switch component {
        case .search:
            return (vertical: 0.5, horizontal: 0.5)
        case .supplementaryCandidates:
            return (vertical: 0.15, horizontal: 0.15)
        }
    }

    @MainActor static public func upsideComponentHeight(_ component: UpsideComponent, orientation: KeyboardOrientation) -> CGFloat {
        Design.keyboardHeight(screenWidth: SemiStaticStates.shared.screenWidth, orientation: orientation, upsideComponent: component) - Design.keyboardHeight(screenWidth: SemiStaticStates.shared.screenWidth, orientation: orientation, upsideComponent: nil)
    }
    @MainActor private static func keyboardBarHeightRatio(orientation: KeyboardOrientation) -> CGFloat {
        switch layoutMode(orientation: orientation) {
        case .phoneVertical:
            37 / 204
        case .padVertical:
            31 / 180
        case .phoneHorizontal:
            28 / 153
        case .padHorizontal:
            9 / 55
        }
    }

    /// バー部分の高さは`interfaceHeight`に基づいて決定する
    @MainActor static func keyboardBarHeight(interfaceHeight: CGFloat, orientation: KeyboardOrientation) -> CGFloat {
        (interfaceHeight - 12) * keyboardBarHeightRatio(orientation: orientation)
    }

    /// Total vertical space occupied by the candidate row: bar plus its existing 6 pt padding on
    /// both edges. Exposed so the extension constraint and SwiftUI layout use one exact value.
    @MainActor public static func keyboardBarReservedHeight(interfaceHeight: CGFloat, orientation: KeyboardOrientation) -> CGFloat {
        keyboardBarHeight(interfaceHeight: interfaceHeight, orientation: orientation) + 12
    }

    /// Height left for keys when the candidate row is omitted. The inverse keeps resize-mode
    /// persistence expressed in the existing full-interface coordinate system.
    @MainActor static func keyboardKeysHeight(interfaceHeight: CGFloat, orientation: KeyboardOrientation) -> CGFloat {
        max(0, interfaceHeight - keyboardBarReservedHeight(interfaceHeight: interfaceHeight, orientation: orientation))
    }

    @MainActor static func keyboardInterfaceHeight(keysHeight: CGFloat, orientation: KeyboardOrientation) -> CGFloat {
        let ratio = keyboardBarHeightRatio(orientation: orientation)
        return max(12, keysHeight / (1 - ratio) + 12)
    }

    /// Resolve the optional number-row projection from the same geometry used by every QWERTY key.
    /// The supplied interface size is the standard/manual-resize baseline and is never mutated here.
    @MainActor public static func qwertyNumberRowLayout(
        for tab: KeyboardTab.ExistentialTab,
        enabled: Bool,
        standardInterfaceSize: CGSize,
        orientation: KeyboardOrientation
    ) -> QwertyNumberRowLayoutDecision.Layout {
        let standardDesign = TabDependentDesign(
            width: 10,
            height: QwertyNumberRowLayoutDecision.standardRowCount,
            interfaceSize: standardInterfaceSize,
            orientation: orientation
        )
        return QwertyNumberRowLayoutDecision.resolve(
            tab: tab,
            enabled: enabled,
            standardInterfaceHeight: standardInterfaceSize.height,
            standardKeysHeight: standardDesign.keysHeight,
            verticalSpacing: standardDesign.verticalSpacing
        )
    }

    /// Visible keyboard-body height after candidate-bar collapse and optional QWERTY row projection.
    @MainActor public static func qwertyNumberRowVisibleHeight(
        standardInterfaceHeight: CGFloat,
        interfaceWidth: CGFloat,
        orientation: KeyboardOrientation,
        tab: KeyboardTab.ExistentialTab,
        enabled: Bool,
        candidateBarCollapsed: Bool
    ) -> CGFloat {
        let standardVisibleHeight = candidateBarCollapsed
            ? keyboardKeysHeight(interfaceHeight: standardInterfaceHeight, orientation: orientation)
            : standardInterfaceHeight
        let layout = qwertyNumberRowLayout(
            for: tab,
            enabled: enabled,
            standardInterfaceSize: CGSize(width: interfaceWidth, height: standardInterfaceHeight),
            orientation: orientation
        )
        return max(0, standardVisibleHeight + layout.additionalHeight)
    }

    /// Inverse used by the existing drag-resize binding so only the standard height is persisted.
    /// A short monotonic solve keeps this projection independent from private device-specific ratios.
    @MainActor public static func standardInterfaceHeightForQwertyNumberRow(
        renderedVisibleHeight: CGFloat,
        interfaceWidth: CGFloat,
        orientation: KeyboardOrientation,
        tab: KeyboardTab.ExistentialTab,
        enabled: Bool,
        candidateBarCollapsed: Bool
    ) -> CGFloat {
        guard enabled, QwertyNumberRowLayoutDecision.supportsNumberRow(tab) else {
            return candidateBarCollapsed
                ? keyboardInterfaceHeight(keysHeight: renderedVisibleHeight, orientation: orientation)
                : renderedVisibleHeight
        }
        let target = max(0, renderedVisibleHeight)
        var lower: CGFloat = 0
        var upper = max(12, target)
        while qwertyNumberRowVisibleHeight(
            standardInterfaceHeight: upper,
            interfaceWidth: interfaceWidth,
            orientation: orientation,
            tab: tab,
            enabled: enabled,
            candidateBarCollapsed: candidateBarCollapsed
        ) < target {
            upper *= 2
        }
        for _ in 0..<32 {
            let middle = (lower + upper) / 2
            let projected = qwertyNumberRowVisibleHeight(
                standardInterfaceHeight: middle,
                interfaceWidth: interfaceWidth,
                orientation: orientation,
                tab: tab,
                enabled: enabled,
                candidateBarCollapsed: candidateBarCollapsed
            )
            if projected < target {
                lower = middle
            } else {
                upper = middle
            }
        }
        return (lower + upper) / 2
    }

    @MainActor static func largeTextViewFontSize(_ text: String, upsideComponent: UpsideComponent?, orientation: KeyboardOrientation) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 10)
        let size = text.size(withAttributes: [.font: font])
        // 閉じるボタンの高さの分
        return (self.keyboardScreenHeight(upsideComponent: upsideComponent, orientation: orientation) * 0.85) / size.height * 10
    }

    public enum Fonts: Sendable {
        case `default`
        func azooKeyIconFont(fixedSize: CGFloat) -> Font {
            Font.custom("AzooKeyIcon-Regular", fixedSize: fixedSize)
        }

        public func azooKeyIconFont(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
            Font.custom("AzooKeyIcon-Regular", size: size, relativeTo: style)
        }

        @MainActor public func iconFontSize(keyViewFontSizePreference: CGFloat) -> CGFloat {
            if keyViewFontSizePreference != -1 {
                return UIFontMetrics.default.scaledValue(for: keyViewFontSizePreference)
            }
            return UIFontMetrics.default.scaledValue(for: 20)
        }

        @MainActor func iconImageFont(keyViewFontSizePreference: CGFloat, theme: ThemeData<some ApplicationSpecificTheme>) -> Font {
            Font.system(size: self.iconFontSize(keyViewFontSizePreference: keyViewFontSizePreference), weight: theme.textFont.weight)
        }

        func resultViewFontSize(userPrefrerence: CGFloat) -> CGFloat {
            userPrefrerence == -1 ? 18 : userPrefrerence
        }

        func resultViewFont(theme: ThemeData<some ApplicationSpecificTheme>, userSizePrefrerence: CGFloat, fontSize: CGFloat? = nil) -> Font {
            Font.system(size: fontSize ?? resultViewFontSize(userPrefrerence: userSizePrefrerence)).weight(theme.textFont.weight)
        }

        func forceJapaneseFont(text: String) -> AttributedString {
            var attributedString = AttributedString(text)
            attributedString.languageIdentifier = "ja"
            return attributedString
        }

        func forceJapaneseFont(text: String, theme: ThemeData<some ApplicationSpecificTheme>, userSizePrefrerence: CGFloat) -> AttributedString {
            let baseFont = self.resultViewFont(theme: theme, userSizePrefrerence: userSizePrefrerence)

            var attributedString = AttributedString(text)
            attributedString.languageIdentifier = "ja"
            attributedString.font = baseFont

            return attributedString
        }

        enum LabelFontSizeStrategy {
            case max
            case xlarge
            case large
            case medium
            case small
            case xsmall
            case xxsmall

            var scale: CGFloat {
                switch self {
                case .xlarge:
                    return 1.2
                case .large, .max:
                    return 1
                case .medium:
                    return 0.8
                case .small:
                    return 0.7
                case .xsmall:
                    return 0.6
                case .xxsmall:
                    return 0.5
                }
            }
        }

        private func getMaximumFontSize(for text: String, width: CGFloat, maxFontSize: Int) -> CGFloat {
            var lowerBound = 9
            var upperBound = maxFontSize
            var mid = 0
            while lowerBound < upperBound {
                mid = (lowerBound + upperBound + 1) / 2
                let size = UIFontMetrics.default.scaledValue(for: CGFloat(mid))
                let font = UIFont.systemFont(ofSize: size, weight: .regular)
                let title_size = text.size(withAttributes: [.font: font])
                if title_size.width < width * 0.95 {
                    lowerBound = mid
                } else {
                    upperBound = mid - 1
                }
            }
            let size = UIFontMetrics.default.scaledValue(for: CGFloat(lowerBound))
            return size
        }

        @MainActor func keyLabelFont(text: String, width: CGFloat, fontSize: LabelFontSizeStrategy, userDecidedSize: CGFloat, theme: ThemeData<some ApplicationSpecificTheme>) -> Font {
            if case .max = fontSize {
                let size = self.getMaximumFontSize(for: text, width: width, maxFontSize: 100)
                return Font.system(size: size, weight: theme.textFont.weight, design: .default)
            }

            if userDecidedSize != -1 {
                return .system(size: userDecidedSize * fontSize.scale, weight: theme.textFont.weight, design: .default)
            }
            let maxFontSize = if text.count == 1 {
                Int(25 * fontSize.scale)
            } else {
                Int(22 * fontSize.scale)
            }
            let size = self.getMaximumFontSize(for: text, width: width, maxFontSize: maxFontSize)
            return Font.system(size: size, weight: theme.textFont.weight, design: .default)
        }
    }

    public enum Colors: Sendable {
        case `default`

        public var backGroundColor: Color {
            Color("BackGroundColor_iOS15")
        }

        public var nativeSpecialKeyColor: Color {
            Color("NativeSpecialKeyColor")
        }

        public var specialEnterKeyColor: Color {
            Color("OpenKeyColor")
        }

        public var normalKeyColor: Color {
            Color("NormalKeyColor")
        }

        public var specialKeyColor: Color {
            Color("TabKeyColor_iOS15")
        }

        public var highlightedKeyColor: Color {
            Color("HighlightedKeyColor")
        }

        public var suggestKeyColor: Color {
            .white
        }
    }

    public enum Language: Sendable {
        case `default`

        func getEnterKeyText(_ state: EnterKeyState) -> String {
            switch state {
            case .complete:
                return "確定"
            case let .return(type):
                switch type {
                case .default:
                    return "改行"
                case .go:
                    return "開く"
                case .google:
                    return "ググる"
                case .join:
                    return "参加"
                case .next:
                    return "次へ"
                case .route:
                    return "経路"
                case .search:
                    return "検索"
                case .send:
                    return "送信"
                case .yahoo:
                    return "Yahoo!"
                case .done:
                    return "完了"
                case .emergencyCall:
                    return "緊急連絡"
                case .continue:
                    return "続行"
                @unknown default:
                    return "改行"
                }
            }
        }
    }
}
