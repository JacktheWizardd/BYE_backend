import XCTest
@testable import Classwise

@MainActor
final class NetworkShutdownTests: XCTestCase {
    func testFinalReleaseIsOffline() {
        XCTAssertTrue(NetworkShutdown.isActive, "The final release must ship with all network features off.")
    }

    func testUpdaterStaysInertWhenShutDown() {
        // ClasswiseApp passes nil info while the shutdown is active, which never starts Sparkle.
        let updater = AppUpdater(info: NetworkShutdown.isActive ? nil : ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "key"])
        XCTAssertFalse(updater.isEnabled)
        XCTAssertFalse(updater.canCheckForUpdates)
    }
}
