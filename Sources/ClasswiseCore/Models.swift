import Foundation

public struct Course: Hashable, Codable, Sendable {
    public let subject: String
    public let number: String
    public var display: String { "\(subject) \(number)" }
    public var key: String { subject + number }
    /// Comparison only: preserve source labels and persistent cache keys.
    public var matchingKey: String {
        let prefix = number.prefix(while: { !$0.isNumber })
        let remainder = number.dropFirst(prefix.count)
        let digits = remainder.prefix(while: { $0.isNumber })
        let significant = digits.drop(while: { $0 == "0" })
        return subject + prefix + (significant.isEmpty ? "0" : String(significant)) + remainder.dropFirst(digits.count)
    }

    public init(_ input: String) throws {
        let cleaned = input.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let regex = try NSRegularExpression(pattern: "^([A-Z]{2,8})\\s*([A-Z]?\\d{1,4}[A-Z]?)$")
        guard let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let s = Range(match.range(at: 1), in: cleaned), let n = Range(match.range(at: 2), in: cleaned)
        else { throw AppError.message("Enter a subject and course number, such as ETH 014 or POLS C1000.") }
        subject = String(cleaned[s]); number = String(cleaned[n])
    }

    public func matchesReview(_ code: String) -> Bool {
        // Do not guess cross-listed courses or accept a bare number as an exact match.
        (try? Course(code).matchingKey) == matchingKey
    }
}

public enum AppError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public struct Term: Codable, Identifiable, Hashable, Sendable {
    public var id: String { termCode }
    public let termCode: String
    public let termName: String
    public let termDisplayControl: String
}

public struct ScheduleRow: Decodable, Sendable {
    public let values: [String: String]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        var result: [String: String] = [:]
        for k in c.allKeys {
            if let value = try? c.decode(String.self, forKey: k) { result[k.stringValue] = value }
            else if let value = try? c.decode(Int.self, forKey: k) { result[k.stringValue] = String(value) }
        }
        values = result
    }
    public subscript(_ key: String) -> String { values[key] ?? "" }
}

private struct DynamicKey: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}

public struct Section: Codable, Identifiable, Hashable, Sendable {
    public var id: String { crn }
    public let crn: String
    public let title: String
    public let start: String
    public let end: String
    public let formats: [String]
    public let meetings: [String]
    public let status: String
    public var fullyOnline: Bool { !formats.isEmpty && formats.allSatisfy { $0 == "OD" } }
    public var delivery: String {
        if fullyOnline { return "Online · no scheduled meetings" }
        if formats.contains("HY") { return "Hybrid · campus meetings required" }
        if formats.allSatisfy({ ["OD", "OL", "OS", "ON"].contains($0) }) { return "Online · scheduled meetings" }
        return "In person"
    }
    public var dateLabel: String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "yyyy-MM-dd"
        let display = DateFormatter(); display.locale = Locale(identifier: "en_US"); display.timeZone = TimeZone(secondsFromGMT: 0); display.dateFormat = "MMM d, yyyy"
        func label(_ source: String) -> String {
            parser.date(from: String(source.prefix(10))).map { display.string(from: $0) } ?? "Date unavailable"
        }
        return "\(label(start)) – \(label(end))"
    }
}

public struct Review: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let course: String
    public let text: String
    public let date: String
    public let rating: Double?
    public let difficulty: Double?
    public let online: Bool?
    public init(id: String, course: String, text: String, date: String, rating: Double?, difficulty: Double?, online: Bool?) {
        self.id = id; self.course = course; self.text = text; self.date = date
        self.rating = rating; self.difficulty = difficulty; self.online = online
    }
    public var excerpt: String {
        text.count > 500 ? String(text.prefix(500)) + "…" : text
    }
    public var postedLabel: String { date.isEmpty ? "Posted date unavailable" : "Posted \(String(date.prefix(10)))" }
}

public struct ReviewCourseCount: Codable, Hashable, Sendable {
    public let label: String
    public let count: Int?
    public init(label: String, count: Int?) { self.label = label; self.count = count }
}

/// Coverage belongs to a source filter, never to an instructor name alone.
public struct ReviewCoverage: Codable, Hashable, Sendable {
    public var reviewIDs: [String]
    public var nextCursor: String?
    public var hasNextPage: Bool
    public var updatedAt: Date
    public init(reviewIDs: [String], nextCursor: String?, hasNextPage: Bool, updatedAt: Date = Date()) {
        self.reviewIDs = reviewIDs; self.nextCursor = nextCursor; self.hasNextPage = hasNextPage; self.updatedAt = updatedAt
    }
    public var finished: Bool { !hasNextPage || reviewIDs.count >= 50 }
}

