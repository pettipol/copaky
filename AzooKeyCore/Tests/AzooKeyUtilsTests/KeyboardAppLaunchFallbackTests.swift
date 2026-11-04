import Foundation
import CustardKit
import XCTest
@testable import KeyboardViews

// Copaky [H-17]: preserve legacy decoding while replacing all launches with safe instructions.
final class KeyboardAppLaunchFallbackTests: XCTestCase {
    func testLegacyContainingAppAndShortcutsActionsRemainDecodable() throws {
        for (scheme, target, expected) in [
            (LaunchItem.LaunchableApplication.azooKey, "settings", "copaky://settings"),
            (.shortcuts, "run-shortcut?name=Example", "shortcuts://run-shortcut?name=Example")
        ] {
            let legacy = CodableActionData.launchApplication(.init(scheme: scheme, target: target))
            let data = try JSONEncoder().encode(legacy)
            let decoded = try JSONDecoder().decode(CodableActionData.self, from: data)
            XCTAssertEqual(decoded.actionType, .openApp(expected), "Saved and imported legacy actions must still decode")
        }
    }

    func testManualInstructionsCoverContainingAppAndAllOtherSchemes() {
        XCTAssertEqual(TemporalMessage.blockedAppLaunch(scheme: "copaky://settings"), .openCopakyManually)
        XCTAssertEqual(TemporalMessage.blockedAppLaunch(scheme: "COPAKY://"), .openCopakyManually)
        for target in ["shortcuts://run-shortcut?name=Example", "https://example.com", "", "invalid"] {
            XCTAssertEqual(TemporalMessage.blockedAppLaunch(scheme: target), .appLaunchUnavailable,
                           "Unsupported and malformed destinations must fail closed without launching")
        }
        for message in [TemporalMessage.openCopakyManually, .appLaunchUnavailable] {
            guard case .ok = message.dismissCondition else {
                XCTFail("Instructions must remain visible until the user acknowledges them")
                return
            }
        }
        // Distinct arbitrary payloads produce the same payload-free enum case, never a URL-bearing error.
        XCTAssertEqual(TemporalMessage.blockedAppLaunch(scheme: "shortcuts://private-first"),
                       TemporalMessage.blockedAppLaunch(scheme: "https://private-second"))
    }
}
