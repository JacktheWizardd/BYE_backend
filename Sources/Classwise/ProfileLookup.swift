import Foundation
import ClasswiseCore

/// Ambiguity is actionable data, not a retrieval error.
enum ProfileLookupOutcome {
    case verified(RMPProfile)
    case selectionRequired([RMPProfile], invalidatedProfileID: String? = nil)
    case unavailable(String)
}
struct ProfileIdentityMismatch: Error {}

@MainActor
protocol ProfileReader: AnyObject {
    func stop()
    func candidates(_ professor: Professor, discoverAll: Bool) async throws -> [RMPProfile]
    func preview(_ professor: Professor, profileID: String) async throws -> RMPProfile
    func expand(_ professor: Professor, profile: RMPProfile,
                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile
}

@MainActor
protocol CourseProfileReader: ProfileReader {
    func expand(_ professor: Professor, profile: RMPProfile, courseFilter: String?, limit: Int,
                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile
}

extension CourseProfileReader {
    func expand(_ professor: Professor, profile: RMPProfile, courseFilter: String?,
                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        try await expand(professor, profile: profile, courseFilter: courseFilter, limit: ReviewCoverage.limit, onProfile: onProfile)
    }

    func expand(_ professor: Professor, profile: RMPProfile, matching course: Course,
                onProfile: @MainActor (RMPProfile) -> Void) async throws -> RMPProfile {
        var result = profile
        while !ReviewFilter.thisCourse.finished(in: result, course: course) {
            try Task.checkCancellation()
            guard let label = ReviewFilter.thisCourse.sourceLabels(in: result, course: course).first(where: {
                result.reviewCoverage?[ReviewFilter.coverageKey($0)]?.finished != true
            }) else { break }
            let remaining = ReviewCoverage.limit - ReviewFilter.thisCourse.retrievedIDs(in: result, course: course).count
            let existing = result.reviewCoverage?[ReviewFilter.coverageKey(label)]?.reviewIDs.count ?? 0
            result = try await expand(professor, profile: result, courseFilter: label,
                                      limit: min(ReviewCoverage.limit, existing + remaining), onProfile: onProfile)
            // Duplicate IDs across labels can leave room in the combined budget.
            // Continue that source, but never spin on a reader that made no progress.
            if result.reviewCoverage?[ReviewFilter.coverageKey(label)]?.finished != true,
               (result.reviewCoverage?[ReviewFilter.coverageKey(label)]?.reviewIDs.count ?? 0) <= existing {
                throw AppError.message("Review retrieval made no progress. Try again.")
            }
        }
        try Task.checkCancellation()
        return result
    }
}

extension ProfileReader {
    func lookupOutcome(_ professor: Professor, preferredProfileID: String? = nil) async throws -> ProfileLookupOutcome {
        do {
            if let id = preferredProfileID {
                do { return .verified(try await preview(professor, profileID: id)) }
                catch is ProfileIdentityMismatch {
                    // Never silently replace a preference whose identity changed.
                    let options = (try? await candidates(professor, discoverAll: true)) ?? []
                    try Task.checkCancellation()
                    return .selectionRequired(options.filter { $0.id != id }, invalidatedProfileID: id)
                }
            }
            let options = IdentityMatcher.eligible(name: professor.name, candidates: try await candidates(professor, discoverAll: false))
            try Task.checkCancellation()
            if options.count > 1 { return .selectionRequired(options) }
            guard let candidate = options.first else { return .unavailable("No matching PCC profile could be confirmed. Try again or check RMP.") }
            do { return .verified(try await preview(professor, profileID: candidate.id)) }
            catch is ProfileIdentityMismatch { return .selectionRequired(options.filter { $0.id != candidate.id }) }
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            return .unavailable(error.localizedDescription)
        }
    }
}
