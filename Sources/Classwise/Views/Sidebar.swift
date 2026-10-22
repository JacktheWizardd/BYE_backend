import SwiftUI
import ClasswiseCore

/// The v3 sidebar: wordmark, Search ⌘K, Home, Your classes (in the order added) and the student's profile.
struct Sidebar: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight
    @State private var hoveredClass: String?

    private enum Item: Hashable { case home, course(String) }
    private var active: Item? {
        switch model.route {
        case .home: .home
        case .results: model.course.map { .course($0.display) }
        case .welcome, .name, .number: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Brand(compact: true).padding(.leading, 6)
            Button { model.commandMenuOpen = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold))
                    Text("Search")
                    Spacer(minLength: 4)
                    Keycap(text: "⌘K")
                }
                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                .padding(.horizontal, 9).frame(minHeight: 32)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.tileLine))
                .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain).accessibilityLabel("Search classes").accessibilityHint("Command K")
            VStack(alignment: .leading, spacing: 2) {
                row(.home, isActive: active == .home) {
                    Label("Home", systemImage: "house").font(.system(size: 13))
                } action: { model.goHome() }
                if !model.recentClasses.isEmpty {
                    Text("Your classes").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.secondary)
                        .padding(.leading, 9).padding(.top, 14).padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.recentClasses, id: \.display) { course in
                        row(.course(course.display), isActive: active == .course(course.display)) {
                            Text(course.display).font(BYEFont.mono(12))
                        } action: { model.openClass(course) }
                        .accessibilityLabel("Open \(course.display)")
                        .overlay(alignment: .trailing) {
                            RemoveClassButton(course: course, rowHovered: hoveredClass == course.display) { model.removeClass(course) }
                        }
                        .onHover { inside in
                            if inside { hoveredClass = course.display } else if hoveredClass == course.display { hoveredClass = nil }
                        }
                        .contextMenu { Button("Remove from Your classes") { model.removeClass(course) } }
                        .accessibilityAction(named: "Remove from Your classes") { model.removeClass(course) }
                    }
                }
            }
            .animation(BYEMotion.spring(reduce: reduceMotion), value: active)
            Spacer(minLength: 12)
            profile
        }
        .padding(.horizontal, 10).padding(.top, 38).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper2)
        .foregroundStyle(Palette.ink)
    }

    private func row(_ item: Item, isActive: Bool, @ViewBuilder label: () -> some View, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label().frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).frame(minHeight: 32)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 8).fill(Palette.card)
                            .shadow(color: Palette.ink.opacity(0.12), radius: 1, y: 1)
                            .matchedGeometryEffect(id: "sidebar-highlight", in: highlight)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var profile: some View {
        Button { model.settingsTab = .general } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Palette.ink)
                    if let initial = model.displayName.first {
                        Text(String(initial).uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.paper)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 11)).foregroundStyle(Palette.paper)
                    }
                }.frame(width: 26, height: 26)
                Text(model.displayName.isEmpty ? "Guest" : model.displayName)
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Palette.secondary)
            }
            .padding(6).frame(minHeight: 40)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.displayName.isEmpty ? "Guest" : model.displayName), settings")
    }
}

/// The × that removes a class from Your classes. It shows while the row is hovered or the × has keyboard focus, as on Windows.
private struct RemoveClassButton: View {
    let course: Course
    let rowHovered: Bool
    let remove: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: remove) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.secondary)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused)
        .opacity(rowHovered || focused ? 1 : 0)
        .padding(.trailing, 4)
        .help("Remove \(course.display) from Your classes")
        .accessibilityLabel("Remove \(course.display) from Your classes")
    }
}

/// A small keyboard key, as in "⌘K anywhere".
struct Keycap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 5).frame(minHeight: 16)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.tileLine))
            .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 5).fill(Palette.tileLine).frame(height: 1) }
            .accessibilityHidden(true)
    }
}
