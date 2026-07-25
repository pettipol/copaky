//
//  CopakyAssetCaptureTests.swift — instructional-asset recapture (F1 residue)
//  同梱チュートリアル画像の再撮影用スイート（F1残作業）
//
//  Captures, per system language and appearance (both set by the orchestrator,
//  scripts/asset_capture.sh):
//    asset_appsettings   Settings ▸ Apps ▸ Copaky page (base for
//                        initSettingKeyboardImage-hand; on a physical device the
//                        same page also shows "Paste from Other Apps" →
//                        pasteFromOtherAppsSetting)
//    asset_keyboards     Settings ▸ … ▸ Copaky keyboards page (base for
//                        initSettingAzooKeySwitchImage-hand)
//    asset_fa_alert      the Allow-Full-Access warning alert, captured BEFORE
//                        dismissing it (base for fullAccessAlert)
//
//  The suite leaves Full Access ON (alert dismissed with Allow/許可).
//  Simulator note: the paste-permission dialog (pasteRequestDialogue) and the
//  "Paste from Other Apps" settings row do NOT exist on the Simulator — those
//  two assets are capturable on a physical device only (same suite works there).
//

import XCTest

@MainActor
final class CopakyAssetCaptureTests: XCTestCase {

    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    /// Multi-locale Settings labels (system language: ja / en; it kept for local dev).
    private enum AL {
        static let apps = ["アプリ", "Apps", "App"]
        static let keyboards = ["キーボード", "Keyboards", "Tastiere"]
        static let allowFullAccess = ["フルアクセスを許可", "Allow Full Access", "Consenti accesso completo", "Consenti pieno accesso"]
        static let allowButton = ["許可", "Allow", "Consenti"]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Helpers (self-contained, mirroring CopakyScreenshotTests)

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(string: app.debugDescription)
        a.name = "tree-\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    private func settle(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func firstMatch(in app: XCUIApplication, labels: [String], timeout: TimeInterval = 6) -> XCUIElement? {
        let pred = NSPredicate(format: "label IN %@ OR identifier IN %@ OR title IN %@", labels, labels, labels)
        let queries: [XCUIElementQuery] = [
            app.cells.matching(pred),
            app.buttons.matching(pred),
            app.switches.matching(pred),
            app.staticTexts.matching(pred),
            app.otherElements.matching(pred),
        ]
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for q in queries where q.firstMatch.exists {
                return q.firstMatch
            }
            settle(0.3)
        } while Date() < deadline
        return nil
    }

    @discardableResult
    private func tapFirst(in app: XCUIApplication, labels: [String], timeout: TimeInterval = 6, scrollUpTo scrolls: Int = 0) -> Bool {
        var attempts = 0
        repeat {
            if let el = firstMatch(in: app, labels: labels, timeout: timeout), el.isHittable {
                el.tap()
                return true
            }
            if attempts < scrolls {
                app.swipeUp()
                settle(0.5)
            }
            attempts += 1
        } while attempts <= scrolls
        return false
    }

    // MARK: - Capture

    func test_assetCapture() throws {
        settings.launch()
        settle(1.0)

        // Settings root → Apps (bottom of the root list)
        XCTAssertTrue(tapFirst(in: settings, labels: AL.apps, timeout: 4, scrollUpTo: 4),
                      "Apps row not found in Settings root")
        settle(0.8)

        // Apps list → Copaky
        XCTAssertTrue(tapFirst(in: settings, labels: ["Copaky"], timeout: 6, scrollUpTo: 2),
                      "Copaky row not found in Apps list")
        settle(1.0)
        shot("asset_appsettings")

        // Copaky page → Keyboards
        XCTAssertTrue(tapFirst(in: settings, labels: AL.keyboards, timeout: 6, scrollUpTo: 1),
                      "Keyboards row not found on Copaky page")
        settle(1.0)

        // Full Access switch: force OFF BEFORE the page shot (turning OFF shows no
        // alert) so asset_keyboards is deterministic across appearance passes —
        // the enable-flow image must show Full Access not yet granted.
        let fa = settings.switches.matching(NSPredicate(format: "label IN %@", AL.allowFullAccess)).firstMatch
        guard fa.waitForExistence(timeout: 6) else {
            dump(settings, "asset-no-fa-toggle")
            XCTFail("Allow Full Access switch not found")
            return
        }
        if (fa.value as? String) == "1" {
            fa.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            settle(1.2)
        }
        shot("asset_keyboards")

        fa.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        let alert = settings.alerts.firstMatch
        guard alert.waitForExistence(timeout: 6) else {
            dump(settings, "asset-no-fa-alert")
            XCTFail("Full Access alert did not appear")
            return
        }
        settle(0.6)
        shot("asset_fa_alert")

        // Dismiss with Allow so the simulator/device state stays Full-Access-ON
        let allow = settings.alerts.buttons.matching(NSPredicate(format: "label IN %@", AL.allowButton)).firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 4), "Allow button not found on Full Access alert")
        allow.tap()
        settle(1.0)
        XCTAssertEqual(fa.value as? String, "1", "Allow Full Access did not turn ON")
    }
}
