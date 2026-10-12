import SwiftUI
import ClasswiseCore

private enum Palette {
    static let background = Color(red: 250/255, green: 250/255, blue: 249/255)
    static let surface = Color(red: 243/255, green: 243/255, blue: 241/255)
    static let line = Color.black.opacity(0.09)
    static let secondary = Color(red: 0.39, green: 0.39, blue: 0.37)
    static let accent = Color(red: 0.77, green: 0.36, blue: 0.20)
}
private struct PillStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 19).padding(.vertical, 11)
            .background(primary ? Color.black : Palette.surface, in: Capsule())
            .foregroundStyle(primary ? .white : .black)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Capsule())
    }
}
private struct Eyebrow: View {
    let title: String
    var body: some View { Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.8).foregroundStyle(Palette.secondary) }
}
private func score(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
private struct Brand: View {
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Palette.accent).frame(width: 8, height: 8)
            Text("BYE").font(.system(size: 18, weight: .semibold))
            Text("— before you enroll").font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }.accessibilityElement(children: .combine)
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if model.showingResults { results } else { SearchView(model: model) }
        }
        .foregroundStyle(.black)
        .tint(Palette.accent)
        .task {
            #if !BYE_MODEL_EVAL
            await model.loadTerms()
            #endif
        }
        .sheet(isPresented: Binding(get: { model.chooserID != nil }, set: { if !$0 { model.chooserID = nil } })) {
            ProfileChooser(model: model)
        }
        .onChange(of: model.displayed.map(\.id)) { _, _ in model.reconcileSelection() }
        .onChange(of: model.selectedID) { _, _ in model.requestSelectedReport() }
        #if BYE_AUDIT
        .onChange(of: model.selected?.summary) { _, summary in AppAudit.summaryObserved(summary, profile:model.selected?.profile?.id) }
        #endif
        #if BYE_MODEL_EVAL
        .onChange(of: model.selected?.summary) { _, summary in ModelEvaluation.summaryObserved(summary,profile:model.selected?.profile?.id,showingResults:model.showingResults) }
        .onChange(of: model.showingResults) { _, showing in ModelEvaluation.summaryObserved(model.selected?.summary,profile:model.selected?.profile?.id,showingResults:showing) }
        #endif
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                Brand()
                Rectangle().fill(Palette.line).frame(width: 1, height: 23)
                Text(model.course?.display ?? "").font(.system(size: 15, weight: .semibold))
                Text(model.searchedTerm?.termName ?? "").font(.system(size: 14)).foregroundStyle(Palette.secondary)
                Spacer()
                Button("Refresh") { model.refresh() }.buttonStyle(PillStyle()).disabled(model.busy)
                Button("Change search") { model.changeSearch() }.buttonStyle(PillStyle())
            }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 23)
            Divider().overlay(Palette.line)
            HStack(spacing: 0) {
                professorList.frame(width: 300)
                Rectangle().fill(Palette.line).frame(width: 1)
                if let professor = model.selected, let course = model.course {
                    ProfessorReport(model: model, professor: professor, course: course, scheduleURL: model.scheduleURL,
                                    checkingRatings: model.busy,
                                    loadingDetails: model.loadingDetailsID == professor.id || model.retryingIDs.contains(professor.id),
                                    detailCancelled: model.detailCancelled,
                                    retrying: model.retryingIDs.contains(professor.id), canRetry: !model.busy && !model.loadingDetails) {
                        model.retrySummary(id: professor.id)
                    }.id(professor.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 15) {
                        Text(model.filtered.isEmpty ? "No matching classes" : "Choose a professor").font(.system(size: 28, weight: .semibold))
                        Text(model.onlineOnly ? "Try turning off Fully online only." : "PCC may not offer this course in the selected semester.")
                            .foregroundStyle(Palette.secondary)
                        if let url = model.scheduleURL { Link("Check PCC’s schedule", destination: url).buttonStyle(PillStyle()) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            footer
        }
    }
    private var professorList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Eyebrow(title: "Your options")
                Text("Professors").font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                Text("\(model.sectionCount) sections · \(model.filtered.count) professors")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                if model.busy {
                    Text("Ratings appear as each professor is checked. Pending results are not ranked yet.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                }
                Picker("Sort professors", selection: $model.sort) {
                    ForEach(ProfessorSort.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Sort professors").pickerStyle(.menu)
                Toggle("Fully online only", isOn: $model.onlineOnly).toggleStyle(.checkbox).font(.system(size: 12))
                VStack(spacing: 9) {
                    ForEach(model.displayed) { professor in
                        ProfessorListCard(model: model, professor: professor, selected: model.selectedID == professor.id) { model.selectedID = professor.id }
                    }
                }
                if !model.showAll && model.filtered.count > 5 {
                    Button("View all \(model.filtered.count) professors") { model.showAll = true }
                        .buttonStyle(PillStyle()).frame(maxWidth: .infinity)
                }
                if model.showAll && model.filtered.count > 5 {
                    Button("Show top five") { model.showAll = false }.buttonStyle(PillStyle())
                }
                Text("Ratings reflect student feedback across reviewed courses. They don’t guarantee a grade.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
            }.padding(24)
        }.accessibilityLabel("Professor results")
    }
    private var footer: some View {
        HStack(spacing: 10) {
            if model.busy {
                ProgressView().controlSize(.small)
                Text(model.progress).font(.system(size: 12))
                Button("Cancel") { model.cancel() }.buttonStyle(.link).font(.system(size: 12))
            } else if model.loadingDetails {
                ProgressView().controlSize(.small)
                Text(model.detailProgress ?? "Loading this professor’s report…").font(.system(size: 12))
                Button("Stop loading") { model.cancelDetails() }.buttonStyle(.link).font(.system(size: 12))
            } else {
                Circle().fill(Palette.accent).frame(width: 5, height: 5)
                Text("PCC schedule · Rate My Professors · AI summaries run on your Mac")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
        }.padding(.horizontal, 28).padding(.vertical, 13).background(Palette.surface)
    }
}

private struct SearchView: View {
    @ObservedObject var model: AppModel
    @FocusState private var courseFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Brand()
                Spacer()
                Text("PASADENA CITY COLLEGE").font(.system(size: 10, weight: .medium)).tracking(1.8).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 40).padding(.top, 38)
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(title: "A little clarity before you enroll")
                Text("Find your\nprofessor.").font(.system(size: 64, weight: .semibold)).tracking(-3).lineSpacing(-4)
                    .padding(.top, 18).padding(.bottom, 16)
                Text("Your class. Your semester. A clearer choice.")
                    .font(.system(size: 16)).foregroundStyle(Palette.secondary).padding(.bottom, 38)
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Class").font(.system(size: 13, weight: .semibold))
                        TextField("Enter your course", text: $model.input).textFieldStyle(.plain)
                            .font(.system(size: 18)).padding(15).background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                            .focused($courseFocused).onSubmit { if !model.busy { model.start() } }
                            .accessibilityLabel("Class").accessibilityHint("For example, ETH 014 or POLS C1000")
                        Text("Example: ETH 014 or POLS C1000").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }.frame(width: 265)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Semester").font(.system(size: 13, weight: .semibold))
                        Picker("Semester", selection: $model.termID) {
                            if model.terms.isEmpty { Text(model.loadingTerms ? "Loading semesters…" : "Select semester").tag("") }
                            ForEach(model.terms) { Text($0.termName).tag($0.id) }
                        }.labelsHidden().pickerStyle(.menu).controlSize(.large)
                            .padding(10).frame(height: 52).background(.white, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line)).accessibilityLabel("Semester")
                    }.frame(width: 245)
                }
                if model.suggestionLoading || !model.suggestions.isEmpty { courseSuggestions.padding(.top, 12) }
                HStack(spacing: 15) {
                    Button { model.start() } label: { Label("Find professors", systemImage: "arrow.right").labelStyle(.titleAndIcon) }
                        .buttonStyle(PillStyle(primary: true)).disabled(model.busy || model.terms.isEmpty)
                        .keyboardShortcut(.defaultAction)
                    if model.busy {
                        ProgressView().controlSize(.small)
                        Button("Cancel") { model.cancel() }.buttonStyle(.link)
                    }
                }.padding(.top, 28)
                if model.busy { Text(model.progress).font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 15) }
                if let error = model.error {
                    Text(error).font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 18).fixedSize(horizontal: false, vertical: true)
                    if model.terms.isEmpty {
                        Button("Retry semesters") { Task { await model.loadTerms() } }.buttonStyle(.link).padding(.top, 8)
                    }
                }
            }.frame(width: 540, alignment: .leading)
            Spacer()
            HStack {
                Text("One simple search.")
                Spacer()
                Text("Made for a more informed choice.")
            }.font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(40)
        }.onAppear { courseFocused = true; model.updateCourseSuggestions() }
            .onChange(of: model.input) { _, _ in model.updateCourseSuggestions() }
            .onChange(of: model.termID) { _, _ in model.updateCourseSuggestions() }
    }
    private var courseSuggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.suggestionLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Finding PCC courses…").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }.padding(12)
            }
            if !model.suggestions.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.suggestions) { suggestion in
                            Button { model.chooseSuggestion(suggestion); courseFocused = true } label: {
                                HStack(spacing: 14) {
                                    Text(suggestion.course.display).font(.system(size: 12, weight: .semibold))
                                        .frame(width: 100, alignment: .leading)
                                    Text(suggestion.title).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                }.padding(.horizontal, 13).padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel("Use \(suggestion.course.display), \(suggestion.title)")
                        }
                    }
                }.frame(height: min(CGFloat(model.suggestions.count) * 35, 105))
                    .accessibilityLabel("Matching PCC courses")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
    }
}

