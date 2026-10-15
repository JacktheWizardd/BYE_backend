import XCTest
@testable import Classwise
@testable import ClasswiseCore

@MainActor
final class ScheduleFilterTests: XCTestCase {
    private func fixture() throws -> (AppModel, URL, FilterReaderCounter) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BYE-DayTests-\(UUID())")
        let counter = FilterReaderCounter()
        let model = AppModel(summaryProvider: FilterSummary(), cache: ReportCache(directory: directory),
                             choices: ProfileChoiceStore(directory: directory), makeReader: { FilterReader(counter: counter) })
        let course = try Course("MATH005A")
        let records: [[String: String]] = [
            ["crn": "A1", "pfaName": "Alpha Instructor", "monDay": "M", "wedDay": "W"],
            ["crn": "A2", "pfaName": "Alpha Instructor", "tueDay": "T"],
            ["crn": "A3", "pfaName": "Alpha Instructor", "schdCode": "OD"],
            ["crn": "A4", "pfaName": "Alpha Instructor"],
            ["crn": "B1", "pfaName": "Beta Instructor", "friDay": "F"],
            ["crn": "C1", "pfaName": "Gamma Instructor", "schdCode": "OL", "satDay": "S", "sunDay": "U"],
            ["crn": "D1", "pfaName": "Delta Instructor", "monDay": "M"],
            ["crn": "D1", "pfaName": "Delta Instructor", "schdCode": "B"]
        ].map { ["subjCode": "MATH", "courseNumbDisplay": "005A", "schdCode": "L", "courseTitle": "Fictional Calculus"]
            .merging($0, uniquingKeysWith: { _, value in value }) }
        let rows = try JSONDecoder().decode([ScheduleRow].self, from: JSONSerialization.data(withJSONObject: records))
        model.course = course; model.input = course.display
        model.professors = ScheduleParser.professors(rows: rows, course: course)
        model.showingResults = true; model.selectedID = "alpha instructor"
        return (model, directory, counter)
    }

    func testFiltersSectionsBeforeProfessorsAndUpdatesCountsWithoutDiscardingSourceData() throws {
        let (model, directory, counter) = try fixture()
        defer { model.cancel(); try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(model.availableDays.isEmpty)
        XCTAssertEqual(model.sectionCount, 7)
        XCTAssertEqual(model.filtered.count, 4)
        let original = model.professors
        model.availableDays = [.monday, .wednesday]
        XCTAssertEqual(model.sectionCount, 2)
        XCTAssertEqual(model.filtered.map(\.name), ["Alpha Instructor"])
        XCTAssertEqual(model.selected?.sections.map(\.crn), ["A1", "A3"])
        XCTAssertEqual(model.professors.flatMap(\.sections), original.flatMap(\.sections))
        model.availableDays = [.monday, .tuesday, .wednesday, .thursday]
        XCTAssertEqual(model.sectionCount, 1, "More picked days keeps only classes meeting on all of them, plus fully online")
        XCTAssertEqual(model.filtered.count, 1)
        XCTAssertEqual(model.selected?.sections.map(\.crn), ["A3"])
        model.availableDays = [.tuesday]
        XCTAssertEqual(model.sectionCount, 2)
        XCTAssertEqual(model.filtered.count, 1)
        XCTAssertEqual(model.selected?.sections.map(\.crn), ["A2", "A3"])
        model.availableDays.removeAll()
        XCTAssertEqual(model.sectionCount, 7)
        XCTAssertEqual(model.filtered.count, 4)
        XCTAssertEqual(counter.calls, 0, "Day changes must not start lookups")
    }

    func testOnlineOnlyCombinesWithDaysAndClearingDaysRestoresUnknownSchedules() throws {
        let (model, directory, counter) = try fixture()
        defer { model.cancel(); try? FileManager.default.removeItem(at: directory) }
        model.availableDays = [.monday]
        XCTAssertEqual(model.selected?.sections.map(\.crn), ["A1", "A3"])
        XCTAssertTrue(model.filtered.contains { $0.id == "delta instructor" }, "A known Monday meeting matches even with a TBA lab")
        model.onlineOnly = true
        XCTAssertEqual(model.sectionCount, 1)
        XCTAssertEqual(model.filtered.count, 1)
        XCTAssertEqual(model.selected?.sections.map(\.crn), ["A3"])
        model.availableDays = [.saturday, .sunday]
        XCTAssertEqual(model.selected?.sections.map(\.crn), ["A3"])
        model.onlineOnly = false
        XCTAssertEqual(model.sectionCount, 2)
        XCTAssertTrue(model.filtered.contains { $0.name == "Gamma Instructor" })
        model.availableDays = [.saturday]
        XCTAssertEqual(model.sectionCount, 2, "A Saturday/Sunday class meets on Saturday")
        XCTAssertTrue(model.filtered.contains { $0.name == "Gamma Instructor" })
        model.availableDays = [.saturday, .monday]
        XCTAssertEqual(model.sectionCount, 1)
        XCTAssertFalse(model.filtered.contains { $0.name == "Gamma Instructor" })
        model.availableDays.removeAll()
        XCTAssertEqual(model.sectionCount, 7)
        XCTAssertTrue(model.selected?.sections.first(where: { $0.crn == "A4" })?.scheduleNotAnnounced == true)
        XCTAssertTrue(model.filtered.first(where: { $0.id == "delta instructor" })?.sections.first?.scheduleNotAnnounced == true)
        XCTAssertEqual(counter.calls, 0)
    }

    func testSelectionStaysWhenVisibleAndReturnsToOverviewWhenHidden() throws {
        let (model, directory, _) = try fixture()
        defer { model.cancel(); try? FileManager.default.removeItem(at: directory) }
        model.availableDays = [.monday, .wednesday]
        XCTAssertEqual(model.selectedID, "alpha instructor", "A visible choice is kept")
        model.availableDays = []
        model.selectedID = "beta instructor"
        model.availableDays = [.monday]
        XCTAssertNil(model.selectedID, "Hiding the open professor returns to the overview, never to someone else")
        model.availableDays = []
        model.selectedID = "delta instructor"
        model.onlineOnly = true
        XCTAssertNil(model.selectedID)
        model.professors = model.professors.filter { $0.name == "Beta Instructor" }
        model.reconcileSelection()
        XCTAssertTrue(model.filtered.isEmpty)
        XCTAssertEqual(model.sectionCount, 0)
        XCTAssertNil(model.selectedID)
        model.onlineOnly = false
        model.availableDays = []
        XCTAssertNil(model.selectedID, "No professor opens on its own when results reappear")
        XCTAssertEqual(model.filtered.map(\.name), ["Beta Instructor"])
        model.selectedID = "beta instructor"
        model.availableDays = [.monday, .wednesday]
        XCTAssertTrue(model.filtered.isEmpty, "Days that miss a class meeting must produce an empty result")
        XCTAssertEqual(model.sectionCount, 0)
        XCTAssertNil(model.selectedID)
        model.availableDays.removeAll()
        XCTAssertEqual(model.sectionCount, 1)
        XCTAssertNil(model.selectedID)
    }

    func testNoProfessorIsSelectedUntilTheStudentPicks() throws {
        let (model, directory, _) = try fixture()
        defer { model.cancel(); try? FileManager.default.removeItem(at: directory) }
        model.selectedID = nil
        model.reconcileSelection()
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.selected)
        model.sort = .difficulty
        model.reconcileSelection()
        XCTAssertNil(model.selected, "Sorting never opens a professor")
    }

    func testHiddenSelectionIsReconciledEvenWhenTopFiveIDsDoNotChange() throws {
        let (model, directory, _) = try fixture()
        defer { model.cancel(); try? FileManager.default.removeItem(at: directory) }
        let monday = Section(crn: "m", title: "Fictional", start: "", end: "", formats: ["L"], meetings: [], status: "O",
                             schedule: SectionSchedule(days: [.monday], hasUnannouncedMeetings: false))
        let friday = Section(crn: "f", title: "Fictional", start: "", end: "", formats: ["L"], meetings: [], status: "O",
                             schedule: SectionSchedule(days: [.friday], hasUnannouncedMeetings: false))
        model.professors = (0..<6).map { Professor(id: "p\($0)", name: "Professor \($0)", sections: [$0 == 5 ? friday : monday]) }
        model.selectedID = "p5"
        let before = model.displayed.map(\.id)
        model.availableDays = [.monday]
        XCTAssertEqual(model.displayed.map(\.id), before)
        XCTAssertNil(model.selectedID, "The hidden report closes instead of switching to the first card")
    }

    func testSharedDaysSurviveChangeSearchStartAndRefresh() throws {
        let (model, directory, _) = try fixture()
        defer { model.cancel(); try? FileManager.default.removeItem(at: directory) }
        model.availableDays = [.tuesday, .thursday]
        model.changeSearch()
        XCTAssertFalse(model.showingResults)
        XCTAssertEqual(model.availableDays, [.tuesday, .thursday])
        model.start() // No selected semester: no external request.
        XCTAssertEqual(model.availableDays, [.tuesday, .thursday])
        model.refresh()
        XCTAssertEqual(model.availableDays, [.tuesday, .thursday])
    }
}

@MainActor private final class FilterReaderCounter { var calls = 0 }
@MainActor private final class FilterReader: ProfileReader {
    let counter: FilterReaderCounter
    init(counter: FilterReaderCounter) { self.counter = counter }
    func stop() { }
    func candidates(_ professor: Professor, discoverAll: Bool) async throws -> [RMPProfile] { counter.calls += 1; return [] }
    func preview(_ professor: Professor, profileID: String) async throws -> RMPProfile { counter.calls += 1; throw URLError(.unsupportedURL) }
    func expand(_ professor: Professor, profile: RMPProfile, onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile { counter.calls += 1; return profile }
}
private struct FilterSummary: SummaryProvider {
    let cacheIdentity = "fictional-day-filter"
    func summarize(reviews: [Review], course: Course) async throws -> ReviewSummary { throw URLError(.unsupportedURL) }
}
