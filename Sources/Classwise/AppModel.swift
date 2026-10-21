import SwiftUI
import ClasswiseCore

/// The screen the main window shows.
enum AppRoute: Equatable { case welcome, name, home, results }

/// The sections of Settings.
enum SettingsTab: Hashable { case general, updates, about }

/// How a student left one professor's reviews, restored when they come back to that professor this session.
struct ReviewChoice: Equatable {
    var filter: ReviewFilter
    var chosenByUser: Bool
    var sort: ReviewSort
    var limit: Int
}

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
    @Published var route: AppRoute
    /// Results are one route; leaving them returns Home (the welcome stays until it is finished).
    var showingResults: Bool {
        get { route == .results }
        set { if newValue { route = .results } else if route == .results { route = .home } }
    }
    /// The ⌘K menu, over Home or results. It never opens during the first run.
    @Published var commandMenuOpen = false {
        didSet { if commandMenuOpen && (route == .welcome || route == .name) { commandMenuOpen = false } }
    }
    /// The open Settings sheet tab, or nil when it is closed. Like ⌘K, it waits until the welcome is finished.
    @Published var settingsTab: SettingsTab? {
        didSet {
            if settingsTab != nil && (route == .welcome || route == .name) { settingsTab = nil }
            if settingsTab != nil { commandMenuOpen = false }
        }
    }
    @Published private(set) var displayName: String
    @Published private(set) var recentClasses: [Course]
    private let preferences: AppPreferences
    /// Each recent class is a tab for this session: its professors, filters and open report come back at once.
    private struct ClassSession {
        let professors: [Professor]
        let selectedID: String?
        let availableDays: Set<Weekday>
        let onlineOnly: Bool
        let sort: ProfessorSort
        let showAll: Bool
    }
    private var sessions: [String: ClassSession] = [:]
    private var reviewChoices: [String: ReviewChoice] = [:]
    /// Busy describes the ratings pass, not optional report work.
    @Published var busy = false
    @Published var progress = ""
    @Published var selectedID: String?
    @Published var sort: ProfessorSort = .rating
    @Published var onlineOnly = false {
        didSet { if showingResults { reconcileSelection() } }
    }
    @Published var availableDays: Set<Weekday> = [] {
        didSet { if showingResults { reconcileSelection() } }
    }
    @Published var showAll = false
    @Published var retryingIDs: Set<String> = []
    @Published var loadingDetailsID: String?
    @Published var summaryLoadingID: String?
    @Published var detailProgress: String?
    @Published var detailCancelled = false
    @Published var courseReviewIssues: [String: String] = [:]
    @Published var suggestionLoading = false
    @Published private var suggestionCatalog: [CourseSuggestion] = []
    #if BYE_AUDIT
    var auditPreviewLimit: Int? = nil
    var auditSummariesEnabled = true
    #endif
    @Published var scheduleMetadata: ScheduleMetadata?
    private let pcc: PCCClient
    let summariesEnabled: Bool
    private let summaryProvider: (any SummaryProvider)?
    private var summaryCacheProvider: String? { summaryProvider is OllamaClient ? nil : summaryProvider?.cacheIdentity }
    private var prewarmTask: Task<Void, Never>?
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
    private var pendingDetailFilter: ReviewFilter?
    private var pendingSummaryID: String?
    private var attemptedSummaries: Set<String> = []
    private var attemptedDetails: Set<String> = []
    private var checkedCount = 0
    private var runID = UUID()
    private var detailRunID = UUID()
    #if DEBUG
    private(set) var quickPassSnapshot: [Professor] = []
    #endif

    init(pcc: PCCClient = PCCClient.sharedBackend(), ollama: OllamaClient? = nil, summaryProvider: (any SummaryProvider)? = nil, cache: ReportCache? = nil,
         choices: ProfileChoiceStore? = nil, summariesEnabled: Bool = false, preferences: AppPreferences = AppPreferences(),
         makeReader: @escaping @MainActor () -> any ProfileReader = { RMPAPIReader() }) {
        self.pcc = pcc; self.summariesEnabled = summariesEnabled
        self.preferences = preferences; displayName = preferences.displayName; recentClasses = preferences.recentClasses
        route = preferences.hasOnboarded ? .home : .welcome
        self.summaryProvider = summariesEnabled ? (summaryProvider ?? ollama ?? AppleSummaries.make()) : nil
        self.cache = cache ?? ReportCache(directory: BetaStorage.directory.appendingPathComponent("Reports"))
        self.choices = choices ?? ProfileChoiceStore(directory: BetaStorage.directory); self.makeReader = makeReader
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
            cache.invalidate(name: professors[index].name, course: course, subject: professors[index].subjectCode, profileID: old.id, summaryProvider: summaryCacheProvider, includeSummary: summariesEnabled)
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
    /// Classes matching any query, for the command menu (which also opens over results).
    func courseMatches(_ query: String) -> [CourseSuggestion] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        return CourseSuggestions.match(courses: suggestionCatalog, query: query)
    }
    var selectedTerm: Term? { terms.first { $0.id == termID } }
    var filtered: [Professor] {
        guard let course else { return [] }
        let list = professors.compactMap { professor -> Professor? in
            var result = professor
            result.sections = professor.sections.filter {
                (!onlineOnly || $0.fullyOnline) && $0.fits(availableDays: availableDays)
            }
            return result.sections.isEmpty ? nil : result
        }
        return Ordering.professors(list, by: sort, course: course)
    }
    var displayed: [Professor] { showAll ? filtered : Array(filtered.prefix(5)) }
    /// The class title from PCC's schedule, in title case.
    var courseTitle: String { professors.lazy.flatMap(\.sections).first.map { displayTitle($0.title) } ?? "" }
    /// "Fall 2026 · Mon, Wed · Fully online": the semester and the filters in use.
    var searchSummary: String {
        let days = Weekday.allCases.filter { availableDays.contains($0) }.map(\.shortLabel).joined(separator: ", ")
        return [searchedTerm?.termName ?? "", days, onlineOnly ? "Fully online" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    /// Share of professors whose RMP lookup has finished, for the progress meter.
    var checkedFraction: Double {
        guard !professors.isEmpty else { return 0 }
        return Double(professors.filter { $0.state != .pending && $0.state != .searching }.count) / Double(professors.count)
    }
    var sectionCount: Int { Set(filtered.flatMap { $0.sections.map(\.crn) }).count }
    var selected: Professor? { filtered.first { $0.id == selectedID } }
    var scheduleURL: URL? {
        guard let course, let searchedTerm else { return nil }
        return PCCClient.scheduleURL(term: searchedTerm, course: course)
    }
    func reconcileSelection() {
        // Incoming ratings may reorder the top five. Keep the report the student opened;
        // if filters hide it, return to the course overview rather than opening someone else.
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = nil }
    }
    private var termsCheckedAt = Date.distantPast
    func refreshPublishedTermsIfNeeded(onActivation: Bool = false) async {
        let age = Date().timeIntervalSince(termsCheckedAt)
        guard pcc.usesSharedSchedule,
              age >= 3600 || (terms.isEmpty && (onActivation || age >= 60)) else { return }
        await loadTerms(refresh: true, quietly: !terms.isEmpty)
    }
    func loadTerms(refresh: Bool = false, quietly: Bool = false) async {
        guard (terms.isEmpty || refresh), !loadingTerms else { return }
        loadingTerms = true; termsCheckedAt = Date()
        if !quietly { error = nil }
        defer { loadingTerms = false }
        do { terms = try await pcc.terms(); if termID.isEmpty { termID = terms.first?.id ?? "" }; termsCheckedAt = Date() }
        catch { if !quietly { self.error = (error as? AppError)?.localizedDescription ?? "Couldn’t load PCC semesters. Check your connection and try again." } }
    }
    func updateCourseSuggestions() {
        guard !showingResults || commandMenuOpen, let term = selectedTerm else { return }
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
        saveSession()
        let restored = force ? nil : sessions[Self.sessionKey(term, parsed)]
        cancel()
        runID = UUID(); let run = runID
        #if BYE_AUDIT
        if auditSummariesEnabled, let summaryProvider { prewarmTask = Task { [summaryProvider] in await summaryProvider.prewarm() } }
        #else
        if let summaryProvider { prewarmTask = Task { await summaryProvider.prewarm() } }
        #endif
        scheduleMetadata = nil; scheduleFailures = 0; scheduleRetrySeconds = 60
        let query = input
        course = parsed; searchedTerm = term; error = nil; busy = true; progress = "Finding classes at PCC…"
        attemptedDetails = []; attemptedSummaries = []; courseReviewIssues = [:]
        if let restored {
            // A class revisited this session reappears at once and reloads in the background.
            professors = restored.professors; showingResults = true; apply(restored)
        } else { professors = []; selectedID = nil; showAll = false; showingResults = false }
        searchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if runID == run {
                    searchTask = nil
                    if !Task.isCancelled { pumpPreviews() } else { busy = false; progress = "" }
                }
            }
            do {
                let shared = try await pcc.courseRows(term: term, query: query)
                let rows: [ScheduleRow]
                if let shared { rows = shared.rows }
                else { rows = try await pcc.schedule(term: term, force: force) }
                try Task.checkCancellation(); guard runID == run else { return }
                scheduleMetadata = shared?.metadata
                let parsed = try CourseSuggestions.resolve(parsed, rows: rows)
                course = parsed
                input = parsed.display
                let found = ScheduleParser.professors(rows: rows, course: parsed)
                // No professor opens on its own: the student picks, so BYE never spotlights one.
                // A revisited class keeps the professor the student had opened.
                professors = found; showingResults = true
                if let session = restored ?? (force ? nil : sessions[Self.sessionKey(term, parsed)]) { apply(session) } else { selectedID = nil }
                recentClasses = preferences.remember(parsed)
                checkedCount = 0
                var missing: [Int] = []
                // All cached scores appear before any website or local-model work.
                for index in professors.indices {
                    if !force, let cached = cache.load(name: professors[index].name, course: parsed, subject: professors[index].subjectCode, preferredProfileID: choices.choice(name: professors[index].name, subject: professors[index].subjectCode), summaryProvider: summaryCacheProvider, includeSummary: summariesEnabled) {
                        professors[index].profile = cached.profile; professors[index].summary = cached.summary
                        professors[index].checkedAt = cached.checkedAt; professors[index].state = .ready
                        professors[index].reviewsComplete = cached.reviewsComplete ?? true
                        checkedCount += 1
                    } else { missing.append(index) }
                }
                // Queue all jobs before dispatch, so optional detail work stays gated.
                #if BYE_AUDIT
                let selectedMissing = auditPreviewLimit.map { limit in missing.filter { $0 < limit } } ?? missing
                pendingPreviews = selectedMissing.map { PreviewJob(id: self.professors[$0].id, generation: self.professors[$0].generation, action: .lookup) }
                AppAudit.log?.event("course_results", ["course":parsed.display,"professors":found.count,"selected_lookups":selectedMissing.count])
                #else
                pendingPreviews = missing.map { PreviewJob(id: self.professors[$0].id, generation: self.professors[$0].generation, action: .lookup) }
                #endif
                pumpPreviews()
            } catch is CancellationError { }
            catch { if runID == run { self.error = error.localizedDescription; showingResults = false } }
        }
    }
    private static func sessionKey(_ term: Term, _ course: Course) -> String { "\(term.id) \(course.display)" }
    private var currentSessionKey: String? {
        guard let course, let searchedTerm else { return nil }
        return Self.sessionKey(searchedTerm, course)
    }
    /// Restores filters, then the open professor if the filters still show them.
    private func apply(_ session: ClassSession) {
        sort = session.sort; showAll = session.showAll
        onlineOnly = session.onlineOnly; availableDays = session.availableDays
        selectedID = filtered.contains { $0.id == session.selectedID } ? session.selectedID : nil
    }
    /// Keeps the open class's state for this session. Only recent classes are kept, so memory stays bounded.
    private func saveSession() {
        guard showingResults, !professors.isEmpty, let key = currentSessionKey else { return }
        sessions[key] = ClassSession(professors: professors, selectedID: selectedID, availableDays: availableDays,
                                     onlineOnly: onlineOnly, sort: sort, showAll: showAll)
        let kept = Set(recentClasses.map(\.display))
        sessions = sessions.filter { key, _ in kept.contains { key.hasSuffix(" " + $0) } }
        reviewChoices = reviewChoices.filter { key, _ in sessions.keys.contains { key.hasPrefix($0 + "|") } }
    }
    func reviewChoice(for professorID: String) -> ReviewChoice? {
        currentSessionKey.flatMap { reviewChoices[$0 + "|" + professorID] }
    }
    func saveReviewChoice(_ choice: ReviewChoice, for professorID: String) {
        guard let key = currentSessionKey else { return }
        reviewChoices[key + "|" + professorID] = choice
    }

    // MARK: Home, first run and the student's name

    /// Opens a class from Home, the sidebar or the command menu.
    func openClass(_ course: Course) {
        if showingResults, self.course?.display == course.display { return }
        input = course.display; start()
    }
    func goHome() { saveSession(); changeSearch() }
    func continueFromWelcome() { route = .name }
    /// Finishes the first run. An empty name is allowed: the student stays "Guest".
    func finishOnboarding(name: String) {
        setDisplayName(name); preferences.hasOnboarded = true; route = .home
    }
    func showWelcomeAgain() { saveSession(); cancel(); error = nil; commandMenuOpen = false; settingsTab = nil; route = .welcome }
    /// Saves the name on this Mac. Returns false for an empty name or one that breaks the name rule.
    @discardableResult
    func setDisplayName(_ name: String) -> Bool {
        let normalized = AppPreferences.normalizedName(name)
        guard !normalized.isEmpty, AppPreferences.isValidName(normalized) else { return false }
        preferences.displayName = normalized; displayName = normalized
        return true
    }
    private func updateProgress() {
        let checked = professors.filter { [.ready, .unavailable, .selectionRequired].contains($0.state) }.count
        progress = "Checking ratings · \(checked) of \(professors.count)"
    }
    private func saveReport(index: Int, course: Course) {
        guard let profile = professors[index].profile else { return }
        #if BYE_AUDIT
        AppAudit.log?.event("profile_saved", ["profile":profile.id,"course":course.display,"decoded_reviews":profile.reviews.count,"complete":professors[index].reviewsComplete])
        #endif
        cache.save(CachedReport(profile: profile, summary: professors[index].summary,
                                checkedAt: professors[index].checkedAt ?? Date(),
                                reviewsComplete: professors[index].reviewsComplete),
                   name: professors[index].name, course: course, subject: professors[index].subjectCode, summaryProvider: summaryCacheProvider, includeSummary: summariesEnabled)
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
              !filter.finished(in: profile, course: course) else { return }
        if case .source(let source) = filter {
            guard profile.courseCounts?.contains(where: { $0.label == source }) == true || profile.reviews.contains(where: { $0.course == source }) else { return }
        }
        selectedID = id; pendingDetailID = id; pendingDetailFilter = filter; detailCancelled = false
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
    private func loadDetails(index: Int, course: Course, run: UUID, detailRun: UUID, filter: ReviewFilter? = nil) async {
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
                    if filter == .thisCourse {
                        full = try await courseReader.expand(professors[index], profile: profile, matching: course, onProfile: publish)
                    } else {
                        full = try await courseReader.expand(professors[index], profile: profile, courseFilter: filter.requestLabel(course: course), onProfile: publish)
                    }
                } else { full = try await reader.expand(professors[index], profile: profile, onProfile: publish) }
                guard !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: profileID) else { return }
                if profile.reviews != full.reviews {
                    professors[index].summary = nil
                    attemptedSummaries.remove(id)
                }
                professors[index].profile = full
                if filter == nil { professors[index].reviewsComplete = true; professors[index].reviewIssue = nil }
                else if let label = filter?.requestLabel(course: course) { courseReviewIssues[id + "|" + label] = nil }
                saveReport(index: index, course: course)
            } catch {
                guard !Task.isCancelled, runID == run, detailRunID == detailRun, currentProfile(index: index, generation: generation, profileID: profileID) else { return }
                if let label = filter?.requestLabel(course: course) { courseReviewIssues[id + "|" + label] = "More reviews for this class couldn’t be loaded. Saved reviews remain available; try again." }
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
        guard summariesEnabled, let summaryProvider else { return }
        #if BYE_AUDIT
        guard auditSummariesEnabled else { return }
        #endif
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
                    let summary = try await summaryProvider.summarize(reviews: evidence.reviews, course: course)
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
        guard summariesEnabled else { return }
        guard !busy, !loadingDetails, let index = professors.firstIndex(where: { $0.id == id }) else { return }
        professors[index].summary = nil
        professors[index].summaryIssue = nil; professors[index].reviewIssue = nil
        if let course { saveReport(index: index, course: course) }
        attemptedDetails.remove(id); attemptedSummaries.remove(id); selectedID = id; requestSelectedReport()
    }
    func retryReviews(id: String) {
        guard !busy, !loadingDetails, let index = professors.firstIndex(where: { $0.id == id }) else { return }
        professors[index].reviewIssue = nil
        attemptedDetails.remove(id); selectedID = id; requestSelectedReport()
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
        prewarmTask?.cancel(); prewarmTask = nil
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
    @Published private(set) var scheduleRetrySeconds = 60.0
    private var scheduleFailures = 0
    private var refreshingSchedule = false
    func refreshSchedule() async {
        guard pcc.usesSharedSchedule, !refreshingSchedule, !busy, showingResults, let course, let searchedTerm else { return }
        refreshingSchedule = true; let operation = runID
        defer { refreshingSchedule = false }
        do {
            guard let shared = try await pcc.courseRows(term: searchedTerm, query: course.display) else { return }
            try Task.checkCancellation(); guard operation == runID else { return }
            let previous = Dictionary(uniqueKeysWithValues: professors.map { ($0.id, $0) })
            professors = ScheduleParser.professors(rows: shared.rows, course: course).map { item in
                if var old = previous[item.id], old.name == item.name, old.subjectCode == item.subjectCode { old.sections = item.sections; return old }
                var next = item; next.state = .unavailable; next.issue = "PCC updated the instructor assignment. Retrieve a verified profile when ready."; return next
            }
            scheduleMetadata = shared.metadata; scheduleFailures = 0; scheduleRetrySeconds = 60
            reconcileSelection()
            if let chooserID, !professors.contains(where: { $0.id == chooserID }) { self.chooserID = nil }
        } catch {
            guard operation == runID, !Task.isCancelled else { return }
            scheduleFailures = min(scheduleFailures + 1, 4)
            scheduleRetrySeconds = min(900, 60 * pow(2, Double(scheduleFailures)))
            expireAvailability()
        }
    }
    func expireAvailability(at now: Date = Date()) {
        guard let metadata = scheduleMetadata, metadata.expired(at: now) else { return }
        for index in professors.indices { for section in professors[index].sections.indices {
            professors[index].sections[section].details?.seatsOpen = nil
            professors[index].sections[section].details?.capacity = nil
            professors[index].sections[section].details?.waitlistCount = nil
            professors[index].sections[section].details?.waitlistCapacity = nil
        } }
    }
    func refresh() {
        guard let course, let searchedTerm else { return }
        if pcc.usesSharedSchedule { Task { await refreshSchedule() }; return }
        input = course.display; termID = searchedTerm.id; start(force: true)
    }
}
