import SwiftUI
import ClasswiseCore

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
                        Text(!model.availableDays.isEmpty
                             ? (model.onlineOnly ? "Try changing or clearing Class days, or turning off Fully online only." : "Try changing or clearing Class days to see other schedules.")
                             : (model.onlineOnly ? "Try turning off Fully online only." : "PCC may not offer this course in the selected semester."))
                            .foregroundStyle(Palette.secondary)
                        if !model.availableDays.isEmpty {
                            Button("Clear days") { model.availableDays.removeAll() }.buttonStyle(PillStyle())
                        }
                        if model.onlineOnly {
                            Button("Show all formats") { model.onlineOnly = false }.buttonStyle(PillStyle())
                        }
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
                Text("\(model.sectionCount) \(model.sectionCount == 1 ? "section" : "sections") · \(model.filtered.count) \(model.filtered.count == 1 ? "professor" : "professors")")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                if model.busy {
                    Text("Ratings appear as each professor is checked. Pending results are not ranked yet.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                }
                Picker("Sort professors", selection: $model.sort) {
                    ForEach(ProfessorSort.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().accessibilityLabel("Sort professors").pickerStyle(.menu)
                Toggle("Fully online only", isOn: $model.onlineOnly).toggleStyle(.checkbox).font(.system(size: 12))
                AvailableDaysPicker(selection: $model.availableDays)
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
                Text(model.summariesEnabled ? "PCC schedule · Rate My Professors · AI summaries run on your Mac" : "PCC schedule · Rate My Professors")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
        }.padding(.horizontal, 28).padding(.vertical, 13).background(Palette.surface)
    }
}
