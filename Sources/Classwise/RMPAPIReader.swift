import Foundation
import ClasswiseCore
import BYEAPI

@MainActor
final class RMPAPIReader: CourseProfileReader {
    private let client: RMPClient
    private var generation = UUID()
    init(client: RMPClient = .shared) { self.client = client }
    func stop() { generation = UUID() }
    private func check(_ run: UUID) throws {
        try Task.checkCancellation()
        if generation != run { throw CancellationError() }
    }
    func candidates(_ professor: Professor, discoverAll: Bool) async throws -> [RMPProfile] {
        guard professor.canSearch else { return [] }
        let run = generation
        var found: [RMPProfile] = [], cursor: String?, visited = Set<String>()
        for _ in 0..<4 {
            do {
                let page = try await client.search(name: professor.name, cursor: cursor)
                try check(run)
                found = IdentityMatcher.eligible(name: professor.name, candidates: found + page.profiles)
                if !discoverAll && !found.isEmpty { return found }
                guard page.hasNextPage, let next = page.nextCursor else { break }
                guard visited.insert(next).inserted else { throw RMPAPIError.pagination }
                cursor = next
            } catch {
                try check(run)
                if !found.isEmpty { return found }
                throw error
            }
        }
        return found
    }
    private func verify(_ profile: RMPProfile, professor: Professor, expectedID: String) throws {
        guard profile.id == expectedID, IdentityMatcher.matches(name: professor.name, profile: profile) else { throw ProfileIdentityMismatch() }
    }
    private func fetch(_ professor: Professor, id: String, count: Int, cursor: String?, filter: String?) async throws -> ProfessorReviewPage {
        do {
            let page = try await client.profile(id: id, count: count, cursor: cursor, courseFilter: filter)
            try verify(page.profile, professor: professor, expectedID: id)
            return page
        } catch RMPAPIError.invalidIdentity { throw ProfileIdentityMismatch() }
    }
    func preview(_ professor: Professor, profileID: String) async throws -> RMPProfile {
        let run = generation
        let page = try await fetch(professor, id: profileID, count: 3, cursor: nil, filter: nil)
        try check(run)
        var profile = page.profile
        profile.reviewCoverage = ["all": ReviewCoverage(reviewIDs: page.sourceReviewIDs, nextCursor: page.nextCursor, hasNextPage: page.hasNextPage)]
        return profile
    }
    func expand(_ professor: Professor, profile: RMPProfile,
                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        try await expand(professor, profile: profile, courseFilter: nil, onProfile: onProfile)
    }
    func expand(_ professor: Professor, profile: RMPProfile, courseFilter: String?, limit: Int,
                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        let run = generation, key = ReviewFilter.coverageKey(courseFilter)
        var result = profile
        var coverage = profile.reviewCoverage?[key] ?? ReviewCoverage(reviewIDs: [], nextCursor: nil, hasNextPage: true)
        var visited = Set<String>()
        // A finite page budget also handles repeated/empty source pages safely.
        for _ in 0..<10 {
            try check(run)
            if coverage.finished || coverage.reviewIDs.count >= limit { return result }
            let page = try await fetch(professor, id: profile.id, count: min(20, limit - coverage.reviewIDs.count), cursor: coverage.nextCursor, filter: courseFilter)
            try check(run)
            let newIDs = page.sourceReviewIDs.filter { !coverage.reviewIDs.contains($0) }
            guard !page.hasNextPage || !newIDs.isEmpty,
                  !page.hasNextPage || visited.insert(page.nextCursor ?? "").inserted else { throw RMPAPIError.pagination }
            coverage.reviewIDs = Array((coverage.reviewIDs + newIDs).prefix(ReviewCoverage.limit))
            coverage.nextCursor = page.nextCursor; coverage.hasNextPage = page.hasNextPage; coverage.updatedAt = Date()
            // Refresh source metadata and overwrite changed reviews by their stable source IDs.
            var merged = page.profile
            let reviews = Dictionary((result.reviews + page.profile.reviews).map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            merged.reviews = Ordering.reviews(Array(reviews.values), by: .recent)
            // A filtered page can omit course metadata; retain labels already discovered.
            merged.courseCounts = Self.mergeCourseCounts(result.courseCounts, page.profile.courseCounts)
            merged.reviewCoverage = result.reviewCoverage ?? [:]; merged.reviewCoverage?[key] = coverage
            result = merged
            onProfile(result)
        }
        if !coverage.finished && coverage.reviewIDs.count < limit { throw RMPAPIError.pagination }
        return result
    }
    /// Keeps first-seen label order so the UI doesn't reshuffle between pages; later counts win.
    nonisolated static func mergeCourseCounts(_ existing: [ReviewCourseCount]?, _ incoming: [ReviewCourseCount]?) -> [ReviewCourseCount]? {
        guard let incoming else { return existing }
        var merged = existing ?? []
        for count in incoming {
            if let index = merged.firstIndex(where: { $0.label == count.label }) { merged[index] = count }
            else { merged.append(count) }
        }
        return merged
    }
}
