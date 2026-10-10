import Foundation
import ClasswiseCore

public struct ProfessorSearchPage: Sendable {
    public let profiles: [RMPProfile]
    public let hasNextPage: Bool
    public let nextCursor: String?
}
public struct ProfessorReviewPage: Sendable {
    public var profile: RMPProfile
    public let sourceReviewIDs: [String]
    public let hasNextPage: Bool
    public let nextCursor: String?
}

/// Native client: narrow typed operations instead of an arbitrary-URL proxy.
public final class RMPClient: Sendable {
    public static let shared = RMPClient()
    private let transport: RMPTransport
    public init(transport: RMPTransport = RMPTransport()) { self.transport = transport }
    private struct Payload<V: Encodable>: Encodable { let query: String; let variables: V }
    private func query<V: Encodable, T: Decodable>(_ query: String, variables: V, as: T.Type) async throws -> T {
        let body = try JSONEncoder().encode(Payload(query: query, variables: variables))
        let bytes = try await transport.send(body)
        let envelope: Envelope<T>
        do { envelope = try JSONDecoder().decode(Envelope<T>.self, from: bytes) }
        catch { throw RMPAPIError.malformedResponse }
        guard envelope.errors?.isEmpty != false else { throw RMPAPIError.graphql }
        guard let data = envelope.data else { throw RMPAPIError.malformedResponse }
        return data
    }
    public func search(name: String, cursor: String? = nil) async throws -> ProfessorSearchPage {
        struct SearchQuery: Encodable { let text: String; let schoolID: String }
        struct Variables: Encodable { let query: SearchQuery; let count = 20; let cursor: String? }
        let data = try await query(RMPQueries.search, variables: Variables(query: SearchQuery(text: name, schoolID: Data("School-2649".utf8).base64EncodedString()), cursor: cursor), as: SearchData.self)
        let connection = data.search.teachers
        guard connection.edges.count <= 20 else { throw RMPAPIError.malformedResponse }
        let profiles = try connection.edges.map { try $0.node.profile() }
        try validate(connection.pageInfo, cursor: cursor)
        return ProfessorSearchPage(profiles: profiles, hasNextPage: connection.pageInfo.hasNextPage, nextCursor: connection.pageInfo.endCursor)
    }
    public func profile(id: String, count: Int = 3, cursor: String? = nil, courseFilter: String? = nil) async throws -> ProfessorReviewPage {
        guard !id.isEmpty, id.allSatisfy(\.isNumber), let number = Int(id), number > 0 else { throw RMPAPIError.invalidIdentity }
        struct Variables: Encodable { let id: String; let count: Int; let cursor: String?; let courseFilter: String? }
        let requestedCount = min(50, max(1, count))
        let data = try await query(RMPQueries.profile, variables: Variables(id: Data("Teacher-\(number)".utf8).base64EncodedString(), count: requestedCount, cursor: cursor, courseFilter: courseFilter), as: ProfileData.self)
        guard let teacher = data.node else { throw RMPAPIError.invalidIdentity }
        var profile = try teacher.profile()
        guard profile.id == id, let ratings = teacher.ratings else { throw RMPAPIError.invalidIdentity }
        guard ratings.edges.count <= requestedCount else { throw RMPAPIError.malformedResponse }
        try validate(ratings.pageInfo, cursor: cursor)
        profile.reviews = try ratings.edges.compactMap { try $0.node.review() }
        let ids = ratings.edges.map { $0.node.id }
        guard Set(ids).count == ids.count else { throw RMPAPIError.pagination }
        return ProfessorReviewPage(profile: profile, sourceReviewIDs: ids, hasNextPage: ratings.pageInfo.hasNextPage, nextCursor: ratings.pageInfo.endCursor)
    }
    private func validate(_ info: PageInfo, cursor: String?) throws {
        if info.hasNextPage {
            guard let next = info.endCursor, !next.isEmpty, next != cursor else { throw RMPAPIError.pagination }
        }
    }
}