private struct ProfessorListCard: View {
    @ObservedObject var model: AppModel
    let professor: Professor
    let selected: Bool
    let select: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(professor.name).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.leading)
                        Spacer(minLength: 3)
                        if selected { Circle().fill(Palette.accent).frame(width: 6, height: 6).padding(.top, 5) }
                    }
                    if let profile = professor.profile {
                        HStack(spacing: 14) {
                            Text("\(score(profile.rating))/5 rating")
                            Text("\(score(profile.difficulty))/5 difficulty")
                        }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                        Text(profile.ratingCount.map { "\($0) ratings · \(professor.sections.count) \(professor.sections.count == 1 ? "section" : "sections")" } ?? "Rating count unavailable")
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    } else {
                        Text(professor.state == .selectionRequired ? "Choose profile" : professor.state == .unavailable ? "Cannot retrieve RMP info" : professor.state == .searching ? "Checking RMP…" : "Not checked yet")
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(professor.name). Rating \(score(professor.profile?.rating)) out of five. Difficulty \(score(professor.profile?.difficulty)) out of five. \(professor.profile?.ratingCount.map { "\($0) ratings." } ?? "Ratings not available.") \(selected ? "Selected." : "View report.")")
            if professor.state == .selectionRequired {
                Button("Choose profile") { model.openChooser(id: professor.id) }.buttonStyle(.link)
            }
            if professor.state == .unavailable || professor.state == .pending {
                Button("Try again") { model.retryProfessor(id: professor.id) }
                    .buttonStyle(.link).disabled(model.isPreviewing(professor.id))
            }
            if professor.state == .unavailable { Link("Check on RMP ↗", destination: professor.searchURL).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
        }
        .padding(15)
        .foregroundStyle(professor.state == .unavailable ? Palette.secondary : .black)
        .background(selected ? Color.white : Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Palette.accent.opacity(0.6) : .clear, lineWidth: 1))
    }
}

