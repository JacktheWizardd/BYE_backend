import Foundation

/// PCC prints titles in capitals; show them in title case but keep Roman numerals and lowercase
/// small joining words after the first. Shared rule: packages/core/vectors/display-title.json.
public func displayTitle(_ raw: String) -> String {
    raw.split(separator: " ").enumerated().map { index, word in
        let upper = word.uppercased()
        if ["I", "II", "III", "IV", "V", "VI"].contains(upper) { return upper }
        if index > 0, ["AND", "OF", "TO", "THE", "FOR", "IN"].contains(upper) { return upper.lowercased() }
        return word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }.joined(separator: " ")
}

/// Neutral facts about a class for the course overview. It never names, ranks or recommends a professor.
public struct CourseOverviewStats: Equatable, Sendable {
    public let sectionCount: Int
    public let professorCount: Int
    /// Open seats across sections that publish them; nil when none do.
    public let openSeats: Int?
    /// "In person 2 · Hybrid 1", most common first.
    public let formats: String
    public let terms: String

    public init(professors: [Professor]) {
        var seen = Set<String>()
        let sections = professors.flatMap(\.sections).filter { seen.insert($0.crn).inserted }
        sectionCount = sections.count
        professorCount = professors.count
        let known = sections.compactMap { $0.details?.seatsOpen }
        openSeats = known.isEmpty ? nil : known.reduce(0, +)
        formats = Self.breakdown(sections.map(\.formatLabel))
        terms = Self.breakdown(sections.compactMap { $0.details?.termPart }.filter { !$0.isEmpty })
    }

    static func breakdown(_ labels: [String]) -> String {
        Dictionary(labels.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }
}

/// How full a section is, for the seat bar colour: ink while seats are plentiful, yellow at 10 or fewer,
/// red at 5 or fewer (including full). A Mac extra; the web and Windows bars do not change colour.
public enum SeatLevel: Sendable { case plenty, low, critical }

extension SectionDetails {
    public var seatLevel: SeatLevel? {
        seatsOpen.map { $0 <= 5 ? .critical : $0 <= 10 ? .low : .plenty }
    }
    /// Share of seats taken, so a full class reads as a full bar. Zero without a capacity.
    public var takenFraction: Double {
        guard let open = seatsOpen, let capacity, capacity > 0 else { return 0 }
        return min(1, max(0, Double(capacity - open) / Double(capacity)))
    }
    /// "Waitlist 3 of 10", "Full · waitlist 3 of 10", "Full", or empty when PCC published no waitlist.
    public var waitlistLabel: String {
        let text = waitlistCount.map { count in waitlistCapacity.map { "Waitlist \(count) of \($0)" } ?? "Waitlist \(count)" } ?? ""
        if isFull { return text.isEmpty ? "Full" : "Full · " + text.lowercased() }
        return text
    }
}

extension Professor {
    /// The list row's status line while there is no verified RMP profile.
    public var listStatus: String {
        switch state {
        case .selectionRequired: candidates.count > 1 ? "Two or more RMP profiles · Choose profile" : "Profile needs confirmation · Choose profile"
        case .unavailable: "Cannot retrieve RMP info"
        case .searching: "Checking RMP…"
        case .pending, .ready: "Not checked yet"
        }
    }
    /// The professor page heading while there is no verified RMP profile.
    public var reportStatusTitle: String {
        switch state {
        case .selectionRequired: "Choose profile"
        case .unavailable: "Cannot retrieve RMP info"
        case .searching: "Checking RMP for \(name)…"
        case .pending, .ready: "Student feedback hasn’t been checked yet."
        }
    }
}

/// The collectible stamp on a BYE review, picked by luck from its ID so it never reflects the scores (BYE stays neutral).
/// FNV-1a 32-bit over UTF-16 code units, then `h % 100`: 2% legendary, 6% epic, 12% rare, 25% uncommon, 55% common.
/// Shared rule: packages/core/vectors/stamp-tier.json.
public enum StampTier: String, CaseIterable, Sendable {
    case common, uncommon, rare, epic, legendary

    public init(reviewID: String) {
        var hash: UInt32 = 2_166_136_261
        for unit in reviewID.utf16 { hash = (hash ^ UInt32(unit)) &* 16_777_619 }
        let roll = hash % 100
        self = roll < 2 ? .legendary : roll < 8 ? .epic : roll < 20 ? .rare : roll < 45 ? .uncommon : .common
    }
}
