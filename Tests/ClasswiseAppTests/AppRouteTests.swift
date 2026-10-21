import XCTest
@testable import Classwise
@testable import ClasswiseCore

final class AppPreferencesTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    override func setUp() { suite = "BYE-PreferencesTests-\(UUID())"; defaults = UserDefaults(suiteName: suite) }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testNameFollowsTheWindowsRule() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.displayName = "  Zoë   O’Neil-Ng \n"
        XCTAssertEqual(preferences.displayName, "Zoë O’Neil-Ng", "Ends trimmed and repeated spaces collapsed")
        for bad in ["Alex\u{0007}", "Alex<script>", "Alexandra Fictional Student", "a@b"] {
            XCTAssertFalse(AppPreferences.isValidName(AppPreferences.normalizedName(bad)), bad)
        }
        XCTAssertTrue(AppPreferences.isValidName("Nguyễn Văn 2"))
        preferences.displayName = "Alex<script>"
        XCTAssertEqual(preferences.displayName, "", "An invalid name clears rather than saving")
        defaults.set("Bad\u{0000}Name", forKey: "bye.displayName")
        XCTAssertEqual(preferences.displayName, "", "A tampered stored name reads as no name")
    }

    func testRecentClassesKeepInsertionOrderAndDropTheOldestPastFive() throws {
        let preferences = AppPreferences(defaults: defaults)
        for code in ["MATH 005A", "ENGL 001A", "MATH 005A", "CHEM 001A", "PSYC 001", "HIST 007A"] {
            preferences.remember(try Course(code))
        }
        XCTAssertEqual(preferences.recentClasses.map(\.display), ["MATH 005A", "ENGL 001A", "CHEM 001A", "PSYC 001", "HIST 007A"],
                       "Revisiting a class keeps its place")
        preferences.remember(try Course("ETH 014"))
        XCTAssertEqual(preferences.recentClasses.map(\.display), ["ENGL 001A", "CHEM 001A", "PSYC 001", "HIST 007A", "ETH 014"])
    }

    func testUnreadableStoredClassesAreIgnored() {
        defaults.set(["MATH 005A", "not a class!!", "MATH 005A"], forKey: "bye.recentClasses")
        XCTAssertEqual(AppPreferences(defaults: defaults).recentClasses.map(\.display), ["MATH 005A"])
    }
}

