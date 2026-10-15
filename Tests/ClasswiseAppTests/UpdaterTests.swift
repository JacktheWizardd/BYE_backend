import XCTest
@testable import Classwise

final class UpdaterTests: XCTestCase {
    private let key = "CpVpvUEH+nVuA7BEZ1IJqGfSDPF8DyYL8FAx+DEF78o="

    func testUnconfiguredBundlesStayInert() {
        XCTAssertFalse(AppUpdater.isConfigured(info: nil))
        XCTAssertFalse(AppUpdater.isConfigured(info: [:]))
        XCTAssertFalse(AppUpdater.isConfigured(info: ["CFBundleName": "BYE Test"]))
        XCTAssertFalse(AppUpdater.isConfigured(info: ["SUFeedURL": "https://example.com/appcast.xml"]))
        XCTAssertFalse(AppUpdater.isConfigured(info: ["SUFeedURL": " ", "SUPublicEDKey": key]))
        XCTAssertFalse(AppUpdater.isConfigured(info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": ""]))
    }

    func testInsecureRemoteFeedsAreRejected() {
        XCTAssertFalse(AppUpdater.isConfigured(info: ["SUFeedURL": "http://example.com/appcast.xml", "SUPublicEDKey": key]))
        XCTAssertFalse(AppUpdater.isConfigured(info: ["SUFeedURL": "file:///tmp/appcast.xml", "SUPublicEDKey": key]))
    }

    func testDistributionAndLocalVerificationFeedsAreAccepted() {
        XCTAssertTrue(AppUpdater.isConfigured(info: ["SUFeedURL": "https://raw.githubusercontent.com/o/r/main/appcast.xml", "SUPublicEDKey": key]))
        XCTAssertTrue(AppUpdater.isConfigured(info: ["SUFeedURL": "http://127.0.0.1:8000/appcast.xml", "SUPublicEDKey": key]))
    }

    @MainActor
    func testUnconfiguredUpdaterDoesNothing() {
        let updater = AppUpdater(info: nil)
        XCTAssertFalse(updater.isEnabled)
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        updater.checkForUpdates()
    }
}
