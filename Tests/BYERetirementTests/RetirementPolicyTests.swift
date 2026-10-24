import XCTest
@testable import BYERetirement

final class RetirementPolicyTests: XCTestCase {
    func testOnlyDistributionFeedIsAllowed() {
        XCTAssertTrue(RetirementPolicy.allowsFeed(RetirementPolicy.site + "/updates/appcast.xml"))
        for value in ["https://evil.example/updates/appcast.xml", RetirementPolicy.site + "/api/reviews/", RetirementPolicy.site + "/updates/appcast.xml?x=1", "https://user@bye-before-you-enroll.pages.dev/updates/appcast.xml", "http://127.0.0.1:8798/appcast.xml"] {
            XCTAssertFalse(RetirementPolicy.allowsFeed(value))
        }
    }
    func testLoopbackRequiresVerificationBuild() {
        XCTAssertTrue(RetirementPolicy.allowsFeed("http://127.0.0.1:8798/appcast.xml", verification: true))
        XCTAssertFalse(RetirementPolicy.allowsFeed("http://127.0.0.1:8798/anything", verification: true))
        XCTAssertFalse(RetirementPolicy.allowsFeed("http://192.168.1.1/appcast.xml", verification: true))
    }
    func testUnbundledTestRunnerCannotRevealArbitraryFolder() {
        XCTAssertNil(RetirementPolicy.revealURL(bundle: Bundle(for: Self.self)))
    }
}
