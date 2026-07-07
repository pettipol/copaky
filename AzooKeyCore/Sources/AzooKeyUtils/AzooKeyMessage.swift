//
//  AzooKeyMessage.swift
//  azooKey
//
//  Created by β α on 2023/07/22.
//  Copyright © 2023 DevEn3. All rights reserved.
//

import Foundation
import KeyboardViews

public enum MessageIdentifier: String, CaseIterable, MessageIdentifierProtocol {
    case mock = "mock_alert_2022_09_16_03"
    case iOS26_4_new_emoji = "iOS_26_4_new_emoji_commit"                    // MARK: frozen
    case iOS18_4_new_emoji = "iOS_18_4_new_emoji_commit"                    // MARK: frozen
    case iOS17_4_new_emoji = "iOS_17_4_new_emoji_commit"                    // MARK: frozen
    case ver1_9_user_dictionary_update = "ver1_9_user_dictionary_update_release" // MARK: frozen
    case ver2_1_emoji_tab = "ver2_1_emoji_tab"

    // MARK: 過去にプロダクションで用いていたメッセージID
    // ver1_9_user_dictionary_updateが実行されれば不要になるので、この宣言は削除
    // case ver1_5_update_loudstxt = "ver1_5_update_loudstxt"           // MARK: frozen
    // iOS17_4_new_emojiが実行されれば不要になるので、これらの宣言は削除
    // case iOS16_4_new_emoji = "iOS_16_4_new_emoji_commit"                    // MARK: frozen
    // case iOS14_5_new_emoji = "iOS_14_5_new_emoji_fixed_ver_1_6_1"    // MARK: frozen
    // case iOS15_4_new_emoji = "iOS_15_4_new_emoji"                    // MARK: frozen
    // 新機能の紹介も削除
    // case liveconversion_introduction = "liveconversion_introduction" // MARK: frozen
    // case ver1_8_autocomplete_introduction = "ver1_8_autocomplete_introduction" // MARK: frozen

    public var key: String {
        self.rawValue + "_status"
    }

    public var needUsingContainerApp: Bool {
        switch self {
        case .ver1_9_user_dictionary_update, .ver2_1_emoji_tab:
            return true
        case .iOS26_4_new_emoji, .iOS18_4_new_emoji, .iOS17_4_new_emoji, .mock:
            return false
        }
    }

    public var id: String {
        self.rawValue
    }
}

public enum AzooKeyMessageProvider: ApplicationSpecificKeyboardViewMessageProvider {
    public typealias MessageID = MessageIdentifier

    public static var userDefaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroupKey)! }

    public static var messages: [MessageData<MessageIdentifier>] {
        [
            MessageData(
                id: .ver1_9_user_dictionary_update,
                title: "お願い",
                description: "内部データの更新のため本体アプリを開いてください。\n更新は数秒で終わります。",
                button: .one(.openContainerURL(text: "更新", url: "copaky://", autoDone: false)),
                precondition: {
                    // ユーザ辞書に登録があるのが条件。
                    // Copaky: fail-soft — if the App Group container is unavailable, don't surface the message.
                    guard let directoryPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupKey) else {
                        return false
                    }
                    let binaryFilePath = directoryPath.appendingPathComponent("user.louds", isDirectory: false).path
                    return FileManager.default.fileExists(atPath: binaryFilePath)
                },
                silentDoneCondition: {
                    // ダウンロードがv1.9以降の場合はDone
                    if (SharedStore.initialAppVersion ?? .azooKey_v1_7_1) >= .azooKey_v1_9 {
                        return true
                    }
                    return false
                },
                containerAppShouldMakeItDone: {
                    // ユーザ辞書に登録がない場合はDoneにして良い。
                    // Copaky: fail-soft — if the container is unavailable there is nothing to migrate, mark as done.
                    guard let directoryPath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroupKey) else {
                        return true
                    }
                    let binaryFilePath = directoryPath.appendingPathComponent("user.louds", isDirectory: false).path
                    return !FileManager.default.fileExists(atPath: binaryFilePath)
                }
            ),
            MessageData(
                id: .ver2_1_emoji_tab,
                title: "お知らせ",
                description: "Copakyで絵文字タブが使えるようになりました。本体アプリを開き、タブバーに絵文字タブを追加しますか？",
                button: .two(primary: .openContainerURL(text: "追加", url: "copaky://", autoDone: false), secondary: .later),
                precondition: {
                    true
                },
                silentDoneCondition: {
                    // Copaky: a fresh install already carries the emoji tab in the DEFAULT tab bar,
                    // so a throwing `tabbar(identifier:0)` (no saved tab bar yet) must fall back to
                    // `.default` — otherwise this one-time notice storms on every keyboard load.
                    let tabbar = (try? CustardManager.load().tabbar(identifier: 0)) ?? .default
                    return tabbar.items.contains(where: {$0.actions.contains(.moveTab(.system(.emoji_tab)))})
                },
                containerAppShouldMakeItDone: { true }
            ),
        ]
    }
}

public extension MessageManager where ID == MessageIdentifier {
    @MainActor init() {
        self.init(necessaryMessages: AzooKeyMessageProvider.messages, userDefaults: UserDefaults(suiteName: SharedStore.appGroupKey)!)
    }
}
