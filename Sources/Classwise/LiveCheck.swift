#if DEBUG
import Foundation
import AppKit
import ClasswiseCore

/// Explicit developer-only integration check, never loaded as sample data.
@MainActor
enum LiveCheck {
    /// Runs the real first pass without reusing cached ratings, then checks that
    /// extra reviews were requested only for the opened report.
    static func runSpeed(output: String) async {
        let start = Date()
        var results: [String: Any] = ["startedAt": start.description, "course": "MATH 005A", "semester": "Fall 2026"]
        let model = AppModel()
        await model.loadTerms()
        guard let term = model.terms.first(where: { $0.termName == "Fall 2026" }) else {
            results["passed"] = false; results["error"] = "Fall 2026 is not published."
            finish(results, output: output); return
        }
        model.input = "MATH 005A"; model.termID = term.id; model.start(force: true)
        var firstResult: Double?
        while model.busy, Date().timeIntervalSince(start) < 180 {
            if firstResult == nil, model.professors.contains(where: { $0.profile != nil }) {
                firstResult = Date().timeIntervalSince(start)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        results["firstResultSeconds"] = firstResult
        results["ratingsPassSeconds"] = Date().timeIntervalSince(start)
        results["sections"] = Set(model.professors.flatMap { $0.sections.map(\.crn) }).count
        results["professors"] = model.professors.count
        results["verifiedProfiles"] = model.professors.filter { $0.profile != nil }.count
        results["previews"] = model.quickPassSnapshot.map { p in
            ["name": p.name, "rating": p.profile.flatMap(\.rating).map { $0 as Any } ?? NSNull(),
             "difficulty": p.profile.flatMap(\.difficulty).map { $0 as Any } ?? NSNull(), "reviews": p.profile?.reviews.count ?? 0,
             "state": p.state.rawValue, "issue": p.issue ?? ""] as [String: Any]
        }
        let previewsBounded = model.quickPassSnapshot.allSatisfy { ($0.profile?.reviews.count ?? 0) <= 3 }
        results["previewLimitPassed"] = previewsBounded
        // No other report should have entered pagination or summary generation.
        let untouched = model.quickPassSnapshot
        results["unopenedReportsUntouched"] = untouched.allSatisfy { !$0.reviewsComplete && $0.summary == nil }
        results["passed"] = !model.busy && model.error == nil && firstResult != nil && previewsBounded
        model.cancel()
        results["finishedAt"] = Date().description
        finish(results, output: output)
    }
    /// Regression check for a profile whose embedded preview arrives before its review controls.
    static func runReviewExpansion(output: String) async {
        let start = Date()
        var results: [String: Any] = ["startedAt": start.description, "course": "MATH 005A", "semester": "Fall 2026"]
        do {
            let pcc = PCCClient(), course = try Course("MATH005A")
            let term = try await pcc.terms().first(where: { $0.termCode == "202670" })
            guard let term else { throw AppError.message("Fall 2026 is not published.") }
            let professors = try await pcc.professors(course: course, term: term)
            guard let professor = professors.first(where: { $0.name == "Anahit Asadyan" }) else {
                throw AppError.message("The integration-check instructor is not in the current PCC schedule.")
            }
            let reader = RMPBrowser()
            let preview = try await reader.lookup(professor, initialReviewsOnly: true)
            results["previewSeconds"] = Date().timeIntervalSince(start)
            results["previewReviews"] = preview.reviews.count
            var progress: [Int] = []
            let full = try await reader.expand(professor, profile: preview) { progress.append($0.reviews.count); results["reviewProgress"] = progress }
            results["rating"] = full.rating; results["difficulty"] = full.difficulty
            results["sourceRatingCount"] = full.ratingCount
            results["reviewProgress"] = progress; results["retrievedReviews"] = full.reviews.count
            results["reviewSeconds"] = Date().timeIntervalSince(start)
            var summary: ReviewSummary?
            do {
                summary = try await OllamaClient().summarize(reviews: full.reviews, course: course)
                results["summary"] = summary?.overview; results["analyzedReviews"] = summary?.analyzedCount
                results["summaryPassed"] = true
            } catch {
                results["summaryPassed"] = false; results["summaryError"] = error.localizedDescription
            }
            ReportCache().save(CachedReport(profile: full, summary: summary, checkedAt: Date(), reviewsComplete: true),
                               name: professor.name, course: course)
            results["passed"] = preview.reviews.count <= 3 && full.reviews.count > preview.reviews.count
        } catch { results["passed"] = false; results["error"] = error.localizedDescription }
        results["finishedAt"] = Date().description
        finish(results, output: output)
    }
    static func run(output: String) async {
        var results: [String: Any] = ["startedAt": Date().description]
        do {
            let pcc = PCCClient(), course = try Course("ETH014")
            let terms = try await pcc.terms()
            guard let term = terms.first(where: { $0.termCode == "202650" }) else {
                throw AppError.message("Summer 2026 is no longer published.")
            }
            let professors = try await pcc.professors(course: course, term: term)
            results["pccProfessors"] = professors.count
            results["pccSections"] = Set(professors.flatMap { $0.sections.map(\.crn) }).count
            guard let professor = professors.first(where: { $0.name == "Martha Toscano" }) else {
                throw AppError.message("Live-check instructor is not in this schedule.")
            }
            let reader = RMPBrowser()
            let profile = try await reader.lookup(professor)
            results["rmpName"] = profile.name; results["rmpID"] = profile.id
            results["rating"] = profile.rating; results["difficulty"] = profile.difficulty
            results["retrievedReviews"] = profile.reviews.count
            let summary = try await OllamaClient().summarize(reviews: profile.reviews, course: course)
            results["summary"] = summary.overview
            results["analyzedReviews"] = summary.analyzedCount
            results["exactCourseReviews"] = summary.exactCourseCount
            results["passed"] = true
        } catch { results["passed"] = false; results["error"] = error.localizedDescription }
        results["finishedAt"] = Date().description
        finish(results, output: output)
    }
    private static func finish(_ results: [String: Any], output: String) {
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
            try? data.write(to: URL(fileURLWithPath: output), options: .atomic)
            print(String(data: data, encoding: .utf8)!)
        }
        NSApplication.shared.terminate(nil)
    }
}
#endif
