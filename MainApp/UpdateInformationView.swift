//
//  UpdateInformationView.swift
//  MainApp
//
//  Created by ensan on 2020/12/03.
//  Copyright © 2020 ensan. All rights reserved.
//  Copaky changelog (D1): the historical azooKey version list was replaced by a Copaky
//  first-release entry. Copaky is a fork of azooKey (MIT); the scaffolding views below
//  are kept from azooKey.
//

import SwiftUI

struct UpdateInformationView: View {
    var body: some View {
        Form {
            VersionView("0.1", releaseDate: "近日公開予定") {
                ParagraphView("Copaky の最初のプレビュー版です。") {
                    "オフラインのクリップボード履歴をキーボードに統合した、プライバシー優先の日本語入力です"
                    "コピーした内容はこの端末内にのみ保存され、外部には一切送信されません"
                }
                ParagraphView("完全オフラインで動作します。") {
                    "テレメトリや変換・使用状況などのデータを外部に送信することはありません"
                    "クリップボードの読み取りは、ユーザの操作があったときにのみ行います"
                    "フルアクセスがなくても日本語入力は使えます（クリップボード履歴の保存にはフルアクセスが必要です）"
                }
            }
            Section(footer: Text("Copaky は独立したプロジェクトです。高精度なかな漢字変換など入力の中核はオープンソースの azooKey（MIT）を基盤としており、その成果に感謝します。")) {
                FallbackLink("View azooKey on GitHub", destination: URL(string: "https://github.com/azooKey/azooKey")!)
            }
        }.navigationBarTitle(Text("更新履歴"), displayMode: .inline)
    }
}

private struct HeadlineView: View {
    private let version: String
    private let releaseDate: String
    init(_ version: String, releaseDate: String) {
        self.version = version
        self.releaseDate = releaseDate
    }

    var body: some View {
        HStack(alignment: .bottom) {
            Text("ver \(version)")
                .font(.title2)
            Spacer()
            Text("\(releaseDate)配信")
                .font(.subheadline)
        }
        .padding(2)
    }

}

@resultBuilder
private struct ArrayBuilder {
    public static func buildBlock<T>(_ values: T...) -> [T] {
        values
    }
}

private struct ParagraphView: View {
    private let headline: String
    private let points: () -> [String]

    init(_ headline: String, @ArrayBuilder points: @escaping () -> [String] = {[String]()}) {
        self.headline = headline
        self.points = points
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("⚫︎\(headline)").bold()
            let allPoints = points()
            ForEach(allPoints.indices, id: \.self) {i in
                Text("・\(allPoints[i])")
            }
        }
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
        .padding(.bottom, 3)
    }

}

private struct VersionView<Content: View>: View {
    private let content: () -> Content

    private let version: String
    private let releaseDate: String

    init(_ version: String, releaseDate: String, @ViewBuilder _ content: @escaping () -> Content) {
        self.content = content
        self.version = version
        self.releaseDate = releaseDate
    }

    var body: some View {
        Section {
            VStack(alignment: .leading) {
                HeadlineView(version, releaseDate: releaseDate)
                Divider()
                content()
            }
            .multilineTextAlignment(.leading)
        }
    }

}
