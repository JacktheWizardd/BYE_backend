import Foundation

/// A short-lived semester cache shared by suggestions and actual course searches.
/// Concurrent callers reuse one request, including a refresh already in progress.
actor ScheduleCache {
    private struct Entry { let rows: [ScheduleRow]; let savedAt: Date }
    private struct Flight { let id: UUID; let task: Task<[ScheduleRow], Error> }
    private var entries: [String: Entry] = [:]
    private var flights: [String: Flight] = [:]
    private let lifetime: TimeInterval
    private let now: () -> Date

    init(lifetime: TimeInterval = 300, now: @escaping () -> Date = Date.init) {
        self.lifetime = lifetime; self.now = now
    }

    func rows(termCode: String, force: Bool, load: @escaping () async throws -> [ScheduleRow]) async throws -> [ScheduleRow] {
        if let flight = flights[termCode] { return try await flight.task.value }
        if !force, let entry = entries[termCode] {
            let age = now().timeIntervalSince(entry.savedAt)
            if age >= 0 && age < lifetime { return entry.rows }
        }
        let id = UUID(), task = Task { try await load() }
        flights[termCode] = Flight(id: id, task: task)
        do {
            let rows = try await task.value
            if flights[termCode]?.id == id {
                entries[termCode] = Entry(rows: rows, savedAt: now())
                flights[termCode] = nil
            }
            return rows
        } catch {
            if flights[termCode]?.id == id { flights[termCode] = nil }
            throw error
        }
    }
}

public struct CourseSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { course.key }
    public let course: Course
    public let title: String
    public init(course: Course, title: String) { self.course = course; self.title = title }
}

public enum CourseSuggestions {
    public static func resolve(_ query: Course, rows: [ScheduleRow]) throws -> Course {
        let matches = catalog(rows: rows).filter { $0.course.matchingKey == query.matchingKey }
        if let exact = matches.first(where: { $0.course.key == query.key }) { return exact.course }
        guard matches.count <= 1 else { throw AppError.message("More than one PCC course matches. Choose an official course from the suggestions.") }
        return matches.first?.course ?? query
    }
    public static func catalog(rows: [ScheduleRow]) -> [CourseSuggestion] {
        var unique: [String: CourseSuggestion] = [:]
        for row in rows where !["R", "X"].contains(row["fwSectOpenInd"]) && !row["crn"].isEmpty {
            let subj = row["subjCode"].trimmingCharacters(in: .whitespacesAndNewlines)
            let numb = row["courseNumbDisplay"].trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep the space so codes like STAT C1000 parse as subject STAT, number C1000.
            guard !subj.isEmpty, !numb.isEmpty, let course = try? Course(subj + " " + numb) else { continue }
            let title = row["courseTitle"].trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = unique[course.key], !existing.title.isEmpty,
               title.isEmpty || existing.title.localizedStandardCompare(title) != .orderedDescending { continue }
            unique[course.key] = CourseSuggestion(course: course, title: title)
        }
        return unique.values.sorted { $0.course.display.localizedStandardCompare($1.course.display) == .orderedAscending }
    }
    public static func match(rows: [ScheduleRow], query: String, limit: Int = 5) -> [CourseSuggestion] {
        match(courses: catalog(rows: rows), query: query, limit: limit)
    }
    public static func match(courses: [CourseSuggestion], query: String, limit: Int = 5) -> [CourseSuggestion] {
        func normalized(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: \.isWhitespace).joined(separator: " ").uppercased()
        }
        let needle = normalized(query), compact = needle.replacingOccurrences(of: " ", with: "")
        guard !needle.isEmpty, limit > 0 else { return [] }
        let parsed = try? Course(query)
        func rank(_ item: CourseSuggestion) -> Int? {
            let title = normalized(item.title)
            if item.course.key == compact || item.course.matchingKey == parsed?.matchingKey { return 0 }
            if item.course.key.hasPrefix(compact) || parsed.map({ item.course.matchingKey.hasPrefix($0.matchingKey) }) == true { return 1 }
            if title.hasPrefix(needle) { return 2 }
            if item.course.key.contains(compact) { return 3 }
            if title.contains(needle) { return 4 }
            return nil
        }
        let ranked: [(suggestion: CourseSuggestion, rank: Int)] = courses.compactMap { item in
            guard let score = rank(item) else { return nil }
            return (suggestion: item, rank: score)
        }
        let sorted = ranked.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            return a.suggestion.course.display.localizedStandardCompare(b.suggestion.course.display) == .orderedAscending
        }
        return sorted.prefix(limit).map { $0.suggestion }
    }
}
