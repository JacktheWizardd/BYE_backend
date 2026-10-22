import Foundation

public struct ScheduleMetadata: Decodable, Sendable, Hashable {
    public let term: String?
    public let catalogVersion: String?
    public let availabilityVersion: String?
    public let sourceCheckedAt: String?
    public let stale: Bool?
    public var checkedAt: Date? {
        guard let value = sourceCheckedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    public func expired(at now: Date = Date()) -> Bool {
        guard let date = checkedAt else { return true }
        return stale == true || now.timeIntervalSince(date) >= 900 || date.timeIntervalSince(now) > 60
    }
}
private struct ScheduleEnvelope<T: Decodable & Sendable>: Decodable, Sendable { let data: T; let meta: ScheduleMetadata }
private struct PublishedTerm: Decodable, Sendable { let termCode: String; let name: String }
private struct ScheduleCourse: Codable, Sendable { let key: String; let subject: String; let number: String; let title: String }
private struct Availability: Decodable, Sendable {
    let statusCode: String?
    let enrolled: Int?, capacity: Int?, seatsAvailable: Int?, waitlistCount: Int?, waitlistCapacity: Int?, waitlistAvailable: Int?
}
private struct AvailabilityItem: Decodable, Sendable { let crn: String; let availability: Availability? }
private struct ScheduleMeeting: Decodable, Sendable {
    let startDate: String?, endDate: String?, beginTime: String?, endTime: String?, formatCode: String?, campus: String?, building: String?, room: String?
    struct SourceFields: Decodable, Sendable { let ptrmDesc: String? }
    let sourceFields: SourceFields?
    let days: [String]
    static let unknown = ScheduleMeeting(startDate: nil, endDate: nil, beginTime: nil, endTime: nil,
        formatCode: nil, campus: nil, building: nil, room: nil, sourceFields: nil, days: [])
}
private struct ScheduleInstructor: Decodable, Sendable { let assignmentId: String; let role: String; let name: String? }
private struct ScheduleSection: Decodable, Sendable {
    let crn: String; let courseKey: String; let units: String?
    let meetings: [ScheduleMeeting]; let instructors: [ScheduleInstructor]
    var availability: Availability?
}
public struct SharedCourseSchedule: Sendable { public let rows: [ScheduleRow]; public let metadata: ScheduleMetadata }

/// The actor owns bounded response caches. It never requests PCC directly.
public actor ScheduleAPIClient {
    private let base: URL?
    private let key: String
    private let session: URLSession
    private var responses: [String: (etag: String, data: Data)] = [:]
    private var termCatalogs: [String: (version: String?, courses: [ScheduleCourse])] = [:]
    private var courses: [String: (sections: [ScheduleSection], metadata: ScheduleMetadata)] = [:]
    private var blockedUntil = Date.distantPast
    private let cacheDirectory: URL?
    private let now: @Sendable () -> Date
    public init(base: URL?, key: String, session: URLSession? = nil,
                cacheDirectory: URL? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base; self.key = key; self.session = session ?? Self.makeSession(); self.now = now
        self.cacheDirectory = cacheDirectory
    }
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForResource = 25
        return URLSession(configuration: config)
    }
    public static func configured(session: URLSession? = nil) -> ScheduleAPIClient {
        let environment = ProcessInfo.processInfo.environment
        let address = environment["BYE_SCHEDULE_API_URL"] ?? Bundle.main.object(forInfoDictionaryKey: "BYEScheduleAPIURL") as? String ?? ""
        let key = environment["BYE_SCHEDULE_API_KEY"] ?? Bundle.main.object(forInfoDictionaryKey: "BYEScheduleAPIKey") as? String ?? ""
        return ScheduleAPIClient(base: URL(string: address), key: key, session: session,
            cacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("BYE/ScheduleCatalogs"))
    }
    private func get<T: Decodable & Sendable>(_ path: String) async throws -> ScheduleEnvelope<T> {
        guard let base, !key.isEmpty, base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil, base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(base.host ?? "")) else { throw AppError.message("The BYE schedule service is not configured.") }
        guard now() >= blockedUntil else { throw AppError.message("The schedule service is cooling down. Try again shortly.") }
        guard let url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else { throw AppError.message("Invalid schedule request.") }
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "apikey"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cached = responses[path] { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request, delegate: ScheduleRedirectPolicy.shared)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AppError.message("The schedule service is unavailable.") }
        if http.statusCode == 304, let cached = responses[path] { return try JSONDecoder().decode(ScheduleEnvelope<T>.self, from: cached.data) }
        guard http.statusCode == 200, data.count <= 8 * 1024 * 1024 else {
            if let retry = http.value(forHTTPHeaderField: "Retry-After"), let seconds = Double(retry), seconds > 0 { blockedUntil = now().addingTimeInterval(min(seconds, 86400)) }
            throw AppError.message("The BYE schedule service is unavailable. Try again shortly.")
        }
        let body = try JSONDecoder().decode(ScheduleEnvelope<T>.self, from: data)
        let parts = path.split(separator: "/")
        if parts.count >= 3, parts[1] == "terms", body.meta.term != String(parts[2]) {
            throw AppError.message("The schedule semester could not be verified.")
        }
        if let tag = http.value(forHTTPHeaderField: "ETag") {
            if responses.count >= 24, let oldest = responses.keys.sorted().first { responses[oldest] = nil }
            responses[path] = (tag, data)
        }
        return body
    }
    private func path(_ term: String) throws -> String {
        guard term.count == 6, term.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { throw AppError.message("Choose a published semester.") }
        return "/v1/terms/" + term
    }
    public func terms() async throws -> [Term] {
        let response: ScheduleEnvelope<[PublishedTerm]> = try await get("/v1/terms")
        guard response.data.count <= 100, Set(response.data.map(\.termCode)).count == response.data.count else {
            throw AppError.message("Invalid published semesters.")
        }
        for term in response.data { _ = try path(term.termCode) }
        return response.data.map { Term(termCode: $0.termCode, termName: $0.name, termDisplayControl: "Y") }
    }
    private func catalogFile(_ term: String) -> URL? {
        guard term.count == 6, term.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return cacheDirectory?.appendingPathComponent(term + ".json")
    }
    private func refreshCatalog(term: String) async throws -> [ScheduleCourse] {
        let response: ScheduleEnvelope<[ScheduleCourse]> = try await get(try path(term) + "/catalog")
        guard response.data.count <= 25000 else { throw AppError.message("The course catalog is too large.") }
        if let file = catalogFile(term) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(response.data) { try? data.write(to: file, options: .atomic) }
            let files = (try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)) ?? []
            let older = files.filter { $0.pathExtension == "json" && $0 != file }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in older.dropFirst(2) { try? FileManager.default.removeItem(at: old) }
        }
        return response.data
    }
    public func catalogRows(term: String) async throws -> [ScheduleRow] {
        if let file = catalogFile(term), let data = try? Data(contentsOf: file), data.count <= 2 * 1024 * 1024,
           let saved = try? JSONDecoder().decode([ScheduleCourse].self, from: data), saved.count <= 25000 {
            // Revalidate before publishing suggestions; offline reads keep the course-only cache.
            let catalog: [ScheduleCourse]
            do { catalog = try await refreshCatalog(term: term) }
            catch {
                try Task.checkCancellation()
                catalog = saved
            }
            return catalog.map { ScheduleRow(values: ["termCode": term, "subjCode": $0.subject, "courseNumbDisplay": $0.number, "courseTitle": $0.title, "crn": "00000"]) }
        }
        let catalog = try await refreshCatalog(term: term)
        return catalog.map { ScheduleRow(values: ["termCode": term, "subjCode": $0.subject, "courseNumbDisplay": $0.number, "courseTitle": $0.title, "crn": "00000"]) }
    }
    public func courseRows(term: String, query: String) async throws -> SharedCourseSchedule {
        let prefix = try path(term)
        let manifest: ScheduleEnvelope<ScheduleMetadata> = try await get(prefix + "/manifest")
        guard let version = manifest.meta.catalogVersion, !version.isEmpty,
              let availabilityVersion = manifest.meta.availabilityVersion, !availabilityVersion.isEmpty else {
            throw AppError.message("The schedule version could not be verified.")
        }
        var catalog = termCatalogs[term]
        if catalog == nil || catalog?.version != manifest.meta.catalogVersion {
            let response: ScheduleEnvelope<[ScheduleCourse]> = try await get(prefix + "/catalog")
            guard response.meta.catalogVersion == version else { throw AppError.message("The schedule changed. Try again shortly.") }
            catalog = (manifest.meta.catalogVersion, response.data)
            if termCatalogs.count >= 3, let oldest = termCatalogs.keys.sorted().first { termCatalogs[oldest] = nil }
            termCatalogs[term] = catalog
        }
        let typed = try Course(query)
        let matches = (catalog?.courses ?? []).filter { (try? Course($0.key).matchingKey) == typed.matchingKey }
        guard let course = matches.first(where: { (try? Course($0.key).key) == typed.key }) ?? (matches.count == 1 ? matches.first : nil), let encoded = course.key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw AppError.message("Choose an official course from the suggestions.") }
        let cacheKey = term + "|" + course.key
        var current = courses[cacheKey]
        if current == nil || current?.metadata.catalogVersion != manifest.meta.catalogVersion {
            let response: ScheduleEnvelope<[ScheduleSection]> = try await get(prefix + "/courses/" + encoded + "/sections")
            guard response.meta.catalogVersion == version else { throw AppError.message("The schedule changed. Try again shortly.") }
            current = (response.data, response.meta)
        } else if var old = current {
            if old.metadata.availabilityVersion != manifest.meta.availabilityVersion || old.metadata.expired(at: now()) != manifest.meta.expired(at: now()) || (old.metadata.sourceCheckedAt != manifest.meta.sourceCheckedAt && !manifest.meta.expired(at: now())) {
                let crns = Array(Set(old.sections.map(\.crn))).sorted()
                var values: [String: AvailabilityItem] = [:]
                for start in stride(from: 0, to: crns.count, by: 100) {
                    let batch = crns[start..<min(start + 100, crns.count)].joined(separator: ",")
                    let response: ScheduleEnvelope<[AvailabilityItem]> = try await get(prefix + "/availability?crns=" + batch)
                    guard response.meta.catalogVersion == version,
                          response.meta.availabilityVersion == availabilityVersion else {
                        throw AppError.message("The schedule changed. Try again shortly.")
                    }
                    for item in response.data { values[item.crn] = item }
                }
                old.sections = old.sections.map { section in var updated = section; updated.availability = values[section.crn]?.availability; return updated }
            }
            old.metadata = manifest.meta; current = old
        }
        try Task.checkCancellation()
        guard let current else { throw AppError.message("No schedule was returned.") }
        if courses.count >= 12, let oldest = courses.keys.sorted().first { courses[oldest] = nil }
        courses[cacheKey] = current
        var rows: [ScheduleRow] = []
        for section in current.sections {
            guard section.courseKey == course.key else { throw AppError.message("The schedule identity could not be verified.") }
            let availability = current.metadata.expired(at: now()) ? nil : section.availability
            let names = section.instructors.isEmpty ? [String?](arrayLiteral: nil) : section.instructors.map(\.name)
            for meeting in section.meetings.isEmpty ? [ScheduleMeeting.unknown] : section.meetings { for name in names {
                var row = ["termCode": term, "subjCode": course.subject, "courseNumbDisplay": course.number, "courseTitle": course.title, "crn": section.crn, "pfaName": name ?? "", "creditHrLow": section.units ?? "", "ptrmDesc": meeting.sourceFields?.ptrmDesc ?? "", "ptrmStartDate": meeting.startDate ?? "", "ptrmEndDate": meeting.endDate ?? "", "beginTime": meeting.beginTime ?? "", "endTime": meeting.endTime ?? "", "schdCode": meeting.formatCode ?? "", "bldgDesc": meeting.building ?? "", "roomCode": meeting.room ?? "", "campDesc": meeting.campus ?? "", "fwSectOpenInd": availability?.statusCode ?? ""]
                for day in ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] { row[day + "Day"] = meeting.days.contains(day) ? day : "" }
                let counts: [(String, Int?)] = [("seatsAvail", availability?.seatsAvailable), ("maxEnrl", availability?.capacity), ("waitCount", availability?.waitlistCount), ("waitCapacity", availability?.waitlistCapacity)]
                for (key, count) in counts { if let count { row[key] = String(count) } }
                rows.append(ScheduleRow(values: row))
            } }
        }
        return SharedCourseSchedule(rows: rows, metadata: current.metadata)
    }
}

private final class ScheduleRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = ScheduleRedirectPolicy()
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