public enum ReviewFilter: Hashable, Sendable {
    case thisCourse, allCourses, source(String)
    public func reviews(in profile: RMPProfile, course: Course) -> [Review] {
        let reviews: [Review]
        switch self {
        case .thisCourse: reviews = profile.reviews.filter { course.matchesReview($0.course) }
        case .allCourses:
            if let ids = profile.reviewCoverage?["all"]?.reviewIDs {
                let included = Set(ids); reviews = profile.reviews.filter { included.contains($0.id) }
            } else { reviews = profile.reviews }
        case .source(let label): reviews = profile.reviews.filter { $0.course == label }
        }
        return Array(Ordering.reviews(reviews, by: .recent).prefix(50))
    }
    public func requestLabel(course: Course) -> String? {
        switch self { case .thisCourse: return course.key; case .allCourses: return nil; case .source(let label): return label }
    }
    public static func coverageKey(_ label: String?) -> String { label.map { "course|" + $0 } ?? "all" }
}

public struct RMPProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let school: String
    public let schoolID: Int?
    public let department: String
    public let rating: Double?
    public let difficulty: Double?
    public let ratingCount: Int?
    public let wouldTakeAgain: Double?
    public var reviews: [Review]
    public var courseCounts: [ReviewCourseCount]?
    public var reviewCoverage: [String: ReviewCoverage]?
    public init(id: String, firstName: String, lastName: String, school: String, schoolID: Int?, department: String,
                rating: Double?, difficulty: Double?, ratingCount: Int?, wouldTakeAgain: Double?, reviews: [Review],
                courseCounts: [ReviewCourseCount]? = nil, reviewCoverage: [String: ReviewCoverage]? = nil) {
        self.id = id; self.firstName = firstName; self.lastName = lastName; self.school = school; self.schoolID = schoolID
        self.department = department; self.rating = rating; self.difficulty = difficulty; self.ratingCount = ratingCount
        self.wouldTakeAgain = wouldTakeAgain; self.reviews = reviews; self.courseCounts = courseCounts; self.reviewCoverage = reviewCoverage
    }
    public var name: String { firstName + " " + lastName }
    public var url: URL { URL(string: "https://www.ratemyprofessors.com/professor/\(id)")! }
}

public struct SummaryPoint: Codable, Hashable, Sendable {
    public let text: String
    public let reviewIDs: [String]
    public init(text: String, reviewIDs: [String]) { self.text = text; self.reviewIDs = reviewIDs }
}

public struct ReviewSummary: Codable, Hashable, Sendable {
    public let overview: String
    public let positives: [SummaryPoint]
    public let concerns: [SummaryPoint]
    public var analyzedCount: Int
    public var exactCourseCount: Int
    public var generatedAt: Date
    /// Provider/policy identity and the complete reviews actually analyzed.
    public var providerIdentity: String? = nil
    public var evidence: [Review]? = nil
    public init(overview: String, positives: [SummaryPoint], concerns: [SummaryPoint], analyzedCount: Int,
                exactCourseCount: Int, generatedAt: Date, providerIdentity: String? = nil, evidence: [Review]? = nil) {
        self.overview = overview; self.positives = positives; self.concerns = concerns
        self.analyzedCount = analyzedCount; self.exactCourseCount = exactCourseCount; self.generatedAt = generatedAt
        self.providerIdentity = providerIdentity; self.evidence = evidence
    }
}

public enum LookupState: String, Codable, Sendable { case pending, searching, ready, selectionRequired, unavailable }

public struct Professor: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public var sections: [Section]
    public var subjectCode: String = ""
    public var subjectDescription: String = ""
    public var candidates: [RMPProfile] = []
    public var generation: UUID = UUID()
    public var pendingProfileID: String?
    public var profile: RMPProfile?
    public var summary: ReviewSummary?
    public var state: LookupState = .pending
    public var issue: String?
    public var summaryIssue: String?
    public var checkedAt: Date?
    public var reviewsComplete = false
    public var reviewIssue: String?
    public var searchURL: URL {
        var parts = URLComponents(string: "https://www.ratemyprofessors.com/search/professors/2649")!
        parts.queryItems = [.init(name: "q", value: name)]
        return parts.url!
    }
    public var sourceURL: URL { profile?.url ?? searchURL }
    public var canSearch: Bool { !["staff", "tba", "instructor to be announced"].contains(name.lowercased()) }
}

public enum ProfessorSort: String, CaseIterable, Identifiable {
    case rating = "Highest rated", difficulty = "Lowest difficulty", reviews = "Student reviews"
    public var id: String { rawValue }
}
public enum ReviewSort: String, CaseIterable, Identifiable {
    case recent = "Most recent", highest = "Highest rating", lowest = "Lowest rating", difficulty = "Lowest difficulty"
    public var id: String { rawValue }
}

