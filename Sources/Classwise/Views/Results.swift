import SwiftUI
import ClasswiseCore

/// Results: course header, filters and the professor list on the left, the professor page (or the neutral overview) on the right.
struct ResultsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(spacing: 0) {
                ProfessorColumn(model: model).frame(width: 300).background(Palette.paper2)
                Rectangle().fill(Palette.line).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let course = model.course {
                Text(course.display).font(BYEFont.mono(12)).foregroundStyle(Palette.paper)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Palette.ink, in: RoundedRectangle(cornerRadius: BYERadius.sm))
            }
            Text(model.courseTitle).font(BYEFont.display(17, bold: true)).lineLimit(1)
            Text(model.searchSummary).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
            if let metadata = model.scheduleMetadata {
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    Text(metadata.expired(at: context.date) ? "Older schedule · seat counts hidden" : "Checked \(max(0, Int(context.date.timeIntervalSince(metadata.checkedAt ?? context.date) / 60))) min ago")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Refresh") { model.refresh() }.buttonStyle(StickerButtonStyle(kind: .secondary)).disabled(model.busy)
            Button("Change search") { model.goHome() }.buttonStyle(StickerButtonStyle(kind: .secondary))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var detail: some View {
        if let professor = model.selected, let course = model.course {
            // Kept mounted while switching professors, so numbers glide and nothing flashes.
            ProfessorReport(model: model, professor: professor, course: course, scheduleURL: model.scheduleURL,
                            checkingRatings: model.busy,
                            loadingDetails: model.loadingDetailsID == professor.id || model.retryingIDs.contains(professor.id),
                            detailCancelled: model.detailCancelled,
                            retrying: model.retryingIDs.contains(professor.id), canRetry: !model.busy && !model.loadingDetails) {
                model.retrySummary(id: professor.id)
            }
        } else if model.filtered.isEmpty {
            if !model.busy { NoMatches(model: model) }
        } else {
            CourseOverview(course: model.course, title: model.courseTitle, summary: model.searchSummary, stats: CourseOverviewStats(professors: model.filtered))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.busy {
                ProgressMeter(fraction: model.checkedFraction)
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
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Palette.paper2)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

/// The left column: counts, "I'm free" days, Online only, the sort and the list.
private struct ProfessorColumn: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Professors").font(BYEFont.display(22, bold: true)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(plural(model.sectionCount, "section")) · \(plural(model.filtered.count, "professor"))")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DayBubbles(selection: $model.availableDays, disabled: model.onlineOnly)
                    Button { model.onlineOnly.toggle() } label: {
                        Text("Online only").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.onlineOnly ? Palette.paper : Palette.ink)
                            .padding(.horizontal, 12).frame(minHeight: 30)
                            .background(model.onlineOnly ? Palette.ink : Palette.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(model.onlineOnly ? Palette.ink : Palette.tileLine, lineWidth: BYEBorder.control))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Fully online only")
                    .accessibilityAddTraits(model.onlineOnly ? .isSelected : [])
                }
                Segmented(label: "Sort professors", options: [(.rating, "Rating"), (.difficulty, "Difficulty"), (.reviews, "Reviews")],
                          selection: $model.sort)
                if model.busy && model.professors.isEmpty { LoadingRows() }
                if model.busy && !model.professors.isEmpty {
                    Text("Ratings appear as each professor is checked. Pending results are not ranked yet.")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ProfessorList(model: model)
                if !model.showAll && model.filtered.count > 5 {
                    Button("View all \(model.filtered.count) professors") { model.showAll = true }
                        .buttonStyle(StickerButtonStyle(kind: .secondary)).frame(maxWidth: .infinity)
                }
                if model.showAll && model.filtered.count > 5 {
                    Button("Show top five") { model.showAll = false }.buttonStyle(StickerButtonStyle(kind: .ghost))
                }
                Text(disclaimer).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .accessibilityLabel("Professor results")
    }
}

