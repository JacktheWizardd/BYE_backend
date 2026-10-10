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
    @Published var suggestionLoading = false
    @Published private var suggestionCatalog: [CourseSuggestion] = []
    private let pcc: PCCClient
    private let ollama: OllamaClient
    private let cache: ReportCache
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var summaryTask: Task<Void, Never>?
    private var suggestionTask: Task<Void, Never>?
    private var suggestionTermID = ""
    private var browsers: [RMPBrowser] = []
    private var detailReader: RMPBrowser?
    private var pendingDetailID: String?
    private var pendingSummaryID: String?
    private var attemptedSummaries: Set<String> = []
    private var attemptedDetails: Set<String> = []
    private var checkedCount = 0
    private var runID = UUID()
    private var detailRunID = UUID()
    #if DEBUG
    private(set) var quickPassSnapshot: [Professor] = []
    #endif

    init(pcc: PCCClient = PCCClient(), ollama: OllamaClient = OllamaClient(), cache: ReportCache = ReportCache()) {
        self.pcc = pcc; self.ollama = ollama; self.cache = cache
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
        professors = []; selectedID = nil; showAll = false; showingResults = false; attemptedDetails = []; attemptedSummaries = []
        searchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if runID == run {
                    busy = false; progress = ""; browsers = []; searchTask = nil
                    if !Task.isCancelled { requestSelectedReport() }
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
                    if !force, let cached = cache.load(name: professors[index].name, course: parsed) {
                        professors[index].profile = cached.profile; professors[index].summary = cached.summary
                        professors[index].checkedAt = cached.checkedAt; professors[index].state = .ready
                        professors[index].reviewsComplete = cached.reviewsComplete ?? true
                        checkedCount += 1
                    } else { missing.append(index) }
                }
                let readers = [RMPBrowser(), RMPBrowser()]
                browsers = readers
                var availableReaders = readers
                updateProgress()
                await SearchPipeline.run(indices: missing, lookup: { [self] index in
                    guard !Task.isCancelled, self.runID == run else { return }
                    let reader = availableReaders.removeFirst()
                    defer { availableReaders.append(reader) }
                    self.professors[index].state = .searching
                    do {
                        let profile = try await reader.lookup(self.professors[index], initialReviewsOnly: true)
                        try Task.checkCancellation(); guard self.runID == run else { return }
                        self.professors[index].profile = profile; self.professors[index].state = .ready
                        self.professors[index].checkedAt = Date(); self.professors[index].reviewsComplete = false
                        self.saveReport(index: index, course: parsed)
                    } catch {
                        guard !Task.isCancelled, self.runID == run else { return }
                        self.professors[index].state = .unavailable
                        self.professors[index].issue = error.localizedDescription; self.professors[index].checkedAt = Date()
                    }
                    self.checkedCount += 1; self.updateProgress()
                })
                #if DEBUG
                if !Task.isCancelled, runID == run { quickPassSnapshot = professors }
                #endif
            } catch is CancellationError { }
            catch { if runID == run { self.error = error.localizedDescription } }
        }
    }
    private func updateProgress() { progress = "Checking ratings · \(checkedCount) of \(professors.count)" }
    private func saveReport(index: Int, course: Course) {
        guard let profile = professors[index].profile else { return }
        cache.save(CachedReport(profile: profile, summary: professors[index].summary,
                                checkedAt: professors[index].checkedAt ?? Date(),
                                reviewsComplete: professors[index].reviewsComplete),
                   name: professors[index].name, course: course)
    }
    /// Website and model work have separate single-worker queues. Only opened
    /// reports are requested; the latest selection replaces pending work.
    func requestSelectedReport() {
        pendingDetailID = nil
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
        guard detailTask == nil else { return }
        let run = runID, detailRun = detailRunID
        detailTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if runID == run, detailRunID == detailRun {
                    loadingDetailsID = nil; detailReader = nil; detailTask = nil; updateDetailProgress()
                }
            }
            while !Task.isCancelled, runID == run, detailRunID == detailRun, let id = pendingDetailID {
                pendingDetailID = nil; attemptedDetails.insert(id)
                guard let index = professors.firstIndex(where: { $0.id == id }), let course else { continue }
                loadingDetailsID = id; updateDetailProgress()
                await loadDetails(index: index, course: course, run: run, detailRun: detailRun)
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
    private func loadDetails(index: Int, course: Course, run: UUID, detailRun: UUID) async {
        guard let profile = professors[index].profile else { return }
        let id = professors[index].id
        if !professors[index].reviewsComplete {
            let reader = RMPBrowser(); detailReader = reader
            do {
                let full = try await reader.expand(professors[index], profile: profile) { [weak self] partial in
                    guard let self, !Task.isCancelled, self.runID == run, self.detailRunID == detailRun else { return }
                    if Set(self.professors[index].profile?.reviews.map(\.id) ?? []) != Set(partial.reviews.map(\.id)) {
                        self.professors[index].summary = nil
                    }
                    self.professors[index].profile = partial
                    self.saveReport(index: index, course: course)
                }
                guard !Task.isCancelled, runID == run, detailRunID == detailRun else { return }
                if Set(profile.reviews.map(\.id)) != Set(full.reviews.map(\.id)) {
                    professors[index].summary = nil
                }
                professors[index].profile = full; professors[index].reviewsComplete = true
                professors[index].reviewIssue = nil
                saveReport(index: index, course: course)
            } catch {
                guard !Task.isCancelled, runID == run, detailRunID == detailRun else { return }
                professors[index].reviewIssue = "More reviews couldn’t be loaded. The verified scores and retrieved reviews are still available."
            }
            detailReader = nil
        }
        guard !Task.isCancelled, runID == run, detailRunID == detailRun else { return }
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
                }
            }
            while !Task.isCancelled, runID == run, detailRunID == detailRun, let id = pendingSummaryID {
                pendingSummaryID = nil; attemptedSummaries.insert(id); summaryLoadingID = id; updateDetailProgress()
                guard let index = professors.firstIndex(where: { $0.id == id }), let course,
                      let evidence = professors[index].profile else { retryingIDs.remove(id); continue }
                do {
                    let summary = try await ollama.summarize(reviews: evidence.reviews, course: course)
                    guard !Task.isCancelled, runID == run, detailRunID == detailRun else { return }
                    professors[index].summary = summary; professors[index].summaryIssue = nil
                } catch {
                    guard !Task.isCancelled, runID == run, detailRunID == detailRun else { return }
                    professors[index].summaryIssue = error.localizedDescription
                }
                retryingIDs.remove(id)
                if !Task.isCancelled, runID == run, detailRunID == detailRun { saveReport(index: index, course: course) }
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
        detailReader?.stop(); detailReader = nil; pendingDetailID = nil
        retryingIDs = []; loadingDetailsID = nil; detailProgress = nil; detailCancelled = true
    }
    func cancel() {
        runID = UUID(); searchTask?.cancel(); searchTask = nil
        browsers.forEach { $0.stop() }; browsers = []
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
