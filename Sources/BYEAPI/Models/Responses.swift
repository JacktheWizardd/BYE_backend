import Foundation
import ClasswiseCore

struct Envelope<T: Decodable>: Decodable { let data: T?; let errors: [GraphError]? }
struct GraphError: Decodable { let message: String? }
struct Connection<T: Decodable>: Decodable {
    struct Edge: Decodable { let node: T }
    let edges: [Edge]
    let pageInfo: PageInfo
}
struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
struct SearchData: Decodable {
    struct Search: Decodable { let teachers: Connection<Teacher> }
    let search: Search
}
struct ProfileData: Decodable { let node: Teacher? }
struct Teacher: Decodable {
    struct School: Decodable { let id: String?; let legacyId: Int?; let name: String }
    struct CourseCount: Decodable { let courseName: String; let courseCount: Int? }
    let id: String?
    let legacyId: Int?
    let firstName: String
    let lastName: String
    let department: String?
    let avgRating: Double?
    let avgDifficulty: Double?
    let numRatings: Int?
    let wouldTakeAgainPercent: Double?
    let school: School
    let courseCodes: [CourseCount]?
    let ratings: Connection<Rating>?

    static func numericID(_ global: String?, legacy: Int?, kind: String) throws -> String {
        var decoded: String?
        if let global {
            guard let bytes = Data(base64Encoded: global), let text = String(data: bytes, encoding: .utf8),
                  text.hasPrefix(kind + "-") else { throw RMPAPIError.invalidIdentity }
            let number = String(text.dropFirst(kind.count + 1))
            guard !number.isEmpty, number.allSatisfy(\.isNumber), let value = Int(number), value > 0 else { throw RMPAPIError.invalidIdentity }
            decoded = String(value)
        }
        if let legacy {
            guard legacy > 0, decoded == nil || decoded == String(legacy) else { throw RMPAPIError.invalidIdentity }
            return String(legacy)
        }
        guard let decoded else { throw RMPAPIError.invalidIdentity }
        return decoded
    }
    func profile() throws -> RMPProfile {
        let teacherID = try Self.numericID(id, legacy: legacyId, kind: "Teacher")
        let schoolID = try Self.numericID(school.id, legacy: school.legacyId, kind: "School")
        guard !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RMPAPIError.invalidIdentity }
        return RMPProfile(id: teacherID, firstName: firstName, lastName: lastName, school: school.name, schoolID: Int(schoolID),
                          department: department ?? "", rating: Self.score(avgRating), difficulty: Self.score(avgDifficulty),
                          ratingCount: numRatings.flatMap { $0 >= 0 ? $0 : nil },
                          wouldTakeAgain: wouldTakeAgainPercent.flatMap { (0...100).contains($0) ? $0 : nil }, reviews: [],
                          courseCounts: courseCodes?.map { ReviewCourseCount(label: $0.courseName, count: $0.courseCount.flatMap { $0 >= 0 ? $0 : nil }) })
    }
    static func score(_ value: Double?) -> Double? { value.flatMap { (1...5).contains($0) ? $0 : nil } }
}
struct Rating: Decodable {
    let id: String
    let comment: String?
    let helpfulRating: Double?
    let difficultyRating: Double?
    let date: String?
    let `class`: String?
    let isForOnlineClass: Bool?
    func review() throws -> Review? {
        guard !id.isEmpty else { throw RMPAPIError.malformedResponse }
        guard let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Review(id: id, course: `class` ?? "", text: comment, date: date ?? "",
                      rating: Teacher.score(helpfulRating), difficulty: Teacher.score(difficultyRating), online: isForOnlineClass)
    }
}
