import SwiftUI
import ClasswiseCore

@MainActor
final class AppModel: ObservableObject {
    @Published var input = ""
    @Published var terms: [Term] = []
    @Published var termID = ""
    @Published var loadingTerms = false
    @Published var error: String?
    @Published var course: Course?
    @Published var searchedTerm: Term?
    @Published var professors: [Professor] = []
    @Published var showingResults = false
    /// Busy describes the ratings pass, not optional report work.
    @Published var busy = false
    @Published var progress = ""
    @Published var selectedID: String?
    @Published var sort: ProfessorSort = .rating
    @Published var onlineOnly = false
    @Published var showAll = false
    @Published var retryingIDs: Set<String> = []
    @Published var loadingDetailsID: String?
    @Published var summaryLoadingID: String?
    @Published var detailProgress: String?
    @Published var detailCancelled = false
    @Published var courseReviewIssues: [String: String] = [:]
    @Published var suggestionLoading = false
    @Published private var suggestionCatalog: [CourseSuggestion] = []
    private let pcc: PCCClient
    private let ollama: OllamaClient
    @Published var chooserID: String?
    @Published var chooserIssue: String?
    private let choices: ProfileChoiceStore
    private let makeReader: @MainActor () -> any ProfileReader
    private enum PreviewAction { case lookup, discover, select(String) }
    private struct PreviewJob {
        let id: String
        let generation: UUID
        let action: PreviewAction
        let token = UUID()
    }
    private var pendingPreviews: [PreviewJob] = []
    private var activePreviews: [String: PreviewJob] = [:]
    private var previewTasks: [String: Task<Void, Never>] = [:]
    private var previewReaders: [String: any ProfileReader] = [:]
    private var idlePreviewReaders: [any ProfileReader] = []
    private let cache: ReportCache
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var suggestionTermID = ""
    private var detailReader: (any ProfileReader)?
    private var pendingDetailID: String?
    private var pendingDetailFilter: String?
    private var pendingSummaryID: String?
    private var attemptedSummaries: Set<String> = []
    private var attemptedDetails: Set<String> = []
    private var checkedCount = 0
    private var runID = UUID()
    private var detailRunID = UUID()
    #if DEBUG
    private(set) var quickPassSnapshot: [Professor] = []
    #endif

