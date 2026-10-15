import XCTest
@testable import ClasswiseCore

final class CourseShorthandTests: XCTestCase {
    private func rows() throws -> [ScheduleRow] {
        try JSONDecoder().decode([ScheduleRow].self, from: Data("""
        [
          {"subjCode":"MATH","courseNumbDisplay":"005A","courseTitle":"Calculus I","crn":"1","pfaName":"Fictional Instructor","fwSectOpenInd":"O"},
          {"subjCode":"MATH","courseNumbDisplay":"005B","courseTitle":"Calculus II","crn":"2","pfaName":"Other Instructor","fwSectOpenInd":"O"},
          {"subjCode":"MATH","courseNumbDisplay":"005C","courseTitle":"Hidden course","crn":"3","fwSectOpenInd":"X"}
        ]
        """.utf8))
    }
    func testShorthandResolvesOfficialCourseAndSameSections() throws {
        let rows = try rows(), official = try Course("MATH 005A")
        for input in ["math 5a", "math5a", " MATH 05A ", "math 005a", "math 0005a"] {
            let query = try Course(input)
            XCTAssertEqual(try CourseSuggestions.resolve(query, rows: rows), official)
            XCTAssertEqual(ScheduleParser.professors(rows: rows, course: query).map(\.id), ScheduleParser.professors(rows: rows, course: official).map(\.id))
            XCTAssertEqual(ScheduleParser.professors(rows: rows, course: query).flatMap(\.sections), ScheduleParser.professors(rows: rows, course: official).flatMap(\.sections))
            XCTAssertEqual(CourseSuggestions.match(rows: rows, query: input).first?.course, official)
        }
        XCTAssertEqual(try Course("math5a").display, "MATH 5A", "Parsing retains original formatting; resolution supplies the official label")
    }
    func testPrefixesSuffixesAndSubjectsRemainDistinct() throws {
        let course = try Course("MATH005A")
        for code in ["MATH5A", "math 05a", "MATH0005A"] { XCTAssertTrue(course.matchesReview(code)) }
        for code in ["MATH5", "MATH5B", "MATH15A", "HIST5A", "5A", "MATH C5A", "MATH5A junk", "MATH5A5B"] { XCTAssertFalse(course.matchesReview(code)) }
        XCTAssertTrue(try Course("POLS C1000").matchesReview("POLSC1000"))
        XCTAssertFalse(try Course("POLS C1000").matchesReview("POLS1000"))
        XCTAssertTrue(try Course("MATH 000").matchesReview("MATH0"))
    }
    func testCommonCourseNumbersKeepTheirLetterWithTheNumber() throws {
        let rows = try JSONDecoder().decode([ScheduleRow].self, from: Data("""
        [{"subjCode":"STAT","courseNumbDisplay":"C1000","courseTitle":"Introduction to Statistics","crn":"9","pfaName":"Fictional Instructor","fwSectOpenInd":"O"}]
        """.utf8))
        XCTAssertEqual(CourseSuggestions.match(rows: rows, query: "stat c1000").map(\.course.display), ["STAT C1000"], "Not \"STATC 1000\"")
        XCTAssertEqual(try CourseSuggestions.resolve(try Course("statc1000"), rows: rows).display, "STAT C1000")
        XCTAssertEqual(ScheduleParser.professors(rows: rows, course: try Course("STAT C1000")).count, 1)
        XCTAssertEqual(ScheduleParser.professors(rows: rows, course: try Course("statc1000")).count, 1, "Typed without a space still matches")
    }
    func testSuggestionsSupportPartialShorthandWithoutHiddenRows() throws {
        XCTAssertEqual(CourseSuggestions.match(rows: try rows(), query: "math 5").map(\.course.display), ["MATH 005A", "MATH 005B"])
        XCTAssertTrue(CourseSuggestions.match(rows: try rows(), query: "math5c").isEmpty)
        let missing = try Course("math99a")
        XCTAssertEqual(try CourseSuggestions.resolve(missing, rows: rows()), missing)
        XCTAssertTrue(ScheduleParser.professors(rows: try rows(), course: missing).isEmpty)
        XCTAssertEqual(CourseSuggestions.match(rows: try rows(), query: "calculus").count, 2)
    }
    func testEquivalentLabelsFeedThisCourseAndSummaryEvidence() throws {
        let reviews = ["MATH5A", "MATH05A", "MATH5B"].enumerated().map { i, label in
            Review(id: "r\(i)", course: label, text: "Fictional review", date: "2026-10-10", rating: 4, difficulty: 2, online: nil)
        }
        let profile = RMPProfile(id: "fictional", firstName: "Test", lastName: "Instructor", school: "Pasadena City College", schoolID: 2649,
                                 department: "Math", rating: 4, difficulty: 2, ratingCount: 3, wouldTakeAgain: nil, reviews: reviews)
        let course = try Course("MATH005A")
        XCTAssertEqual(Set(ReviewFilter.thisCourse.reviews(in: profile, course: course).map(\.id)), ["r0", "r1"])
        XCTAssertEqual(ReviewFilter.source("MATH5A").reviews(in: profile, course: course).map(\.id), ["r0"])
        XCTAssertEqual(Set(SummaryBuilder.selectedReviews(reviews, course: course).map(\.id)), ["r0", "r1"])
        let summary = try SummaryBuilder.validate(Data("{\"positives\":[],\"concerns\":[]}".utf8), reviews: Array(reviews.prefix(2)), course: course)
        XCTAssertEqual(summary.exactCourseCount, 2)
        XCTAssertEqual(ReviewFilter.thisCourse.requestLabel(course: course), "MATH005A")
    }

