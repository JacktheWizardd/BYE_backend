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

    private static let courseRegex = try! NSRegularExpression(pattern: "^([A-Z]{2,8})\\s*([A-Z]?\\d{1,4}[A-Z]*)$")

    public init(_ input: String) throws {
        let cleaned = input.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = Course.courseRegex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
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
    public init(values: [String: String]) { self.values = values }
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

public enum Weekday: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case monday = "Monday", tuesday = "Tuesday", wednesday = "Wednesday", thursday = "Thursday"
    case friday = "Friday", saturday = "Saturday", sunday = "Sunday"
    public var id: String { rawValue }
    public var shortLabel: String { String(rawValue.prefix(3)) }
    var sourceField: String { shortLabel.lowercased() + "Day" }
}

public struct SectionSchedule: Codable, Hashable, Sendable {
    public let days: Set<Weekday>
    public let hasUnannouncedMeetings: Bool
    public init(days: Set<Weekday>, hasUnannouncedMeetings: Bool) {
        self.days = days; self.hasUnannouncedMeetings = hasUnannouncedMeetings
    }
}

/// Enrollment and term facts PCC publishes for a section. Every field is optional because older caches and
/// rows without these keys still decode.
public struct SectionDetails: Codable, Hashable, Sendable {
    public var seatsOpen: Int?
    public var capacity: Int?
    public var waitlistCount: Int?
    public var waitlistCapacity: Int?
    public var termPart: String
    public var campus: String
    public var units: String
    public init(seatsOpen: Int? = nil, capacity: Int? = nil, waitlistCount: Int? = nil, waitlistCapacity: Int? = nil,
                termPart: String = "", campus: String = "", units: String = "") {
        self.seatsOpen = seatsOpen; self.capacity = capacity
        self.waitlistCount = waitlistCount; self.waitlistCapacity = waitlistCapacity
        self.termPart = termPart; self.campus = campus; self.units = units
    }
    init(row: ScheduleRow) {
        func count(_ key: String) -> Int? { Int(row[key].trimmingCharacters(in: .whitespaces)) }
        func text(_ key: String) -> String { row[key].trimmingCharacters(in: .whitespacesAndNewlines) }
        self.init(seatsOpen: count("seatsAvail").map { max(0, $0) }, capacity: count("maxEnrl"),
                  waitlistCount: count("waitCount"), waitlistCapacity: count("waitCapacity"),
                  termPart: text("ptrmDesc"), campus: text("campDesc"), units: text("creditHrLow"))
    }
    public var isFull: Bool { seatsOpen == 0 }
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
    public var schedule: SectionSchedule? = nil
    public var details: SectionDetails? = nil
    public var fullyOnline: Bool { !formats.isEmpty && formats.allSatisfy { $0 == "OD" } }
    /// Short format label for tags: In person, Hybrid, Online · live or Online · async.
    public var formatLabel: String {
        if fullyOnline { return "Online · async" }
        if formats.contains("HY") { return "Hybrid" }
        if !formats.isEmpty && formats.allSatisfy({ ["OD", "OL", "OS", "ON"].contains($0) }) { return "Online · live" }
        return "In person"
    }
    public var scheduleNotAnnounced: Bool {
        !fullyOnline && (schedule == nil || schedule?.hasUnannouncedMeetings == true || schedule?.days.isEmpty == true)
    }
    /// True when the section meets on every picked day (it may meet on other days too).
    /// Fully online sections have no meetings and always match; sections with no announced days never do.
    public func fits(availableDays: Set<Weekday>) -> Bool {
        if availableDays.isEmpty || fullyOnline { return true }
        guard let schedule, !schedule.days.isEmpty else { return false }
        return availableDays.isSubset(of: schedule.days)
    }
    public var delivery: String {
        if fullyOnline { return "Online · no scheduled meetings" }
        if formats.contains("HY") { return "Hybrid · campus meetings required" }
        if formats.allSatisfy({ ["OD", "OL", "OS", "ON"].contains($0) }) { return "Online · scheduled meetings" }
        return "In person"
    }
    private static let startEndParser: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        return parser
    }()
    private static let startEndDisplay: DateFormatter = {
        let display = DateFormatter()
        display.locale = Locale(identifier: "en_US")
        display.timeZone = TimeZone(secondsFromGMT: 0)
        display.dateFormat = "MMM d, yyyy"
        return display
    }()

    public var dateLabel: String {
        func label(_ source: String) -> String {
            Section.startEndParser.date(from: String(source.prefix(10))).map { Section.startEndDisplay.string(from: $0) } ?? "Date unavailable"
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
        // Decode here too: reports cached before 0.4.0 can still hold encoded entities.
        let visible = Review.visibleText(text)
        return visible.count > 500 ? String(visible.prefix(500)) + "…" : visible
    }
    /// RMP comments can contain HTML character references such as `&#8212;` or `&amp;`; show the characters.
    public static func visibleText(_ source: String) -> String {
        guard source.contains("&") else { return source }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "—", "ndash": "–",
                     "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“"]
        var result = ""
        var rest = Substring(source)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let tail = rest[amp...]
            if let semi = tail.prefix(12).firstIndex(of: ";") {
                let name = tail[tail.index(after: amp)..<semi]
                var decoded: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = named[name.lowercased()]
                }
                if let decoded {
                    result += decoded
                    rest = tail[tail.index(after: semi)...]
                    continue
                }
            }
            result += "&"
            rest = tail.dropFirst()
        }
        return result + rest
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
    /// Most reviews retrieved per source filter, and per combined "this course" view.
    public static let limit = 50
    public var reviewIDs: [String]
    public var nextCursor: String?
    public var hasNextPage: Bool
    public var updatedAt: Date
    public init(reviewIDs: [String], nextCursor: String?, hasNextPage: Bool, updatedAt: Date = Date()) {
        self.reviewIDs = reviewIDs; self.nextCursor = nextCursor; self.hasNextPage = hasNextPage; self.updatedAt = updatedAt
    }
    public var finished: Bool { !hasNextPage || reviewIDs.count >= ReviewCoverage.limit }
}