    init(pcc: PCCClient = PCCClient(), ollama: OllamaClient = OllamaClient(), cache: ReportCache = ReportCache(),
         choices: ProfileChoiceStore = ProfileChoiceStore(),
         makeReader: @escaping @MainActor () -> any ProfileReader = { RMPAPIReader() }) {
        self.pcc = pcc; self.ollama = ollama; self.cache = cache
        self.choices = choices; self.makeReader = makeReader
    }
    var chooserProfessor: Professor? { professors.first { $0.id == chooserID } }
    func isPreviewing(_ id: String) -> Bool {
        activePreviews[id] != nil || pendingPreviews.contains { $0.id == id }
    }
    func openChooser(id: String) {
        guard let professor = professors.first(where: { $0.id == id }) else { return }
        chooserID = id; chooserIssue = nil
        if let current = professor.profile, let index = professors.firstIndex(where: { $0.id == id }) {
            professors[index].candidates = IdentityMatcher.eligible(name: professor.name, candidates: professors[index].candidates + [current])
        }
        if professor.profile != nil { enqueuePreview(id: id, action: .discover) }
    }
    func retryProfessor(id: String) { enqueuePreview(id: id, action: .lookup) }
    func chooseProfile(id: String, profileID: String) {
        guard !isPreviewing(id), let index = professors.firstIndex(where: { $0.id == id }),
              professors[index].candidates.contains(where: { $0.id == profileID }) else { return }
        if let old = professors[index].profile, let course {
            cache.invalidate(name: professors[index].name, course: course, subject: professors[index].subjectCode, profileID: old.id)
        }
        courseReviewIssues = courseReviewIssues.filter { !$0.key.hasPrefix(id + "|") }
        professors[index].generation = UUID()
        professors[index].pendingProfileID = profileID
        professors[index].profile = nil; professors[index].summary = nil
        professors[index].checkedAt = nil; professors[index].reviewsComplete = false
        professors[index].issue = nil; professors[index].reviewIssue = nil; professors[index].summaryIssue = nil
        attemptedDetails.remove(id); attemptedSummaries.remove(id); retryingIDs.remove(id)
        if pendingDetailID == id { pendingDetailID = nil }
        if pendingSummaryID == id { pendingSummaryID = nil }
        if loadingDetailsID == id { detailTask?.cancel(); detailReader?.stop() }
        if summaryLoadingID == id { summaryTask?.cancel() }
        chooserID = nil
        enqueuePreview(id: id, action: .select(profileID))
    }
    private func enqueuePreview(id: String, action: PreviewAction) {
        guard !isPreviewing(id), let professor = professors.first(where: { $0.id == id }) else { return }
        pendingPreviews.append(PreviewJob(id: id, generation: professor.generation, action: action))
        busy = true; pumpPreviews()
    }
    private func pumpPreviews() {
        while activePreviews.count < 2, !pendingPreviews.isEmpty {
            let job = pendingPreviews.removeFirst()
            guard let index = professors.firstIndex(where: { $0.id == job.id }), professors[index].generation == job.generation else { continue }
            let professor = professors[index], reader = idlePreviewReaders.popLast() ?? makeReader(), run = runID
            activePreviews[job.id] = job; previewReaders[job.id] = reader
            if case .discover = job.action { } else { professors[index].state = .searching; professors[index].issue = nil }
            previewTasks[job.id] = Task { [weak self] in
                guard let self else { return }
                defer {
                    reader.stop()
                    if self.runID == run, self.activePreviews[job.id]?.token == job.token {
                        self.activePreviews[job.id] = nil; self.previewReaders[job.id] = nil; self.previewTasks[job.id] = nil
                        self.idlePreviewReaders.append(reader)
                        self.checkedCount += 1; self.pumpPreviews()
                    }
                }
                do {
                    let outcome: ProfileLookupOutcome
                    switch job.action {
                    case .lookup:
                        if let course { cache.invalidate(name: professor.name, course: course, subject: professor.subjectCode) }
                        let preference = professor.pendingProfileID ?? choices.choice(name: professor.name, subject: professor.subjectCode)
                        outcome = try await reader.lookupOutcome(professor, preferredProfileID: preference)
                    case .discover:
                        let found = try await reader.candidates(professor, discoverAll: true)
                        let combined = found + (professor.profile.map { [$0] } ?? [])
                        outcome = .selectionRequired(IdentityMatcher.eligible(name: professor.name, candidates: combined))
                    case .select(let id):
                        do { outcome = .verified(try await reader.preview(professor, profileID: id)) }
                        catch is ProfileIdentityMismatch {
                            outcome = .selectionRequired(professor.candidates.filter { $0.id != id }, invalidatedProfileID: id)
                        }
                    }
                    guard !Task.isCancelled, runID == run, professors[index].generation == job.generation else { return }
                    if case .discover = job.action {
                        if case .selectionRequired(let candidates, _) = outcome { professors[index].candidates = candidates }
                        return
                    }
                    switch outcome {
                    case .verified(let profile):
                        if professors[index].profile?.id != profile.id || professors[index].profile?.reviews != profile.reviews {
                            professors[index].summary = nil; professors[index].summaryIssue = nil
                            attemptedSummaries.remove(job.id); attemptedDetails.remove(job.id)
                        }
                        professors[index].profile = profile; professors[index].state = .ready
                        professors[index].checkedAt = Date(); professors[index].reviewsComplete = false
                        if professor.pendingProfileID == profile.id {
                            professors[index].pendingProfileID = nil
                            if !choices.save(profileID: profile.id, name: professor.name, subject: professor.subjectCode) {
                                professors[index].issue = "This profile is verified, but your choice could not be saved on this Mac."
                            }
                        }
                        if let course { saveReport(index: index, course: course) }
                    case .selectionRequired(let candidates, let invalidated):
                        // A fresh lookup that becomes ambiguous is unresolved,
                        // even when an earlier report was already visible.
                        professors[index].profile = nil; professors[index].summary = nil
                        professors[index].checkedAt = nil; professors[index].reviewsComplete = false
                        professors[index].reviewIssue = nil; professors[index].summaryIssue = nil
                        attemptedDetails.remove(job.id); attemptedSummaries.remove(job.id); retryingIDs.remove(job.id)
                        if loadingDetailsID == job.id { detailTask?.cancel(); detailReader?.stop() }
                        if summaryLoadingID == job.id { summaryTask?.cancel() }
                        professors[index].pendingProfileID = nil
                        professors[index].candidates = candidates; professors[index].state = .selectionRequired
                        professors[index].issue = candidates.isEmpty ? "No eligible profile is available yet. Try again or check RMP." : (candidates.count > 1 ? "Several PCC profiles share this name. Choose which profile to use." : "Choose a PCC profile to verify before using its information.")
                        if let invalidated, let course {
                            cache.invalidate(name: professor.name, course: course, subject: professor.subjectCode, profileID: invalidated)
                        }
                        if let invalidated, choices.choice(name: professor.name, subject: professor.subjectCode) == invalidated {
                            choices.save(profileID: nil, name: professor.name, subject: professor.subjectCode)
                        }
                    case .unavailable(let message):
                        professors[index].state = .unavailable; professors[index].issue = message
                    }
                } catch {
                    guard !Task.isCancelled, runID == run, professors[index].generation == job.generation else { return }
                    if case .discover = job.action { chooserIssue = error.localizedDescription }
                    else { professors[index].state = .unavailable; professors[index].issue = error.localizedDescription }
                }
            }
        }
        busy = searchTask != nil || !pendingPreviews.isEmpty || !activePreviews.isEmpty
        updateProgress()
        if !busy {
            progress = ""
            #if DEBUG
            quickPassSnapshot = professors
            #endif
            requestSelectedReport()
        }
    }
    private func currentProfile(index: Int, generation: UUID, profileID: String) -> Bool {
        professors.indices.contains(index) && professors[index].generation == generation && professors[index].profile?.id == profileID
    }

