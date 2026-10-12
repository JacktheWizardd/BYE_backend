import SwiftUI
import ClasswiseCore

struct SearchView: View {
    @ObservedObject var model: AppModel
    @FocusState private var courseFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Brand()
                Spacer()
                Text("PASADENA CITY COLLEGE").font(.system(size: 10, weight: .medium)).tracking(1.8).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 40).padding(.top, 38)
            GeometryReader { geometry in
                ScrollView {
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
                        AvailableDaysPicker(selection: $model.availableDays).padding(.top, 20)
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
                        .padding(.vertical, 24).frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                }
            }
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
