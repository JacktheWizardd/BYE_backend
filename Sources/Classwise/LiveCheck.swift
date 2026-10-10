#if DEBUG
import Foundation
import AppKit
import ClasswiseCore
import FoundationModels

/// Explicit developer-only integration check, never loaded as sample data.
@MainActor
enum LiveCheck {
    /// Opt-in live Apple check. All caches/preferences are temporary; no Ollama client is used.
    static func runApple(output: String) async {
        var results: [String: Any] = ["startedAt": Date().description, "usesOllama": false,
            "scope": "Local first-use is not a guaranteed OS-cold model; generation excludes network retrieval.",
            "storage": "Temporary directory, removed afterward"]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BYE-Apple-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            guard #available(macOS 26.4, *) else { throw AppError.message("macOS 26.4 is required") }
            results["availability"] = String(describing: SystemLanguageModel.default.availability)
            let course = try Course("MATH005A"), network = Date()
            let professor = try await appleBenchmarkProfessor()
            guard let full = professor.profile else { throw AppError.message("No verified benchmark profile") }
            results["retrievalSeconds"] = Date().timeIntervalSince(network)
            results["retrievalNote"] = "Reuses a previous verified benchmark snapshot for up to 24 hours when present; no saved AI summary."
            results["profileID"] = full.id; results["name"] = full.name; results["downloadedReviews"] = full.reviews.count
            let first = AppleSummaryProvider(), firstStart = Date()
            let firstSummary = try await first.summarize(reviews: full.reviews, course: course)
            results["firstUseGenerationSeconds"] = Date().timeIntervalSince(firstStart)
            results["firstSummary"] = firstSummary.overview
            results["firstAnalyzedReviews"] = firstSummary.analyzedCount
            results["firstMetrics"] = await first.lastMetrics
            let warm = AppleSummaryProvider(), preparation = Date()
            await warm.prewarm()
            try await Task.sleep(for: .seconds(1))
            results["prewarmLeadSeconds"] = Date().timeIntervalSince(preparation)
            var opened = professor; opened.profile = full; opened.state = .ready
            opened.reviewsComplete = true; opened.checkedAt = Date()
            let cache = ReportCache(directory: directory)
            let report = AppModel(summaryProvider: warm, cache: cache, choices: ProfileChoiceStore(directory: directory))
            defer { report.cancel() }
            report.course = course; report.professors = [opened]; report.selectedID = opened.id; report.showingResults = true
            let openedAt = Date()
            report.requestSelectedReport()
            try await waitNative { report.professors[0].summary != nil || report.professors[0].summaryIssue != nil }
            guard let summary = report.professors[0].summary else {
                throw AppError.message(report.professors[0].summaryIssue ?? "No Apple summary")
            }
            results["prewarmedReportOpenSeconds"] = Date().timeIntervalSince(openedAt)
            results["warmMetrics"] = await warm.lastMetrics
            results["analyzedReviews"] = summary.analyzedCount; results["exactCourseReviews"] = summary.exactCourseCount
            results["provider"] = summary.providerIdentity
            results["firstSummary"] = firstSummary.overview; results["warmSummary"] = summary.overview
            let cacheStart = Date()
            let saved = ReportCache(directory: directory).load(name: full.name, course: course,
                subject: professor.subjectCode, summaryProvider: warm.cacheIdentity)
            results["cacheReadSeconds"] = Date().timeIntervalSince(cacheStart)
            results["cacheSurvivedRecreation"] = saved?.summary == summary
            // Open the actual cached report through the app model as well.
            report.professors[0].summary = saved?.summary
            let cachedOpen = Date(); report.requestSelectedReport()
            results["cachedReportOpenSeconds"] = Date().timeIntervalSince(cachedOpen)
            results["cachedOpenDidNotStartGeneration"] = !report.loadingDetails
            results["points"] = (summary.positives + summary.concerns).map { point in
                ["text": point.text, "reviewIDs": point.reviewIDs,
                 "sourceEvidence": (summary.evidence ?? []).filter { point.reviewIDs.contains($0.id) }.map { ["id": $0.id, "course": $0.course, "text": $0.text] }] as [String: Any]
            }
            let evidence = summary.evidence ?? []
            results["wholeReviewEvidence"] = evidence.allSatisfy { full.reviews.contains($0) }
            results["passed"] = saved?.summary == summary && evidence.count == summary.analyzedCount && evidence.allSatisfy { full.reviews.contains($0) }
        } catch { results["passed"] = false; results["error"] = error.localizedDescription }
        results["finishedAt"] = Date().description
        finish(results, output: output)
    }

    private static func appleBenchmarkProfessor() async throws -> Professor {
        let file = URL(fileURLWithPath: "/tmp/bye-apple-benchmark-input.json")
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Professor.self, from: data),
           let profile = saved.profile, let checked = saved.checkedAt,
           (0..<86400).contains(Date().timeIntervalSince(checked)), IdentityMatcher.matches(name: saved.name, profile: profile) {
            return saved
        }
        let pcc = PCCClient(), course = try Course("MATH005A")
        guard let term = try await pcc.terms().first(where: { $0.termCode == "202670" }) else {
            throw AppError.message("Fall 2026 is not published")
        }
        guard var professor = try await pcc.professors(course: course, term: term).first(where: { $0.name == "Anahit Asadyan" }) else {
            throw AppError.message("Live-check instructor not in schedule")
        }
        let reader = RMPAPIReader()
        guard case .verified(let preview) = try await reader.lookupOutcome(professor) else {
            throw AppError.message("Live profile needs explicit selection or is unavailable")
        }
        professor.profile = try await reader.expand(professor, profile: preview, onProfile: { _ in })
        professor.state = .ready; professor.reviewsComplete = true; professor.checkedAt = Date()
        try JSONEncoder().encode(professor).write(to: file, options: .atomic)
        return professor
    }

    static func runAppleQuality(output: String) async {
        var results: [String: Any] = ["startedAt": Date().description, "fictional": true, "usesOllama": false]
        do {
            let course = try Course("MATH005A")
            let cases = [
                ("shared-positive", ["The explanations were clear and helpful.", "Clear explanations helped me understand the material."]),
                ("shared-concern", ["Exams counted for most of the final grade.", "The exams had a very heavy weight in my grade."]),
                ("negation", ["Clear explanations. The homework was not excessive.", "Very clear explanations and never too much homework."]),
                ("disagreement", ["The explanations were clear.", "The explanations were confusing and unclear."]),
                ("different-concerns", ["The homework was excessive.", "The exams were very difficult."])
            ]
            var reports: [[String: Any]] = []
            for (label, texts) in cases {
                let reviews = texts.enumerated().map { Review(id: "fictional-\($0.offset)", course: "MATH005A", text: $0.element,
                    date: "2026-01-01", rating: nil, difficulty: nil, online: nil) }
                let provider = AppleSummaries.make(), start = Date()
                let summary = try await provider.summarize(reviews: reviews, course: course)
                reports.append(["case": label, "sourceTexts": texts, "seconds": Date().timeIntervalSince(start),
                    "overview": summary.overview,
                    "positives": summary.positives.map { ["text": $0.text, "reviewIDs": $0.reviewIDs] },
                    "concerns": summary.concerns.map { ["text": $0.text, "reviewIDs": $0.reviewIDs] }])
            }
            results["cases"] = reports; results["completed"] = true
            results["note"] = "Semantic accuracy requires human review; completion is not an automatic quality verdict."
        } catch { results["completed"] = false; results["error"] = error.localizedDescription }
        results["finishedAt"] = Date().description; finish(results, output: output)
    }

    /// Runs the real first pass without reusing cached ratings, then checks that
    /// extra reviews were requested only for the opened report.
    static func runSpeed(output: String) async {
        let start = Date()
        var results: [String: Any] = ["startedAt": start.description, "course": "MATH 005A", "semester": "Fall 2026"]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BYE-Speed-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory))
        results["retrieval"] = "URLSession API"; results["storage"] = "Temporary cache/preferences, removed afterward"
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
            let reader = RMPAPIReader()
            guard case .verified(let preview) = try await reader.lookupOutcome(professor) else { throw AppError.message("Live profile needs explicit selection or is unavailable.") }
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
            let reader = RMPAPIReader()
            guard case .verified(let profile) = try await reader.lookupOutcome(professor) else { throw AppError.message("Live profile needs explicit selection or is unavailable.") }
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
    /// Uses the native API directly. No model client or persistent user preferences are involved.
    static func runMatching(output: String) async {
        var result: [String: Any] = ["startedAt": Date().description, "requestedSemester": "Winter 2027", "usesOllama": false, "retrieval": "URLSession API"]
        do {
            let pcc = PCCClient()
            guard let term = try await pcc.terms().first(where: { $0.termName == "Winter 2027" }) else {
                throw AppError.message("Winter 2027 is not currently published.")
            }
            let rows = try await pcc.schedule(term: term)
            let names = ["Daniel Hamman", "Jose Lopez"]
            var observations: [[String: Any]] = []
            for name in names {
                let started = Date()
                let official = rows.filter { $0["pfaName"].trimmingCharacters(in: .whitespacesAndNewlines) == name }
                let courses = Set(official.compactMap { try? Course($0["subjCode"] + $0["courseNumbDisplay"]) }).sorted { $0.key < $1.key }
                guard let course = courses.first,
                      let professor = ScheduleParser.professors(rows: rows, course: course).first(where: { $0.name == name }) else {
                    observations.append(["name": name, "limitation": "Instructor not found in published Winter 2027 sections."])
                    continue
                }
                let reader = RMPAPIReader()
                var observation: [String: Any] = ["name": name, "course": course.display,
                    "subject": professor.subjectCode, "subjectDescription": professor.subjectDescription]
                switch try await reader.lookupOutcome(professor) {
                case .verified(let profile):
                    observation["outcome"] = "verified"; observation["profileID"] = profile.id
                    observation["previewReviews"] = profile.reviews.count
                case .selectionRequired(let options, _):
                    observation["outcome"] = "selectionRequired"
                    observation["candidates"] = options.map { ["id": $0.id, "name": $0.name, "department": $0.department, "school": $0.school] }
                    var verified: [String] = []
                    for candidate in options {
                        if let profile = try? await reader.preview(professor, profileID: candidate.id), profile.reviews.count <= 3 {
                            verified.append(profile.id)
                        }
                    }
                    observation["individuallyVerifiedIDs"] = verified
                    observation["selectionRecovery"] = try await verifyNativeSelection(professor, course: course, options: options)
                case .unavailable(let message): observation["outcome"] = "unavailable"; observation["limitation"] = message
                }
                observation["totalSeconds"] = Date().timeIntervalSince(started)
                reader.stop(); observations.append(observation)
            }
            result["observations"] = observations
            result["passed"] = observations.first(where: { $0["name"] as? String == "Daniel Hamman" }).map {
                ["verified", "selectionRequired"].contains($0["outcome"] as? String ?? "") &&
                (($0["selectionRecovery"] as? [String: Any])?["passed"] as? Bool ?? true)
            } ?? false
            if observations.contains(where: { (($0["selectionRecovery"] as? [String: Any])?["passed"] as? Bool) == false }) {
                result["passed"] = false
            }
        } catch { result["passed"] = false; result["limitation"] = error.localizedDescription }
        result["finishedAt"] = Date().description
        finish(result, output: output)
    }
    /// Isolated live acceptance: UI-facing model actions with real API responses,
    /// temporary preferences/cache, and no selected report (therefore no AI job).
    private static func verifyNativeSelection(_ professor: Professor, course: Course, options: [RMPProfile]) async throws -> [String: Any] {
        guard options.count >= 2 else { return ["limitation": "Two eligible live profiles are required."] }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BYE-Live-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ReportCache(directory: directory), store = ProfileChoiceStore(directory: directory)
        let model = AppModel(cache: cache, choices: store)
        defer { model.cancel() }
        model.course = course; model.showingResults = true; model.professors = [professor]
        model.retryProfessor(id: professor.id)
        try await waitNative { !model.busy }
        let ambiguous = model.professors[0].state == .selectionRequired
        model.openChooser(id: professor.id); model.chooserID = nil
        let dismissed = model.professors[0].state == .selectionRequired && model.professors[0].profile == nil
        model.chooseProfile(id: professor.id, profileID: options[0].id)
        try await waitNative { !model.busy }
        guard let first = model.professors[0].profile else { throw AppError.message("Live choice failed verification.") }
        let saved = ProfileChoiceStore(directory: directory).choice(name: professor.name, subject: professor.subjectCode) == first.id
        let restart = AppModel(cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory))
        defer { restart.cancel() }
        restart.course = course; restart.professors = [professor]; restart.showingResults = true
        restart.retryProfessor(id: professor.id)
        try await waitNative { !restart.busy }
        let reverified = restart.professors[0].profile?.id == first.id
        // Deliberately seed a test-only wrong identity from the other live
        // instructor. Fresh API verification must invalidate it and recover to
        // explicit selection; production never saves an unverified choice.
        let wrongIdentity = professor.name == "Daniel Hamman" ? "958265" : "1913925"
        store.save(profileID: wrongIdentity, name: professor.name, subject: professor.subjectCode)
        restart.retryProfessor(id: professor.id)
        try await waitNative { !restart.busy }
        let mismatchRecovered = restart.professors[0].state == .selectionRequired && store.choice(name: professor.name, subject: professor.subjectCode) == nil
        model.openChooser(id: professor.id)
        let openingPreservesData = model.professors[0].profile?.id == first.id
        try await waitNative { !model.busy }
        model.chooseProfile(id: professor.id, profileID: options[1].id)
        let clearsImmediately = model.professors[0].profile == nil && model.professors[0].sections == professor.sections
        try await waitNative { !model.busy }
        let replacement = model.professors[0].profile?.id == options[1].id
        let reader = RMPAPIReader()
        let start = Date()
        let preview = try await reader.preview(professor, profileID: first.id)
        let previewSeconds = Date().timeIntervalSince(start)
        let all = try await reader.expand(professor, profile: preview) { _ in }
        let expansionSeconds = Date().timeIntervalSince(start) - previewSeconds
        var filtered = all
        if let label = all.courseCounts?.first?.label {
            filtered = try await reader.expand(professor, profile: all, courseFilter: label) { _ in }
        }
        cache.save(CachedReport(profile: filtered, summary: nil, checkedAt: Date(), reviewsComplete: true), name: professor.name, course: course, subject: professor.subjectCode)
        let warmStart = Date()
        let otherCourse = try Course(course.subject + "999")
        let reused = ReportCache(directory: directory).load(name: professor.name, course: otherCourse, subject: professor.subjectCode, preferredProfileID: first.id)
        let warmSeconds = Date().timeIntervalSince(warmStart)
        let cacheReused = reused?.profile.id == first.id && reused?.profile.reviews == filtered.reviews
        // Exercise an actually unavailable local summary endpoint without stopping
        // the owner's running Ollama service or changing their settings.
        let report = AppModel(ollama: OllamaClient(endpoint: URL(string: "http://127.0.0.1:1/api/chat")!), cache: cache, choices: store)
        defer { report.cancel() }
        var opened = professor; opened.profile = filtered; opened.state = .ready
        opened.reviewsComplete = true; opened.checkedAt = Date()
        report.course = course; report.professors = [opened]; report.showingResults = true; report.selectedID = professor.id
        report.requestSelectedReport()
        try await waitNative { report.professors[0].summaryIssue != nil || report.professors[0].summary != nil }
        let summaryUnavailable = report.professors[0].summaryIssue != nil && report.professors[0].profile == filtered
        let passed = ambiguous && dismissed && saved && reverified && mismatchRecovered && openingPreservesData && clearsImmediately && replacement && cacheReused && summaryUnavailable && preview.reviews.count <= 3 && (all.reviewCoverage?["all"]?.reviewIDs.count ?? 51) <= 50
        return ["passed": passed, "ambiguous": ambiguous, "dismissalUnresolved": dismissed,
                "preferencePersisted": saved, "freshVerificationAfterStoreRecreation": reverified,
                "liveIdentityMismatchRecoveredToSelection": mismatchRecovered,
                "changeProfilePreservesUntilConfirmed": openingPreservesData, "confirmationClearsImmediately": clearsImmediately,
                "replacementVerified": replacement, "crossCourseCacheReused": cacheReused,
                "unavailableSummaryPreservesAPIData": summaryUnavailable,
                "summaryFailureMethod": "Unavailable loopback port 1; owner's Ollama service untouched",
                "previewSeconds": previewSeconds, "allReviewExpansionSeconds": expansionSeconds,
                "warmCacheSeconds": warmSeconds, "previewReviews": preview.reviews.count,
                "allReviews": all.reviewCoverage?["all"]?.reviewIDs.count ?? 0,
                "filterCoverage": (filtered.reviewCoverage ?? [:]).mapValues { $0.reviewIDs.count },
                "usesOllama": false, "storage": "Temporary test directory, removed afterward",
                "scope": "Real API and model actions; window dismissal/relaunch visual checks are separate."]
    }
    private static func waitNative(_ condition: () -> Bool) async throws {
        let end = Date().addingTimeInterval(100)
        while !condition() {
            guard Date() < end else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    private static func finish(_ results: [String: Any], output: String) {
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) {
            try? data.write(to: URL(fileURLWithPath: output), options: .atomic)
            print(String(data: data, encoding: .utf8)!)
        }
        // Let each caller unwind its temporary-storage defers before exiting.
        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }
}
#endif
