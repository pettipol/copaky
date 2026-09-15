//
//  SharedStore.swift
//  azooKey
//
//  Created by ensan on 2020/11/20.
//  Copyright © 2020 ensan. All rights reserved.
//

import Foundation
import SwiftUtils
import os

private let sharedStoreLog = OSLog(subsystem: "com.pettipol.copaky", category: "SharedStore")

public enum SharedStore {
    @MainActor public static let userDefaults = Self.groupUserDefaults(suiteName: Self.appGroupKey)
    public static let bundleName = "com.pettipol.copaky.keyboard"
    public static let appGroupKey = "group.com.pettipol.copaky"

    /// Copaky [H-21]: the App Group suite must never crash the extension — a lost entitlement or
    /// provisioning-profile mismatch falls back to `.standard` and is reported via os_log.
    /// Copaky [H-21]: App Group はエクステンションをクラッシュさせてはならない — 権限や
    /// プロビジョニングプロファイルの不整合時は `.standard` にフォールバックし、os_log で報告する。
    public static func groupUserDefaults(suiteName: String) -> UserDefaults {
        if let defaults = UserDefaults(suiteName: suiteName) {
            return defaults
        }
        os_log(.fault, log: sharedStoreLog, "[H-21] App Group UserDefaults unavailable for suite %{public}@; falling back to standard defaults", suiteName)
        return .standard
    }

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

}
