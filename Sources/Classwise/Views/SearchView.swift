import SwiftUI
import ClasswiseCore

struct SearchView: View {
    @ObservedObject var model: AppModel
    @FocusState private var courseFocused: Bool
    private let field = RoundedRectangle(cornerRadius: 10)
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find your").font(BYEFont.display(52))
                            Highlighted(text: "professor.", font: BYEFont.display(52))
                        }.padding(.top, 18).padding(.bottom, 14)
                            .accessibilityElement(children: .combine)
                        Text("Your class. Your semester. A clearer choice.")
                            .font(.system(size: 16)).foregroundStyle(Palette.secondary).padding(.bottom, 34)
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Class").font(.system(size: 13, weight: .semibold))
                                TextField("Enter your course", text: $model.input).textFieldStyle(.plain)
                                    .font(.system(size: 17)).padding(14).background(Palette.card, in: field)
                                    .overlay(field.strokeBorder(courseFocused ? Palette.ink : Palette.lineStrong, lineWidth: 1.5))
                                    .focused($courseFocused).onSubmit { if !model.busy { model.start() } }
                                    .accessibilityLabel("Class").accessibilityHint("For example, ETH 014 or POLS C1000")
                                    // Float suggestions over the form so they never push the Find button out of view.
                                    .overlay(alignment: .topLeading) {
                                        if showSuggestions {
                                            courseSuggestions.offset(y: 54)
                                        }
                                    }
                                    .zIndex(1) // draw the list above the example line and day buttons below it
                                Text("Example: ETH 014 or POLS C1000").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }.frame(width: 300)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Semester").font(.system(size: 13, weight: .semibold))
                                Picker("Semester", selection: $model.termID) {
                                    if model.terms.isEmpty { Text(model.loadingTerms ? "Loading semesters…" : "Select semester").tag("") }
                                    ForEach(model.terms) { Text($0.termName).tag($0.id) }
                                }.labelsHidden().pickerStyle(.menu).controlSize(.large)
                                    .padding(.horizontal, 10).frame(height: 52).background(Palette.card, in: field)
                                    .overlay(field.strokeBorder(Palette.lineStrong, lineWidth: 1.5)).accessibilityLabel("Semester")
                            }.frame(width: 224)
                        }.zIndex(1)
                        AvailableDaysPicker(selection: $model.availableDays).frame(width: 360).padding(.top, 22)
                        Toggle("Fully online only", isOn: $model.onlineOnly).toggleStyle(.checkbox)
                            .font(.system(size: 13)).padding(.top, 16)
                        HStack(spacing: 15) {
                            Button { model.start() } label: { Label("Find professors", systemImage: "arrow.right").labelStyle(.titleAndIcon) }
                                .buttonStyle(PillStyle(primary: true)).disabled(model.busy || model.terms.isEmpty)
                                .keyboardShortcut(.defaultAction)
                            if model.busy {
                                ProgressView().controlSize(.small)
                                Button("Cancel") { model.cancel() }.buttonStyle(TextLinkStyle())
                            }
                        }.padding(.top, 28)
                        if model.busy { Text(model.progress).font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(.top, 15) }
                        if let error = model.error {
                            Text(error).font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(.top, 18).fixedSize(horizontal: false, vertical: true)
                            if model.terms.isEmpty {
                                Button("Retry semesters") { Task { await model.loadTerms() } }.buttonStyle(TextLinkStyle()).padding(.top, 8)
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
    /// Open only while typing: closed when the field is empty, unfocused, or already holds an exact course code.
    private var showSuggestions: Bool {
        let typed = model.input.trimmingCharacters(in: .whitespaces)
        guard courseFocused, !typed.isEmpty, model.suggestionLoading || !model.suggestions.isEmpty else { return false }
        return !model.suggestions.contains { $0.course.display.caseInsensitiveCompare(typed) == .orderedSame }
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
                            SuggestionRow(suggestion: suggestion) { model.chooseSuggestion(suggestion); courseFocused = true }
                        }
                    }.padding(4)
                }.frame(height: min(CGFloat(model.suggestions.count) * 36 + 8, 116))
                    .accessibilityLabel("Matching PCC courses")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: field)
            .overlay(field.strokeBorder(Palette.line))
            .shadow(color: Palette.ink.opacity(0.12), radius: 14, y: 8)
    }
}

private struct SuggestionRow: View {
    let suggestion: CourseSuggestion
    let choose: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: choose) {
            HStack(spacing: 12) {
                Text(suggestion.course.display).font(BYEFont.mono(12)).frame(width: 96, alignment: .leading)
                Text(displayTitle(suggestion.title)).font(.system(size: 12)).foregroundStyle(hovering ? Palette.ink : Palette.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.padding(.horizontal, 10).padding(.vertical, 9)
                .background(hovering ? Palette.brandSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .accessibilityLabel("Use \(suggestion.course.display), \(suggestion.title)")
    }
}