private struct ProfessorReport: View {
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
        professor.profile?.reviewCoverage?[ReviewFilter.coverageKey(selectedLabel)]?.finished == true
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
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
                        Text(professor.issue ?? "PCC sections are available below. Ratings and reviews will appear here when retrieved.")
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
                sections
                HStack(spacing: 12) {
                    if let scheduleURL { Link("PCC schedule ↗", destination: scheduleURL).buttonStyle(PillStyle()) }
                    Link("Rate My Professors ↗", destination: professor.sourceURL).buttonStyle(PillStyle())
                }
                if let date = professor.checkedAt {
                    Text("RMP checked \(date.formatted(date: .abbreviated, time: .shortened)). Refresh to check again.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.padding(.horizontal, 38).padding(.vertical, 34).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Professor report")
        .onChange(of: professor.profile?.id) { _, _ in reviewLimit = 3; reviewFilter = .thisCourse }
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
                    Text("Requests this class label from RMP. Reviews for other classes and overall scores stay separate.")
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
                    HStack {
                        Text("CRN \(section.crn)").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(section.delivery).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Text(section.title).font(.system(size: 12))
                    Text(section.dateLabel).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    ForEach(section.meetings, id: \.self) { Text($0).font(.system(size: 12)).foregroundStyle(Palette.secondary) }
                }.padding(17).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct ScoreCard: View {
    let value: Double?
    let title: String
    let helper: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(score(value)).font(.system(size: 57, weight: .medium)).tracking(-2)
                if value != nil { Text("/ 5").font(.system(size: 18)).foregroundStyle(Palette.secondary) }
            }
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(value == nil ? "Not available" : helper).font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(23)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value.map { String(format: "%.1f out of 5", $0) } ?? "not available"). \(helper)")
    }
}
private struct ReviewCard: View {
    let review: Review
    let sourceURL: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(review.course.isEmpty ? "Course not specified" : review.course).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Rating \(score(review.rating))/5 · Difficulty \(score(review.difficulty))/5").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Text(review.excerpt).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
            HStack {
                Text(review.postedLabel).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                Link("Original on RMP ↗", destination: sourceURL).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }.padding(21).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }
}


