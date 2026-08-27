//
//  KeyLabel.swift
//  Keyboard
//
//  Created by ensan on 2020/10/20.
//  Copyright © 2020 ensan. All rights reserved.
//

import Foundation
import SwiftUI
import struct CustardKit.CustardKeyDirectionalLabel

public enum KeyLabelType: Sendable, Equatable {
    /// Verbatim label: the payload is rendered as-is. Use it for the CHARACTERS a key types.
    /// そのまま表示されるラベル。キーが入力する「文字そのもの」に使う。
    case text(String)
    /// Copaky: functional label resolved through the app's string catalog.
    /// The payload doubles as the catalog key (source language: Japanese), so a key that reads
    /// "戻る" shows "Back"/"Indietro" once the UI language is English/Italian.
    /// Use it ONLY for words the user reads (space, return, back…), NEVER for typed characters.
    /// Copaky: 文字列カタログ経由で解決される機能ラベル（ペイロードがそのままカタログのキー）。
    /// ユーザーが読む語にのみ使い、入力される文字には使わないこと。
    case localizedText(String)
    case symbols([String])
    case mainAndDirections(String, CustardKeyDirectionalLabel)
    case image(String)
    case customImage(String)
    case changeKeyboard
    case selectable(String, String)
    /// Copaky: main text with a small hint rendered ABOVE it (e.g. digit hints on the QWERTY top row)
    /// メイン文字の上に小さなヒントを表示する（QWERTY最上段の数字ヒント用）
    case textWithUpperHint(String, String)
}

public struct DirectionalKeyLabel: View {
    public init(main: String, directions: CustardKeyDirectionalLabel, font: Font = .body, subFont: Font = .caption) {
        self.main = main
        self.directions = directions
        self.font = font
        self.subFont = subFont
    }
    
    let main: String
    let directions: CustardKeyDirectionalLabel
    let font: Font
    let subFont: Font

    @ViewBuilder
    private func optionalLabel(_ label: String?, font: Font) -> some View {
        if let label {
            Text(label)
                .font(font)
        }
    }

