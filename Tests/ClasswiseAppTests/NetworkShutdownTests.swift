import XCTest
@testable import Classwise

@MainActor
final class NetworkShutdownTests: XCTestCase {
    func testReleaseIsOnline() {
        XCTAssertFalse(NetworkShutdown.isActive, "0.5.0 ships with search, ratings and updates turned back on.")
    }

    func testDistributionInfoEnablesUpdatesWhenOnline() {
        // ClasswiseApp passes the bundle info while the shutdown is off. Checked statically so the test never starts Sparkle.
        let info: [String: Any]? = NetworkShutdown.isActive ? nil : ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "key"]
        XCTAssertTrue(AppUpdater.isConfigured(info: info))
    }

    func testUpdaterStaysInertWithoutFeed() {
        let updater = AppUpdater(info: nil)
        XCTAssertFalse(updater.isEnabled)
        XCTAssertFalse(updater.canCheckForUpdates)
    }
}
