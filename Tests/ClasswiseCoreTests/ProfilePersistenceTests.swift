import XCTest
@testable import ClasswiseCore

final class ProfilePersistenceTests: XCTestCase {
    private func profile(_ id: String, department: String = "Math") -> RMPProfile {
        RMPProfile(id: id, firstName: "Fictional", lastName: "Instructor", school: "Pasadena City College", schoolID: 2649,
                   department: department, rating: 4, difficulty: 3, ratingCount: 10, wouldTakeAgain: 80, reviews: [])
    }
    func testDuplicatesDeduplicateButDepartmentsNeverResolveIdentity() {
        let a = profile("1"), b = profile("2", department: "History")
        XCTAssertEqual(IdentityMatcher.eligible(name: a.name, candidates: [a, a, b]).count, 2)
        XCTAssertNil(IdentityMatcher.unique(name: a.name, candidates: [a, a, b]))
        XCTAssertEqual(IdentityMatcher.unique(name: a.name, candidates: [a, a])?.id, "1")
    }
    func testManualChoiceSurvivesRecreationAndIsIsolatedBySubject() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(ProfileChoiceStore(directory: directory).save(profileID: "1", name: "Fictional Instructor", subject: "MATH"))
        let recreated = ProfileChoiceStore(directory: directory)
        XCTAssertEqual(recreated.choice(name: " fictional  INSTRUCTOR ", subject: "math"), "1")
        XCTAssertNil(recreated.choice(name: "Fictional Instructor", subject: "HIST"))
        XCTAssertTrue(recreated.save(profileID: nil, name: "Fictional Instructor", subject: "MATH"))
        XCTAssertNil(ProfileChoiceStore(directory: directory).choice(name: "Fictional Instructor", subject: "MATH"))
    }
    func testCachesCannotCrossProfilesSubjectsOrExpiry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ReportCache(directory: directory), course = try Course("MATH005A"), now = Date()
        for id in ["1", "2"] { cache.save(CachedReport(profile: profile(id), summary: nil, checkedAt: now), name: "Fictional Instructor", course: course) }
        XCTAssertEqual(cache.load(name: "Fictional Instructor", course: course)?.profile.id, "2")
        XCTAssertEqual(cache.load(name: "Fictional Instructor", course: course, preferredProfileID: "1")?.profile.id, "1")
        XCTAssertNil(cache.load(name: "Fictional Instructor", course: course, preferredProfileID: "3"))
        XCTAssertNil(cache.load(name: "Fictional Instructor", course: course, subject: "HIST"))
        XCTAssertNil(cache.load(name: "Fictional Instructor", course: course, now: now.addingTimeInterval(86401)))
    }
    func testOldV2CacheRemainsUntouchedAndCannotLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let course = try Course("MATH005A")
        let key = Data("v2|Fictional Instructor|MATH005A".utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let file = directory.appendingPathComponent(key + ".json")
        let data = try JSONEncoder().encode(CachedReport(profile: profile("1"), summary: nil, checkedAt: Date()))
        try data.write(to: file)
        XCTAssertNil(ReportCache(directory: directory).load(name: "Fictional Instructor", course: course))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }
    func testSubjectMetadataConflictsDoNotInventDescription() throws {
        let rows = try JSONDecoder().decode([ScheduleRow].self, from: Data("""
        [{"subjCode":"MATH","subjDesc":"Mathematics","courseNumbDisplay":"005A","crn":"1","pfaName":"Fictional Instructor"},
         {"subjCode":"MATH","subjDesc":"Different","courseNumbDisplay":"005A","crn":"2","pfaName":"Fictional Instructor"}]
        """.utf8))
        let professors = ScheduleParser.professors(rows: rows, course: try Course("MATH005A"))
        XCTAssertEqual(professors.first?.subjectCode, "MATH")
        XCTAssertEqual(professors.first?.subjectDescription, "")
        XCTAssertEqual(ScheduleParser.professors(rows: Array(rows.prefix(1)), course: try Course("MATH005A")).first?.subjectDescription, "Mathematics")
    }
}
