// Query design adapted from Amaan's rate-my-professors-client-ts (MIT).
// Copyright (c) 2026 Amaan. See THIRD_PARTY_NOTICES.md and bundled notices.
enum RMPQueries {
    static let identity = "id legacyId firstName lastName department school { id legacyId name }"
    static let statistics = "avgRating avgDifficulty numRatings wouldTakeAgainPercent"
    static let search = """
    query BYESearch($query: TeacherSearchQuery!, $count: Int!, $cursor: String) {
      search: newSearch { teachers(query: $query, first: $count, after: $cursor) {
        edges { node { \(identity) } } pageInfo { hasNextPage endCursor }
      } }
    }
    """
    static let profile = """
    query BYEProfile($id: ID!, $count: Int!, $cursor: String, $courseFilter: String) {
      node(id: $id) { ... on Teacher {
        \(identity) \(statistics)
        courseCodes { courseName courseCount }
        ratings(first: $count, after: $cursor, courseFilter: $courseFilter) {
          edges { node { id comment helpfulRating difficultyRating date class isForOnlineClass } }
          pageInfo { hasNextPage endCursor }
        }
      } }
    }
    """
}
