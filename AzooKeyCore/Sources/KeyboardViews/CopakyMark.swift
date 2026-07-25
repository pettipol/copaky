//
//  CopakyMark.swift
//  Copaky
//
//  The Copaky brand mark: a clipboard card carrying the kanji 写 ("copy") in brand red,
//  echoing the dual-clipboard 書/写 composition of the app icon.
//  Copakyのブランドマーク。アプリアイコンの書/写クリップボード構成を踏襲した、赤い「写」入りのカード。
//

import SwiftUI

public struct CopakyMark: View {
    /// Brand red of the app icon (#D7000F) / アプリアイコンのブランドレッド
    private static let brandRed = Color(red: 215 / 255, green: 0 / 255, blue: 15 / 255)
    /// Fixed ink color (#161616) so the mark reads identically on the white card in light and dark mode.
    private static let ink = Color(red: 0.086, green: 0.086, blue: 0.086)

    @ScaledMetric private var scaledSize: CGFloat
    private let fixedSize: CGFloat?
    private let tint: Color?

    /// Dynamic-Type-scaling variant for the app header and onboarding rows (colored card).
    /// 本体アプリのヘッダー・オンボーディング用（Dynamic Type追従・カラー版）。
    public init(fontSize: CGFloat, relativeTo textStyle: Font.TextStyle = .body) {
        self._scaledSize = ScaledMetric(wrappedValue: fontSize * 1.2, relativeTo: textStyle)
        self.fixedSize = nil
        self.tint = nil
    }

    /// Fixed-size monochrome variant, tinted with a single color — for the keyboard tab-bar button.
    /// キーボードのタブバーボタン用（固定サイズ・テーマ色で単色描画）。
    public init(fixedSize: CGFloat, color: Color) {
        self._scaledSize = ScaledMetric(wrappedValue: fixedSize)
        self.fixedSize = fixedSize
        self.tint = color
    }

    private var side: CGFloat {
        fixedSize ?? scaledSize
    }

    public var body: some View {
        let s = side
        let lineWidth = max(1, s * 0.06)
        ZStack {
            // clipboard card / クリップボードの台紙
            if let tint {
                RoundedRectangle(cornerRadius: s * 0.13)
                    .strokeBorder(tint, lineWidth: lineWidth)
                    .frame(width: s * 0.8, height: s * 0.9)
                    .offset(y: s * 0.03)
            } else {
                RoundedRectangle(cornerRadius: s * 0.13)
                    .fill(.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: s * 0.13)
                            .strokeBorder(Self.ink, lineWidth: lineWidth)
                    }
                    .frame(width: s * 0.8, height: s * 0.9)
                    .offset(y: s * 0.03)
            }
            // metal clip on top / 上部の金具
            Capsule()
                .fill(tint ?? Self.ink)
                .frame(width: s * 0.4, height: s * 0.15)
                .offset(y: -s * 0.42)
            // the kanji 写 ("copy") / 「写」
            Text(verbatim: "写")
                .font(.system(size: s * 0.48, weight: .semibold))
                .foregroundStyle(tint ?? Self.brandRed)
                .offset(y: s * 0.07)
        }
        .frame(width: s, height: s)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        CopakyMark(fontSize: 40)
        CopakyMark(fontSize: 30, relativeTo: .title)
        HStack {
            CopakyMark(fixedSize: 26, color: .black)
            CopakyMark(fixedSize: 26, color: .white)
                .padding(6)
                .background(Color.black)
        }
    }
    .padding()
}
