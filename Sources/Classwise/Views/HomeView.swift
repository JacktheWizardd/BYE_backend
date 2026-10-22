import SwiftUI
import ClasswiseCore

/// Home is the search: a greeting, one big class field with suggestions as you type, the semester and Find professors.
struct HomeView: View {
    @ObservedObject var model: AppModel
    @FocusState private var fieldFocused: Bool
    @State private var highlighted: Int?
    @State private var dismissed = false
    /// Text the app put in the field (a picked suggestion); it must not reopen the list.
    @State private var settledText: String?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Morning" : hour < 18 ? "Hey" : "Evening"
    }
    private var suggestions: [CourseSuggestion] { dismissed ? [] : Array(model.suggestions.prefix(6)) }
    private var suggestionsOpen: Bool { fieldFocused && !suggestions.isEmpty }
    private var canSearch: Bool { !model.busy && !model.terms.isEmpty && !model.input.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 14) {
            greetingRow.fadeIn(0)
            Text("What are you taking next term?").font(.system(size: 16)).foregroundStyle(Palette.body).fadeIn(1)
            searchForm.padding(.top, 10).zIndex(10).fadeIn(2)
            tip.padding(.top, 8).fadeIn(3)
            hints.fadeIn(4)
        }
        .frame(maxWidth: 520).padding(.horizontal, 40).padding(.vertical, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            Sticker(text: "BYE never ranks professors. Promise.", tilt: -3, weight: .semibold)
                .padding(22).allowsHitTesting(false)
        }
        .onAppear { fieldFocused = true; model.updateCourseSuggestions() }
        .onChange(of: model.input) { _, value in
            // Class codes are always shown in capitals, as on Windows.
            let upper = value.uppercased()
            if upper != value { model.input = upper; return }
            if value == settledText { return }
            settledText = nil; dismissed = false; highlighted = nil; model.updateCourseSuggestions()
        }
        .onChange(of: model.termID) { _, _ in model.updateCourseSuggestions() }
        .onChange(of: model.commandMenuOpen) { _, open in if !open { fieldFocused = true } }
    }

    private var greetingRow: some View {
        HStack(alignment: .top, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if model.displayName.isEmpty { Text("\(greeting).") }
                else {
                    Text("\(greeting), ")
                    SwipedWord(text: model.displayName, size: 40)
                    Text(".")
                }
            }
            .font(BYEFont.display(40, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.displayName.isEmpty ? "\(greeting)." : "\(greeting), \(model.displayName).")
            .accessibilityAddTraits(.isHeader)
            if let term = model.selectedTerm { Sticker(text: term.termName).offset(y: -10).accessibilityHidden(true) }
        }
    }

    private var searchForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            classField.zIndex(1)
            HStack(spacing: 10) {
                Text("Semester").font(.system(size: 13, weight: .semibold))
                Picker("Semester", selection: $model.termID) {
                    if model.terms.isEmpty { Text(model.loadingTerms ? "Loading semesters…" : "Select semester").tag("") }
                    ForEach(model.terms) { Text($0.termName).tag($0.id) }
                }
                .labelsHidden().pickerStyle(.menu).frame(minWidth: 160, alignment: .leading).fixedSize()
                .disabled(model.terms.isEmpty).accessibilityLabel("Semester")
                Spacer(minLength: 8)
                Button("Find professors →", action: submit).buttonStyle(StickerButtonStyle()).disabled(!canSearch)
            }
            if model.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(model.progress).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    Button("Cancel") { model.cancel() }.buttonStyle(TextLinkStyle())
                }
                .accessibilityElement(children: .contain)
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.system(size: 13)).foregroundStyle(Palette.body).fixedSize(horizontal: false, vertical: true)
                    if model.terms.isEmpty && !model.loadingTerms {
                        Button("Retry semesters") { Task { await model.loadTerms() } }.buttonStyle(TextLinkStyle())
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.paper2, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    /// The big field with a hard ink shadow that presses in while focused.
    private var classField: some View {
        let shape = RoundedRectangle(cornerRadius: BYERadius.lg)
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(Palette.secondary)
            TextField("MATH 5A", text: $model.input)
                .textFieldStyle(.plain).font(BYEFont.mono(18)).autocorrectionDisabled()
                .focused($fieldFocused)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    guard suggestionsOpen else { return .ignored }
                    dismissed = true; highlighted = nil; return .handled
                }
                .accessibilityLabel("Class").accessibilityHint("For example, ETH 014 or POLS C1000")
            Keycap(text: "↵")
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: BYEBorder.sticker))
        .background(shape.fill(Palette.ink).offset(x: fieldFocused ? 1 : 3, y: fieldFocused ? 1 : 3))
        .offset(x: fieldFocused ? 2 : 0, y: fieldFocused ? 2 : 0)
        .animation(.easeOut(duration: 0.2), value: fieldFocused)
        .overlay(alignment: .topLeading) {
            if suggestionsOpen { suggestionList.offset(y: 64) }
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button { choose(suggestion) } label: {
                    HStack(spacing: 12) {
                        Text(suggestion.course.display).font(BYEFont.mono(13)).frame(width: 100, alignment: .leading)
                        Text(displayTitle(suggestion.title)).font(.system(size: 13)).foregroundStyle(Palette.body).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 44)
                    .background(highlighted == index ? Palette.tile : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { highlighted = index } }
                .accessibilityLabel("Use \(suggestion.course.display), \(displayTitle(suggestion.title))")
                .accessibilityAddTraits(highlighted == index ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
        .byeShadow(BYEShadow.float)
        .accessibilityElement(children: .contain).accessibilityLabel("Matching PCC courses")
    }

    private var tip: some View {
        (Text("Type a class code like ") + Text("ETH 014").font(BYEFont.mono(14)).foregroundStyle(Palette.ink)
            + Text(" or ") + Text("POLS C1000").font(BYEFont.mono(14)).foregroundStyle(Palette.ink)
            + Text(". We’ll round up every section, seat and review so you know what you’re signing up for."))
            .font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(3)
            .multilineTextAlignment(.center).frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
    }

    private var hints: some View {
        HStack(spacing: 6) {
            Keycap(text: "⌘K"); Text("anywhere ·")
            Keycap(text: "↑"); Keycap(text: "↓"); Text("to move ·")
            Keycap(text: "↵"); Text("to open")
        }
        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Command K opens the command menu anywhere. Arrow keys move, Return opens.")
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard suggestionsOpen else { return .ignored }
        let next = (highlighted ?? (delta > 0 ? -1 : suggestions.count)) + delta
        highlighted = min(max(next, 0), suggestions.count - 1)
        return .handled
    }
    private func choose(_ suggestion: CourseSuggestion) {
        settledText = suggestion.course.display; model.chooseSuggestion(suggestion); dismissed = true; highlighted = nil; fieldFocused = true
    }
    private func submit() {
        if suggestionsOpen, let highlighted, suggestions.indices.contains(highlighted) { choose(suggestions[highlighted]); return }
        guard canSearch else { return }
        dismissed = true; model.start()
    }
}
