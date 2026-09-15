//
//  checkKeyboardActivation.swift
//  azooKey
//
//  Created by ensan on 2023/03/14.
//  Copyright © 2023 ensan. All rights reserved.
//

import Foundation
import class UIKit.UITextInputMode
import enum AzooKeyUtils.SharedStore

extension SharedStore {
    @MainActor static func checkKeyboardActivation() -> Bool {
        // Copaky [H-23]: private KVC key inherited from upstream; guarded so a missing accessor
        // degrades to "not detected" instead of crashing.
        // Copaky [H-23]: 上流由来の非公開KVCキー。アクセサが無ければクラッシュせず「未検出」に留める。
        let keyboards = UITextInputMode.activeInputModes.compactMap { mode -> String? in
            guard mode.responds(to: Selector(("identifier"))) else {
                return nil
            }
            return mode.value(forKey: "identifier") as? String
        }
        return keyboards.contains { $0.hasPrefix(SharedStore.bundleName) }
    }
}
