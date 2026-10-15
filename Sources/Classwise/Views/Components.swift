import SwiftUI
import CoreText
import ClasswiseCore

// Colours from the BYE design system (light only): ivory and stone grounds, Jet Black type and
// buttons, warm grey secondary text, and yellow reserved for the wordmark, rating bars and the progress meter.
enum Palette {
    static let paper = Color(hex: 0xFAF8F3)
    static let paper2 = Color(hex: 0xF2EEE6)
    static let card = Color.white
    static let tile = Color(hex: 0xEAE5DB)
    static let tileLine = Color(hex: 0xDDD6C9)
    static let ink = Color(hex: 0x161618)
    static let secondary = Color(hex: 0x6B665E)
    static let line = Color(hex: 0xE2DCD0)
    static let lineStrong = Color(hex: 0x8C857A)
    static let brandSoft = Color(hex: 0xEFE9DD)
    static let highlight = Color(hex: 0xF2C14E)
    static let signal = Color(hex: 0xB8401A)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// Finds a file shipped in Sources/Classwise/Resources, in a packaged app or a `swift run`.
func bundledResource(_ name: String, _ ext: String) -> URL? {
    #if DEBUG
    Bundle.main.url(forResource: name, withExtension: ext) ?? Bundle.module.url(forResource: name, withExtension: ext)
    #else
    // Avoid SwiftPM's absolute developer paths in distributed executables.
    Bundle.main.url(forResource: name, withExtension: ext)
        ?? Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Classwise_Classwise.bundle"))?
            .url(forResource: name, withExtension: ext)
    #endif
}

enum BYEFont {
    static func registerBundledFonts() {
        for name in ["LibreBaskerville-SemiBold", "LibreBaskerville-Bold"] {
            if let url = bundledResource(name, "ttf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
    /// Libre Baskerville for headlines, names and scores.
    static func display(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "LibreBaskerville-Bold" : "LibreBaskerville-SemiBold", size: size)
    }
    /// Course codes and CRNs.
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

struct PillStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, primary: primary) }
    private struct PillBody: View {
        let configuration: ButtonStyle.Configuration
        let primary: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            let shape = Capsule()
            configuration.label.font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 17).frame(minHeight: 34)
                .foregroundStyle(!enabled ? Palette.secondary : primary && !hovering ? Palette.paper : Palette.ink)
                .background(!enabled ? Color.clear : primary ? (hovering ? Palette.highlight : Palette.ink) : Palette.card, in: shape)
                .overlay {
                    if !enabled { shape.strokeBorder(Palette.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) }
                    else if !primary { shape.strokeBorder(hovering ? Palette.ink : Palette.lineStrong, lineWidth: 1.5) }
                }
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(shape)
                .onHover { hovering = $0 }
        }
    }
}

/// Small underlined text action, used where a full pill would be too loud.
struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).underline()
            .opacity(configuration.isPressed ? 0.6 : 1).contentShape(Rectangle())
    }
}

struct Eyebrow: View {
    let title: String
    var body: some View { Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.secondary) }
}

func score(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }

/// The BYE wordmark: Libre Baskerville Bold over a yellow highlighter swipe.
struct Brand: View {
    var compact = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("BYE").font(BYEFont.display(compact ? 21 : 25, bold: true)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 3)
                .background(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 5).fill(Palette.highlight).frame(height: compact ? 8 : 9).offset(y: -3)
                }
            if !compact { Text("Before You Enroll").font(.system(size: 13)).foregroundStyle(Palette.secondary) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("BYE, Before You Enroll")
    }
}

/// Words with a highlighter swipe behind their lower half.
struct Highlighted: View {
    let text: String
    let font: Font
    var body: some View {
        Text(text).font(font).padding(.horizontal, 2)
            .background(alignment: .bottom) { Rectangle().fill(Palette.highlight).frame(height: 18).offset(y: -6) }
    }
}

struct CourseChip: View {
    let text: String
    var body: some View {
        Text(text).font(BYEFont.mono(12)).foregroundStyle(Palette.ink)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Palette.paper2, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
    }
}

struct Tag: View {
    enum Kind { case info, term, signal }
    let text: String
    var kind: Kind = .info
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8)
            .foregroundStyle(kind == .signal ? Color.white : Palette.ink)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(kind == .info ? Palette.brandSoft : kind == .term ? Palette.card : Palette.signal, in: shape)
            .overlay { if kind == .term { shape.strokeBorder(Palette.line) } }
    }
}

struct RatingBar: View {
    let value: Double?
    var track: Color = Palette.card
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Palette.highlight).frame(width: geometry.size.width * min(1, max(0, (value ?? 0) / 5)))
            }
        }.frame(height: 6).accessibilityHidden(true)
    }
}

