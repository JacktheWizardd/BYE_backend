import SwiftUI
import CoreText
import ClasswiseCore

// Colours from the BYE design system (light only), read from the shared tokens in BYETokens.swift:
// ivory and stone grounds, Jet Black type and buttons, warm grey secondary text, and restrained yellow.
// Older names are kept so existing views read the tokens without a rename.
enum Palette {
    static let paper = BYEColor.paper
    static let paper2 = BYEColor.linen
    static let card = BYEColor.card
    static let tile = BYEColor.tile
    static let tileLine = BYEColor.tileLine
    static let ink = BYEColor.ink
    static let body = BYEColor.ink2
    static let secondary = BYEColor.ink3
    static let line = BYEColor.line
    static let lineStrong = BYEColor.lineStrong
    static let brandSoft = BYEColor.brandSoft
    static let highlight = BYEColor.accent
    static let signal = BYEColor.signal
}

extension View {
    /// Applies token shadow layers in order (for example the hard `BYEShadow.sticker` offset).
    func byeShadow(_ layers: [BYEShadowLayer]) -> some View {
        layers.reduce(AnyView(self)) { view, layer in
            AnyView(view.shadow(color: layer.color, radius: layer.radius, x: layer.x, y: layer.y))
        }
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

/// The v3 pill: primary is Jet Black with a yellow offset shadow that turns yellow on hover;
/// ghost is plain text that gains a stone fill on hover. Pressing pushes it into its shadow.
struct StickerButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost }
    var kind: Kind = .primary
    func makeBody(configuration: Configuration) -> some View { StickerBody(configuration: configuration, kind: kind) }
    private struct StickerBody: View {
        let configuration: ButtonStyle.Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            let shape = Capsule(), pressed = configuration.isPressed
            let fill: Color = switch kind {
            case _ where !enabled: kind == .ghost ? .clear : Palette.tile
            case .primary: hovering ? Palette.highlight : Palette.ink
            case .secondary: Palette.card
            case .ghost: hovering ? Palette.tile : .clear
            }
            // Disabled buttons go flat stone with no shadow, so they never read as a muddy primary.
            configuration.label.font(.system(size: 14, weight: .bold))
                .foregroundStyle(!enabled ? Palette.secondary : kind == .primary && !hovering ? Palette.paper : Palette.ink)
                .padding(.horizontal, 18).frame(minHeight: 44)
                .background(fill, in: shape)
                .overlay { if kind != .ghost { shape.strokeBorder(enabled ? Palette.ink : Palette.tileLine, lineWidth: BYEBorder.control) } }
                .background {
                    if kind == .primary && enabled && !pressed {
                        shape.fill(hovering ? Palette.ink : Palette.highlight).offset(x: 3, y: 3)
                    }
                }
                .offset(x: pressed && kind == .primary ? 2 : 0, y: pressed && kind == .primary ? 2 : 0)
                .contentShape(shape)
                .onHover { hovering = $0 && enabled }
                .animation(.easeOut(duration: BYEDuration.fast), value: hovering)
        }
    }
}

/// A short tilted label with a hard ink shadow, like a sticker on a notebook. Only short stickers tilt.
struct Sticker: View {
    let text: String
    var tilt: Double = BYETilt.sticker
    var weight: Font.Weight = .bold
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        Text(text).font(.system(size: 11, weight: weight)).foregroundStyle(Palette.ink).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Palette.card, in: shape)
            .overlay(shape.strokeBorder(Palette.ink, lineWidth: BYEBorder.sticker))
            .background(shape.fill(Palette.ink).offset(x: 2, y: 2))
            .rotationEffect(.degrees(tilt))
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

/// A yellow bar out of five that glides to a new value.
struct RatingBar: View {
    let value: Double?
    var track: Color = Palette.card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(Palette.highlight).frame(width: geometry.size.width * min(1, max(0, (value ?? 0) / 5)))
            }
        }.frame(height: 6).accessibilityHidden(true)
            .animation(BYEMotion.bars(reduce: reduceMotion), value: value)
    }
}

/// Initials in a circle: stone in list rows, yellow on the professor page.
struct Avatar: View {
    let name: String
    var accent = false
    var size: CGFloat = 30
    private var initials: String {
        name.split(separator: " ").compactMap(\.first).prefix(2).map { String($0).uppercased() }.joined()
    }
    var body: some View {
        Text(initials).font(accent ? BYEFont.display(size * 0.34, bold: true) : .system(size: size * 0.36, weight: .bold))
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(accent ? Palette.highlight : Palette.tile, in: Circle())
            .accessibilityHidden(true)
    }
}

/// A labelled number on a stone tile that counts to its new value, with an optional bar out of five.
struct StatTile: View {
    let value: Double?
    var digits = 1
    var suffix: String?
    let label: String
    var bar: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: String { value.map { String(format: "%.\(digits)f", $0) } ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text).font(BYEFont.display(24, bold: true)).monospacedDigit()
                    .contentTransition(.numericText(value: value ?? 0))
                    .animation(BYEMotion.count(reduce: reduceMotion), value: value)
                if let suffix, value != nil { Text(suffix).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
            }
            if let bar { RatingBar(value: bar, track: Palette.tile).frame(height: 4) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.paper2, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == nil ? "not available" : text + (suffix ?? ""))")
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
                        Capsule().fill(Palette.tile)
                        Capsule().fill(barColor)
                            .frame(width: geometry.size.width * (details?.takenFraction ?? 0))
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
    /// Colour follows SectionDetails.seatLevel.
    private var barColor: Color {
        switch details?.seatLevel {
        case .critical: Palette.signal
        case .low: Palette.highlight
        default: Palette.ink
        }
    }
    private var waitlist: String { details?.waitlistLabel ?? "" }
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
            Text(review.excerpt).font(.system(size: 13)).foregroundStyle(Palette.body).lineSpacing(4).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Text(review.postedLabel).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                Link("Original on RMP ↗", destination: sourceURL).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink)
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.line))
    }
}

/// One PCC section: CRN, format and term tags, schedule, location and units, and open seats.
/// A section that misses the picked class days is tagged "Other days".
struct ClassCard: View {
    let section: ClasswiseCore.Section
    var matches = true
    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    CourseChip(text: "CRN \(section.crn)")
                    Tag(text: section.formatLabel)
                    if let term = section.details?.termPart, !term.isEmpty { Tag(text: term, kind: .term) }
                    if !matches { Tag(text: "Other days", kind: .term) }
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
        .padding(.horizontal, 16).padding(.vertical, 14)
        // A section on other days steps back: a soft outline and no hard shadow.
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(matches ? Palette.ink : Palette.tileLine, lineWidth: BYEBorder.sticker))
        .background { if matches { RoundedRectangle(cornerRadius: 12).fill(Palette.ink).offset(x: 2, y: 2) } }
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

