//
//  CustardInformationView.swift
//  MainApp
//
//  Created by ensan on 2021/02/23.
//  Copyright © 2021 ensan. All rights reserved.
//

import AzooKeyUtils
import CustardKit
import Foundation
import KeyboardViews
import SwiftUI
import SwiftUIUtils
import SwiftUtils

extension Custard {
    var userMadeTenKeyCustard: UserMadeGridFitCustard? {
        guard self.interface.keyStyle == .tenkeyStyle else {
            return nil
        }
        guard case let .gridFit(layout) = self.interface.keyLayout else {
            return nil
        }
        var keys: [KeyPosition: UserMadeKeyData] = [:]
        // empty keysは「キー情報のない位置」とする
        var emptyKeys = Set<KeyPosition>()
        for (position, key) in self.interface.keys {
            guard case let .gridFit(value) = position else {
                // エラーでもいいかもしれない
                continue
            }
            guard value.width > 0 && value.height > 0 else {
                continue
            }
            keys[.gridFit(x: value.x, y: value.y)] = .init(model: key, width: value.width, height: value.height)
            // 削除を反映する
            // empty keysには消えるやつだけ残っていて欲しい
            for px in value.x ..< value.x + value.width {
                for py in value.y ..< value.y + value.height {
                    if px == value.x && py == value.y {
                        continue
                    }
                    emptyKeys.update(with: .gridFit(x: px, y: py))
                }
            }
        }
        return UserMadeGridFitCustard(
            tabName: self.identifier,
            rowCount: layout.rowCount.description,
            columnCount: layout.columnCount.description,
            inputStyle: self.input_style,
            language: self.language,
            keys: keys,
            emptyKeys: emptyKeys,
            addTabBarAutomatically: true
        )
    }
}

fileprivate extension CustardLanguage {
    var label: LocalizedStringKey {
        switch self {
        case .en_US:
            return "英語"
        case .ja_JP:
            return "日本語"
        case .el_GR:
            return "ギリシャ語"
        case .undefined:
            return "指定なし"
        case .none:
            return "変換なし"
        }
    }
}

fileprivate extension CustardInputStyle {
    var label: LocalizedStringKey {
        switch self {
        case .direct:
            return "ダイレクト"
        case .roman2kana:
            return "ローマ字かな入力"
        }
    }
}

fileprivate extension CustardInternalMetaData.Origin {
    var description: LocalizedStringKey {
        switch self {
        case .userMade:
            return "このアプリで作成"
        case .imported:
            return "読み込んだデータ"
        }
    }
}

private final class ShareURL {
    private(set) var url: URL?

    func setURL(_ url: URL?) {
        if let url {
            self.url = url
        }
    }
}

struct CustardInformationView: View {
    private let initialCustard: Custard
    @Binding private var path: [CustomizeTabView.Path]
    @State private var showActivityView = false
    @State private var exportedData = ShareURL()
    @State private var added = false
    @EnvironmentObject private var appStates: MainAppStates

    init(custard: Custard, path: Binding<[CustomizeTabView.Path]> = .constant([])) {
        self.initialCustard = custard
        self._path = path
    }

    private var custard: Custard {
        (try? appStates.custardManager.custard(identifier: initialCustard.identifier)) ?? initialCustard
    }

    private var keyboardPreview: some View {
        KeyboardPreview(scale: 0.7, defaultTab: .custard(custard))
    }

    var body: some View {
        Form {
            let custard = custard
            CenterAlignedView {
                keyboardPreview
            }
            LabeledContent("タブ名", value: custard.metadata.display_name)
            LabeledContent("識別子") {
                Text(verbatim: custard.identifier).monospaced()
            }
            LabeledContent("言語") {
                Text(custard.language.label)
            }
            switch custard.language {
            case .en_US:
                if appStates.englishLayout == .custard(custard.identifier) {
                    Text("英語のデフォルトタブに設定されています")
                } else {
                    Button("このタブを英語のデフォルトに設定") {
                        EnglishKeyboardLayout.set(newValue: .custard(custard.identifier))
                        appStates.englishLayout = .custard(custard.identifier)
                    }
                }
            case .ja_JP:
                if appStates.japaneseLayout == .custard(custard.identifier) {
                    Text("日本語のデフォルトタブに設定されています")
                } else {
                    Button("このタブを日本語のデフォルトに設定") {
                        JapaneseKeyboardLayout.set(newValue: .custard(custard.identifier))
                        appStates.japaneseLayout = .custard(custard.identifier)
                    }
                }
            case .el_GR, .undefined, .none:
                EmptyView()
            }
            LabeledContent("入力方式") {
                Text(custard.input_style.label)
            }
            if let metadata = appStates.custardManager.metadata[custard.identifier] {
                LabeledContent("由来") {
                    Text(metadata.origin.description)
                }

                if metadata.origin == .userMade,
                   let userdata = try? appStates.custardManager.userMadeCustardData(identifier: custard.identifier) {
                    switch userdata {
                    case let .gridScroll(value):
                        NavigationLink("編集する") {
                            EditingScrollCustardView(manager: $appStates.custardManager, editingItem: value, path: $path)
                        }
                        .foregroundStyle(.accentColor)
                    case let .tenkey(value):
                        NavigationLink("編集する") {
                            EditingGridFitCustardView(manager: $appStates.custardManager, editingItem: value, path: $path)
                        }
                        .foregroundStyle(.accentColor)
                    }
                } else if let editingItem = custard.userMadeTenKeyCustard {
                    NavigationLink("編集する") {
                        EditingGridFitCustardView(manager: $appStates.custardManager, editingItem: editingItem, path: $path)
                    }
                    .foregroundStyle(.accentColor)
                }
            }
            if added || appStates.custardManager.checkTabExistInTabBar(tab: .custom(custard.identifier)) {
                Text("タブバーに追加済み")
            } else {
                Button("タブバーに追加") {
                    do {
                        try appStates.custardManager.addTabBar(item: TabBarItem(label: .text(custard.metadata.display_name), pinned: false, actions: [.moveTab(.custom(custard.identifier))]))
                        added = true
                    } catch {
                        debug(error)
                    }
                }
            }
            // Copaky: offline-true (v0.1) — local file sharing only. The remote "share link" feature
            // (upload to custard.azookey.com) has been removed; export the tab as a .json file instead.
            // Copaky: オフライン徹底（v0.1）。共有はローカルのファイル書き出しのみ（クラウド共有リンクは削除）。
            Button("ファイルを共有") {
                guard let encoded = try? JSONEncoder().encode(custard) else {
                    debug("書き出しに失敗")
                    return
                }
                // tmpディレクトリを取得
                let directory = FileManager.default.temporaryDirectory
                let path = directory.appendingPathComponent("\(custard.identifier).json")
                do {
                    // 書き出してpathをセット
                    try encoded.write(to: path, options: .atomicWrite)
                    exportedData.setURL(path)
                    showActivityView = true
                } catch {
                    debug(error.localizedDescription)
                    return
                }
            }
        }
        .navigationBarTitle(Text("カスタムタブの情報"), displayMode: .inline)
        .sheet(isPresented: self.$showActivityView, content: {
            ActivityView(
                activityItems: [exportedData.url].compactMap {$0},
                applicationActivities: nil
            )
        })
    }
}
