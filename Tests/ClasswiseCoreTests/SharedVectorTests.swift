import XCTest
@testable import ClasswiseCore

/// Runs the website's shared test vectors (vendored by `node scripts/sync-bye-shared.mjs` into
/// apps/cross-platform/vendor/bye-shared/core/vectors) against the Mac's Core, so every BYE app keeps the same rules.
final class SharedVectorTests: XCTestCase {
    private let vectors = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("apps/cross-platform/vendor/bye-shared/core/vectors")

    private func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: vectors.appendingPathComponent(name + ".json")))
    }
    private static let days: [String: Weekday] = Dictionary(uniqueKeysWithValues: Weekday.allCases.map { ($0.shortLabel, $0) })

    func testClassDays() throws {
        struct File: Decodable { let cases: [Case] }
        struct Case: Decodable {
            struct SectionFacts: Decodable { let formats: [String]; let days: [String]; let unannouncedMeetings: Bool? }
            let name: String; let section: SectionFacts; let picked: [String]; let expected: Bool
        }
        let file = try load("class-days", as: File.self)
        XCTAssertFalse(file.cases.isEmpty)
        for test in file.cases {
            let days = Set(try test.section.days.map { try XCTUnwrap(Self.days[$0], "unknown day \($0)") })
            let section = Section(crn: "v", title: "", start: "", end: "", formats: test.section.formats, meetings: [], status: "O",
                                  schedule: SectionSchedule(days: days, hasUnannouncedMeetings: test.section.unannouncedMeetings ?? false))
            let picked = Set(try test.picked.map { try XCTUnwrap(Self.days[$0]) })
            XCTAssertEqual(section.fits(availableDays: picked), test.expected, test.name)
        }
    }

    func testDisplayTitle() throws {
        struct File: Decodable { let cases: [Case] }
        struct Case: Decodable { let raw: String; let expected: String }
        let file = try load("display-title", as: File.self)
        XCTAssertFalse(file.cases.isEmpty)
        for test in file.cases { XCTAssertEqual(displayTitle(test.raw), test.expected, test.raw) }
    }

    func testFormatLabel() throws {
        struct File: Decodable { let cases: [Case] }
        struct Case: Decodable { let formats: [String]; let expected: String }
        let file = try load("format-label", as: File.self)
        XCTAssertFalse(file.cases.isEmpty)
        for test in file.cases {
            let section = Section(crn: "v", title: "", start: "", end: "", formats: test.formats, meetings: [], status: "O")
            if test.formats.isEmpty && test.expected == "In person" {
                // The vendored vector predates the shared "Format not announced" rule (website, 2026-10-20).
                // Remove this branch once `node scripts/sync-bye-shared.mjs` brings the updated vector.
                XCTAssertEqual(section.formatLabel, "Format not announced")
                continue
            }
            XCTAssertEqual(section.formatLabel, test.expected, test.formats.joined(separator: ","))
        }
    }

    func testReviewOrder() throws {
        struct File: Decodable { let reviews: [Item]; let cases: [Case] }
        struct Item: Decodable { let id: String; let rating: Double?; let difficulty: Double?; let date: String }
        struct Case: Decodable { let by: String; let expected: [String] }
        let file = try load("review-order", as: File.self)
        let reviews = file.reviews.map { Review(id: $0.id, course: "", text: "", date: $0.date, rating: $0.rating, difficulty: $0.difficulty, online: nil) }
        let sorts: [String: ReviewSort] = ["recent": .recent, "oldest": .oldest, "highest": .highest, "lowest": .lowest,
                                           "highestDifficulty": .highestDifficulty, "difficulty": .difficulty]
        XCTAssertEqual(Set(file.cases.map(\.by)), Set(sorts.keys), "Every shared sort has a Mac ReviewSort")
        for test in file.cases {
            let sort = try XCTUnwrap(sorts[test.by])
            XCTAssertEqual(Ordering.reviews(reviews, by: sort).map(\.id), test.expected, test.by)
        }
    }

    /// The stamp vector is not vendored yet: it lives on the website branch `claude/merged-reviews` (ac79bb1).
    /// Until that merges and `node scripts/sync-bye-shared.mjs` runs, a byte-for-byte copy sits beside this file.
    func testStampTier() throws {
        struct File: Decodable { let cases: [Case] }
        struct Case: Decodable { let id: String; let expected: String }
        let vendored = vectors.appendingPathComponent("stamp-tier.json")
        let url = FileManager.default.fileExists(atPath: vendored.path) ? vendored
            : URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Vectors/stamp-tier.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.cases.count, 13)
        for test in file.cases { XCTAssertEqual(StampTier(reviewID: test.id).rawValue, test.expected, test.id) }
    }

    /// Over 10,000 IDs every tier stays within 1.5 points of its share.
    func testStampTierOdds() {
        var counts: [StampTier: Int] = [:]
        for index in 0..<10_000 { counts[StampTier(reviewID: "review-\(index)"), default: 0] += 1 }
        let expected: [StampTier: Double] = [.legendary: 2, .epic: 6, .rare: 12, .uncommon: 25, .common: 55]
        for (tier, share) in expected {
            XCTAssertEqual(Double(counts[tier] ?? 0) / 100, share, accuracy: 1.5, tier.rawValue)
        }
    }
}
