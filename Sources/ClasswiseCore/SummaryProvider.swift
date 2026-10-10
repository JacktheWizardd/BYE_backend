import Foundation

public protocol SummaryProvider {
    var cacheIdentity: String { get }
    func prewarm() async
    func summarize(reviews: [Review], course: Course) async throws -> ReviewSummary
}

public extension SummaryProvider {
    func prewarm() async { }
}

/// Whole-review prefix selection; the cost includes instructions, schema and prompt.
public enum SummaryEvidence {
    /// Conservative lexical corroboration, not a general semantic proof. Reject
    /// paraphrases with modifiers/topics absent from either cited source.
    public static func corroborated(_ point: SummaryPoint, reviews: [Review], concern: Bool) -> Bool {
        let stop = Set("a an the this that these those it its is are was were be been being of to for in on at by from with as and or but she he they i me my we our their professor teacher instructor student students reported report reports very really".split(separator: " ").map(String.init))
        let variants = ["exams": "exam", "tests": "exam", "test": "exam", "hw": "homework",
            "lectures": "lecture", "explanations": "explanation", "explains": "explanation",
            "explaining": "explanation", "clearly": "clear", "clarity": "clear",
            "heavily": "heavy", "grades": "grade", "grading": "grade", "weighted": "weight",
            "weights": "weight", "weighting": "weight", "caring": "care", "cares": "care",
            "never": "not", "no": "not"]
        func words(_ text: String) -> [String] {
            text.lowercased().replacingOccurrences(of: "’", with: "'")
                .replacingOccurrences(of: "n't", with: " not")
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { variants[String($0)] ?? String($0) }
        }
        let anchors = Set(words(point.text)).subtracting(stop)
        let unfavorable = Set("heavy difficult excessive unclear confusing unfair biased bias strict hard expensive costly unhelpful poor bad inconsistent late stressful challenging high".split(separator: " ").map(String.init))
        let negated = anchors.contains("not")
        let favorable = Set("clear helpful fair kind good great engaging organized responsive easy".split(separator: " ").map(String.init))
        guard anchors.count >= 2 else { return false }
        if concern && (anchors.isDisjoint(with: unfavorable) || negated) { return false }
        if !concern && !anchors.isDisjoint(with: unfavorable) && !negated { return false }
        if !concern && negated && !anchors.isDisjoint(with: favorable) { return false }
        let source = reviews.filter { point.reviewIDs.contains($0.id) }
        guard source.count == 2 else { return false }
        return source.allSatisfy { review in
            let tokens = words(review.text)
            guard anchors.isSubset(of: Set(tokens)) else { return false }
            if !negated {
                for index in tokens.indices where anchors.contains(tokens[index]) {
                    let prefix = tokens[max(0, index - 3)..<index]
                    if prefix.contains("not") { return false }
                }
            }
            return true
        }
    }

    /// Salvage only a corroborated leading observation; never add new wording.
    public static func corroboratedPoint(_ point: SummaryPoint, reviews: [Review], concern: Bool) -> SummaryPoint? {
        if corroborated(point, reviews: reviews, concern: concern) { return point }
        let words = point.text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > 2 else { return nil }
        let unfinished = Set(["and", "or", "but", "with", "of", "to", "for", "the", "a", "an", "not", "no", "never"])
        for count in stride(from: words.count - 1, through: 2, by: -1) {
            let last = words[count - 1].lowercased().trimmingCharacters(in: .punctuationCharacters)
            guard !unfinished.contains(last) else { continue }
            let candidate = SummaryPoint(text: words.prefix(count).joined(separator: " "), reviewIDs: point.reviewIDs)
            if corroborated(candidate, reviews: reviews, concern: concern) { return candidate }
        }
        return nil
    }

    public static func compactPoint(_ text: String, numbers: [Int], reviews: [Review]) -> SummaryPoint? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard numbers.count == 2, Set(numbers).count == 2,
              numbers.allSatisfy({ $0 > 0 && $0 <= reviews.count }),
              !text.isEmpty, text.count <= 96,
              text.split(whereSeparator: { $0.isWhitespace }).count <= 14 else { return nil }
        let ids = numbers.map { reviews[$0 - 1].id }
        guard Set(ids).count == 2 else { return nil }
        return SummaryPoint(text: text, reviewIDs: ids)
    }

    public static func fit(_ reviews: [Review], budget: Int,
                           cost: ([Review]) async throws -> Int) async throws -> [Review] {
        guard budget > 0 else { return [] }
        var low = 0, high = reviews.count
        while low < high {
            try Task.checkCancellation()
            let middle = (low + high + 1) / 2
            if try await cost(Array(reviews.prefix(middle))) <= budget { low = middle }
            else { high = middle - 1 }
        }
        let result = Array(reviews.prefix(low))
        guard !result.isEmpty, try await cost(result) <= budget else { return [] }
        return result
    }
}
