//
//  ReclaimUITests.swift
//  ReclaimUITests
//
//  Simulator UI validation (docs/25 "Simulator" column). Scope is
//  deliberately narrow and deterministic: these tests run on a fresh
//  GitHub-hosted iOS 17.5 simulator with an EMPTY photo library and a
//  .notDetermined permission state, so they assert what is stable in that
//  environment:
//
//    - the app launches into the Dashboard with its core controls,
//    - the storage card shows REAL device capacity (any simulator has a
//      real container volume — the app must display it, never a 0/blank
//      placeholder),
//    - permission states render their intended affordances before any
//      system dialog (first run = .notDetermined for both frameworks),
//    - the scan gate: the control exists but is DISABLED until any
//      permission is granted (docs/25 Permissions row, automated portion).
//
//  Query strategy: controls are located by explicit accessibility
//  identifiers ("dashboard.scanButton") where XCUITest's automatic label
//  joining proved unreliable for styled SwiftUI Button content (Label with
//  .borderedProminent — run 33), and by static text labels elsewhere.
//  The accessibilityHint string (the on-device privacy disclosure) is not
//  exposed through the XCUITest element graph, so it is covered by the
//  code audit (docs/24 §12) rather than a runtime assertion.
//
//  They intentionally do NOT tap "Allow" (no system-permission-dialog
//  automation) and do NOT run a scan (an empty library makes scan-result
//  assertions vacuous). Deleting real assets can never happen in UI tests:
//  the destructive path requires photos to exist, a selection, and an
//  explicit confirmation — none of which these tests construct.
//
//  This is simulator validation, NOT physical-device validation.
//

import XCTest

final class ReclaimUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    // MARK: - Launch & dashboard contract

    @discardableResult
    private func launchToDashboard() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Reclaim"].waitForExistence(timeout: 10),
                      "the Dashboard must render its navigation title on launch")
        return app
    }

    /// The scan control, located by its explicit accessibility identifier —
    /// robust against SwiftUI's label joining of styled Label content.
    private func scanButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["dashboard.scanButton"]
    }

    func test_launch_rendersDashboardStorageCardAndScanControl() throws {
        let app = launchToDashboard()

        XCTAssertTrue(app.staticTexts["Storage"].exists,
                      "the storage card must be present on the dashboard")
        XCTAssertTrue(scanButton(in: app).waitForExistence(timeout: 5),
                      "the scan control must exist on first launch")
    }

    func test_storageCard_showsRealCapacity_notABlankOrPlaceholder() throws {
        let app = launchToDashboard()

        // DeviceCapacity is read from the simulator's real container volume;
        // the card renders "<used> used of <total>". A missing row means the
        // app failed to read real capacity — an error state would render
        // "Storage information unavailable" instead, which this assertion
        // also rejects.
        let usedOfPredicate = NSPredicate(format: "label CONTAINS %@", "used of")
        let usedOfText = app.staticTexts.matching(usedOfPredicate).firstMatch
        XCTAssertTrue(usedOfText.waitForExistence(timeout: 5),
                      "the storage card must display real device capacity ('used of <total>'); showing the unavailable-state text here means capacity reading failed")
        XCTAssertFalse(usedOfText.label.contains("unavailable"),
                       "the unavailable state must not masquerade as a capacity reading")
    }

    func test_firstLaunch_unrequestedPermissions_renderTheirAffordances() throws {
        let app = launchToDashboard()

        // Fresh install = .notDetermined for both frameworks: each prompt
        // row renders with an "Allow" button. This verifies the app's own
        // permission-state UI (docs/25 Permissions row, automated portion).
        // The system permission dialog itself is NOT automation-verified
        // here — disclosed limitation in docs/25.
        XCTAssertTrue(app.staticTexts["Photos Access"].waitForExistence(timeout: 5),
                      "photos prompt row must render while access is not yet determined")
        XCTAssertTrue(app.staticTexts["Contacts Access"].exists,
                      "contacts prompt row must render while access is not yet determined")
        XCTAssertTrue(app.buttons["Allow"].firstMatch.exists,
                      "an Allow affordance must exist while access is not yet determined")
    }

    func test_scanControl_disabledUntilAnyPermissionGranted() throws {
        let app = launchToDashboard()

        let button = scanButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        // First launch, nothing granted: the scan button is disabled rather
        // than hidden — the UI must show the user the path, gated. isEnabled
        // is readable on the (non-hittable) disabled control.
        XCTAssertFalse(button.isEnabled,
                       "scanning must be impossible until at least one permission is granted")
    }
}