    public var body: some View {
        ZStack {
            HStack {
                self.optionalLabel(directions.left, font: subFont)
                Spacer(minLength: 0)
                self.optionalLabel(directions.right, font: subFont)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                self.optionalLabel(directions.top, font: subFont)
                Spacer(minLength: 0)
                self.optionalLabel(directions.bottom, font: subFont)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(main)
                .font(font)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
public struct KeyLabel<Extension: ApplicationSpecificKeyboardViewExtension>: View {
    private let labelType: KeyLabelType
    private let width: CGFloat
    private var textColor: Color?
    private var textSize: Design.Fonts.LabelFontSizeStrategy
    @Environment(Extension.Theme.self) private var theme
    @Environment(\.userActionManager) private var action
    @EnvironmentObject private var variableStates: VariableStates

    private var mainKeyColor: Color {
        textColor ?? theme.textColor.color
    }

    init(_ type: KeyLabelType, width: CGFloat, textSize: Design.Fonts.LabelFontSizeStrategy = .large, textColor: Color? = nil) {
        self.labelType = type
        self.width = width
        self.textColor = textColor
        self.textSize = textSize
    }

    private var keyViewFontSize: CGFloat {
        Extension.SettingProvider.keyViewFontSize
    }

    public var body: some View {
        switch self.labelType {
        case let .text(text):
            let font = Design.fonts.keyLabelFont(text: text, width: width, fontSize: self.textSize, userDecidedSize: keyViewFontSize, theme: theme)
            Text(text)
                .font(font)
                .foregroundStyle(mainKeyColor)
                .allowsHitTesting(false)

        case let .localizedText(key):
            // Resolve first: the font must be sized on the TRANSLATED text ("Emergency" is much wider
            // than "緊急連絡"), so we cannot hand a LocalizedStringKey straight to Text.
            // 先に解決する: フォント幅は翻訳後の文字列で決める必要があるため。
            let text = String(localized: String.LocalizationValue(key), bundle: .main)
            let font = Design.fonts.keyLabelFont(text: text, width: width, fontSize: self.textSize, userDecidedSize: keyViewFontSize, theme: theme)
            Text(verbatim: text)
                .font(font)
                .foregroundStyle(mainKeyColor)
                .allowsHitTesting(false)

        case let .symbols(symbols):
            let mainText = symbols.first!
            let font = Design.fonts.keyLabelFont(text: mainText, width: width, fontSize: self.textSize, userDecidedSize: keyViewFontSize, theme: theme)
            let subText = symbols.dropFirst().joined()
            let subFont = Design.fonts.keyLabelFont(text: subText, width: width, fontSize: .xsmall, userDecidedSize: keyViewFontSize, theme: theme)
            VStack {
                Text(mainText)
                    .font(font)
                Text(subText)
                    .font(subFont)
            }
            .foregroundStyle(mainKeyColor)
            .allowsHitTesting(false)

        case let .mainAndDirections(mainText, directions):
            let font = Design.fonts.keyLabelFont(text: mainText, width: width, fontSize: self.textSize, userDecidedSize: keyViewFontSize, theme: theme)
            let directionLabels = [
                directions.top,
                directions.left,
                directions.right,
                directions.bottom
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            let subFontText = directionLabels.max(by: { $0.count < $1.count }) ?? ""
            let subFont = Design.fonts.keyLabelFont(text: subFontText, width: width, fontSize: .xxsmall, userDecidedSize: keyViewFontSize, theme: theme)
            DirectionalKeyLabel(main: mainText, directions: directions, font: font, subFont: subFont)
                .foregroundStyle(mainKeyColor)
                .allowsHitTesting(false)
        case let .image(imageName):
            Image(systemName: imageName)
                .font(Design.fonts.iconImageFont(keyViewFontSizePreference: Extension.SettingProvider.keyViewFontSize, theme: theme))
                .foregroundStyle(mainKeyColor)
                .allowsHitTesting(false)

        case let .customImage(imageName):
            Image(imageName)
                .resizable()
                .frame(width: 30, height: 30, alignment: .leading)
                .allowsHitTesting(false)

        case .changeKeyboard:
            (self.action.makeChangeKeyboardButtonView() as ChangeKeyboardButtonView<Extension>)
                .foregroundStyle(mainKeyColor)

        case let .textWithUpperHint(main, hint):
            let font = Design.fonts.keyLabelFont(text: main, width: width, fontSize: self.textSize, userDecidedSize: keyViewFontSize, theme: theme)
            let hintFont = Design.fonts.keyLabelFont(text: hint, width: width, fontSize: .xsmall, userDecidedSize: keyViewFontSize, theme: theme)
            VStack(spacing: -1) {
                Text(hint)
                    .font(hintFont)
                    .foregroundStyle(mainKeyColor.opacity(0.6))
                Text(main)
                    .font(font)
                    .foregroundStyle(mainKeyColor)
            }
            // VoiceOver reads the letter only — the digit is a visual hint, reachable via long-press
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: main))
            .allowsHitTesting(false)

        case let .selectable(primary, secondery):
            let font = Design.fonts.keyLabelFont(text: primary + primary, width: width, fontSize: self.textSize, userDecidedSize: keyViewFontSize, theme: theme)
            let subFont = Design.fonts.keyLabelFont(text: secondery + secondery, width: width, fontSize: .small, userDecidedSize: keyViewFontSize, theme: theme)

            HStack(alignment: .bottom) {
                Text(primary)
                    .font(font)
                    .padding(.trailing, -5)
                    .foregroundStyle(mainKeyColor)
                Text(secondery)
                    .font(subFont.bold())
                    .foregroundStyle(.gray)
                    .padding(.leading, -5)
                    .offset(y: -1)
            }
            .accessibilityIdentifier("keyboard-language-switch-\(primary)-\(secondery)")
            .allowsHitTesting(false)
        }
    }

    consuming func textColor(_ color: Color?) -> Self {
        self.textColor = color
        return self
    }
    consuming func textSize(_ textSize: Design.Fonts.LabelFontSizeStrategy) -> Self {
        self.textSize = textSize
        return self
    }
}