/// "I'm free" day bubbles. Results filter as soon as a day is toggled; a toggled bubble pops.
struct DayBubbles: View {
    @Binding var selection: Set<Weekday>
    var disabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped: Weekday?
    private func label(_ day: Weekday) -> String {
        switch day {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "Th"
        case .friday: "F"
        case .saturday: "Sa"
        case .sunday: "Su"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("I’m free").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondary)
                Spacer()
                if !selection.isEmpty && !disabled {
                    Button("Clear") { selection.removeAll() }.buttonStyle(TextLinkStyle())
                }
            }
            HStack(spacing: 4) {
                ForEach(Weekday.allCases) { day in
                    let on = selection.contains(day)
                    Button {
                        if on { selection.remove(day) } else { selection.insert(day) }
                        popped = day
                    } label: {
                        Text(label(day)).font(.system(size: 11, weight: .bold))
                            .foregroundStyle(on ? Palette.paper : Palette.ink)
                            .frame(width: 34, height: 34)
                            .background(on ? Palette.ink : Palette.card, in: Circle())
                            .overlay(Circle().strokeBorder(on ? Palette.ink : Palette.tileLine, lineWidth: BYEBorder.control))
                            .contentShape(Circle())
                            .phaseAnimator([0, 1, 2], trigger: reduceMotion || popped != day ? false : on) { content, phase in
                                content.scaleEffect(phase == 1 ? 0.85 : phase == 2 ? 1.08 : 1)
                            } animation: { _ in .spring(response: 0.18, dampingFraction: 0.6) }
                    }
                    .buttonStyle(.plain)
                    .disabled(disabled)
                    .opacity(disabled ? 0.4 : 1)
                    .accessibilityLabel(day.rawValue)
                    .accessibilityValue(on ? "Selected" : "Not selected")
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("available-day-" + day.rawValue.lowercased())
                }
            }
            if !selection.isEmpty && !disabled {
                Text("Shows classes that meet on every picked day. Fully online classes still show.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("I’m free (class days)")
    }
}

/// A segmented control whose white thumb slides to the chosen option.
struct Segmented<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, text in
                let on = value == selection
                Button { selection = value } label: {
                    Text(text).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Palette.ink : Palette.body)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7).fill(Palette.card)
                                    .shadow(color: Palette.ink.opacity(0.15), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Palette.tile, in: RoundedRectangle(cornerRadius: 9))
        .animation(BYEMotion.glide(reduce: reduceMotion), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// The professor list. The open professor gets an outlined highlight that slides between rows, rows glide when
/// re-sorted, and ↑ ↓ move between professors (opening them, as on Windows).
private struct ProfessorList: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 4) {
            ForEach(model.displayed) { professor in
                ProfessorRow(model: model, professor: professor, selected: model.selectedID == professor.id) {
                    model.selectedID = professor.id
                }
                .anchorPreference(key: RowBounds.self, value: .bounds) { [professor.id: $0] }
            }
        }
        // One highlight that always exists and glides to the open row. A new click retargets it from wherever it is,
        // so fast clicks never cross-fade two copies (which skipped frames and flashed the ink shadow).
        .backgroundPreferenceValue(RowBounds.self) { rows in
            GeometryReader { proxy in
                if let id = model.selectedID, let anchor = rows[id] {
                    let frame = proxy[anchor]
                    StickerHighlight()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .animation(BYEMotion.glide(reduce: reduceMotion), value: id)
                        // Re-sorting moves the open row with the same spring as the rows.
                        .animation(BYEMotion.spring(reduce: reduceMotion), value: model.displayed.map(\.id))
                        .transition(.opacity)
                }
            }
        }
        .animation(BYEMotion.spring(reduce: reduceMotion), value: model.displayed.map(\.id))
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
    }
    private func move(_ delta: Int) -> KeyPress.Result {
        let list = model.displayed
        guard !list.isEmpty else { return .ignored }
        let at = list.firstIndex { $0.id == model.selectedID } ?? (delta > 0 ? -1 : list.count)
        model.selectedID = list[min(max(at + delta, 0), list.count - 1)].id
        return .handled
    }
}

private struct RowBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The ink sticker behind the open professor: card fill, ink outline and a hard 2pt ink shadow, drawn as one shape.
private struct StickerHighlight: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        ZStack {
            shape.fill(Palette.ink).offset(x: 2, y: 2)
            shape.fill(Palette.card)
            shape.strokeBorder(Palette.ink, lineWidth: BYEBorder.sticker)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

private struct ProfessorRow: View {
    @ObservedObject var model: AppModel
    let professor: Professor
    let selected: Bool
    let select: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: select) {
                HStack(spacing: 10) {
                    Avatar(name: professor.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(professor.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Group {
                            if let profile = professor.profile {
                                Text("Difficulty \(score(profile.difficulty)) · \(profile.wouldTakeAgain.map { "\(Int($0.rounded()))% would take again" } ?? "take-again rate unavailable")")
                                Text("\(profile.ratingCount.map { plural($0, "rating") } ?? "Rating count unavailable") · \(plural(professor.sections.count, "section"))")
                            } else {
                                Text(professor.listStatus)
                                Text(plural(professor.sections.count, "section"))
                            }
                        }
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        if professor.profile != nil { RatingBar(value: professor.profile?.rating, track: Palette.tile).frame(height: 4).padding(.top, 3) }
                    }
                    Spacer(minLength: 0)
                    Text(score(professor.profile?.rating)).font(BYEFont.display(19, bold: true)).monospacedDigit()
                        .foregroundStyle(professor.profile == nil ? Palette.secondary : Palette.ink)
                        .contentTransition(.numericText(value: professor.profile?.rating ?? 0))
                        .animation(BYEMotion.count(reduce: reduceMotion), value: professor.profile?.rating)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(professor.name). Rating \(score(professor.profile?.rating)) out of five. Difficulty \(score(professor.profile?.difficulty)) out of five. \(professor.profile?.ratingCount.map { "\($0) ratings." } ?? "Ratings not available.")")
            .accessibilityAddTraits(selected ? .isSelected : [])
            if professor.state == .selectionRequired || professor.state == .unavailable || professor.state == .pending {
                HStack(spacing: 12) {
                    if professor.state == .selectionRequired {
                        Button("Choose profile") { model.openChooser(id: professor.id) }.buttonStyle(TextLinkStyle())
                    } else {
                        Button("Try again") { model.retryProfessor(id: professor.id) }
                            .buttonStyle(TextLinkStyle()).disabled(model.isPreviewing(professor.id))
                    }
                    if professor.state == .unavailable {
                        Link("Check on RMP ↗", destination: professor.searchURL).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(10)
        .background {
            if hovering && !selected { RoundedRectangle(cornerRadius: 10).fill(Palette.tile.opacity(0.6)) }
        }
        .onHover { hovering = $0 }
    }
}

/// Skeleton rows while the schedule loads, with a little rotating copy (still with Reduce Motion).
private struct LoadingRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let copy = ["Asking around…", "Reading the PCC schedule…", "Counting open seats…"]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1.2)) { context in
                let index = reduceMotion ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 1.2) % Self.copy.count
                Text(Self.copy[index]).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 10) {
                    Circle().fill(Palette.tile).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(Palette.tile).frame(width: 140, height: 8)
                        Capsule().fill(Palette.tile).frame(width: 90, height: 6)
                    }
                }
                .padding(10)
                .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { content, opacity in content.opacity(opacity) }
                    animation: { _ in .easeInOut(duration: 0.5) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading professors")
    }
}

