//
//  SettingTab.swift
//  MainApp
//
//  Created by ensan on 2020/09/16.
//  Copyright © 2020 ensan. All rights reserved.
//

import AzooKeyUtils
import KeyboardViews
import StoreKit
import SwiftUI

struct SettingTabView: View {
    @State private var searchQuery: String = ""
    // The Form must own this editMode: reorder handles are drawn by the List machinery, which reads
    // editMode from ITS environment — a value set inside a row never reaches it (measured 27/08).
    @State private var activeLanguagesEditMode = EditMode.inactive
    @State private var path: [CustomizeTabView.Path] = []
    /// Copaky: 13 sections is a lot to land in. Off = a short "Essentials" list with the settings
    /// people actually look for; on = every section, exactly as before. Persisted, and always
    /// bypassed while searching so a query can never miss a hidden row.
    /// Copaky: 既定では「基本設定」だけを表示し、必要な人だけ全設定を開く。検索中は常に全表示。
    @AppStorage("settings_show_all_sections") private var showAllSections = false

    private var showsEverything: Bool {
        showAllSections || !searchQuery.isEmpty
    }
    @Environment(\.requestReview) var requestReview
    @EnvironmentObject private var appStates: MainAppStates
    private func canFlickLayout(_ layout: LanguageLayout) -> Bool {
        if layout == .flick {
            return true
        }
        if case .custard = layout {
            return true
        }
        return false
    }

    private func canQwertyLayout(_ layout: LanguageLayout) -> Bool {
        if layout == .qwerty {
            return true
        }
        return false
    }

