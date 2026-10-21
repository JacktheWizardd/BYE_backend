import SwiftUI
import ClasswiseCore

/// ⌘K from anywhere after the first run: jump to a class (PCC matches for the chosen semester,
/// or your recent classes) or run an action. Esc or a click outside closes it.
struct CommandMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var active = 0
    @State private var shown = false
    @FocusState private var focused: Bool

    enum Action: CaseIterable {
        case home, settings, updates, name, welcome
        var label: String {
            switch self {
            case .home: "Go home"
            case .settings: "Open settings"
            case .updates: "Check for updates"
            case .name: "Change your name"
            case .welcome: "Show welcome again"
            }
        }
        var symbol: String {
            switch self {
            case .home: "house"
            case .settings: "gearshape"
            case .updates: "arrow.triangle.2.circlepath"
            case .name: "person.text.rectangle"
            case .welcome: "sparkles"
            }
        }
    }
    private enum Item {
        case course(Course, String)
        case action(Action)
        var key: String {
            switch self {
            case .course(let course, _): "c " + course.display
            case .action(let action): "a " + action.label
            }
        }
    }

    private var needle: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var classes: [Item] {
        needle.isEmpty
            ? model.recentClasses.prefix(3).map { .course($0, "Recent") }
            : model.courseMatches(query).prefix(4).map { .course($0.course, displayTitle($0.title)) }
    }
    private var actions: [Item] {
        Action.allCases.filter { needle.isEmpty || $0.label.lowercased().contains(needle) }.map { .action($0) }
    }
    private var items: [Item] { classes + actions }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.ink.opacity(0.18).ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)
            panel
                .padding(.top, 72)
                .scaleEffect(shown || reduceMotion ? 1 : 0.94, anchor: .top)
                .opacity(shown || reduceMotion ? 1 : 0)
        }
        .onAppear {
            focused = true; model.updateCourseSuggestions()
            withAnimation(BYEMotion.spring(reduce: reduceMotion)) { shown = true }
        }
        .onChange(of: query) { _, _ in active = 0 }
        .onExitCommand { close() }
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").font(.system(size: 15)).foregroundStyle(Palette.secondary)
                TextField("Type a command or a class…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 15)).autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { if items.indices.contains(active) { run(items[active]) } }
                    .onKeyPress(.downArrow) { active = min(active + 1, max(items.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { active = max(active - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .accessibilityLabel("Type a command or a class")
                Keycap(text: "esc")
            }
            .padding(.horizontal, 14).frame(minHeight: 50)
            Rectangle().fill(Palette.line).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !classes.isEmpty { group(needle.isEmpty ? "Your classes" : "Classes") }
                        ForEach(Array(classes.enumerated()), id: \.element.key) { index, item in row(item, index: index) }
                        if !actions.isEmpty { group("Actions") }
                        ForEach(Array(actions.enumerated()), id: \.element.key) { index, item in row(item, index: classes.count + index) }
                        if items.isEmpty {
                            Text("Nothing matches. Try a class code like MATH 5A.")
                                .font(.system(size: 13)).foregroundStyle(Palette.secondary).padding(12)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
                .onChange(of: active) { _, index in
                    if items.indices.contains(index) { proxy.scrollTo(items[index].key) }
                }
            }
        }
        .frame(width: 520)
        .background(Palette.card, in: shape)
        .overlay(shape.strokeBorder(Palette.ink, lineWidth: BYEBorder.sticker))
        .background(shape.fill(Palette.ink).offset(x: 4, y: 4))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command menu")
        .accessibilityAddTraits(.isModal)
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: Item, index: Int) -> some View {
        let isActive = index == active
        return Button { run(item) } label: {
            HStack(spacing: 10) {
                switch item {
                case .course(let course, let title):
                    Text(course.display).font(BYEFont.mono(13)).frame(minWidth: 86, alignment: .leading)
                    Text(title).font(.system(size: 13)).foregroundStyle(Palette.body).lineLimit(1)
                case .action(let action):
                    Image(systemName: action.symbol).font(.system(size: 14)).foregroundStyle(Palette.secondary).frame(width: 20)
                    Text(action.label).font(.system(size: 13))
                }
                Spacer(minLength: 4)
                Keycap(text: "↵").opacity(isActive ? 1 : 0)
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
            .background(isActive ? Palette.tile : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.key)
        .onHover { if $0 { active = index } }
        .accessibilityLabel(accessibilityLabel(item))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func accessibilityLabel(_ item: Item) -> String {
        switch item {
        case .course(let course, let title): "Open \(course.display), \(title)"
        case .action(let action): action.label
        }
    }

    private func close() { model.commandMenuOpen = false }

    private func run(_ item: Item) {
        close()
        switch item {
        case .course(let course, _): model.openClass(course)
        case .action(.home): model.goHome()
        case .action(.settings), .action(.name): model.settingsTab = .general
        case .action(.updates): model.settingsTab = .updates
        case .action(.welcome): model.showWelcomeAgain()
        }
    }
}
