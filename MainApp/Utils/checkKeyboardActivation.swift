import Foundation
import enum AzooKeyUtils.SharedStore

extension SharedStore {
    // Copaky [H-23]: local user confirmation; this does not detect enabled keyboards.
    // Copaky [H-23]: ユーザーによる確認のみを保存し、キーボードの有効状態は判定しない。
    @MainActor static func hasCompletedKeyboardSetup() -> Bool {
        UserDefaults.standard.bool(forKey: "copaky_keyboard_setup_confirmed")
    }
}