public enum Ordering {
    public static func professors(_ list: [Professor], by order: ProfessorSort, course: Course) -> [Professor] {
        list.sorted { a, b in
            if (a.state == .unavailable) != (b.state == .unavailable) { return a.state != .unavailable }
            let av: Double; let bv: Double
            switch order {
            case .rating: av = a.profile?.rating ?? -1; bv = b.profile?.rating ?? -1
            case .difficulty: av = -(a.profile?.difficulty ?? 100); bv = -(b.profile?.difficulty ?? 100)
            case .reviews:
                av = Double(a.profile?.reviews.filter { course.matchesReview($0.course) }.count ?? 0)
                bv = Double(b.profile?.reviews.filter { course.matchesReview($0.course) }.count ?? 0)
            }
            if av != bv { return av > bv }
            if a.profile?.ratingCount != b.profile?.ratingCount { return (a.profile?.ratingCount ?? 0) > (b.profile?.ratingCount ?? 0) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    public static func reviews(_ list: [Review], by order: ReviewSort) -> [Review] {
        list.sorted { a, b in
            let av: Double; let bv: Double
            switch order {
            case .recent: return a.date == b.date ? a.id < b.id : a.date > b.date
            case .highest: av = a.rating ?? -1; bv = b.rating ?? -1
            case .lowest: av = -(a.rating ?? 100); bv = -(b.rating ?? 100)
            case .difficulty: av = -(a.difficulty ?? 100); bv = -(b.difficulty ?? 100)
            }
            return av == bv ? a.date > b.date : av > bv
        }
    }
}

public enum ScheduleParser {
    public static func professors(rows: [ScheduleRow], course: Course) -> [Professor] {
        let matches = rows.filter {
            (try? Course($0["subjCode"] + $0["courseNumbDisplay"]).matchingKey) == course.matchingKey &&
            !["R", "X"].contains($0["fwSectOpenInd"]) && !$0["crn"].isEmpty
        }
        // Group by instructor as well as CRN to retain explicitly listed co-instructors.
        let instructors = Dictionary(grouping: matches) { row in
            let name = row["pfaName"].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Instructor to be announced" : name
        }
        return instructors.map { name, records in
            let sections = Dictionary(grouping: records, by: { $0["crn"] }).map { crn, meetings in
                let first = meetings[0]
                let formats = Set(meetings.map { $0["schdCode"] }.filter { !$0.isEmpty }).sorted()
                let descriptions = Set(meetings.compactMap { row -> String? in
                    if row["schdCode"] == "OD" { return nil }
                    let weekdays = [("monDay", "Mon"), ("tueDay", "Tue"), ("wedDay", "Wed"), ("thuDay", "Thu"), ("friDay", "Fri"), ("satDay", "Sat"), ("sunDay", "Sun")]
                    let days = weekdays.filter { !row[$0.0].isEmpty }.map { $0.1 }.joined(separator: ", ")
                    func clock(_ value: String) -> String {
                        guard value.count == 4, let hour = Int(value.prefix(2)), let minute = Int(value.suffix(2)), (0..<24).contains(hour), (0..<60).contains(minute) else { return value }
                        return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
                    }
                    let times = [row["beginTime"], row["endTime"]].filter { !$0.isEmpty }.map(clock).joined(separator: " – ")
                    return [days, times, row["bldgDesc"], row["roomCode"]].filter { !$0.isEmpty }.joined(separator: " ")
                }.filter { !$0.isEmpty }).sorted()
                return Section(crn: crn, title: first["courseTitle"], start: first["ptrmStartDate"], end: first["ptrmEndDate"],
                               formats: formats, meetings: descriptions, status: first["fwSectOpenInd"])
            }.sorted { $0.crn < $1.crn }
            var professor = Professor(id: name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current), name: name, sections: sections)
            professor.subjectCode = course.subject
            let descriptions = Set(records.map { $0["subjDesc"].trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            professor.subjectDescription = descriptions.count == 1 ? descriptions.first! : ""
            return professor
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public enum IdentityMatcher {
    private static func tokens(_ name: String) -> [String] {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            .filter { !["dr", "prof", "professor"].contains($0) }
    }
    public static func matches(name: String, profile: RMPProfile) -> Bool {
        guard profile.schoolID == 2649, tokens(profile.school) == tokens("Pasadena City College") else { return false }
        let source = tokens(name), first = tokens(profile.firstName), last = tokens(profile.lastName)
        guard source.count >= 2, let initialName = source.first, let familyName = source.last,
              first.first == initialName, last.contains(familyName) else { return false }
        // Accept a compound family name only when all additional PCC name tokens are represented.
        return source.dropFirst().allSatisfy { (first + last).contains($0) }
    }
    public static func normalizedName(_ name: String) -> String { tokens(name).joined(separator: " ") }
    public static func eligible(name: String, candidates: [RMPProfile]) -> [RMPProfile] {
        Dictionary(candidates.filter { matches(name: name, profile: $0) }.map { ($0.id, $0) },
                   uniquingKeysWith: { _, latest in latest }).values.sorted {
            let a = [$0.name, $0.department, $0.id].joined(separator: "|")
            let b = [$1.name, $1.department, $1.id].joined(separator: "|")
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
    public static func unique(name: String, candidates: [RMPProfile]) -> RMPProfile? {
        let matches = Dictionary(grouping: candidates.filter { matches(name: name, profile: $0) }, by: \.id)
        return matches.count == 1 ? matches.values.first?.first : nil
    }
}
