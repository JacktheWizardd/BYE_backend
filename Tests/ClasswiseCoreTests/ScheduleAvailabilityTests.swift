import XCTest
@testable import ClasswiseCore

final class ScheduleAvailabilityTests: XCTestCase {
    private func sections(_ records: [[String: String]]) throws -> [Section] {
        let rows = records.map { record in
            ["subjCode": "MATH", "courseNumbDisplay": "005A", "crn": "1", "pfaName": "Fictional Instructor", "schdCode": "L", "courseTitle": "Fictional Calculus"]
                .merging(record, uniquingKeysWith: { _, value in value })
        }
        return ScheduleParser.professors(rows: try JSONDecoder().decode([ScheduleRow].self, from: JSONSerialization.data(withJSONObject: rows)),
                                         course: try Course("MATH005A")).flatMap(\.sections)
    }

    func testAllSevenWeekdaysAreReadFromTheirSourceFields() throws {
        let cases: [(String, String, Weekday)] = [("monDay", "M", .monday), ("tueDay", "T", .tuesday),
            ("wedDay", "W", .wednesday), ("thuDay", "R", .thursday), ("friDay", "F", .friday),
            ("satDay", "S", .saturday), ("sunDay", "U", .sunday)]
        for (field, mark, day) in cases {
            let section = try XCTUnwrap(sections([[field: mark]]).first)
            XCTAssertEqual(section.schedule?.days, [day])
            XCTAssertFalse(section.scheduleNotAnnounced)
            XCTAssertTrue(section.fits(availableDays: [day]))
            XCTAssertFalse(section.fits(availableDays: Set(Weekday.allCases).subtracting([day])))
        }
    }