/// What the results open on: neutral facts about the class and a nudge to pick a professor.
/// It never names, ranks or recommends anyone.
struct CourseOverview: View {
    let course: Course?
    let title: String
    let summary: String
    let stats: CourseOverviewStats
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DrawnArrow().frame(width: 78, height: 44)
                Text("Pick a professor.").font(BYEFont.display(26, bold: true)).accessibilityAddTraits(.isHeader)
                Text("We line them up, you decide. BYE won’t choose for you.").font(.system(size: 14)).foregroundStyle(Palette.body)
                Text([course?.display, title, summary].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                HStack(spacing: 8) {
                    StatTile(value: Double(stats.sectionCount), digits: 0, label: stats.sectionCount == 1 ? "section" : "sections")
                    StatTile(value: Double(stats.professorCount), digits: 0, label: stats.professorCount == 1 ? "professor" : "professors")
                    if let openSeats = stats.openSeats { StatTile(value: Double(openSeats), digits: 0, label: "open seats") }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                VStack(alignment: .leading, spacing: 6) {
                    if !stats.formats.isEmpty { fact("Format", stats.formats) }
                    if !stats.terms.isEmpty { fact("Term", stats.terms) }
                }
                Text("Choose a professor on the left to see their sections, ratings and student reviews.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(disclaimer).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 40).padding(.vertical, 48).frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Course overview")
    }
    private func fact(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(name).font(.system(size: 12, weight: .semibold)).frame(width: 56, alignment: .leading)
            Text(value).font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// When filters hide every section.
private struct NoMatches: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No matching classes").font(BYEFont.display(26, bold: true)).accessibilityAddTraits(.isHeader)
            Text(!model.availableDays.isEmpty
                 ? (model.onlineOnly ? "Try changing or clearing your days, or turning off Online only." : "Nobody teaches this on all of those days. Try unticking a day.")
                 : (model.onlineOnly ? "Try turning off Online only." : "PCC may not offer this course in the selected semester."))
                .font(.system(size: 14)).foregroundStyle(Palette.body).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if !model.availableDays.isEmpty {
                    Button("Clear days") { model.availableDays.removeAll() }.buttonStyle(StickerButtonStyle())
                }
                if model.onlineOnly {
                    Button("Show all formats") { model.onlineOnly = false }
                        .buttonStyle(StickerButtonStyle(kind: model.availableDays.isEmpty ? .primary : .secondary))
                }
            }
            if let url = model.scheduleURL {
                Link("Check PCC’s schedule ↗", destination: url).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
            }
        }
        .padding(40).frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The hand-drawn arrow pointing at the list, drawn in once.
private struct DrawnArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    private struct ArrowPath: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / 78
            var path = Path()
            path.move(to: CGPoint(x: 74, y: 10)); path.addCurve(to: CGPoint(x: 9, y: 30), control1: CGPoint(x: 52, y: 2), control2: CGPoint(x: 24, y: 6))
            path.move(to: CGPoint(x: 5, y: 17)); path.addLine(to: CGPoint(x: 9, y: 31)); path.addLine(to: CGPoint(x: 22, y: 27))
            return path.applying(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
    var body: some View {
        ArrowPath().trim(from: 0, to: drawn || reduceMotion ? 1 : 0)
            .stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
            .onAppear { withAnimation(BYEMotion.swipe(reduce: reduceMotion)?.delay(0.3)) { drawn = true } }
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

let disclaimer = "Ratings reflect student feedback across reviewed courses. They don’t guarantee a grade."

func plural(_ count: Int, _ noun: String) -> String { "\(count) \(count == 1 ? noun : noun + "s")" }
