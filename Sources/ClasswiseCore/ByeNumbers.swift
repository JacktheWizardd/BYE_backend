import Foundation

/// A student's BYE number and how many have been given out ("Student 12 of 40").
public struct ByeNumber: Sendable, Hashable, Codable {
    public let number: Int
    public let total: Int
    public init(number: Int, total: Int) { self.number = number; self.total = total }
    /// "BYE-0042"; widens past 9999.
    public static func label(_ number: Int?) -> String { number.map { String(format: "BYE-%04d", $0) } ?? "BYE-····" }
}

/// Gets a student's BYE number through the website's review sign-in: email a code, verify it, claim the number
/// (supabase/007_bye_numbers.sql). The short-lived session cookie lives only in this actor's memory and is dropped
/// once the number arrives; nothing but the number is kept. GET/POST over HTTPS (or loopback HTTP for local tests).
public actor ByeNumberClient {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let site: URL?
    private let fetch: Fetch
    private var session: String?

    public init(site: String, fetch: Fetch? = nil) {
        let url = URL(string: site.replacingOccurrences(of: "/+$", with: "", options: .regularExpression))
        let local = ["localhost", "127.0.0.1", "::1"].contains(url?.host ?? "")
        let valid = url.map { $0.host != nil && $0.user == nil && $0.password == nil && $0.query == nil && $0.fragment == nil
            && ($0.scheme == "https" || ($0.scheme == "http" && local)) } ?? false
        self.site = valid ? url : nil
        if let fetch { self.fetch = fetch } else {
            let config = URLSessionConfiguration.ephemeral
            // Cookies are handled by hand below so the session never reaches a shared or on-disk store.
            config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.httpCookieAcceptPolicy = .never
            config.urlCredentialStorage = nil; config.urlCache = nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForResource = 25
            let session = URLSession(configuration: config)
            self.fetch = { try await session.data(for: $0) }
        }
    }

    /// The website's rule: a confirmed @go.pasadena.edu address with no "+" alias. Nil when it doesn't qualify.
    public static func schoolEmail(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.count <= 254, email.hasSuffix("@go.pasadena.edu") else { return nil }
        let local = email.dropLast("@go.pasadena.edu".count)
        guard !local.isEmpty, !local.contains("+"),
              local.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }) else { return nil }
        return email
    }
    public static func validCode(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (6...10).contains(code.count) && code.allSatisfy(\.isASCII) && code.allSatisfy(\.isNumber) ? code : nil
    }

    /// Emails a sign-in code. Returns the seconds to wait before asking again.
    public func sendCode(email raw: String) async throws -> Int {
        guard let email = Self.schoolEmail(raw) else { throw AppError.message("Use your PCC school email, ending in @go.pasadena.edu.") }
        session = nil
        struct Sent: Decodable { let retryAfter: Int? }
        let sent: Sent = try await call("auth/send", body: ["email": email]).value
        return sent.retryAfter ?? 60
    }

    /// Checks the emailed code, then claims (or re-reads) the number. The session is dropped either way.
    public func verify(email raw: String, code rawCode: String) async throws -> ByeNumber {
        guard let email = Self.schoolEmail(raw) else { throw AppError.message("Use your PCC school email, ending in @go.pasadena.edu.") }
        guard let code = Self.validCode(rawCode) else { throw AppError.message("Enter the complete numeric code from your email.") }
        defer { session = nil }
        struct Verified: Decodable { let signedIn: Bool }
        let verified: (value: Verified, cookie: String?) = try await call("auth/verify", body: ["email": email, "code": code])
        guard verified.value.signedIn, let cookie = verified.cookie else { throw AppError.message("The code could not be confirmed. Request a new one.") }
        session = cookie
        let number: ByeNumber = try await call("number", body: [:]).value
        guard number.number > 0, number.total >= 1 else { throw AppError.message("Your BYE number could not be confirmed. Try again shortly.") }
        return number
    }

    /// How many BYE numbers exist. Public; sends nothing about the student.
    public func total() async throws -> Int {
        let count: (value: Count, cookie: String?) = try await call("numbers", body: nil)
        return count.value.total
    }

    private func call<T: Decodable>(_ route: String, body: [String: String]?) async throws -> (value: T, cookie: String?) {
        guard let site else { throw AppError.message("BYE numbers are not configured.") }
        var request = URLRequest(url: site.appendingPathComponent("api/reviews/" + route)); request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // The website accepts sign-in posts only from its own origin; the app speaks for that site.
            request.setValue(site.absoluteString, forHTTPHeaderField: "Origin")
        }
        if let session { request.setValue(session, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await fetch(request)
        let http = response as? HTTPURLResponse, status = http?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error.message
            throw AppError.message(message ?? (status == 429 ? "Please wait before trying again." : "BYE could not reach its website. Try again shortly."))
        }
        guard let value = try? JSONDecoder().decode(Envelope<T>.self, from: data).data else {
            throw AppError.message("BYE's website returned an unexpected response.")
        }
        return (value, Self.sessionCookie(http?.value(forHTTPHeaderField: "Set-Cookie")))
    }

    private struct Count: Decodable { let total: Int }
    private struct Envelope<T: Decodable>: Decodable { let data: T }
    private struct Failure: Decodable { struct Body: Decodable { let message: String }; let error: Body }

    /// "name=value" of the review session cookie from a Set-Cookie header, ignoring its attributes.
    static func sessionCookie(_ header: String?) -> String? {
        guard let pair = header?.split(separator: ";").first.map({ $0.trimmingCharacters(in: .whitespaces) }),
              let name = pair.split(separator: "=").first, ["__Secure-bye-review", "bye-review-local"].contains(String(name)),
              pair.count > name.count + 1 else { return nil }
        return pair
    }
}
