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
    @State private var reviewFilter: ReviewFilter = .thisCourse
    @State private var reviewSort: ReviewSort = .recent
    @State private var reviewLimit = 3
    private var reviews: [Review] {
        guard let profile = professor.profile else { return [] }
        return Ordering.reviews(reviewFilter.reviews(in: profile, course: course), by: reviewSort)
    }
    private var exactCount: Int { professor.profile?.reviews.filter { course.matchesReview($0.course) }.count ?? 0 }
    private var courseChoices: [ReviewCourseCount] {
        guard let profile = professor.profile else { return [] }
        var labels = Dictionary((profile.courseCounts ?? []).filter { !$0.label.isEmpty }.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        for review in profile.reviews where !review.course.isEmpty && labels[review.course] == nil {
            labels[review.course] = ReviewCourseCount(label: review.course, count: nil)
        }
        return labels.values.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    private var selectedLabel: String? { reviewFilter.requestLabel(course: course) }
    private var filterFinished: Bool {
        professor.profile.map { reviewFilter.finished(in: $0, course: course) } ?? false
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                sections
                if let profile = professor.profile {
                    HStack(spacing: 14) {
                        ScoreCard(value: profile.rating, title: "Student rating", helper: "Higher means better rated")
                        ScoreCard(value: profile.difficulty, title: "Difficulty", helper: "Lower means easier")
                    }
                    HStack {
                        Text(profile.ratingCount.map { "Based on \($0) RMP ratings across courses" } ?? "Overall rating count unavailable")
                        Spacer()
                        if let percent = profile.wouldTakeAgain { Text("\(Int(percent.rounded()))% would take again") }
                    }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    summary
                    studentReviews
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(professor.state == .selectionRequired ? "Choose profile" : professor.state == .unavailable ? "Cannot retrieve RMP info" : professor.state == .searching ? "Finding student feedback…" : "Student feedback hasn’t been checked yet.")
                            .font(.system(size: 21, weight: .medium))
                        Text(professor.issue ?? "PCC sections are available above. Ratings and reviews will appear here when retrieved.")
                            .foregroundStyle(Palette.secondary).font(.system(size: 14)).lineSpacing(4)
                        if professor.state == .selectionRequired {
                            Button("Choose profile") { model.openChooser(id: professor.id) }.buttonStyle(PillStyle(primary: true))
                        }
                        if professor.state == .unavailable || professor.state == .pending || (professor.state == .selectionRequired && professor.candidates.isEmpty) {
                            Button("Try again") { model.retryProfessor(id: professor.id) }
                                .buttonStyle(PillStyle()).disabled(model.isPreviewing(professor.id))
                        }
                        Link("Check on RMP ↗", destination: professor.searchURL).buttonStyle(PillStyle())
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                HStack(spacing: 12) {
                    Link("Rate My Professors ↗", destination: professor.sourceURL).buttonStyle(PillStyle())
                }
                if let date = professor.checkedAt {
                    Text("RMP checked \(date.formatted(date: .abbreviated, time: .shortened)). Refresh to check again.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 38).padding(.vertical, 34).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Professor report")
        .onChange(of: professor.profile?.id) { _, _ in reviewLimit = 3; reviewFilter = .thisCourse; reviewSort = .recent }
        .onChange(of: professor.id) { _, _ in reviewLimit = 3; reviewFilter = .thisCourse; reviewSort = .recent }
        .onChange(of: course) { _, _ in reviewLimit = 3; reviewFilter = .thisCourse; reviewSort = .recent }
        .onChange(of: reviewFilter) { _, _ in reviewLimit = 3 }
        .onChange(of: reviewSort) { _, _ in reviewLimit = 3 }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(title: "Professor profile")
            Text(professor.profile?.name ?? professor.name).font(.system(size: 38, weight: .semibold)).tracking(-1.2)
            if let profile = professor.profile {
                Text([profile.department, profile.school].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Button("Change profile") { model.openChooser(id: professor.id) }
                    .buttonStyle(.link).disabled(model.isPreviewing(professor.id))
                if let issue = professor.issue { Text(issue).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                if profile.name != professor.name { Text("Listed at PCC as \(professor.name)").font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            } else {
                Text("Teaching \(course.display) at Pasadena City College").font(.system(size: 14)).foregroundStyle(Palette.secondary)
            }
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Eyebrow(title: "AI review summary"); Spacer()
                #if BYE_MODEL_EVAL
                Text("LOCAL MODEL · MEASUREMENT").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
                #else
                Text("APPLE AI · ON YOUR MAC").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(Palette.secondary)
                #endif
            }
            if let summary = professor.summary {
                Text(summary.overview).font(.system(size: 15)).lineSpacing(6)
                Text("\(summary.analyzedCount) of \(professor.profile?.reviews.count ?? 0) downloaded reviews analyzed · \(summary.exactCourseCount) for \(course.display) · \(summary.analyzedCount - summary.exactCourseCount) for other or unspecified courses")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                themes("Common positives", points: summary.positives)
                themes("Common concerns", points: summary.concerns)
                #if BYE_MODEL_EVAL
                Text("Offline model measurement with fictional UI fixtures. Check the original reviews for context.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                #else
                Text("Experimental Apple AI summary of student opinions. Check the original reviews for context.").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                #endif
                if summary.positives.isEmpty && summary.concerns.isEmpty && canRetry && !loadingDetails {
                    Button("Retry summary", action: retry).buttonStyle(PillStyle()).disabled(checkingRatings || retrying)
                }
            } else {
                Text(summaryStatus)
                    .font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(4)
                if canRetry && !loadingDetails && (professor.summaryIssue != nil || detailCancelled) {
                    Button(professor.reviewIssue != nil ? "Retry report" : "Retry summary", action: retry)
                        .buttonStyle(PillStyle()).disabled(retrying || (professor.profile?.reviews.isEmpty ?? true))
                    if professor.summaryIssue != nil { Button("Apple Intelligence settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
                    }.buttonStyle(.link) }
                }
            }
        }.padding(25).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
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
    private var studentReviews: some View {
        VStack(alignment: .leading, spacing: 17) {
            Eyebrow(title: "Student reviews")
            if !professor.reviewsComplete {
                HStack(alignment: .top, spacing: 8) {
                    if loadingDetails { ProgressView().controlSize(.small) }
                    Text(professor.reviewIssue ?? (checkingRatings ? "Quick preview · Up to three reviews. More feedback loads after everyone’s ratings are checked." : loadingDetails ? "Quick preview · Loading more reviews for this professor…" : detailCancelled ? "Quick preview · Loading stopped. You can resume the report below." : "Quick preview · More feedback loads when you open this report."))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
                }
                if canRetry && !loadingDetails && (professor.reviewIssue != nil || detailCancelled) {
                    Button(professor.reviewIssue != nil ? "Retry report" : "Load more reviews", action: retry).buttonStyle(PillStyle())
                }
            }
            HStack {
                Picker("Review course", selection: $reviewFilter) {
                    Text("This course · \(course.display)").tag(ReviewFilter.thisCourse)
                    Text("All courses").tag(ReviewFilter.allCourses)
                    ForEach(courseChoices, id: \.label) { item in
                        Text(item.count.map { "\(item.label) (\($0) on RMP)" } ?? "\(item.label) (source count unavailable)")
                            .tag(ReviewFilter.source(item.label))
                    }
                }.pickerStyle(.menu).frame(maxWidth: 330).accessibilityLabel("Review course filter")
                Spacer()
                Picker("Sort reviews", selection: $reviewSort) { ForEach(ReviewSort.allCases) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().pickerStyle(.menu).accessibilityLabel("Sort reviews").frame(maxWidth: 170)
            }
            Text("Showing \(reviews.count) downloaded reviews for this filter (up to 50). Changing the filter uses saved reviews.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if reviewFilter == .thisCourse && exactCount == 0 {
                Text("No downloaded reviews exactly match \(course.display). More may be available on RMP under this or another course label.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            if let label = selectedLabel {
                if let issue = model.courseReviewIssues[professor.id + "|" + label] {
                    Text(issue).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                if !filterFinished {
                    Button("Find more for this class") { model.findMoreReviews(id: professor.id, filter: reviewFilter) }
                        .buttonStyle(PillStyle()).disabled(model.busy || model.loadingDetailsID != nil)
                    Text(reviewFilter == .thisCourse ? "Requests equivalent course labels reported by this professor’s RMP profile." : "Requests this class label from RMP. Reviews for other classes and overall scores stay separate.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else {
                    Text("Finished this filter’s retrieval, or reached the 50-rating limit. Source totals may include reviews without text.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            if reviews.isEmpty { Text("No review text available for this filter.").font(.system(size: 14)).foregroundStyle(Palette.secondary).padding(.vertical, 10) }
            ForEach(Array(reviews.prefix(reviewLimit))) { review in
                ReviewCard(review: review, sourceURL: professor.sourceURL)
            }
            if reviews.count > reviewLimit {
                Button("View more reviews") { reviewLimit += 5 }.buttonStyle(PillStyle()).frame(maxWidth: .infinity)
            }
            Text("Excerpts from accessible reviews, not the complete RMP review history. Dates indicate when reviews were posted.")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }
    }
    private var sections: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(title: "PCC class sections")
            ForEach(professor.sections) { section in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text("CRN \(section.crn)").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if section.fullyOnline {
                            VStack(alignment: .trailing, spacing: 5) {
                                Text("Fully online").font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.6)))
                                Text("No scheduled meetings").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }
                        } else {
                            Text(section.delivery).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Text(section.title).font(.system(size: 12))
                    Text(section.dateLabel).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    ForEach(section.meetings, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                    if section.scheduleNotAnnounced {
                        Text("Schedule not announced").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    }
                }.padding(17).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if let scheduleURL { Link("PCC schedule ↗", destination: scheduleURL).buttonStyle(PillStyle()) }
        }
    }
}
