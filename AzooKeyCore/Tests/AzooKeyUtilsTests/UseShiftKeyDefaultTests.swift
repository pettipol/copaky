import Foundation
@testable import AzooKeyUtils
import XCTest

final class UseShiftKeyDefaultTests: XCTestCase {
    @MainActor
    func testProductionDefaultsUseBottomLeftShift() {
        XCTAssertTrue(UseShiftKey.defaultValue)
        XCTAssertFalse(KeepDeprecatedShiftKeyBehavior.defaultValue)
    }

    @MainActor
    func testStoredValuesSurviveDefaultUpgrade() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(false, forKey: UseShiftKey.key)
        userDefaults.set(true, forKey: KeepDeprecatedShiftKeyBehavior.key)

        XCTAssertFalse(UseShiftKey.resolvedValue(from: userDefaults), "A stored Shift-off choice must survive the new default")
        XCTAssertTrue(KeepDeprecatedShiftKeyBehavior.resolvedValue(from: userDefaults), "A stored legacy-layout choice must survive the new default")
    }

    @MainActor
    func testMissingKeysResolveToNewDefaultsWithoutMaterializing() throws {
        let (userDefaults, suiteName) = try makeUserDefaults()
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(UseShiftKey.resolvedValue(from: userDefaults))
        XCTAssertFalse(KeepDeprecatedShiftKeyBehavior.resolvedValue(from: userDefaults))
        XCTAssertNil(userDefaults.object(forKey: UseShiftKey.key), "Resolving a default must not persist it")
        XCTAssertNil(userDefaults.object(forKey: KeepDeprecatedShiftKeyBehavior.key), "Resolving a default must not persist it")
    }

    private func makeUserDefaults() throws -> (UserDefaults, String) {
        let suiteName = "UseShiftKeyDefaultTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return (userDefaults, suiteName)
    }
}