    private func isCustard(_ layout: LanguageLayout) -> Bool {
        if case .custard = layout {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if !showsEverything {
                    // Copaky: the short list. Same views as below — a row is defined once and shown
                    // here or in its own section, never duplicated in behaviour.
                    Section("基本設定") {
                        NavigationLink("キーボードの種類を設定する") {
                            KeyboardLayoutTypeDetailsView()
                        }
                        BoolSettingView(.liveConversion)
                        BoolSettingView(.enableNumberRowHints)
                        BoolSettingView(.enableQwertyNumberRow)
                        ActiveKeyboardLanguagesSettingRows(editMode: $activeLanguagesEditMode)
                        // Copaky: keep auto-accent next to the Italian-language switch it qualifies.
                        // Copaky: アクセント自動補正を対象となるイタリア語設定の直後に置く。
                        BoolSettingView(.italianAutoAccentOnSpace)
                        BoolSettingView(.enableLatinAutocorrect)
                        BoolSettingView(.enableClipboardHistoryManagerTab)
                        BoolSettingView(.displayTabBarButton)
                        BoolSettingView(.hideEmptyCandidateBarOnLatin)
                        BoolSettingView(.enableKeySound)
                        if SemiStaticStates.shared.hapticsAvailable {
                            BoolSettingView(.enableKeyHaptics)
                        }
                        FontSizeSettingView(.keyViewFontSize, .key, availableValueRange: 15 ... 28)
                    }
                }
                Section {
                    Toggle("すべての設定を表示", isOn: $showAllSections)
                } footer: {
                    // Says only what is true: search bypasses the split. It does NOT promise that every
                    // row is findable in every language — many rows still carry Japanese-only keywords.
                    Text("オフのときは、よく使う設定だけを表示します。検索は隠れている設定も対象にします。")
                }
                .searchKeys("すべての設定", "全設定", "tutte", "impostazioni", "all settings")

                if showsEverything {
                Section("キーボードの種類") {
                    NavigationLink("キーボードの種類を設定する") {
                        KeyboardLayoutTypeDetailsView()
                    }
                }
                .searchKeys("キーボードの種類", "レイアウト", "フリック", "ローマ字", "tastiera", "layout", "keyboard", "disposizione")

                Section("ライブ変換") {
                    BoolSettingView(.liveConversion)
                    NavigationLink("詳しい設定") {
                        LiveConversionSettingView()
                    }
                }
                .searchKeys("ライブ変換", "自動変換", "自動確定", "conversione", "automatica", "live", "conversion")

                Section("カスタムキー") {
                    CustomKeysSettingView(settingAdaptive: true)
                        .searchKeys("カスタムキー", "カスタマイズ", "personalizza", "tasti", "custom", "keys")
                    if !self.isCustard(appStates.japaneseLayout) || !self.isCustard(appStates.englishLayout) {
                        BoolSettingView(.useNextCandidateKey)
                            .searchKeys("次候補キー", "candidato", "successivo", "next", "candidate")
                    }
                    if self.canQwertyLayout(appStates.englishLayout) {
                        BoolSettingView(.useShiftKey)
                            .searchKeys("シフトキー", "maiuscole", "shift")
                        // Version 2.2.2以前にインストールしており、UseShiftKey.valueがtrueの人にのみこのオプションを表示する
                        // Copaky: isCopakyEra — never a legacy azooKey install, hide the deprecated toggle
                        if #unavailable(iOS 18), let initialVersion = SharedStore.initialAppVersion, initialVersion <= .azooKey_v2_2_2, !initialVersion.isCopakyEra, UseShiftKey.value == true {
                            BoolSettingView(.keepDeprecatedShiftKeyBehavior)
                                .searchKeys("シフトキー")
                        }
                    }
                    if !SemiStaticStates.shared.needsInputModeSwitchKey, self.canFlickLayout(appStates.japaneseLayout) {
                        BoolSettingView(.enablePasteButton)
                            .searchKeys("ペーストボタン", "ペーストキー", "貼り付け", "incolla", "paste")
                    }
                }
                .inheritSearchKeys()

                Section("バー") {
                    BoolSettingView(.useReflectStyleCursorBar)
                        .searchKeys("カーソルバー", "バー", "cursore", "barra", "cursor", "bar")
                    BoolSettingView(.enableClipboardHistoryManagerTab)
                        .searchKeys("コピー履歴", "クリップボード履歴", "履歴", "appunti", "clipboard", "cronologia")
                    BoolSettingView(.displayTabBarButton)
                        .searchKeys("Copakyボタン", "候補バー", "barra", "suggerimenti", "candidate", "button")
                    BoolSettingView(.hideEmptyCandidateBarOnLatin)
                        .searchKeys("候補バー", "空", "ラテン", "barra", "vuota", "suggerimenti", "empty", "Latin")
                    // NOT wrapped in a hasFullAccess check: that flag is read once at app launch and
                    // never refreshed, so a user who grants Full Access in iOS Settings and comes back
                    // would find the row GONE — and, worse, someone who revokes it later would lose the
                    // only way to turn this off. BoolSettingView already handles requireFullAccess by
                    // disabling the row and offering the shortcut to Settings.
                    BoolSettingView(.useSystemPasteControl)
                        .searchKeys("ペースト", "バナー", "コピー履歴", "incolla", "appunti", "paste")
                    if SemiStaticStates.shared.hasFullAccess {
                        NavigationLink("「ペーストを許可」のダイアログについて") {
                            PasteFromOtherAppsPermissionTipsView()
                        }
                        .searchKeys("ペースト", "コピー履歴", "クリップボード履歴", "履歴")
                    }
                    NavigationLink("タブバーを編集") {
                        EditingTabBarView(manager: $appStates.custardManager)
                    }
                    .searchKeys("タブバー", "バー", "barra", "schede", "tab", "bar")
                }
                .inheritSearchKeys()

                // デバイスが触覚フィードバックをサポートしている場合のみ表示する
                if SemiStaticStates.shared.hapticsAvailable {
                    Section("サウンドと振動") {
                        BoolSettingView(.enableKeySound)
                            .searchKeys("サウンド", "音", "suono", "audio", "sound")
                        BoolSettingView(.enableKeyHaptics)
                            .searchKeys("サウンド", "振動", "vibrazione", "haptics", "vibration")
                    }
                    .inheritSearchKeys()
                } else {
                    Section("サウンド") {
                        BoolSettingView(.enableKeySound)
                    }
                    .searchKeys("サウンド", "音")
                }

                Section("表示") {
                    FontSizeSettingView(.keyViewFontSize, .key, availableValueRange: 15 ... 28)
                        .searchKeys("フォント", "サイズ", "文字サイズ", "carattere", "dimensione", "font", "size", "testo")
                    FontSizeSettingView(.resultViewFontSize, .result, availableValueRange: 12...24)
                        .searchKeys("フォント", "サイズ", "文字サイズ")
                }
                .inheritSearchKeys()

                Section("操作性") {
                    BoolSettingView(.hideResetButtonInOneHandedMode)
                        .searchKeys("片手モード", "解除ボタン", "una mano", "one-handed")
                    if self.canFlickLayout(appStates.japaneseLayout) {
                        FlickSensitivitySettingView(.flickSensitivity)
                            .searchKeys("フリックの感度", "感度", "sensibilita", "flick")
                        BoolSettingView(.enableSmoothDelete)
                            .searchKeys("文頭まで削除", "スムーズ削除", "削除", "フリック", "cancella", "elimina", "delete")
                    }
                    BoolSettingView(.enableNumberRowHints)
                        .searchKeys("数字", "数字キー", "ナンバー", "上段", "number", "numeri", "cifre", "digits")
                    BoolSettingView(.enableQwertyNumberRow)
                        .searchKeys("数字", "数字行", "数字キー", "number", "number row", "digits", "numeri", "cifre", "riga numerica")
                    ActiveKeyboardLanguagesSettingRows(editMode: $activeLanguagesEditMode)
                        .searchKeys("イタリア語", "italiano", "italian", "lingua", "language", "言語")
                    // Copaky: the optional space behavior is adjacent and searchable in JA/EN/IT.
                    // Copaky: 空白での補正設定を隣接表示し、日英伊の語で検索可能にする。
                    BoolSettingView(.italianAutoAccentOnSpace)
                        .searchKeys("イタリア語", "アクセント", "自動補正", "スペース", "italiano", "accento", "automatico", "spazio", "italian", "accent", "automatic", "space")
                    BoolSettingView(.enableLatinAutocorrect)
                        .searchKeys("自動修正", "誤字", "ラテン文字", "refusi", "correzione", "automatica", "tastiere", "latine", "typos", "autocorrect", "latin", "keyboards")
                }
                .inheritSearchKeys()

                Section("変換") {
                    BoolSettingView(.englishCandidate)
                        .searchKeys("英単語変換", "変換", "英語", "英語変換")
                    BoolSettingView(.typographyLetter)
                        .searchKeys("太字", "フォント", "タイポグラフィ", "装飾文字")
                    MarkedTextSettingView(.markedTextSetting)
                        .searchKeys("入力中のテキストを保護", "下線", "テキストを保護")
                    ContactImportSettingView()
                        .searchKeys("連絡先変換", "氏名", "知り合い")
                    NavigationLink("絵文字と顔文字") {
                        AdditionalDictManageView()
                    }
                    .searchKeys("絵文字", "顔文字", "特殊文字")
                }
                .inheritSearchKeys()

                Section("ユーザ辞書") {
                    BoolSettingView(.useOSUserDict)
                        .searchKeys("ユーザ辞書", "追加辞書")
                    NavigationLink("Copakyユーザ辞書") {
                        AzooKeyUserDictionaryView()
                    }
                    .searchKeys("ユーザ辞書", "追加辞書")
                    // Copaky: offline-true — the remote hotfix-dictionary update UI has been removed.
                }
                .inheritSearchKeys()

                Section("学習機能") {
                    LearningTypeSettingView()
                        .searchKeys("学習", "履歴")
                    MemoryResetSettingItemView()
                        .searchKeys("リセット", "学習", "履歴")
                }
                .inheritSearchKeys()

                Section("カスタムタブ") {
                    NavigationLink("カスタムタブの管理") {
                        ManageCustardView(manager: $appStates.custardManager, path: $path)
                    }
                }
                .searchKeys("カスタムタブ", "タブ", "カスタマイズ")

                Section("オープンソースソフトウェア") {
                    Text("CopakyはオープンソースソフトウェアであるazooKeyをベースにしています。azooKeyのソースコードはGitHubで公開されています。")
                    // Copaky: expose the fork's source while keeping the upstream attribution beside it.
                    FallbackLink("View Copaky on GitHub", destination: URL(string: "https://github.com/pettipol/copaky")!)
                    FallbackLink("View azooKey on GitHub", destination: URL(string: "https://github.com/azooKey/azooKey")!)
                    NavigationLink("Acknowledgements") {
                        OpenSourceSoftwaresLicenseView()
                    }
                }
                .searchKeys("オープンソース", "ライセンス", "謝辞", "OSS", "ソフトウェア", "GitHub", "Copaky")

                Section("このアプリについて") {
                    NavigationLink("お問い合わせ") {
                        ContactView()
                    }
                    .searchKeys("お問い合わせ", "質問", "連絡", "メール")
                    // Copaky: expose onboarding from Settings search. / 設定検索から案内へ移動。
                    NavigationLink("はじめに") {
                        GettingStartedTipsView()
                    }
                    .searchKeys("はじめに", "使い方", "フルアクセス", "ペースト", "getting started")
                    // Copaky: summarize the three bundled keyboard languages and their current scope.
                    NavigationLink("対応言語") {
                        SupportedLanguagesView()
                    }
                    .searchKeys("対応言語", "言語", "日本語", "英語", "イタリア語", "languages")
                    FallbackLink("プライバシーポリシー", destination: URL(string: "https://copaky.app/privacy.html")!)
                        .foregroundStyle(.primary)
                        .searchKeys("プライバシーポリシー", "個人情報", "ライセンス")
                    FallbackLink("利用規約", destination: URL(string: "https://copaky.app/terms.html")!)
                        .foregroundStyle(.primary)
                        .searchKeys("利用規約", "規約", "ライセンス")
                    NavigationLink("更新履歴") {
                        UpdateInformationView()
                    }
                    .searchKeys("更新履歴", "アップデート情報", "変更", "バージョン")
                    LabeledContent("URL Scheme") {
                        Text(verbatim: "copaky://")
                            .monospaced()
                    }
                    .searchKeys("URLスキーム")
                    LabeledContent("バージョン") {
                        Text(verbatim: SharedStore.currentAppVersion?.description ?? "取得中です")
                    }
                    .searchKeys("バージョン")
                }
                .inheritSearchKeys()

                }   // showsEverything
            }
            .searchQuery(searchQuery.isEmpty ? nil : searchQuery.searchFolded)
            .environment(\.editMode, $activeLanguagesEditMode)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: CustomizeTabView.Path.self) { destination in
                switch destination {
                case let .information(identifier):
                    if let custard = try? appStates.custardManager.custard(identifier: identifier) {
                        CustardInformationView(custard: custard, path: $path)
                    }
                }
            }
            .onAppear {
                if appStates.requestReviewManager.shouldTryRequestReview, appStates.requestReviewManager.shouldRequestReview() {
                    requestReview()
                }
            }
        }
        .searchable(text: $searchQuery, prompt: Text("検索"))
    }
}
