import XCTest
@testable import ClasswiseCore

final class PresentationTests: XCTestCase {
    private func section(_ crn: String, formats: [String] = ["L"], details: SectionDetails? = nil) -> Section {
        var section = Section(crn: crn, title: "FICTIONAL", start: "", end: "", formats: formats, meetings: [], status: "O")
        section.details = details
        return section
    }

    func testOverviewCountsUniqueSectionsAndOnlyPublishedSeats() {
        let shared = section("1", details: SectionDetails(seatsOpen: 4, capacity: 40, termPart: "Full term"))
        let professors = [
            Professor(id: "a", name: "Fictional A", sections: [shared, section("2", formats: ["HY"], details: SectionDetails(seatsOpen: 10, termPart: "8-week"))]),
            Professor(id: "b", name: "Fictional B", sections: [shared, section("3", formats: ["HY"])]),
        ]
        let stats = CourseOverviewStats(professors: professors)
        XCTAssertEqual(stats.sectionCount, 3, "A co-taught CRN counts once")
        XCTAssertEqual(stats.professorCount, 2)
        XCTAssertEqual(stats.openSeats, 14, "Sections without published seats are left out")
        XCTAssertEqual(stats.formats, "Hybrid 2 · In person 1")
        XCTAssertEqual(stats.terms, "8-week 1 · Full term 1")
        XCTAssertNil(CourseOverviewStats(professors: [Professor(id: "c", name: "Fictional C", sections: [section("4")])]).openSeats)
    }

    func testSeatLevelsAndWaitlistLabels() {
        XCTAssertEqual(SectionDetails(seatsOpen: 11).seatLevel, .plenty)
        XCTAssertEqual(SectionDetails(seatsOpen: 10).seatLevel, .low)
        XCTAssertEqual(SectionDetails(seatsOpen: 5).seatLevel, .critical)
        XCTAssertEqual(SectionDetails(seatsOpen: 0).seatLevel, .critical)
        XCTAssertNil(SectionDetails().seatLevel)
        XCTAssertEqual(SectionDetails(seatsOpen: 10, capacity: 40).takenFraction, 0.75)
        XCTAssertEqual(SectionDetails(seatsOpen: 10).takenFraction, 0, "No capacity, no bar")
        XCTAssertEqual(SectionDetails(seatsOpen: 2, waitlistCount: 3, waitlistCapacity: 10).waitlistLabel, "Waitlist 3 of 10")
        XCTAssertEqual(SectionDetails(seatsOpen: 0, waitlistCount: 3, waitlistCapacity: 10).waitlistLabel, "Full · waitlist 3 of 10")
        XCTAssertEqual(SectionDetails(seatsOpen: 0).waitlistLabel, "Full")
        XCTAssertEqual(SectionDetails(seatsOpen: 4).waitlistLabel, "")
    }

    func testStatusTextNeverSinglesOutAProfessor() {
        var professor = Professor(id: "a", name: "Fictional A", sections: [])
        XCTAssertEqual(professor.listStatus, "Not checked yet")
        professor.state = .searching
        XCTAssertEqual(professor.reportStatusTitle, "Checking RMP for Fictional A…")
        professor.state = .selectionRequired
        XCTAssertEqual(professor.listStatus, "Profile needs confirmation · Choose profile")
        professor.state = .unavailable
        XCTAssertEqual(professor.listStatus, "Cannot retrieve RMP info")
    }
}