/// Open seats with a capacity bar and the waitlist, from PCC's schedule.
struct SeatMeter: View {
    let details: SectionDetails?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let open = details?.seatsOpen {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(open)").font(BYEFont.display(22, bold: true)).foregroundStyle(Palette.ink)
                    Text(details?.capacity.map { "of \($0) seats open" } ?? (open == 1 ? "seat open" : "seats open"))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                // The bar fills as seats are taken, so a full class reads as a full bar.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.card)
                        Capsule().fill(barColor(open: open))
                            .frame(width: geometry.size.width * takenFraction(open: open))
                    }
                }.frame(height: 6)
                Text(waitlist).font(.system(size: 11, weight: details?.isFull == true ? .semibold : .regular))
                    .foregroundStyle(details?.isFull == true ? Palette.signal : Palette.secondary)
            } else {
                Text("Seats unavailable").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }
        .padding(.leading, 18)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.line).frame(width: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(details?.seatsOpen.map { "\($0) seats open. \(waitlist)" } ?? "Seats unavailable")
    }
    /// Black while seats are plentiful, yellow at 10 or fewer, red at 5 or fewer (including full).
    private func barColor(open: Int) -> Color {
        open <= 5 ? Palette.signal : open <= 10 ? Palette.highlight : Palette.ink
    }
    private func takenFraction(open: Int) -> Double {
        guard let capacity = details?.capacity, capacity > 0 else { return 0 }
        return min(1, max(0, Double(capacity - open) / Double(capacity)))
    }
    private var waitlist: String {
        let count = details?.waitlistCount, capacity = details?.waitlistCapacity
        let text = count.map { c in capacity.map { "Waitlist \(c) of \($0)" } ?? "Waitlist \(c)" } ?? ""
        if details?.isFull == true { return text.isEmpty ? "Full" : "Full · " + text.lowercased() }
        return text
    }
}

struct ScoreCard: View {
    let value: Double?
    let title: String
    let helper: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(score(value)).font(BYEFont.display(48)).foregroundStyle(Palette.ink)
                if value != nil { Text("/ 5").font(.system(size: 17)).foregroundStyle(Palette.secondary) }
            }
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(value == nil ? "Not available" : helper).font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
            .background(Palette.paper2, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value.map { String(format: "%.1f out of 5", $0) } ?? "not available"). \(helper)")
    }
}

struct ReviewCard: View {
    let review: Review
    let sourceURL: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if review.course.isEmpty { Text("Course not specified").font(.system(size: 12, weight: .semibold)) }
                else { CourseChip(text: review.course) }
                Spacer()
                Text("Rating \(score(review.rating))/5 · Difficulty \(score(review.difficulty))/5").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Text(review.excerpt).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
            HStack {
                Text(review.postedLabel).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                Link("Original on RMP ↗", destination: sourceURL).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
    }
}

/// One PCC section: CRN, format and term tags, schedule, location and units, and open seats.
struct ClassCard: View {
    let section: ClasswiseCore.Section
    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    CourseChip(text: "CRN \(section.crn)")
                    Tag(text: section.formatLabel)
                    if let term = section.details?.termPart, !term.isEmpty { Tag(text: term, kind: .term) }
                }.padding(.bottom, 2)
                if section.fullyOnline {
                    Text("No scheduled meetings").font(.system(size: 14, weight: .semibold))
                } else if section.meetings.isEmpty {
                    Text("Schedule not announced").font(.system(size: 14, weight: .semibold))
                } else {
                    ForEach(section.meetings, id: \.self) { Text($0).font(.system(size: 14, weight: .semibold)) }
                    if section.scheduleNotAnnounced && !section.meetings.contains(where: { $0.contains("TBA") || $0.contains("no set") }) {
                        Text("Some meetings not announced").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    }
                }
                Text(detailLine).font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            SeatMeter(details: section.details).frame(width: 178, alignment: .leading)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Palette.paper2, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
    private var detailLine: String {
        var parts: [String] = []
        if let campus = section.details?.campus, !campus.isEmpty, !section.fullyOnline { parts.append(campus) }
        parts.append(section.dateLabel)
        if let units = section.details?.units, !units.isEmpty { parts.append(units == "1" ? "1 unit" : "\(units) units") }
        return parts.joined(separator: " · ")
    }
}

extension View {
    /// The sunken linen panel used for summaries and status notes.
    func sunkenPanel(padding: CGFloat = 24) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper2, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// PCC prints titles in capitals; show them in title case but keep Roman numerals.
func displayTitle(_ raw: String) -> String {
    raw.split(separator: " ").enumerated().map { index, word in
        let upper = word.uppercased()
        if ["I", "II", "III", "IV", "V", "VI"].contains(upper) { return upper }
        if index > 0, ["AND", "OF", "TO", "THE", "FOR", "IN"].contains(upper) { return upper.lowercased() }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }.joined(separator: " ")
}
