//
//  KeyboardSetting.swift
//  KeyboardSetting
//
//  Created by ensan on 2021/08/10.
//  Copyright © 2021 ensan. All rights reserved.
//

import Foundation
import SwiftUI

protocol Savable {
    associatedtype SaveValue
    var saveValue: SaveValue {get}
    static func get(_ value: Any) -> Self?
}

@propertyWrapper
public struct KeyboardSetting<T: KeyboardSettingKey> {
    public init(_ key: T) {}
    @MainActor public var wrappedValue: T.Value {
        get {
            T.value
        }
        set {
            T.value = newValue
        }
    }
}

/// 生の`SettingKey`の値を`@State`で宣言した場合、更新の反映ができない。
/// `SettingUpdater`で包むことで、設定の更新を行いつつUIの更新も行われるようにできる。
@MainActor public struct SettingUpdater<Wrapped: KeyboardSettingKey> {
    private var storedValue: Wrapped.Value

    public var value: Wrapped.Value {
        get {
            storedValue
        }
        set {
            storedValue = newValue
            Wrapped.value = newValue
        }
    }

    public init() {
        self.storedValue = Wrapped.value
    }

    public mutating func reload() {
        // Copaky [G-04]: refreshing UI state must not materialize a missing default on disk.
        self.storedValue = Wrapped.value
    }
}

public protocol KeyboardSettingKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
    @MainActor static var title: LocalizedStringKey { get }
    @MainActor static var explanation: LocalizedStringKey { get }
    @MainActor static var value: Value { get set }
    static var requireFullAccess: Bool { get }
}

public protocol StoredInUserDefault {
    associatedtype Value
    static var key: String { get }
}

public extension KeyboardSettingKey {
    static var requireFullAccess: Bool {
        false
    }
}
