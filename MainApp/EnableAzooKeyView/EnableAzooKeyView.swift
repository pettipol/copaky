//
//  EnableAzooKeyView.swift
//  MainApp
//
//  Created by ensan on 2020/11/18.
//  Copyright © 2020 ensan. All rights reserved.
//

import AzooKeyUtils
import SwiftUI
import SwiftUIUtils

enum EnableAzooKeyViewProgress: String, Hashable, Codable, Sendable {
    case menu
    case append
    case setting
    case finish
}

@MainActor
struct EnableAzooKeyView: View {
    @EnvironmentObject private var appStates: MainAppStates
    @State private var step: EnableAzooKeyViewProgress = .menu {
        didSet {
            self.appStates.setTutorialProgress(step)
        }
    }
    @State private var text = ""

    init(resumeProgress: EnableAzooKeyViewProgress? = nil) {
        if let resumeProgress {
            self._step = .init(initialValue: resumeProgress)
        }
    }

    // Copaky [H-23]: leaving setup never records a successful manual keyboard check.
    // Copaky [H-23]: 設定を閉じる操作では、入力確認済みの状態を保存しない。
    private var closeSetupButton: some View {
        CenterAlignedView {
            EnableAzooKeyViewButton("閉じる", systemName: "xmark", style: .destructive) {
                appStates.requireFirstOpenView = false
            }
            .accessibilityIdentifier("setup-close")
        }
    }

    var body: some View {
        ScrollView {
            ScrollViewReader {value in
                CenterAlignedView(padding: 30) {
                    switch self.step {
                    case .menu:
                        VStack(alignment: .leading, spacing: 20) {
                            Spacer()
                            CenterAlignedView {
                                HeaderLogoView()
                            }
                            EnableAzooKeyViewText("Copakyを使う前に、iPhoneのキーボードのリストにCopakyを追加する必要があります", with: "exclamationmark.triangle.fill")
                            CenterAlignedView {
                                EnableAzooKeyViewButton("手順を見る", systemName: "arrowtriangle.right.fill") {
                                    self.step = .append
                                }
                                .accessibilityIdentifier("setup-show-steps")
                            }
                            closeSetupButton
                        }
                        .onAppear {
                            value.scrollTo(0, anchor: .top)
                        }
                    case .append:
                        VStack(alignment: .leading, spacing: 20) {

                            EnableAzooKeyViewHeader("追加する")
                            EnableAzooKeyViewText("下にスクロールして「追加する」を押して", with: "plus.circle")
                            EnableAzooKeyViewText("「キーボード」を押して", with: "keyboard")
                            CenterAlignedView {
                                EnableAzooKeyViewImage(.initSettingKeyboardImageHand)
                            }
                            EnableAzooKeyViewText("Copakyをオンにして", with: "square.and.line.vertical.and.square.fill")
                            CenterAlignedView {
                                EnableAzooKeyViewImage(.initSettingAzooKeySwitchImageHand)
                            }
                            EnableAzooKeyViewText("このアプリを再び開いてください", with: "arrow.turn.down.left")
                            CenterAlignedView {
                                EnableAzooKeyViewButton("追加する", systemName: "plus.circle") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                    }
                                }
                            }
                            EnableAzooKeyViewText("この設定をしないとキーボードが使えません", with: "exclamationmark.triangle.fill")
                            CenterAlignedView {
                                EnableAzooKeyViewButton("設定でCopakyを追加しました", systemName: "checkmark") {
                                    self.step = .setting
                                }
                                .accessibilityIdentifier("setup-added-keyboard")
                            }
                            CenterAlignedView {
                                EnableAzooKeyViewButton("閉じる", systemName: "xmark", style: .destructive) {
                                    appStates.requireFirstOpenView = false
                                }
                            }
                        }
                        .onAppear {
                            value.scrollTo(0, anchor: .top)
                        }
                    case .setting:
                        VStack(alignment: .leading, spacing: 20) {
                            EnableAzooKeyViewHeader("最初の設定")
                            Group {
                                Divider()
                                EnableAzooKeyViewText("日本語キーボードの種類をお選びください", with: "keyboard")
                                // Copaky [F-01]: onboarding configures Japanese only; Latin keeps its QWERTY default.
                                // Copaky [F-01]: 初期設定では日本語だけを変更し、ラテン文字のQWERTY既定値を保つ。
                                LanguageLayoutSettingView(.japaneseKeyboardLayout, setTogether: false)
                            }
                            Group {
                                Divider()
                                EnableAzooKeyViewText("ライブ変換を使用しますか？", with: "character.cursor.ibeam")
                                BoolSettingView(.liveConversion)
                            }
                            Divider()
                            EnableAzooKeyViewText("設定は「設定タブ」でいつでも変えられます", with: "gearshape")
                            CenterAlignedView {
                                EnableAzooKeyViewButton("完了", systemName: "checkmark") {
                                    self.step = .finish
                                }
                                .accessibilityIdentifier("setup-finish-settings")
                            }
                            closeSetupButton
                        }
                        .onAppear {
                            value.scrollTo(0, anchor: .top)
                        }

                    case .finish:
                        VStack(alignment: .leading, spacing: 20) {
                            EnableAzooKeyViewHeader("キーボードを確認する")
                            EnableAzooKeyViewText("下の入力欄をタップし、地球儀ボタンを長押ししてCopakyを選び、文字を入力してください。", with: "globe")
                            TextField("キーボードを開く", text: $text)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("setup-keyboard-test-field")
                            EnableAzooKeyViewText("アプリはキーボードの有効状態を自動判定しません。Copakyで入力できたことをご自身で確認してください。", with: "info.circle")
                            CenterAlignedView {
                                EnableAzooKeyViewButton("Copakyで入力できました", systemName: "checkmark") {
                                    appStates.confirmKeyboardSetup()
                                }
                                .accessibilityIdentifier("setup-confirm-keyboard")
                            }
                            closeSetupButton
                        }
                        .onAppear { value.scrollTo(0, anchor: .top) }

                    }
                }
                .id(0)
            }
        }
        .animation(.interactiveSpring(), value: step)
    }
}
