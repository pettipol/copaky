//
//  App.swift
//  App
//
//  Created by ensan on 2021/08/22.
//  Copyright © 2021 ensan. All rights reserved.
//

import AzooKeyUtils
import KeyboardViews
import SwiftUI

final class MainAppStates: ObservableObject {
    /// Copaky [H-23]: setup completion explicitly confirmed by the user; not live activation.
    @Published var hasCompletedKeyboardSetup: Bool
    @Published var requireFirstOpenView: Bool
    @Published var japaneseLayout: LanguageLayout = .flick
    @Published var englishLayout: LanguageLayout = .flick
    @Published var custardManager: CustardManager
    @Published var internalSettingManager = ContainerInternalSetting()
    @Published var requestReviewManager = RequestReviewManager()

    @MainActor init() {
        let setupCompleted = SharedStore.hasCompletedKeyboardSetup()
        self.hasCompletedKeyboardSetup = setupCompleted
        self.requireFirstOpenView = !setupCompleted
        @KeyboardSetting(.japaneseKeyboardLayout) var japaneseKeyboardLayout
        self.japaneseLayout = japaneseKeyboardLayout
        @KeyboardSetting(.englishKeyboardLayout) var englishKeyboardLayout
        self.englishLayout = englishKeyboardLayout
        self.custardManager = CustardManager.load()
        SemiStaticStates.shared.setHapticsAvailable()
        SemiStaticStates.shared.setScreenWidth(UIScreen.main.bounds.width)
    }

    @MainActor func confirmKeyboardSetup() {
        UserDefaults.standard.set(true, forKey: "copaky_keyboard_setup_confirmed")
        hasCompletedKeyboardSetup = true
        requireFirstOpenView = false
    }

    func setTutorialProgress(_ progress: EnableAzooKeyViewProgress) {
        UserDefaults.standard.set(progress.rawValue, forKey: "tutorial_progress")
    }
    private func resumeTutorialProgress() -> EnableAzooKeyViewProgress? {
        if let progressString = UserDefaults.standard.string(forKey: "tutorial_progress") {
            return EnableAzooKeyViewProgress(rawValue: progressString)
        } else {
            return nil
        }
    }
    func tutorialFinishedSuccessfully() -> Bool {
        if let progress = resumeTutorialProgress() {
            // finishで終わっていない場合、適切ではない
            return progress == .finish
        } else {
            return true
        }
    }
}

@main
struct MainApp: App {
    @StateObject private var appStates = MainAppStates()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStates)
                .onAppear {
                    // MARK: セットアップ
                    SemiStaticStates.shared.setup()
                    // Copaky [G-38]: a build-8 history that grew past the 4 MiB budget is unreadable by the
                    // extension (collapsed); the container app has no memory ceiling and shrinks it here.
                    if let historyURL = ClipboardHistoryManager.historyFileLocation(config: ClipboardHistoryManagerConfig()) {
                        let maxCount = ClipboardHistoryManagerConfig().maxCount
                        Task.detached(priority: .utility) {
                            _ = ClipboardHistoryManager.repairUnreadableHistory(at: historyURL, maxCount: maxCount)
                        }
                    }
                    SharedStore.setInitialAppVersion()
                    SharedStore.setLastAppVersion()
                    // 本体アプリで特定の作業を行わなずにDoneにできる場合。
                    var messageManager = MessageManager()
                    messageManager.getMessagesContainerAppShouldMakeWhichDone().forEach {
                        messageManager.done($0.id)
                    }
                    // 設定を上書きする
                    // Copaky: isCopakyEra — a 0.x initial install is a fresh install, not a pre-2.2.3 legacy one
                    if let initialVersion = SharedStore.initialAppVersion,
                       initialVersion > .azooKey_v2_2_2 || initialVersion.isCopakyEra,
                       KeepDeprecatedShiftKeyBehavior.get() == nil {
                        // Version 2.2.3以降にインストールしたユーザにはこのオプションを有効化しない
                        // Copaky [G-01]: initialize only an absent key; preserve every stored upgrade value.
                        KeepDeprecatedShiftKeyBehavior.value = false
                    }
                }
        }
    }
}