    var loadingDetails: Bool { loadingDetailsID != nil || summaryLoadingID != nil }
    var suggestions: [CourseSuggestion] {
        guard !showingResults, !busy, input.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        return CourseSuggestions.match(courses: suggestionCatalog, query: input)
    }
    var selectedTerm: Term? { terms.first { $0.id == termID } }
    var filtered: [Professor] {
        guard let course else { return [] }
        let list = professors.compactMap { professor -> Professor? in
            var result = professor
            if onlineOnly { result.sections = professor.sections.filter(\.fullyOnline) }
            return result.sections.isEmpty ? nil : result
        }
        return Ordering.professors(list, by: sort, course: course)
    }
    var displayed: [Professor] { showAll ? filtered : Array(filtered.prefix(5)) }
    var sectionCount: Int { Set(filtered.flatMap { $0.sections.map(\.crn) }).count }
    var selected: Professor? { filtered.first { $0.id == selectedID } }
    var scheduleURL: URL? {
        guard let course, let searchedTerm else { return nil }
        return PCCClient.scheduleURL(term: searchedTerm, course: course)
    }
    func reconcileSelection() {
        // Incoming ratings may reorder the top five. Keep the report the student opened.
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = displayed.first?.id }
    }
    func loadTerms() async {
        guard terms.isEmpty, !loadingTerms else { return }
        loadingTerms = true; error = nil
        defer { loadingTerms = false }
        do { terms = try await pcc.terms(); termID = terms.first?.id ?? "" }
        catch { self.error = "Couldn’t load PCC semesters. Check your connection and try again." }
    }
    func updateCourseSuggestions() {
        guard !showingResults, let term = selectedTerm else { return }
        if suggestionTermID == term.id { return }
        suggestionTask?.cancel()
        suggestionCatalog = []; suggestionTermID = ""; suggestionLoading = true
        suggestionTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let rows = try await pcc.schedule(term: term)
                guard !Task.isCancelled, termID == term.id else { return }
                suggestionCatalog = CourseSuggestions.catalog(rows: rows); suggestionTermID = term.id
            } catch { /* Suggestions are optional; the normal search remains available. */ }
            if !Task.isCancelled, termID == term.id { suggestionLoading = false; suggestionTask = nil }
        }
    }
    func chooseSuggestion(_ suggestion: CourseSuggestion) { input = suggestion.course.display }

    func start(force: Bool = false) {
        guard let term = selectedTerm else { error = "Choose a PCC semester first."; return }
        let parsed: Course
        do { parsed = try Course(input) } catch { self.error = error.localizedDescription; return }
        cancel()
        runID = UUID(); let run = runID
        course = parsed; searchedTerm = term; error = nil; busy = true; progress = "Finding classes at PCC…"
        professors = []; selectedID = nil; showAll = false; showingResults = false; attemptedDetails = []; attemptedSummaries = []; courseReviewIssues = [:]
        searchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if runID == run {
                    searchTask = nil
                    if !Task.isCancelled { pumpPreviews() } else { busy = false; progress = "" }
                }
            }
            do {
                let rows = try await pcc.schedule(term: term, force: force)
                try Task.checkCancellation(); guard runID == run else { return }
                let found = ScheduleParser.professors(rows: rows, course: parsed)
                professors = found; showingResults = true; selectedID = found.first?.id
                checkedCount = 0
                var missing: [Int] = []
                // All cached scores appear before any website or local-model work.
                for index in professors.indices {
                    if !force, let cached = cache.load(name: professors[index].name, course: parsed, subject: professors[index].subjectCode, preferredProfileID: choices.choice(name: professors[index].name, subject: professors[index].subjectCode)) {
                        professors[index].profile = cached.profile; professors[index].summary = cached.summary
                        professors[index].checkedAt = cached.checkedAt; professors[index].state = .ready
                        professors[index].reviewsComplete = cached.reviewsComplete ?? true
                        checkedCount += 1
                    } else { missing.append(index) }
                }
                // Queue all jobs before dispatch, so optional detail work stays gated.
                pendingPreviews = missing.map { PreviewJob(id: self.professors[$0].id, generation: self.professors[$0].generation, action: .lookup) }
                pumpPreviews()
            } catch is CancellationError { }
            catch { if runID == run { self.error = error.localizedDescription } }
        }
    }
    private func updateProgress() {
        let checked = professors.filter { [.ready, .unavailable, .selectionRequired].contains($0.state) }.count
        progress = "Checking ratings · \(checked) of \(professors.count)"
    }
    private func saveReport(index: Int, course: Course) {
        guard let profile = professors[index].profile else { return }
        cache.save(CachedReport(profile: profile, summary: professors[index].summary,
                                checkedAt: professors[index].checkedAt ?? Date(),
                                reviewsComplete: professors[index].reviewsComplete),
                   name: professors[index].name, course: course, subject: professors[index].subjectCode)
    }
    /// Website and model work have separate single-worker queues. Only opened
    /// reports are requested; the latest selection replaces pending work.
    func requestSelectedReport() {
        pendingDetailID = nil
        pendingDetailFilter = nil
        if let pending = pendingSummaryID, pending != summaryLoadingID { retryingIDs.remove(pending) }
        pendingSummaryID = nil
        guard !busy, showingResults, let selected, selected.profile != nil else { return }
        detailCancelled = false
        if selected.reviewsComplete {
            if selected.summary == nil { queueSummary(id: selected.id) }
            return
        }
        guard !attemptedDetails.contains(selected.id), loadingDetailsID != selected.id else { return }
        pendingDetailID = selected.id
        startDetailQueue()
    }
    /// This is the only UI action that supplies a class to RMP. Picker changes are local.
    func findMoreReviews(id: String, filter: ReviewFilter) {
        guard !busy, loadingDetailsID == nil, let course,
              let professor = professors.first(where: { $0.id == id }), let profile = professor.profile,
              let label = filter.requestLabel(course: course), !label.isEmpty,
              profile.reviewCoverage?[ReviewFilter.coverageKey(label)]?.finished != true else { return }
        if case .source(let source) = filter {
            guard profile.courseCounts?.contains(where: { $0.label == source }) == true || profile.reviews.contains(where: { $0.course == source }) else { return }
        }
        selectedID = id; pendingDetailID = id; pendingDetailFilter = label; detailCancelled = false
        courseReviewIssues[id + "|" + label] = nil
        startDetailQueue()
    }
    private func startDetailQueue() {
        guard detailTask == nil else { return }
        let run = runID, detailRun = detailRunID
        detailTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if runID == run, detailRunID == detailRun {
                    loadingDetailsID = nil; detailReader = nil; detailTask = nil; updateDetailProgress()
                    if !busy { requestSelectedReport() }
                }
            }
            while !Task.isCancelled, !busy, runID == run, detailRunID == detailRun, let id = pendingDetailID {
                let filter = pendingDetailFilter
                pendingDetailID = nil; pendingDetailFilter = nil
                if filter == nil { attemptedDetails.insert(id) }
                guard let index = professors.firstIndex(where: { $0.id == id }), let course else { continue }
                loadingDetailsID = id; updateDetailProgress()
                await loadDetails(index: index, course: course, run: run, detailRun: detailRun, filter: filter)
            }
        }
    }
    private func updateDetailProgress() {
        if let id = loadingDetailsID, let professor = professors.first(where: { $0.id == id }) {
            detailProgress = "Loading more reviews · \(professor.name)"
        } else if let id = summaryLoadingID, let professor = professors.first(where: { $0.id == id }) {
            detailProgress = "Preparing summary · \(professor.name)"
        } else { detailProgress = nil }
    }
    private func loadDetails(index: Int, course: Course, run: UUID, detailRun: UUID, filter: String? = nil) async {
        guard let profile = professors[index].profile else { return }
        let id = professors[index].id, generation = professors[index].generation
        let profileID = profile.id
        if filter != nil || !professors[index].reviewsComplete {
            let reader = makeReader(); detailReader = reader
            do {
                let publish: @MainActor (RMPProfile) -> Void = { [weak self] partial in
                    guard let self, !Task.isCancelled, self.runID == run, self.detailRunID == detailRun, self.currentProfile(index: index, generation: generation, profileID: profileID), partial.id == profileID else { return }
                    if self.professors[index].profile?.reviews != partial.reviews {
                        self.professors[index].summary = nil
                        self.attemptedSummaries.remove(id)
                    }
                    self.professors[index].profile = partial
                    self.saveReport(index: index, course: course)
                }
                let full: RMPProfile
                if let filter {
                    guard let courseReader = reader as? any CourseProfileReader else { throw AppError.message("Class-specific retrieval is unavailable.") }
                    full = try await courseReader.expand(professors[index], profile: profile, courseFilter: filter, onProfile: publish)
                } else { full = try await reader.expand(professors[index], profile: profile, onProfile: publish) }
                guard !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: profileID) else { return }
                if profile.reviews != full.reviews {
                    professors[index].summary = nil
                    attemptedSummaries.remove(id)
                }
                professors[index].profile = full
                if filter == nil { professors[index].reviewsComplete = true; professors[index].reviewIssue = nil }
                else { courseReviewIssues[id + "|" + filter!] = nil }
                saveReport(index: index, course: course)
            } catch {
                guard !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: profileID) else { return }
                if let filter { courseReviewIssues[id + "|" + filter] = "More reviews for this class couldn’t be loaded. Saved reviews remain available; try again." }
                else { professors[index].reviewIssue = "More reviews couldn’t be loaded. The verified scores and retrieved reviews are still available." }
            }
            detailReader = nil
        }
        guard !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: profileID) else { return }
        // A page already in flight can finish and be cached, while the latest
        // selected report gets the next website job and local-summary slot.
        if selectedID == id { queueSummary(id: id) }
    }
    private func queueSummary(id: String) {
        guard !busy, !attemptedSummaries.contains(id), summaryLoadingID != id,
              let professor = professors.first(where: { $0.id == id }),
              professor.profile != nil, professor.summary == nil else { return }
        if let pending = pendingSummaryID, pending != summaryLoadingID { retryingIDs.remove(pending) }
        pendingSummaryID = id; retryingIDs.insert(id)
        guard summaryTask == nil else { return }
        let run = runID, detailRun = detailRunID
        summaryTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if runID == run, detailRunID == detailRun {
                    summaryLoadingID = nil; summaryTask = nil; updateDetailProgress()
                    if !busy { requestSelectedReport() }
                }
            }
            while !Task.isCancelled, !busy, runID == run, detailRunID == detailRun, let id = pendingSummaryID {
                pendingSummaryID = nil; attemptedSummaries.insert(id); summaryLoadingID = id; updateDetailProgress()
                guard let index = professors.firstIndex(where: { $0.id == id }), let course,
                      let evidence = professors[index].profile else { retryingIDs.remove(id); continue }
                let generation = professors[index].generation
                do {
                    let summary = try await ollama.summarize(reviews: evidence.reviews, course: course)
                    guard !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: evidence.id) else { return }
                    guard professors[index].profile?.reviews == evidence.reviews else {
                        attemptedSummaries.remove(id); retryingIDs.remove(id); continue
                    }
                    professors[index].summary = summary; professors[index].summaryIssue = nil
                } catch {
                    guard !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: evidence.id) else { return }
                    guard professors[index].profile?.reviews == evidence.reviews else {
                        attemptedSummaries.remove(id); retryingIDs.remove(id); continue
                    }
                    professors[index].summaryIssue = error.localizedDescription
                }
                retryingIDs.remove(id)
                if !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: evidence.id) { saveReport(index: index, course: course) }
            }
        }
    }
    func retrySummary(id: String) {
        guard !busy, !loadingDetails, let index = professors.firstIndex(where: { $0.id == id }) else { return }
        professors[index].summaryIssue = nil; professors[index].reviewIssue = nil
        attemptedDetails.remove(id); attemptedSummaries.remove(id); selectedID = id; requestSelectedReport()
    }
    func cancelDetails() {
        if let id = loadingDetailsID { attemptedDetails.remove(id) }
        if let id = pendingDetailID { attemptedDetails.remove(id) }
        if let id = summaryLoadingID { attemptedSummaries.remove(id) }
        detailRunID = UUID(); detailTask?.cancel(); detailTask = nil
        summaryTask?.cancel(); summaryTask = nil; summaryLoadingID = nil; pendingSummaryID = nil
        detailReader?.stop(); detailReader = nil; pendingDetailID = nil; pendingDetailFilter = nil
        retryingIDs = []; loadingDetailsID = nil; detailProgress = nil; detailCancelled = true
    }
    func cancel() {
        runID = UUID(); searchTask?.cancel(); searchTask = nil
        previewTasks.values.forEach { $0.cancel() }; previewReaders.values.forEach { $0.stop() }
        idlePreviewReaders.forEach { $0.stop() }; idlePreviewReaders = []
        pendingPreviews = []; activePreviews = [:]; previewTasks = [:]; previewReaders = [:]
        chooserID = nil; chooserIssue = nil
        cancelDetails()
        for index in professors.indices {
            if professors[index].state == .searching { professors[index].state = .pending }
        }
        busy = false; progress = ""
    }
    func changeSearch() { cancel(); showingResults = false; error = nil }
    func refresh() {
        guard let course, let searchedTerm else { return }
        input = course.display; termID = searchedTerm.id; start(force: true)
    }
}
