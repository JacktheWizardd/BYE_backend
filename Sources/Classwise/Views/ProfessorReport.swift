import SwiftUI
import ClasswiseCore

struct ProfessorReport: View {
    @ObservedObject var model: AppModel
    let professor: Professor
    let course: Course
    let scheduleURL: URL?
    let checkingRatings: Bool
    let loadingDetails: Bool
    let detailCancelled: Bool
    let retrying: Bool
    let canRetry: Bool
    let retry: () -> Void
    @State private var reviewFilter: ReviewFilter
    @State private var filterChosenByUser: Bool
    @State private var reviewSort: ReviewSort
    @State private var reviewLimit: Int
    @State private var reviewSource: ReviewSource
    private let restoredChoice: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel, professor: Professor, course: Course, scheduleURL: URL?, checkingRatings: Bool, loadingDetails: Bool,
         detailCancelled: Bool, retrying: Bool, canRetry: Bool, retry: @escaping () -> Void) {
        self.model = model; self.professor = professor; self.course = course; self.scheduleURL = scheduleURL
        self.checkingRatings = checkingRatings; self.loadingDetails = loadingDetails; self.detailCancelled = detailCancelled
        self.retrying = retrying; self.canRetry = canRetry; self.retry = retry
        // Coming back to a professor this session restores how their reviews were left.
        let saved = model.reviewChoice(for: professor.id)
        restoredChoice = saved != nil
        _reviewFilter = State(initialValue: saved?.filter ?? .thisCourse)
        _filterChosenByUser = State(initialValue: saved?.chosenByUser ?? false)
        _reviewSort = State(initialValue: saved?.sort ?? .recent)
        _reviewLimit = State(initialValue: saved?.limit ?? 3)
        _reviewSource = State(initialValue: saved?.source ?? .both)
    }
    private var reviewChoice: ReviewChoice {
        ReviewChoice(filter: reviewFilter, chosenByUser: filterChosenByUser, sort: reviewSort, limit: reviewLimit, source: reviewSource)
    }
    private var bye: AppModel.ByeLoad? { model.byeState(for: professor) }
    private var byeSet: ByeReviewSet? { if case .loaded(let set) = bye { set } else { nil } }
    /// BYE has finished (loaded or failed), so RMP cards can follow without pushing BYE cards down.
    private var byeFinished: Bool { switch bye { case .loaded, .failed: true; case .loading, nil: false } }
    private var byeReviews: [Review] { reviewFilter.byeReviews(byeSet?.reviews ?? [], course: course) }
    private var cards: [SourcedReview] {
        Ordering.merged(bye: byeReviews, rmp: reviews, source: reviewSource, byeLoaded: byeFinished, by: reviewSort)
    }
    private var byeExactCount: Int { byeSet?.reviews.filter { course.matchesReview($0.course) }.count ?? 0 }
    private var reviews: [Review] {
        guard let profile = professor.profile else { return [] }
        return Ordering.reviews(reviewFilter.reviews(in: profile, course: course), by: reviewSort)
    }
    private var exactCount: Int { (professor.profile?.reviews.filter { course.matchesReview($0.course) }.count ?? 0) + byeExactCount }
    private var courseChoices: [ReviewCourseCount] {
        guard let profile = professor.profile else { return [] }
        var labels = Dictionary((profile.courseCounts ?? []).filter { !$0.label.isEmpty }.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        for review in profile.reviews where !review.course.isEmpty && labels[review.course] == nil {
            labels[review.course] = ReviewCourseCount(label: review.course, count: nil)
        }
        return labels.values.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    /// Courses only BYE reviews mention still appear in the one course filter.
    private var byeOnlyCourses: [String] {
        let known = courseChoices.map(\.label) + [course.display]
        let codes = Set((byeSet?.reviews ?? []).map(\.course).filter { code in
            !code.isEmpty && !known.contains { (try? Course($0))?.matchesReview(code) ?? ($0 == code) }
        })
        return codes.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var selectedLabel: String? { reviewFilter.requestLabel(course: course) }
    private var filterFinished: Bool {
        professor.profile.map { reviewFilter.finished(in: $0, course: course) } ?? false
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header.id("top")
                    byeScores
                    if let profile = professor.profile {
                        scores(profile)
                    } else {
                        unavailable
                    }
                    sections
                    if professor.profile != nil {
                        if model.summariesEnabled { summary } else {
                            Text("AI summaries are temporarily unavailable. Read the original student reviews below.")
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                .sunkenPanel(padding: 14)
                        }
                    }
                    studentReviews
                    sourceLinks
                }
                .padding(.horizontal, 32).padding(.vertical, 28).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
            }
            // The page stays mounted while the student switches professors: it scrolls to the top and
            // restores how that professor's reviews were left this session.
            .onChange(of: professor.id) { _, id in
                if let saved = model.reviewChoice(for: id) {
                    reviewFilter = saved.filter; filterChosenByUser = saved.chosenByUser; reviewSort = saved.sort; reviewLimit = saved.limit
                } else { reviewLimit = 3; reviewSort = .recent; reviewSource = .both; applyPreferredFilter() }
                if let next = model.professors.first(where: { $0.id == id }) { model.loadByeReviews(for: next) }
                proxy.scrollTo("top", anchor: .top)
            }
        }
        .accessibilityLabel("Report for \(professor.profile?.name ?? professor.name)")
        .onChange(of: professor.profile?.id) { _, _ in reviewLimit = 3; reviewSort = .recent; applyPreferredFilter() }
        .onChange(of: course) { _, _ in reviewLimit = 3; reviewSort = .recent; applyPreferredFilter() }
        .onChange(of: reviewFilter) { _, _ in reviewLimit = 3 }
        .onChange(of: professor.profile?.reviews.count) { _, _ in if !filterChosenByUser { applyPreferredFilter() } }
        .onChange(of: byeSet?.reviews.count) { _, _ in if !filterChosenByUser { applyPreferredFilter() } }
        .onChange(of: reviewSource) { _, _ in reviewLimit = 3 }
        .onAppear { model.loadByeReviews(for: professor); if !restoredChoice { applyPreferredFilter() } }
        .onChange(of: reviewSort) { _, _ in reviewLimit = 3 }
        .onChange(of: reviewChoice) { _, choice in model.saveReviewChoice(choice, for: professor.id) }
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(name: professor.profile?.name ?? professor.name, accent: true, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(professor.profile?.name ?? professor.name).font(BYEFont.display(26, bold: true))
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    Text([professor.profile?.department ?? "", "Pasadena City College"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    if professor.profile != nil {
                        Button("Change profile") { model.openChooser(id: professor.id) }
                            .buttonStyle(TextLinkStyle()).disabled(model.isPreviewing(professor.id))
                    }
                }
                if let profile = professor.profile, profile.name != professor.name {
                    Text("Listed at PCC as \(professor.name)").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                if professor.profile != nil, let issue = professor.issue {
                    Text(issue).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
        }
    }
    /// BYE's own scores, above RMP's and never blended with them.
    private var byeScores: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ByeStamp(tier: .common, width: 24)
                Text("BYE student ratings").font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
            }
            switch bye {
            case .loaded(let set) where set.matched && set.count > 0:
                HStack(spacing: 8) {
                    StatTile(value: set.quality, suffix: "/5", label: "BYE quality", bar: set.quality)
                    StatTile(value: set.difficulty, suffix: "/5", label: "Difficulty", bar: set.difficulty)
                    StatTile(value: Double(set.count), digits: 0, label: "BYE reviews")
                }
                .fixedSize(horizontal: false, vertical: true)
                Text(set.ratingIssue ?? "\(plural(set.count, "review")) from PCC students who verified their school email · kept separate from RMP")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            case .loaded:
                HStack(spacing: 10) {
                    Text("No BYE reviews for \(professor.name) yet.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    if let url = ReviewLink.url(professor: professor.name, course: course) {
                        Link("Write the first one ↗", destination: url).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                    }
                }
            case .failed(let message):
                HStack(spacing: 10) {
                    Text(message).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Button("Try again") { model.loadByeReviews(for: professor, retry: true) }.buttonStyle(TextLinkStyle())
                }
            case .loading, nil:
                Text("Checking BYE reviews…").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
    }
    private func scores(_ profile: RMPProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SourceTag(text: "RMP")
                Text("Rate My Professors ratings").font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
            }
            HStack(spacing: 8) {
                StatTile(value: profile.rating, suffix: "/5", label: "RMP rating", bar: profile.rating)
                StatTile(value: profile.difficulty, suffix: "/5", label: "Difficulty", bar: profile.difficulty)
                StatTile(value: profile.wouldTakeAgain.map { $0.rounded() }, digits: 0, suffix: "%", label: "Would take again")
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("\(profile.ratingCount.map { plural($0, "rating") } ?? "Rating count unavailable") across all courses · higher rating is better rated · lower difficulty means easier")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
    }
    /// Before RMP has a verified profile: what is happening and what the student can do.
    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(professor.reportStatusTitle)
                .font(BYEFont.display(19, bold: true))
            Text(professor.issue ?? "PCC sections are available below. Ratings and reviews will appear here when retrieved.")
                .foregroundStyle(Palette.body).font(.system(size: 13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if professor.state == .selectionRequired {
                    Button("Choose profile →") { model.openChooser(id: professor.id) }.buttonStyle(StickerButtonStyle())
                }
                if professor.state == .unavailable || professor.state == .pending || (professor.state == .selectionRequired && professor.candidates.isEmpty) {
                    Button("Try again") { model.retryProfessor(id: professor.id) }
                        .buttonStyle(StickerButtonStyle(kind: .secondary)).disabled(model.isPreviewing(professor.id))
                }
                Link("Check on RMP ↗", destination: professor.searchURL).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
            }
        }
        .sunkenPanel(padding: 18)
    }
    private var sourceLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                if let scheduleURL { Link("PCC schedule ↗", destination: scheduleURL) }
                if professor.profile != nil { Link("Rate My Professors ↗", destination: professor.sourceURL) }
                if let url = ReviewLink.url(professor: professor.name, course: course) { Link("Write a review ↗", destination: url) }
            }
            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
            if let date = professor.checkedAt {
                Text("RMP checked \(date.formatted(date: .abbreviated, time: .shortened)). Refresh to check again.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Eyebrow(title: "AI review summary"); Spacer()
                #if BYE_MODEL_EVAL
                Text("LOCAL MODEL · MEASUREMENT").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
                #else
                Tag(text: "Experimental", kind: .signal)
                #endif
            }
            if let summary = professor.summary {
                Text(summary.overview).font(.system(size: 15)).lineSpacing(6)
                Text("Apple AI · on your Mac · \(summary.analyzedCount) of \(professor.profile?.reviews.count ?? 0) downloaded reviews analyzed · \(summary.exactCourseCount) for \(course.display) · \(summary.analyzedCount - summary.exactCourseCount) for other or unspecified courses")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                themes("Common positives", points: summary.positives)
                themes("Common concerns", points: summary.concerns)
                #if BYE_MODEL_EVAL
                Text("Offline model measurement with fictional UI fixtures. Check the original reviews for context.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                #else
                Text("Experimental Apple AI summary of student opinions. Check the original reviews for context.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                #endif
                if summary.positives.isEmpty && summary.concerns.isEmpty && canRetry && !loadingDetails {
                    Button("Retry summary", action: retry).buttonStyle(StickerButtonStyle(kind: .secondary)).disabled(checkingRatings || retrying)
                }
            } else {
                Text(summaryStatus)
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(4)
                if canRetry && !loadingDetails && (professor.summaryIssue != nil || detailCancelled) {
                    Button(professor.reviewIssue != nil ? "Retry report" : "Retry summary", action: retry)
                        .buttonStyle(StickerButtonStyle(kind: .secondary)).disabled(retrying || (professor.profile?.reviews.isEmpty ?? true))
                    if professor.summaryIssue != nil { Button("Apple Intelligence settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                    }.buttonStyle(TextLinkStyle()) }
                }
            }
        }.sunkenPanel(padding: 20)
    }
    /// Opens on this course when a downloaded review is about it, otherwise on all courses.
    private func applyPreferredFilter() {
        reviewFilter = byeExactCount > 0 ? .thisCourse : .preferred(in: professor.profile, course: course)
        filterChosenByUser = false
    }
    private var summaryStatus: String {
        if let issue = professor.summaryIssue { return issue }
        if checkingRatings { return "Checking everyone’s ratings first. More reviews and a summary will follow for the report you open." }
        if retrying { return "Preparing a summary of the retrieved reviews on your Mac…" }
        if loadingDetails { return "Loading more student reviews before preparing a summary…" }
        if detailCancelled { return "Loading stopped. Your ratings and retrieved reviews are still available." }
        return "A summary will be prepared when this report opens. Ratings and original reviews are already available below."
    }
    private func themes(_ title: String, points: [SummaryPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if points.isEmpty { Text("No verified recurring theme in this sample.").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                Text("• " + point.text).font(.system(size: 13)).lineSpacing(4)
            }
        }
    }
    /// One Reviews section for both sources: a Both · BYE · RMP toggle, one course filter and one sort.
    private var studentReviews: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Reviews").font(BYEFont.display(19, bold: true)).accessibilityAddTraits(.isHeader)
                Spacer()
                Segmented(label: "Review source", options: ReviewSource.allCases.map { ($0, $0.label) }, selection: $reviewSource)
                    .frame(maxWidth: 220)
            }
            if reviewSource != .rmp { byeStatus }
            if reviewSource != .bye, professor.profile != nil, !professor.reviewsComplete {
                HStack(alignment: .top, spacing: 8) {
                    if loadingDetails { ProgressView().controlSize(.small) }
                    Text(professor.reviewIssue ?? (checkingRatings ? "Quick preview · Up to three RMP reviews. More feedback loads after everyone’s ratings are checked." : loadingDetails ? "Quick preview · Loading more RMP reviews for this professor…" : detailCancelled ? "Quick preview · Loading stopped. You can resume loading below." : "Quick preview · More RMP feedback loads when you open this report."))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
                }
                if canRetry && !loadingDetails && (professor.reviewIssue != nil || detailCancelled) {
                    Button(professor.reviewIssue != nil ? "Retry reviews" : "Load more reviews") { model.retryReviews(id: professor.id) }.buttonStyle(StickerButtonStyle(kind: .secondary))
                }
            }
            HStack {
                Picker("Review course", selection: Binding(get: { reviewFilter }, set: { reviewFilter = $0; filterChosenByUser = true })) {
                    Text("This course · \(course.display)").tag(ReviewFilter.thisCourse)
                    Text("All courses").tag(ReviewFilter.allCourses)
                    ForEach(courseChoices, id: \.label) { item in
                        Text(item.count.map { "\(item.label) (\($0) on RMP)" } ?? "\(item.label) (source count unavailable)")
                            .tag(ReviewFilter.source(item.label))
                    }
                    ForEach(byeOnlyCourses, id: \.self) { code in
                        Text("\(code) (BYE only)").tag(ReviewFilter.source(code))
                    }
                }.pickerStyle(.menu).frame(maxWidth: 330).accessibilityLabel("Review course filter")
                Spacer()
                Picker("Sort reviews", selection: $reviewSort) { ForEach(ReviewSort.allCases) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).accessibilityLabel("Sort reviews").frame(maxWidth: 170)
            }
            if reviewFilter == .allCourses && exactCount == 0 && !filterChosenByUser {
                HStack(spacing: 12) {
                    Text("No reviews mention \(course.display) yet, so all courses are shown.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    if professor.profile != nil {
                        Button("Find \(course.display) reviews") {
                            reviewFilter = .thisCourse; filterChosenByUser = true
                            model.findMoreReviews(id: professor.id, filter: .thisCourse)
                        }.buttonStyle(TextLinkStyle()).disabled(model.busy || model.loadingDetailsID != nil)
                    }
                }
            } else if reviewFilter == .thisCourse && exactCount == 0 {
                Text("No downloaded reviews exactly match \(course.display). More may be available on RMP under this or another course label.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            if reviewSource != .bye, professor.profile != nil, let label = selectedLabel {
                if let issue = model.courseReviewIssues[professor.id + "|" + label] {
                    Text(issue).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                if !filterFinished {
                    Button("Find more for this class") { model.findMoreReviews(id: professor.id, filter: reviewFilter) }
                        .buttonStyle(StickerButtonStyle(kind: .secondary)).disabled(model.busy || model.loadingDetailsID != nil)
                    Text(reviewFilter == .thisCourse ? "Requests equivalent course labels reported by this professor’s RMP profile." : "Requests this class label from RMP. Reviews for other classes and overall scores stay separate.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else {
                    Text("Finished this filter’s RMP retrieval, or reached the 50-rating limit. Source totals may include reviews without text.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            if cards.isEmpty && (reviewSource == .rmp || byeFinished) {
                Text("No review text available for this filter.").font(.system(size: 14)).foregroundStyle(Palette.secondary).padding(.vertical, 10)
            }
            // Two columns once the page is wide enough; changing the sort glides each review to its new place.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(Array(cards.prefix(reviewLimit))) { card in
                    if card.source == .bye {
                        ReviewCard(review: card.review, stamp: StampTier(reviewID: card.review.id))
                    } else {
                        ReviewCard(review: card.review, sourceURL: professor.sourceURL)
                    }
                }
            }
            .animation(BYEMotion.spring(reduce: reduceMotion), value: cards.prefix(reviewLimit).map(\.id))
            if cards.count > reviewLimit {
                Button("View more reviews") { reviewLimit += 5 }.buttonStyle(StickerButtonStyle(kind: .secondary)).frame(maxWidth: .infinity)
            }
            Text("BYE reviews come from PCC students who verified their school email. RMP reviews are excerpts, not the complete RMP review history. Dates indicate when reviews were posted.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }
    }
    /// What BYE's own reviews are doing; shown in Both and BYE.
    @ViewBuilder private var byeStatus: some View {
        switch bye {
        case .loading, nil:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(reviewSource == .both ? "Loading BYE reviews first. RMP reviews follow." : "Loading BYE reviews…")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        case .failed(let message):
            HStack(spacing: 10) {
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Button("Retry BYE reviews") { model.loadByeReviews(for: professor, retry: true) }.buttonStyle(TextLinkStyle())
            }
        case .loaded(let set) where !set.complete:
            Text("Showing the newest \(set.reviews.count) BYE reviews.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
        case .loaded:
            EmptyView()
        }
    }
    /// Every section this professor teaches; ones that miss the picked filters are tagged "Other days".
    private var allSections: [ClasswiseCore.Section] {
        model.professors.first { $0.id == professor.id }?.sections ?? professor.sections
    }
    private var sections: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("Sections ") + Text("· \(allSections.count)").foregroundStyle(Palette.secondary))
                .font(BYEFont.display(19, bold: true)).accessibilityAddTraits(.isHeader)
            ForEach(allSections) { section in
                ClassCard(section: section, matches: (!model.onlineOnly || section.fullyOnline) && section.fits(availableDays: model.availableDays))
            }
        }
    }
}

/// Opens the BYE website's review form, prefilled by name. The website resolves
/// the names to database IDs and only fills them in on an unambiguous match.
enum ReviewLink {
    static let defaultSite = "https://bye-before-you-enroll.pages.dev"

    /// Distribution builds carry `BYEWebsiteURL` from scripts/build-app.sh;
    /// test builds fall back to the default site.
    static func site(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let value = (info?["BYEWebsiteURL"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? defaultSite : value
    }

    static func url(professor: String, course: Course, site: String = site()) -> URL? {
        let name = professor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var components = URLComponents(string: site) else { return nil }
        components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) + "/reviews/"
        components.queryItems = [URLQueryItem(name: "professor", value: name), URLQueryItem(name: "course", value: course.display)]
        // URLComponents leaves "+" alone, but form decoding on the website reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }
}
