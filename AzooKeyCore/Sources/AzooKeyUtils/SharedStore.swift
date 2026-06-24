//
//  SharedStore.swift
//  azooKey
//
//  Created by ensan on 2020/11/20.
//  Copyright © 2020 ensan. All rights reserved.
//

import Foundation
import SwiftUtils

public enum SharedStore {
    @MainActor public static let userDefaults = UserDefaults(suiteName: Self.appGroupKey)!
    public static let bundleName = "DevEn3.azooKey.keyboard"
    public static let appGroupKey = "group.com.azooKey.keyboard"

    private static var appVersionString: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
    private static let initialAppVersionKey = "InitialAppVersion"
    private static let lastAppVersionKey = "LastAppVersion"
    public static var currentAppVersion: AppVersion? {
        if let appVersionString = appVersionString {
            return AppVersion(appVersionString)
        }
        return nil
    }
    // this value will be 1.7.1 at minimum
    @MainActor public static var initialAppVersion: AppVersion? {
        if let appVersionString = userDefaults.string(forKey: initialAppVersionKey) {
            return AppVersion(appVersionString)
        }
        return nil
    }

    // this value will be 2.0.0 at minimum
    @MainActor public static var lastAppVersion: AppVersion? {
        if let appVersionString = userDefaults.string(forKey: lastAppVersionKey) {
            return AppVersion(appVersionString)
        }
        return nil
    }

    @MainActor public static func setInitialAppVersion() {
        if initialAppVersion == nil, let appVersionString = appVersionString {
            SharedStore.userDefaults.set(appVersionString, forKey: initialAppVersionKey)
        }
    }

    @MainActor public static func setLastAppVersion() {
        if let appVersionString = appVersionString {
            SharedStore.userDefaults.set(appVersionString, forKey: lastAppVersionKey)
        }
    }

    public enum ShareThisWordOptions: String, Sendable {
        case 人・動物・会社などの名前
        case 場所・建物などの名前
        case 五段活用
    }

    public static func sendSharedWord(word: String, ruby: String, note: String? = nil, options: [ShareThisWordOptions]) async -> Bool {
        // Disabilitato per conformità offline completa (SviluppoTastieraOpen)
        debug("SharedStore.sendSharedWord disabilitato offline-only")
        return true
    }
}
