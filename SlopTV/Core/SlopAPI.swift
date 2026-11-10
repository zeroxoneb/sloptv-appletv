import Foundation

enum SlopError: LocalizedError {
    case http(Int, String?)
    case noPlayableStream

    var errorDescription: String? {
        switch self {
        case let .http(status, message):
            if status == 429 { return "Too many plays just now. Try again in a minute." }
            return message ?? "The server returned an error (\(status))."
        case .noPlayableStream:
            return "This video has no stream Apple TV can play."
        }
    }
}

/// Thin client for the public tv.slop.cc JSON API (the same endpoints the website uses).
final class SlopAPI: @unchecked Sendable {
    static let shared = SlopAPI()
    static let base = URL(string: "https://tv.slop.cc")!

    let session: URLSession
    private var primedForPlayback = false

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = .shared
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": Self.browserUserAgent,
            "Accept-Language": "en-US,en;q=0.9",
        ]
        session = URLSession(configuration: config)
    }

    /// The playback endpoint only answers requests that look like they come from the website,
    /// so the app presents itself as desktop Safari.
    static let browserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    /// Headers a browser attaches to a same-origin `fetch()` from a tv.slop.cc page.
    static func sameOriginFetchHeaders(referer: URL) -> [String: String] {
        [
            "Origin": base.absoluteString,
            "Referer": referer.absoluteString,
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "cors",
            "Sec-Fetch-Dest": "empty",
        ]
    }

    /// Headers for AVPlayer's manifest and segment requests (the browser sends these too).
    static var mediaHeaders: [String: String] {
        ["User-Agent": browserUserAgent, "Referer": base.absoluteString + "/", "Origin": base.absoluteString]
    }

    // MARK: URLs

    static func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// Poster paths look like `/m/p/<video>/<asset>/<width>`; the server offers 320, 640 and 1920.
    static func imageURL(_ path: String?, width: Int) -> URL? {
        guard var path else { return nil }
        if path.hasPrefix("/m/p/"), let slash = path.lastIndex(of: "/"),
           Int(path[path.index(after: slash)...]) != nil {
            let size = width <= 320 ? 320 : (width <= 640 ? 640 : 1920)
            path = String(path[...slash]) + String(size)
        }
        return absolute(path)
    }

    // MARK: Requests

    private func get<T: Decodable>(_ path: String, _ query: [String: String?] = [:]) async throws -> T {
        var comps = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { comps.queryItems = items.sorted { $0.name < $1.name } }
        let (data, response) = try await session.data(from: comps.url!)
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw SlopError.http(http.statusCode, message)
        }
    }

    func feed(_ spec: ShelfSpec, after: String? = nil, seed: String? = nil) async throws -> FeedPage {
        switch spec.source {
        case .fresh:
            return try await get("/api/browse/fresh", ["chip": spec.chip, "after": after])
        case .discover:
            return try await get("/api/browse/discover",
                                 ["chip": spec.chip, "after": after, "seed": after == nil ? seed : nil])
        }
    }

    func liveNow() async throws -> LiveNow {
        try await get("/api/live/now")
    }

    /// Asks the server for a short-lived playback manifest, the same way the web player does.
    ///
    /// NOTE: tv.slop.cc has no public API for apps. This works by presenting the request as a
    /// browser on the watch page would (see README → "How playback works"). If the site changes
    /// its checks, this is the function that will need updating.
    func playbackURL(for videoID: String) async throws -> URL {
        // Like a browser, visit the watch page first so the session cookie is set.
        try await primeSession(videoID)
        do {
            return try await requestPlayback(videoID)
        } catch SlopError.http(403, _) {
            // The session may have expired; load the page again and retry once.
            primedForPlayback = false
            try await primeSession(videoID)
            return try await requestPlayback(videoID)
        }
    }

    private func primeSession(_ videoID: String) async throws {
        guard !primedForPlayback else { return }
        var req = URLRequest(url: Self.base.appendingPathComponent("v/\(videoID)"))
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        _ = try await session.data(for: req)
        primedForPlayback = true
    }

    private func requestPlayback(_ videoID: String) async throws -> URL {
        let encoded = videoID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? videoID
        var req = URLRequest(url: URL(string: "/api/play/\(encoded)", relativeTo: Self.base)!.absoluteURL)
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        for (k, v) in Self.sameOriginFetchHeaders(referer: Self.base.appendingPathComponent("v/\(videoID)")) {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let (data, response) = try await session.data(for: req)
        try Self.check(response, data)
        let info = try JSONDecoder().decode(PlayInfo.self, from: data)

        let isHLS = { (s: String) in s.range(of: #"\.m3u8($|[?#])"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let candidate = info.hlsUrl
            ?? (isHLS(info.manifestUrl) ? info.manifestUrl : nil)
            ?? info.mp4Url
            ?? info.manifestUrl
        guard let url = Self.absolute(candidate) else { throw SlopError.noPlayableStream }
        return url
    }

    var cookies: [HTTPCookie] { HTTPCookieStorage.shared.cookies(for: Self.base) ?? [] }
}
