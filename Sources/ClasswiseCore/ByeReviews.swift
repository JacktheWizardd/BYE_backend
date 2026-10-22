import Foundation

/// BYE's own student reviews for one PCC instructor, read from the BYE website's public `/api/reviews/*` routes.
/// They are kept apart from RMP: separate scores, separate cards, never blended.
public struct ByeReviewSet: Sendable, Hashable {
    /// False when no BYE professor matches the PCC name exactly; BYE never guesses between people.
    public let matched: Bool
    public let count: Int
    public let quality: Double?
    public let difficulty: Double?
    /// Present when the scores could not be loaded although reviews may still be listed.
    public let ratingIssue: String?
    /// Every listed review, newest first (up to `ByeReviewClient.reviewLimit`). `course` holds the BYE course code.
    public let reviews: [Review]
    /// False when more reviews exist than were downloaded.
    public let complete: Bool
    public let retrievedAt: Date

    public init(matched: Bool, count: Int, quality: Double?, difficulty: Double?, ratingIssue: String?, reviews: [Review], complete: Bool, retrievedAt: Date) {
        self.matched = matched; self.count = count; self.quality = quality; self.difficulty = difficulty
        self.ratingIssue = ratingIssue; self.reviews = reviews; self.complete = complete; self.retrievedAt = retrievedAt
    }
    public static func unmatched(at date: Date) -> ByeReviewSet {
        ByeReviewSet(matched: false, count: 0, quality: nil, difficulty: nil, ratingIssue: nil, reviews: [], complete: true, retrievedAt: date)
    }
}

/// Reads the website's read-only review routes. GET only, no cookies or credentials, HTTPS (or loopback HTTP for tests).
public actor ByeReviewClient {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    /// Pages of 20; five pages covers every professor BYE has today and bounds a single report's requests.
    public static let reviewLimit = 100

    private let site: URL?
    private let fetch: Fetch
    private let now: @Sendable () -> Date

    public init(site: String, fetch: Fetch? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        let url = URL(string: site.replacingOccurrences(of: "/+$", with: "", options: .regularExpression))
        let local = ["localhost", "127.0.0.1", "::1"].contains(url?.host ?? "")
        let valid = url.map { $0.host != nil && $0.user == nil && $0.password == nil && $0.query == nil && $0.fragment == nil
            && ($0.scheme == "https" || ($0.scheme == "http" && local)) } ?? false
        self.site = valid ? url : nil
        self.now = now
        if let fetch { self.fetch = fetch } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil; config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil; config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForResource = 25
            let session = URLSession(configuration: config)
            self.fetch = { try await session.data(for: $0) }
        }
    }

    /// Resolves the PCC name and class to a BYE professor, then loads their scores and reviews.
    public func load(instructor: String, course: Course) async throws -> ByeReviewSet {
        let resolution: Resolution = try await get("resolve", ["instructor": instructor, "course": course.display])
        guard resolution.match == "matched", let professor = resolution.professor else { return .unmatched(at: now()) }
        // Scores and reviews fail independently, so a scores outage still lists reviews.
        async let profileResult: Result<Profile, Error> = { do { return .success(try await get("profile", ["professorId": professor.id])) } catch { return .failure(error) } }()
        var reviews: [Review] = [], seen = Set<String>(), offset: Int? = 0
        while let current = offset, reviews.count < Self.reviewLimit {
            try Task.checkCancellation()
            let page: Page = try await get("list", ["professorId": professor.id, "sort": "recent", "offset": String(current)])
            for item in page.reviews where seen.insert(item.id).inserted {
                reviews.append(Review(id: item.id, course: item.course, text: item.body, date: item.date,
                                      rating: item.quality, difficulty: item.difficulty, online: nil))
            }
            offset = page.nextOffset
        }
        let profile = await profileResult
        let scores = try? profile.get()
        return ByeReviewSet(matched: true, count: scores?.count ?? reviews.count, quality: scores?.quality, difficulty: scores?.difficulty,
                            ratingIssue: scores == nil ? Self.message(for: profile) : nil,
                            reviews: Array(reviews.prefix(Self.reviewLimit)), complete: offset == nil, retrievedAt: now())
    }

    private static func message(for result: Result<Profile, Error>) -> String? {
        guard case .failure(let error) = result else { return nil }
        return (error as? AppError)?.errorDescription ?? "BYE ratings could not be loaded."
    }

    private func get<T: Decodable>(_ route: String, _ query: [String: String]) async throws -> T {
        guard let site, var components = URLComponents(url: site.appendingPathComponent("api/reviews/" + route), resolvingAgainstBaseURL: false) else {
            throw AppError.message("BYE reviews are not configured.")
        }
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw AppError.message("BYE reviews could not be requested.") }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await fetch(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error.message
            throw AppError.message(message ?? (status == 429 ? "BYE reviews are busy. Try again shortly." : "BYE reviews could not be loaded. Try again shortly."))
        }
        do { return try JSONDecoder().decode(Envelope<T>.self, from: data).data }
        catch { throw AppError.message("BYE reviews returned an unexpected response.") }
    }

    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private struct Failure: Decodable { struct Body: Decodable { let message: String }; let error: Body }
    private struct Resolution: Decodable { struct Item: Decodable { let id: String }; let professor: Item?; let match: String }
    private struct Profile: Decodable, Sendable { let count: Int; let quality: Double?; let difficulty: Double? }
    private struct Page: Decodable {
        struct Item: Decodable { let id: String; let quality: Double?; let difficulty: Double?; let body: String; let date: String; let course: String }
        let reviews: [Item]; let nextOffset: Int?
    }
}

/// Which reviews the professor page lists: BYE first, then RMP ("both"), or one source.
public enum ReviewSource: String, CaseIterable, Identifiable, Sendable {
    case both, bye, rmp
    public var id: String { rawValue }
    public var label: String { switch self { case .both: "Both"; case .bye: "BYE"; case .rmp: "RMP" } }
}

/// One card in the merged Reviews list, tagged with where it came from.
public struct SourcedReview: Identifiable, Hashable, Sendable {
    public enum Source: Hashable, Sendable { case bye, rmp }
    public let source: Source
    public let review: Review
    public var id: String { (source == .bye ? "bye|" : "rmp|") + review.id }
}

extension ReviewFilter {
    /// BYE reviews for this filter. A source label matches BYE codes by course (so "MATH5A" finds "MATH 005A").
    public func byeReviews(_ reviews: [Review], course: Course) -> [Review] {
        switch self {
        case .thisCourse: reviews.filter { course.matchesReview($0.course) }
        case .allCourses: reviews
        case .source(let label):
            if let wanted = try? Course(label) { reviews.filter { wanted.matchesReview($0.course) } } else { reviews.filter { $0.course == label } }
        }
    }
}

extension Ordering {
    /// The merged Reviews list: in Both, every BYE review comes first, and RMP waits until BYE has finished loading
    /// so cards never appear and then get pushed down. One sort applies to both sources.
    public static func merged(bye: [Review], rmp: [Review], source: ReviewSource, byeLoaded: Bool, by order: ReviewSort) -> [SourcedReview] {
        let byeCards = reviews(bye, by: order).map { SourcedReview(source: .bye, review: $0) }
        let rmpCards = reviews(rmp, by: order).map { SourcedReview(source: .rmp, review: $0) }
        switch source {
        case .bye: return byeCards
        case .rmp: return rmpCards
        case .both: return byeLoaded ? byeCards + rmpCards : byeCards
        }
    }
}