private struct ProfileChooser: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose RMP profile").font(.title2.weight(.semibold))
            if let professor = model.chooserProfessor {
                Text(professor.name).font(.headline)
                Text([professor.subjectCode, professor.subjectDescription].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(Palette.secondary)
                Text("Profiles stay separate. Choose the profile you want to use for this PCC instructor and subject.")
                    .font(.callout).foregroundStyle(Palette.secondary)
                if model.isPreviewing(professor.id) {
                    ProgressView("Finding profiles…").accessibilityLabel("Loading profile choices")
                }
                if let issue = model.chooserIssue {
                    Text(issue).foregroundStyle(Palette.secondary)
                    Button("Try again") { model.openChooser(id: professor.id) }.disabled(model.isPreviewing(professor.id))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(professor.candidates) { candidate in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(candidate.name).font(.headline)
                                Text("Department: \(candidate.department.isEmpty ? "Unavailable" : candidate.department)")
                                Text(candidate.school).foregroundStyle(Palette.secondary)
                                HStack {
                                    Link("View on RMP ↗", destination: candidate.url)
                                    Spacer()
                                    Button("Use this profile") { model.chooseProfile(id: professor.id, profileID: candidate.id) }
                                        .disabled(model.isPreviewing(professor.id))
                                        .accessibilityLabel("Use \(candidate.name), \(candidate.department.isEmpty ? "department unavailable" : candidate.department), profile \(candidate.id)")
                                }
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                if professor.candidates.isEmpty && !model.isPreviewing(professor.id) {
                    Text("No eligible profile is available. Retry this professor or check the source.")
                    Link("Check on RMP ↗", destination: professor.searchURL)
                }
            }
            HStack { Spacer(); Button("Close") { model.chooserID = nil }.keyboardShortcut(.cancelAction) }
        }.padding(26).frame(width: 560, height: 560).background(Palette.background)
    }
}