    func testReviewTextShowsCharactersInsteadOfHTMLReferences() {
        XCTAssertEqual(Review.visibleText("hard to understand&#8212; lectures"), "hard to understand— lectures")
        XCTAssertEqual(Review.visibleText("Q&amp;A, &quot;fair&quot; &#x2019;s &lt;3"), "Q&A, \"fair\" ’s <3")
        XCTAssertEqual(Review.visibleText("A & B; 5&6 &unknown; &#99999999;"), "A & B; 5&6 &unknown; &#99999999;", "Leave text that is not a valid reference")
        let cached = Review(id: "c", course: "MATH5A", text: "Great class &#8212; take it", date: "", rating: nil, difficulty: nil, online: nil)
        XCTAssertEqual(cached.excerpt, "Great class — take it", "Older cached reviews are decoded on display")
    }

    func testReportsOpenOnAllCoursesWhenNoReviewIsAboutTheClass() throws {
        let course = try Course("MATH004Z")
        func profile(_ labels: [String]) -> RMPProfile {
            RMPProfile(id: "p", firstName: "Test", lastName: "Instructor", school: "PCC", schoolID: 2649, department: "Math",
                       rating: 4, difficulty: 2, ratingCount: labels.count, wouldTakeAgain: nil,
                       reviews: labels.enumerated().map { i, label in
                           Review(id: "r\(i)", course: label, text: "Fictional review", date: "2026-10-10", rating: 4, difficulty: 2, online: nil)
                       })
        }
        XCTAssertEqual(ReviewFilter.preferred(in: profile(["MATH3", "MATH4Z"]), course: course), .thisCourse, "Shorthand labels count as this class")
        XCTAssertEqual(ReviewFilter.preferred(in: profile(["MATH003", "MATH015"]), course: course), .allCourses)
        XCTAssertEqual(ReviewFilter.preferred(in: profile([]), course: course), .thisCourse)
        XCTAssertEqual(ReviewFilter.preferred(in: nil, course: course), .thisCourse)
    }

    func testSourceLabelsRetainOriginalSpellingsAndAggregateCoverage() throws {
        let course = try Course("MATH005A")
        var profile = RMPProfile(id: "p", firstName: "Test", lastName: "Instructor", school: "PCC", schoolID: 2649,
                                 department: "Math", rating: nil, difficulty: nil, ratingCount: nil, wouldTakeAgain: nil, reviews: [],
                                 courseCounts: ["math 5a", "MATH05A", "MATH5A5B", "MATH5B", "5A"].map { ReviewCourseCount(label: $0, count: nil) })
        XCTAssertEqual(ReviewFilter.thisCourse.sourceLabels(in: profile, course: course), ["MATH05A", "math 5a"])
        profile.reviewCoverage = ["course|MATH05A": ReviewCoverage(reviewIDs: ["one"], nextCursor: nil, hasNextPage: false)]
        XCTAssertFalse(ReviewFilter.thisCourse.finished(in: profile, course: course))
        profile.reviewCoverage?["course|math 5a"] = ReviewCoverage(reviewIDs: ["one", "two"], nextCursor: nil, hasNextPage: false)
        XCTAssertEqual(ReviewFilter.thisCourse.retrievedIDs(in: profile, course: course), ["one", "two"])
        XCTAssertTrue(ReviewFilter.thisCourse.finished(in: profile, course: course))
        profile.courseCounts = nil
        XCTAssertEqual(ReviewFilter.thisCourse.sourceLabels(in: profile, course: course), ["MATH05A", "math 5a"], "Saved pagination survives omitted metadata")
        profile.reviewCoverage = nil
        XCTAssertEqual(ReviewFilter.thisCourse.sourceLabels(in: profile, course: course), ["MATH005A"])
        XCTAssertFalse(ReviewFilter.thisCourse.finished(in: profile, course: course))
    }
}