public enum ReviewFilter: Hashable, Sendable {
    case thisCourse, allCourses, source(String)
    /// The filter a report opens on: this course when any downloaded review is about it, otherwise all courses
    /// so the student still sees what is there. A profile without reviews keeps this course.
    public static func preferred(in profile: RMPProfile?, course: Course) -> ReviewFilter {
        guard let reviews = profile?.reviews, !reviews.isEmpty else { return .thisCourse }
        return reviews.contains { course.matchesReview($0.course) } ? .thisCourse : .allCourses
    }
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

    /// Use source spellings for network requests, never guessed aliases.
    public func sourceLabels(in profile: RMPProfile, course: Course) -> [String] {
        switch self {
        case .allCourses: return []
        case .source(let label): return [label]
        case .thisCourse:
            let covered = (profile.reviewCoverage ?? [:]).keys.compactMap {
                $0.hasPrefix("course|") ? String($0.dropFirst(7)) : nil
            }
            let labels = Set(((profile.courseCounts ?? []).map(\.label) + profile.reviews.map(\.course) + covered)
                .filter { course.matchesReview($0) })
            return labels.isEmpty ? [course.key] : labels.sorted()
        }
    }

    public func retrievedIDs(in profile: RMPProfile, course: Course) -> Set<String> {
        Set(sourceLabels(in: profile, course: course).flatMap {
            profile.reviewCoverage?[Self.coverageKey($0)]?.reviewIDs ?? []
        })
    }

    public func finished(in profile: RMPProfile, course: Course) -> Bool {
        if self == .allCourses { return profile.reviewCoverage?["all"]?.finished == true }
        return retrievedIDs(in: profile, course: course).count >= ReviewCoverage.limit || sourceLabels(in: profile, course: course).allSatisfy {
            profile.reviewCoverage?[Self.coverageKey($0)]?.finished == true
        }
    }
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
    case recent = "Latest first", oldest = "Oldest first"
    case highest = "Highest rating", lowest = "Lowest rating"
    case highestDifficulty = "Highest difficulty", difficulty = "Lowest difficulty"
    public var id: String { rawValue }
}

/// Shared, configured once. Each formatter keeps fixed options, so concurrent reads are safe.
private enum ReviewDate {
    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()
    private static let fallbacks: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss Z 'UTC'", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd"].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }
    static func parse(_ raw: String) -> Date? {
        isoFractional.date(from: raw) ?? iso.date(from: raw) ?? fallbacks.lazy.compactMap { $0.date(from: raw) }.first
    }
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
        // Parse once per review rather than inside the sorting comparator.
        let dated = list.map { (review: $0, date: ReviewDate.parse($0.date)) }
        return dated.sorted { a, b in
            func compare<T: Comparable>(_ x: T?, _ y: T?, ascending: Bool) -> Bool? {
                switch (x, y) {
                case (nil, nil): return nil
                case (nil, _): return false
                case (_, nil): return true
                case let (x?, y?): return x == y ? nil : (ascending ? x < y : x > y)
                }
            }
            let scoreOrder: Bool?
            switch order {
            case .recent, .oldest: scoreOrder = nil
            case .highest, .lowest:
                scoreOrder = compare(a.review.rating.flatMap { $0.isFinite ? $0 : nil }, b.review.rating.flatMap { $0.isFinite ? $0 : nil }, ascending: order == .lowest)
            case .highestDifficulty, .difficulty:
                scoreOrder = compare(a.review.difficulty.flatMap { $0.isFinite ? $0 : nil }, b.review.difficulty.flatMap { $0.isFinite ? $0 : nil }, ascending: order == .difficulty)
            }
            return scoreOrder ?? compare(a.date, b.date, ascending: order == .oldest) ?? (a.review.id < b.review.id)
        }.map(\.review)
    }
}