@MainActor
final class AppRouteTests: XCTestCase {
    private var suite = ""
    private var directory: URL!
    private var session: URLSession!
    override func setUp() {
        suite = "BYE-RouteTests-\(UUID())"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BYE-RouteTests-\(UUID())")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [RouteScheduleProtocol.self]
        session = URLSession(configuration: configuration)
    }
    override func tearDown() {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory); session.invalidateAndCancel()
    }
    private func preferences() -> AppPreferences { AppPreferences(defaults: UserDefaults(suiteName: suite)!) }
    private func model() throws -> AppModel {
        let hub = RecoveryHub()
        let model = AppModel(pcc: PCCClient(session: session), cache: ReportCache(directory: directory),
                             choices: ProfileChoiceStore(directory: directory), preferences: preferences(), makeReader: { hub.reader() })
        model.terms = try JSONDecoder().decode([Term].self, from: Data(#"[{"termCode":"202710","termName":"Fictional Term","termDisplayControl":"Y"}]"#.utf8))
        model.termID = "202710"
        return model
    }
    private func wait(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !predicate() {
            if Date() > deadline { XCTFail("Timed out: \(message)"); throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testFirstRunGoesWelcomeNameHomeAndIsRememberedOnThisMac() throws {
        let first = try model()
        XCTAssertEqual(first.route, .welcome)
        first.continueFromWelcome()
        XCTAssertEqual(first.route, .name)
        first.finishOnboarding(name: "  Alex ")
        XCTAssertEqual(first.route, .home)
        XCTAssertEqual(first.displayName, "Alex")
        let relaunched = try model()
        XCTAssertEqual(relaunched.route, .home, "The welcome shows once")
        XCTAssertEqual(relaunched.displayName, "Alex")
        XCTAssertFalse(relaunched.setDisplayName("   "), "An empty name is refused and the old one kept")
        XCTAssertEqual(relaunched.displayName, "Alex")
        relaunched.showWelcomeAgain()
        XCTAssertEqual(relaunched.route, .welcome)
    }

    func testSkippingTheNameStillFinishesTheWelcome() throws {
        let model = try model()
        model.finishOnboarding(name: "")
        XCTAssertEqual(model.route, .home)
        XCTAssertEqual(model.displayName, "")
        XCTAssertEqual(try self.model().route, .home)
    }

    func testShowingResultsBridgeLeavesTheWelcomeAlone() throws {
        let model = try model()
        model.showingResults = false
        XCTAssertEqual(model.route, .welcome)
        model.showingResults = true
        XCTAssertEqual(model.route, .results)
        model.showingResults = false
        XCTAssertEqual(model.route, .home)
    }

    func testRevisitedClassReappearsAtOnceWithItsFiltersAndOpenProfessor() async throws {
        let model = try model(); defer { model.cancel() }
        model.finishOnboarding(name: "")
        model.openClass(try Course("MATH 005A"))
        try await wait("MATH results") { !model.busy && model.showingResults }
        XCTAssertNil(model.selectedID, "No professor opens on its own")
        model.sort = .difficulty; model.availableDays = [.monday]; model.selectedID = "fictional monday"
        model.saveReviewChoice(ReviewChoice(filter: .allCourses, chosenByUser: true, sort: .lowest, limit: 8), for: "fictional monday")

        model.openClass(try Course("ENGL 001A"))
        try await wait("ENGL results") { !model.busy && model.showingResults && model.course?.display == "ENGL 001A" }
        XCTAssertNil(model.reviewChoice(for: "fictional monday"), "Review choices belong to their class")
        XCTAssertEqual(model.recentClasses.map(\.display), ["MATH 005A", "ENGL 001A"])
        model.availableDays = []; model.sort = .rating

        model.openClass(try Course("MATH 005A"))
        XCTAssertTrue(model.showingResults, "The class reappears before the reload finishes")
        XCTAssertEqual(model.course?.display, "MATH 005A")
        XCTAssertEqual(model.professors.map(\.id).sorted(), ["fictional friday", "fictional monday"])
        XCTAssertEqual(model.selectedID, "fictional monday")
        XCTAssertEqual(model.availableDays, [.monday]); XCTAssertEqual(model.sort, .difficulty)
        try await wait("MATH reload") { !model.busy }
        XCTAssertEqual(model.selectedID, "fictional monday", "Reloading keeps the open professor")
        XCTAssertEqual(model.reviewChoice(for: "fictional monday")?.limit, 8)
        XCTAssertEqual(model.recentClasses.map(\.display), ["MATH 005A", "ENGL 001A"], "Order stays as added")
    }

    func testCommandMenuFindsClassesOverResultsButNotDuringTheFirstRun() async throws {
        let model = try model(); defer { model.cancel() }
        model.commandMenuOpen = true
        XCTAssertFalse(model.commandMenuOpen, "⌘K does nothing during the welcome")
        model.finishOnboarding(name: "")
        model.openClass(try Course("MATH 005A"))
        try await wait("MATH results") { !model.busy && model.showingResults }
        model.commandMenuOpen = true
        model.updateCourseSuggestions()
        try await wait("catalog for the menu") { !model.courseMatches("ENGL").isEmpty }
        XCTAssertEqual(model.courseMatches("ENGL").first?.course.display, "ENGL 001A")
        XCTAssertTrue(model.courseMatches("E").isEmpty, "One letter is too short to match")
        XCTAssertTrue(model.suggestions.isEmpty, "Home suggestions stay off over results")
    }

    func testSettingsOpensOverTheClassAndNotDuringTheWelcome() async throws {
        let model = try model(); defer { model.cancel() }
        model.settingsTab = .general
        XCTAssertNil(model.settingsTab, "Settings waits until the welcome is finished")
        model.finishOnboarding(name: "Alex")
        model.openClass(try Course("MATH 005A"))
        try await wait("MATH results") { !model.busy && model.showingResults }
        model.selectedID = "fictional monday"
        model.commandMenuOpen = true
        model.settingsTab = .general
        XCTAssertFalse(model.commandMenuOpen, "Opening settings closes the command menu")
        XCTAssertEqual(model.route, .results, "The class stays open behind the sheet")
        XCTAssertTrue(model.setDisplayName("Sam"))
        XCTAssertEqual(model.displayName, "Sam")
        XCTAssertEqual(model.selectedID, "fictional monday")
        model.showWelcomeAgain()
        XCTAssertNil(model.settingsTab)
        XCTAssertEqual(model.route, .welcome)
    }

    func testGoingHomeKeepsTheClassForLater() async throws {
        let model = try model(); defer { model.cancel() }
        model.finishOnboarding(name: "")
        model.openClass(try Course("MATH 005A"))
        try await wait("MATH results") { !model.busy && model.showingResults }
        model.selectedID = "fictional friday"
        model.goHome()
        XCTAssertEqual(model.route, .home)
        model.openClass(try Course("MATH 005A"))
        XCTAssertEqual(model.selectedID, "fictional friday")
    }
}

private final class RouteScheduleProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let rows = """
        [{"subjCode":"MATH","subjDesc":"Mathematics","courseNumbDisplay":"005A","crn":"1","pfaName":"Fictional Monday","monDay":"M","fwSectOpenInd":"O"},
         {"subjCode":"MATH","subjDesc":"Mathematics","courseNumbDisplay":"005A","crn":"2","pfaName":"Fictional Friday","friDay":"F","fwSectOpenInd":"O"},
         {"subjCode":"ENGL","subjDesc":"English","courseNumbDisplay":"001A","crn":"3","pfaName":"Fictional Writer","tueDay":"T","fwSectOpenInd":"O"}]
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(rows.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
