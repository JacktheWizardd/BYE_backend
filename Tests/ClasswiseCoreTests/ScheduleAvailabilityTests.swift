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

    func testPickedDaysMustAllBeMeetingDaysAndEmptySelectionAllowsAnyDay() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "wedDay": "W", "friDay": "F"]]).first)
        XCTAssertTrue(section.fits(availableDays: []))
        XCTAssertTrue(section.fits(availableDays: [.monday]), "A Monday pick shows every class that meets on Monday")
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday, .friday]))
        XCTAssertFalse(section.fits(availableDays: [.monday, .tuesday]), "Every picked day must be a meeting day")
        XCTAssertFalse(section.fits(availableDays: Set(Weekday.allCases)))
    }

    func testMondayWednesdayClassMatchesItsOwnDaysOnly() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "wedDay": "W"]]).first)
        XCTAssertTrue(section.fits(availableDays: [.monday]))
        XCTAssertTrue(section.fits(availableDays: [.wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertFalse(section.fits(availableDays: [.monday, .tuesday]))
        XCTAssertFalse(section.fits(availableDays: [.monday, .tuesday, .wednesday]))
        XCTAssertFalse(section.fits(availableDays: [.friday]))
    }

    func testMondayFridayClassIsHiddenWhenAPickedDayIsMissing() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "friDay": "F"]]).first)
        XCTAssertFalse(section.fits(availableDays: [.monday, .wednesday]))
        XCTAssertTrue(section.fits(availableDays: [.monday, .friday]))
    }

    func testLectureAndLabDaysAreCombinedAcrossRowsAndDuplicates() throws {
        let lecture = ["monDay": "M", "wedDay": "W", "beginTime": "0900", "endTime": "1000"]
        let section = try XCTUnwrap(sections([lecture, lecture, ["schdCode": "B", "friDay": "F", "beginTime": "1000", "endTime": "1200"]]).first)
        XCTAssertEqual(section.schedule?.days, [.monday, .wednesday, .friday])
        XCTAssertEqual(section.meetings.count, 2)
        XCTAssertTrue(section.fits(availableDays: [.friday]), "Lab days count as meeting days")
        XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday, .friday]))
        XCTAssertFalse(section.fits(availableDays: [.monday, .tuesday, .wednesday, .friday]))
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
            XCTAssertTrue(section.fits(availableDays: [.friday]), "The lab row's Friday belongs to both instructors' section")
            XCTAssertTrue(section.fits(availableDays: [.monday, .wednesday, .friday]))
            XCTAssertFalse(section.fits(availableDays: [.thursday]))
        }
    }

    func testScheduledOnlineAndHybridSectionsStillRequireMeetingDays() throws {
        for format in ["OL", "OS", "ON", "HY"] {
            let section = try XCTUnwrap(sections([["schdCode": format, "tueDay": "T", "thuDay": "R"]]).first)
            XCTAssertFalse(section.fullyOnline)
            XCTAssertFalse(section.fits(availableDays: [.monday, .wednesday]))
            XCTAssertTrue(section.fits(availableDays: [.tuesday, .thursday]))
            XCTAssertTrue(section.fits(availableDays: [.tuesday]))
            XCTAssertFalse(section.fits(availableDays: [.tuesday, .thursday, .saturday]))
        }
        let mixed = try XCTUnwrap(sections([["schdCode": "OD"], ["schdCode": "HY", "satDay": "S"]]).first)
        XCTAssertFalse(mixed.fullyOnline)
        XCTAssertEqual(mixed.schedule?.days, [.saturday])
        XCTAssertFalse(mixed.scheduleNotAnnounced)
        XCTAssertFalse(mixed.fits(availableDays: [.monday]))
        XCTAssertTrue(mixed.fits(availableDays: [.saturday]))
        XCTAssertFalse(mixed.fits(availableDays: [.saturday, .sunday]))
    }

    func testUnknownDaysAreHiddenAndPartlyKnownDaysStillMatch() throws {
        let unknown = try XCTUnwrap(sections([["monDay": " ", "beginTime": "TBA"]]).first)
        XCTAssertTrue(unknown.scheduleNotAnnounced)
        XCTAssertTrue(unknown.fits(availableDays: []))
        XCTAssertFalse(unknown.fits(availableDays: [.monday]))
        let partial = try XCTUnwrap(sections([["monDay": "M"], ["schdCode": "B", "beginTime": "TBA"]]).first)
        XCTAssertEqual(partial.schedule?.days, [.monday])
        XCTAssertTrue(partial.scheduleNotAnnounced)
        XCTAssertTrue(partial.fits(availableDays: []))
        XCTAssertTrue(partial.fits(availableDays: [.monday]), "It is known to meet on Monday")
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
        XCTAssertNil(try JSONDecoder().decode(Section.self, from: data).details, "Older caches have no enrollment details")
    }

    func testEnrollmentTermAndUnitsAreReadFromTheSchedule() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "wedDay": "W", "seatsAvail": "18", "maxEnrl": "30",
            "waitCount": "0", "waitCapacity": "7", "ptrmDesc": "8 Week Second Session", "campDesc": "Colorado Campus",
            "creditHrLow": "5"]]).first)
        let details = try XCTUnwrap(section.details)
        XCTAssertEqual(details.seatsOpen, 18)
        XCTAssertEqual(details.capacity, 30)
        XCTAssertEqual(details.waitlistCount, 0)
        XCTAssertEqual(details.waitlistCapacity, 7)
        XCTAssertEqual(details.termPart, "8 Week Second Session")
        XCTAssertEqual(details.campus, "Colorado Campus")
        XCTAssertEqual(details.units, "5")
        XCTAssertFalse(details.isFull)
        XCTAssertEqual(try JSONDecoder().decode(Section.self, from: JSONEncoder().encode(section)), section)
    }

    func testMissingOrUnreadableSeatCountsStayUnknown() throws {
        let section = try XCTUnwrap(sections([["monDay": "M", "seatsAvail": "", "maxEnrl": "n/a"]]).first)
        XCTAssertNil(section.details?.seatsOpen)
        XCTAssertNil(section.details?.capacity)
        XCTAssertEqual(section.details?.termPart, "")
        let full = try XCTUnwrap(sections([["monDay": "M", "seatsAvail": "-2", "maxEnrl": "30"]]).first)
        XCTAssertEqual(full.details?.seatsOpen, 0, "Over-enrolled sections show as full, not negative")
        XCTAssertTrue(full.details?.isFull == true)
    }

    func testMeetingTextIsReadableForHybridAndUnassignedRooms() throws {
        let hybrid = try XCTUnwrap(sections([
            ["schdCode": "HY", "tueDay": "T", "beginTime": "0700", "endTime": "0930", "bldgDesc": "Online ASYNCH,R", "roomCode": "521"],
            ["schdCode": "HY", "bldgDesc": "Online ASYNCH,R", "roomCode": "Needs Assignment"]
        ]).first)
        XCTAssertEqual(Set(hybrid.meetings), ["Tue 7:00 AM – 9:30 AM · R 521", "Online, no set meeting time"])
        let tba = try XCTUnwrap(sections([["schdCode": "HY", "bldgDesc": "Online ASYNCH,R", "roomCode": "218"]]).first)
        XCTAssertEqual(tba.meetings, ["Time TBA · R 218"])
        let unassigned = try XCTUnwrap(sections([["monDay": "M", "beginTime": "0900", "endTime": "1000", "bldgDesc": "C", "roomCode": "Needs Assignment"]]).first)
        XCTAssertEqual(unassigned.meetings, ["Mon 9:00 AM – 10:00 AM · C · room TBA"])
        let zoom = try XCTUnwrap(sections([["schdCode": "OS", "wedDay": "W", "beginTime": "1800", "endTime": "1900", "bldgDesc": "Online ASYNCH,Online ZOOM", "roomCode": "Needs Assignment"]]).first)
        XCTAssertEqual(zoom.meetings, ["Wed 6:00 PM – 7:00 PM · Online (Zoom)"])
    }

    func testFormatLabelsCoverEachDeliveryMode() throws {
        func label(_ codes: [String]) -> String {
            Section(crn: "1", title: "Fictional", start: "", end: "", formats: codes, meetings: [], status: "O").formatLabel
        }
        XCTAssertEqual(label(["L"]), "In person")
        XCTAssertEqual(label(["HY"]), "Hybrid")
        XCTAssertEqual(label(["OS"]), "Online · live")
        XCTAssertEqual(label(["OD"]), "Online · async")
        XCTAssertEqual(label([]), "In person")
    }
}