public enum ScheduleParser {
    /// Readable place for one meeting. PCC's building field lists every building of the section
    /// ("Online ASYNCH,R"), and an unassigned room reads "Needs Assignment".
    static func place(building: String, room: String) -> String {
        let parts = building.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let campus = parts.filter { !$0.hasPrefix("Online") }
        let roomCode = room.trimmingCharacters(in: .whitespaces)
        let assigned = roomCode.isEmpty || roomCode == "Needs Assignment" ? "" : roomCode
        if campus.isEmpty {
            if parts.contains(where: { $0.localizedCaseInsensitiveContains("zoom") }) { return "Online (Zoom)" }
            return parts.isEmpty ? (assigned.isEmpty ? "" : "Room " + assigned) : "Online"
        }
        let buildings = campus.joined(separator: " / ")
        return assigned.isEmpty ? buildings + " · room TBA" : buildings + " " + assigned
    }

    public static func professors(rows: [ScheduleRow], course: Course) -> [Professor] {
        let matches = rows.filter { row in
            guard !row["crn"].isEmpty else { return false }
            let subj = row["subjCode"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            // Cheap pre-check before parsing. A prefix test, because a code typed without a space
            // ("STATC1000") parses with subject STATC while PCC lists subject STAT.
            if !subj.isEmpty && !course.matchingKey.hasPrefix(subj) { return false }
            return (try? Course(row["subjCode"] + " " + row["courseNumbDisplay"]).matchingKey) == course.matchingKey
        }
        let meetingsByCRN = Dictionary(grouping: matches, by: { $0["crn"] })
        // Retain explicitly listed co-instructors, with every required meeting for their CRN.
        let instructors = Dictionary(grouping: matches) { row in
            let name = row["pfaName"].trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Instructor to be announced" : name
        }
        return instructors.map { name, records in
            let sections = Dictionary(grouping: records, by: { $0["crn"] }).map { crn, instructorMeetings in
                let meetings = meetingsByCRN[crn] ?? instructorMeetings
                let first = meetings[0]
                let formats = Set(meetings.map { $0["schdCode"] }.filter { !$0.isEmpty }).sorted()
                let scheduledMeetings = meetings.filter { $0["schdCode"] != "OD" }
                let rowDays = scheduledMeetings.map { row in
                    Set(Weekday.allCases.filter { !row[$0.sourceField].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
                let schedule = SectionSchedule(days: rowDays.reduce(into: Set<Weekday>()) { $0.formUnion($1) },
                                               hasUnannouncedMeetings: rowDays.contains(where: \.isEmpty))
                let descriptions = Set(meetings.compactMap { row -> String? in
                    if row["schdCode"] == "OD" { return nil }
                    let days = Weekday.allCases.filter { !row[$0.sourceField].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .map(\.shortLabel).joined(separator: ", ")
                    func clock(_ value: String) -> String {
                        guard value.count == 4, let hour = Int(value.prefix(2)), let minute = Int(value.suffix(2)), (0..<24).contains(hour), (0..<60).contains(minute) else { return value }
                        return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
                    }
                    let times = [row["beginTime"], row["endTime"]].filter { !$0.isEmpty }.map(clock).joined(separator: " – ")
                    let when = [days, times].filter { !$0.isEmpty }.joined(separator: " ")
                    let place = ScheduleParser.place(building: row["bldgDesc"], room: row["roomCode"])
                    if when.isEmpty {
                        // A no-time row with no room is the online part of a hybrid class; with a room, the time is unannounced.
                        let roomAssigned = !["", "Needs Assignment"].contains(row["roomCode"].trimmingCharacters(in: .whitespaces))
                        if !roomAssigned && row["bldgDesc"].contains("Online") { return "Online, no set meeting time" }
                        return place.isEmpty ? "" : "Time TBA · " + place
                    }
                    return [when, place].filter { !$0.isEmpty }.joined(separator: " · ")
                }.filter { !$0.isEmpty }).sorted()
                return Section(crn: crn, title: first["courseTitle"], start: first["ptrmStartDate"], end: first["ptrmEndDate"],
                               formats: formats, meetings: descriptions, status: first["fwSectOpenInd"], schedule: schedule,
                               details: SectionDetails(row: first))
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
