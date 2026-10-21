import Foundation
import ClasswiseCore

/// What BYE remembers on this Mac only: the student's first name, whether the welcome was finished,
/// and up to five recent classes. None of it is sent anywhere.
struct AppPreferences {
    static let maxNameLength = 20
    static let maxRecentClasses = 5
    private enum Key {
        static let displayName = "bye.displayName", hasOnboarded = "bye.hasOnboarded", recentClasses = "bye.recentClasses"
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// A stored name that breaks the name rule reads as no name. Setting an invalid or empty name clears it.
    var displayName: String {
        get {
            let name = Self.normalizedName(defaults.string(forKey: Key.displayName) ?? "")
            return Self.isValidName(name) ? name : ""
        }
        nonmutating set {
            let name = Self.normalizedName(newValue)
            if name.isEmpty || !Self.isValidName(name) { defaults.removeObject(forKey: Key.displayName) } else { defaults.set(name, forKey: Key.displayName) }
        }
    }
    var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }
    /// Classes in the order they were first opened. Unreadable or repeated entries are dropped.
    var recentClasses: [Course] {
        var seen = Set<String>()
        let stored = (defaults.stringArray(forKey: Key.recentClasses) ?? []).compactMap { try? Course($0) }
        return Array(stored.filter { seen.insert($0.display).inserted }.suffix(Self.maxRecentClasses))
    }
    /// Adds a class at the end; a class already listed keeps its place, and the oldest drops off past five.
    @discardableResult
    func remember(_ course: Course) -> [Course] {
        var list = recentClasses
        if !list.contains(where: { $0.display == course.display }) { list.append(course) }
        list = Array(list.suffix(Self.maxRecentClasses))
        defaults.set(list.map(\.display), forKey: Key.recentClasses)
        return list
    }

    /// Trims the ends and collapses repeated spaces, as the Windows app does.
    static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).replacing(#/ {2,}/#, with: " ")
    }
    /// The Windows name rule: at most 20 letters, marks, digits, spaces and . ' ’ - (no control characters).
    static func isValidName(_ name: String) -> Bool {
        name.count <= maxNameLength && name.wholeMatch(of: #/[\p{L}\p{M}\p{N} .'’\-]*/#) != nil
    }
}