    func testEveryMeetingDayMustBeAvailableAndEmptySelectionAllowsAnyDay() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "wedDay": "W", "friDay": "F"]]).first)
        XCTAssertTrue(section.fits(availableDays: []))
        XCTAssertFalse(section.fits(availableDays: [.monday]))
        XCTAssertFalse(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday, .friday]))
        XCTAssertTrue(section.fits(availableDays: Set(Weekday.allCases)))
    }

    func testMondayWednesdayFitsWithinWiderAvailability() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "wedDay": "W"]]).first)
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .tuesday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .tuesday, .wednesday, .thursday]))
        XCTAssertFalse(section.fits(availableDays: [.monday, .tuesday, .thursday, .friday]))
        XCTAssertFalse(section.fits(availableDays: [.monday]))
    }

    func testMondayFridayIsHiddenWhenFridayIsUnavailable() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "friDay": "F"]]).first)
        XCTAssertFalse(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday, .friday]))
    }

    func testLectureAndLabDaysAreCombinedAcrossRowsAndDuplicates() throws {
        let lecture = ["monDay": "M", "wedDay": "W", "beginTime": "0900", "endTime": "1000"]
        let section = try XCTUnwrap(sections([lecture, lecture, ["schdCode": "B", "friDay": "F", "beginTime": "1000", "endTime": "1200"]]).first)
        XCTAssertEqual(section.schedule?.days, [.monday, .wednesday, .friday])
        XCTAssertEqual(section.meetings.count, 2)
        XCTAssertFalse(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday, .friday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .tuesday, .wednesday, .friday]))
    }

    func testAsynchronousSectionsAlwaysFitAndHaveNoUnannouncedSchedule() throws {
        let section = try XCTUnwrap(sections([["schdCode": "OD", "bldgDesc": "Online ASYNCH"]]).first)
        XCTAssertTrue(section.fullyOnline)
        XCTAssertEqual(section.schedule?.days, [])
        XCTAssertFalse(section.scheduleNotAnnounced)
        for day in Weekday.allCases { XCTAssertTrue(section.fits(availableDays: [day])) }
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: []))
    }

    func testRequiredMeetingsCountEvenWhenRowsListDifferentInstructors() throws {
        let results = try sections([
            ["pfaName": "Lecture Instructor", "monDay": "M", "wedDay": "W"],
            ["pfaName": "Lab Instructor", "schdCode": "B", "friDay": "F"]
        ])
        XCTAssertEqual(results.count, 2, "Keep both explicitly listed instructors")
        for section in results {
            XCTAssertEqual(section.schedule?.days, [.monday, .wednesday, .friday])
            XCTAssertEqual(section.meetings.count, 2)
            XCTAssertFalse(section.fits(availableDays: [.monday, .wednesday]))
            XCTAssertFalse(section.fits(availableDays: [.friday]))
            XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday, .friday]))
        }
    }

    func testScheduledOnlineAndHybridSectionsStillRequireMeetingDays() throws {
        for format in ["OL", "OS", "ON", "HY"] {
            let section = try XCTUnwrap(sections([["schdCode": format, "tueDay": "T", "thuDay": "R"]]).first)
            XCTAssertFalse(section.fullyOnline)
            XCTAssertFalse(section.fits(availableDays: [.monday, .wednesday]))
            XCTAssertTrue(section.fits(availableDays: [.tuesday, .thursday]))
            XCTAssertFalse(section.fits(availableDays: [.tuesday]))
            XCTAssertTrue(section.fits(availableDays: [.tuesday, .thursday, .saturday]))
        }
        let mixed = try XCTUnwrap(sections([["schdCode": "OD"], ["schdCode": "HY", "satDay": "S"]]).first)
        XCTAssertFalse(mixed.fullyOnline)
        XCTAssertEqual(mixed.schedule?.days, [.saturday])
        XCTAssertFalse(mixed.scheduleNotAnnounced)
        XCTAssertFalse(mixed.fits(availableDays: [.monday]))
        XCTAssertTrue(mixed.fits(availableDays: [.saturday]))
        XCTAssertTrue(mixed.fits(availableDays: [.saturday, .sunday]))
    }

    func testUnknownAndPartlyUnknownDaysAreHiddenWhileFiltering() throws {
        let unknown = try XCTUnwrap(sections([["monDay": " ", "beginTime": "TBA"]]).first)
        XCTAssertTrue(unknown.scheduleNotAnnounced)
        XCTAssertTrue(unknown.fits(availableDays: []))
        XCTAssertFalse(unknown.fits(availableDays: [.monday]))
        let partial = try XCTUnwrap(sections([["monDay": "M"], ["schdCode": "B", "beginTime": "TBA"]]).first)
        XCTAssertEqual(partial.schedule?.days, [.monday])
        XCTAssertTrue(partial.scheduleNotAnnounced)
        XCTAssertTrue(partial.fits(availableDays: []))
        XCTAssertFalse(partial.fits(availableDays: [.monday]))
        XCTAssertFalse(partial.fits(availableDays: [.monday, .wednesday]))
        XCTAssertFalse(partial.fits(availableDays: [.tuesday]))
        let empty = Section(crn: "empty", title: "Fictional", start: "", end: "", formats: ["L"], meetings: [], status: "O",
                            schedule: SectionSchedule(days: [], hasUnannouncedMeetings: false))
        XCTAssertTrue(empty.scheduleNotAnnounced)
        XCTAssertTrue(empty.fits(availableDays: []))
        XCTAssertFalse(empty.fits(availableDays: [.monday]))
    }

    func testOlderSectionsDecodeAsUnknownAndNewMetadataRoundTrips() throws {
        let data = Data("""
        {"crn":"old","title":"Fictional","start":"","end":"","formats":["L"],"meetings":["Mon 9:00 AM"],"status":"O"}
        """.utf8)
        var old = try JSONDecoder().decode(Section.self, from: data)
        XCTAssertNil(old.schedule)
        XCTAssertTrue(old.scheduleNotAnnounced)
        XCTAssertTrue(old.fits(availableDays: []))
        XCTAssertFalse(old.fits(availableDays: [.monday]), "Do not infer structured days from display strings")
        XCTAssertFalse(old.fits(availableDays: [.tuesday]))
        old = Section(crn: "online", title: "Fictional", start: "", end: "", formats: ["OD"], meetings: [], status: "O")
        XCTAssertFalse(old.scheduleNotAnnounced)
        XCTAssertTrue(old.fits(availableDays: [.monday, .wednesday]), "Legacy asynchronous sections keep their exception")
        let current = try XCTUnwrap(sections([["sunDay": "U"]]).first)
        XCTAssertEqual(try JSONDecoder().decode(Section.self, from: JSONEncoder().encode(current)), current)
    }
}
