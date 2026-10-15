import SwiftUI
import ClasswiseCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            if model.showingResults { results } else { SearchView(model: model) }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.ink)
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
    private var courseTitle: String {
        model.professors.lazy.flatMap(\.sections).first.map { displayTitle($0.title) } ?? ""
    }
    private var searchSummary: String {
        let days = Weekday.allCases.filter { model.availableDays.contains($0) }.map(\.shortLabel).joined(separator: ", ")
        return [model.searchedTerm?.termName ?? "", days, model.onlineOnly ? "Fully online" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    /// Share of professors whose RMP lookup has finished, for the progress meter.
    private var checkedFraction: Double {
        guard !model.professors.isEmpty else { return 0 }
        let done = model.professors.filter { $0.state != .pending && $0.state != .searching }.count
        return Double(done) / Double(model.professors.count)
    }
    private var results: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Brand(compact: true)
                Rectangle().fill(Palette.line).frame(width: 1, height: 22)
                if let course = model.course { CourseChip(text: course.display) }
                Text(courseTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(searchSummary).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineLimit(1)
                Spacer()
                Button("Refresh") { model.refresh() }.buttonStyle(PillStyle()).disabled(model.busy)
                Button("Change search") { model.changeSearch() }.buttonStyle(PillStyle())
            }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 18)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(spacing: 0) {
                professorList.frame(width: 300).background(Palette.paper2)
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
                    if model.filtered.isEmpty {
                        emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        CourseOverview(course: model.course, title: courseTitle, summary: searchSummary,
                                       professors: model.filtered).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            footer
        }
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No matching classes").font(BYEFont.display(28))
            Text(!model.availableDays.isEmpty
                 ? (model.onlineOnly ? "Try changing or clearing Class days, or turning off Fully online only." : "Try changing or clearing Class days to see other schedules.")
                 : (model.onlineOnly ? "Try turning off Fully online only." : "PCC may not offer this course in the selected semester."))
                .font(.system(size: 14)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            HStack(spacing: 10) {
                if !model.availableDays.isEmpty {
                    Button("Clear days") { model.availableDays.removeAll() }.buttonStyle(PillStyle(primary: true))
                }
                if model.onlineOnly {
                    Button("Show all formats") { model.onlineOnly = false }.buttonStyle(PillStyle(primary: model.availableDays.isEmpty))
                }
            }
            if let url = model.scheduleURL { Link("Check PCC’s schedule ↗", destination: url).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink) }
        }.padding(40)
    }
    private var professorList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(title: "Your options")
                Text("Professors").font(BYEFont.display(24))
                Text("\(model.sectionCount) \(model.sectionCount == 1 ? "section" : "sections") · \(model.filtered.count) \(model.filtered.count == 1 ? "professor" : "professors")")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Picker("Sort professors", selection: $model.sort) {
                    ForEach(ProfessorSort.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Sort professors").pickerStyle(.menu)
                FilterCard(onlineOnly: $model.onlineOnly, days: $model.availableDays)
                if model.busy {
                    Text("Ratings appear as each professor is checked. Pending results are not ranked yet.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                }
                VStack(spacing: 10) {
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
                ProgressMeter(fraction: checkedFraction)
                Text(model.progress).font(.system(size: 12))
                Button("Cancel") { model.cancel() }.buttonStyle(TextLinkStyle())
            } else if model.loadingDetails {
                ProgressView().controlSize(.small)
                Text(model.detailProgress ?? "Loading this professor’s report…").font(.system(size: 12))
                Button("Stop loading") { model.cancelDetails() }.buttonStyle(TextLinkStyle())
            } else {
                Circle().fill(Palette.highlight).frame(width: 6, height: 6)
                Text(model.summariesEnabled ? "PCC schedule · Rate My Professors · AI summaries run on your Mac" : "PCC schedule · Rate My Professors")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
        }.padding(.horizontal, 28).padding(.vertical, 12)
            .background(Palette.paper2)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

/// What the results open on: neutral facts about the class and a nudge to pick a professor.
/// It never names, ranks or recommends anyone.
struct CourseOverview: View {
    let course: Course?
    let title: String
    let summary: String
    let professors: [Professor]
    private var sections: [ClasswiseCore.Section] {
        var seen = Set<String>()
        return professors.flatMap(\.sections).filter { seen.insert($0.crn).inserted }
    }
    private var seatsOpen: String {
        let known = sections.compactMap { $0.details?.seatsOpen }
        return known.isEmpty ? "—" : "\(known.reduce(0, +))"
    }
    private func breakdown(_ labels: [String]) -> String {
        let counts = Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(title: "Course overview")
                    HStack(spacing: 10) {
                        if let course { CourseChip(text: course.display) }
                        Text(summary).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }
                    Text(title).font(BYEFont.display(38)).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    stat("\(sections.count)", sections.count == 1 ? "section" : "sections")
                    stat("\(professors.count)", professors.count == 1 ? "professor" : "professors")
                    stat(seatsOpen, "seats open")
                }
                VStack(alignment: .leading, spacing: 8) {
                    let formats = breakdown(sections.map(\.formatLabel))
                    let terms = breakdown(sections.compactMap { $0.details?.termPart }.filter { !$0.isEmpty })
                    if !formats.isEmpty { fact("Format", formats) }
                    if !terms.isEmpty { fact("Term", terms) }
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.left").font(.system(size: 14, weight: .semibold)).padding(.top, 2)
                    Text("Choose a professor on the left to see their sections, ratings and student reviews.")
                        .font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
                Text("Ratings reflect student feedback across reviewed courses. They don’t guarantee a grade.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 40).padding(.vertical, 36).frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }.accessibilityLabel("Course overview")
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(BYEFont.display(34))
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondary)
        }.sunkenPanel(padding: 18)
            .accessibilityElement(children: .combine)
    }
    private func fact(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name).font(.system(size: 12, weight: .semibold)).frame(width: 56, alignment: .leading)
            Text(value).font(.system(size: 13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A short yellow bar showing how many professors have been checked.
struct ProgressMeter: View {
    let fraction: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.line)
            Capsule().fill(Palette.highlight).frame(width: max(8, 120 * min(1, fraction)))
        }.frame(width: 120, height: 6)
            .animation(.easeOut(duration: 0.2), value: fraction)
            .accessibilityElement().accessibilityLabel("Progress").accessibilityValue("\(Int(fraction * 100)) percent")
    }
}
