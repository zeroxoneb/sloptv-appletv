import Foundation
import Observation
import Security

/// Your tv.slop.cc session, handed over from a browser where you're already signed in.
///
/// The Apple TV can't complete the site's own sign-in (it needs a browser CAPTCHA or an X login),
/// so instead you paste the browser's cookies into a small page the TV serves on your local
/// network (see LinkServer). They're kept in the Keychain and sent with the app's requests.
@MainActor @Observable
final class AccountModel {
    static let shared = AccountModel()

    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(name: String?)
        case expired
    }

    private(set) var state: State = .unknown
    var isSignedIn: Bool { if case .signedIn = state { true } else { false } }

    private static let keychainAccount = "tv.slop.cc session"
    /// Cloudflare cookies are tied to the browser that got them; sending them from the TV
    /// would only cause challenges, so they're left out.
    private static let skippedCookies: Set<String> = ["cf_clearance", "__cf_bm", "_cfuvid", "__cflb"]

    private init() {}

    /// On launch: reinstall a saved session and check it still works.
    func restore() async {
        guard let saved = Keychain.read(Self.keychainAccount) else { state = .signedOut; return }
        install(Self.parse(saved))
        do {
            let me = try await SlopAPI.shared.me()
            if me["signedIn"] as? Bool == true {
                state = .signedIn(name: Self.displayName(me))
            } else {
                state = .expired
            }
        } catch {
            // Offline or the site is down: assume the session is still good, it'll be checked again.
            state = .signedIn(name: nil)
        }
    }

    /// Validates pasted cookies against `/api/me` and keeps them if they're signed in.
    /// Returns the account name to show, or throws a message explaining what went wrong.
    func signIn(pasted: String) async throws -> String? {
        let cookies = Self.parse(pasted)
        guard !cookies.isEmpty else { throw AccountError("That doesn't look like a cookie. Copy the whole value of the Cookie header.") }
        let previous = Keychain.read(Self.keychainAccount)
        install(cookies)
        let me: [String: Any]
        do {
            me = try await SlopAPI.shared.me()
        } catch {
            throw AccountError("Couldn't reach tv.slop.cc to check the session: \(error.localizedDescription)")
        }
        guard me["signedIn"] as? Bool == true else {
            uninstall(cookies)
            if let previous { install(Self.parse(previous)) }
            throw AccountError("tv.slop.cc says that session isn't signed in. Sign in on the site, reload the page, and copy the Cookie header again.")
        }
        let serialized = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        Keychain.write(Self.keychainAccount, serialized)
        let name = Self.displayName(me)
        state = .signedIn(name: name)
        RatingStore.shared.reset()
        return name
    }

    /// Forgets the session on this Apple TV only (your browser stays signed in).
    func signOut() {
        if let saved = Keychain.read(Self.keychainAccount) { uninstall(Self.parse(saved)) }
        Keychain.delete(Self.keychainAccount)
        state = .signedOut
        RatingStore.shared.reset()
    }

    // MARK: Cookies

    struct Pair { let name: String; let value: String }

    /// Accepts a Cookie header value (`a=1; b=2`), optionally with a leading `Cookie:`.
    static func parse(_ raw: String) -> [Pair] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("cookie:") { text = String(text.dropFirst(7)) }
        return text.split(separator: ";").compactMap { part in
            let kv = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard kv.count == 2, !kv[0].isEmpty, !kv[1].isEmpty, !skippedCookies.contains(kv[0]) else { return nil }
            return Pair(name: kv[0], value: kv[1])
        }
    }

    private func install(_ pairs: [Pair]) {
        for pair in pairs {
            if let cookie = HTTPCookie(properties: [
                .domain: SlopAPI.base.host!, .path: "/", .name: pair.name, .value: pair.value,
                .secure: "TRUE", .expires: Date().addingTimeInterval(400 * 24 * 3600),
            ]) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    private func uninstall(_ pairs: [Pair]) {
        let names = Set(pairs.map(\.name))
        for cookie in SlopAPI.shared.cookies where names.contains(cookie.name) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    private static func displayName(_ me: [String: Any]) -> String? {
        for container in [me, me["viewer"], me["user"], me["profile"], me["person"]].compactMap({ $0 as? [String: Any] }) {
            if let name = container["name"] as? String, !name.isEmpty { return name }
            if let handle = container["handle"] as? String, !handle.isEmpty { return "@\(handle)" }
            if let name = container["displayName"] as? String, !name.isEmpty { return name }
        }
        return nil
    }
}

struct AccountError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Your 👍 per film, kept in sync with the site.
@MainActor @Observable
final class RatingStore {
    static let shared = RatingStore()
    private(set) var ratings: [String: Int] = [:]
    private(set) var likes: [String: Int] = [:]

    func isLiked(_ id: String) -> Bool { ratings[id] == 1 }

    func reset() { ratings = [:]; likes = [:] }

    /// Loads your current rating for a film (only meaningful when signed in).
    func refresh(_ id: String) async {
        guard let social = try? await SlopAPI.shared.social(videoID: id) else { return }
        ratings[id] = social.rating
        if let count = social.likes { likes[id] = count }
    }

    /// Likes the film, or removes your like. Returns a short message to show.
    @discardableResult
    func toggleLike(_ id: String) async -> String {
        guard AccountModel.shared.isSignedIn else {
            return "Sign in from the Account tab to like films."
        }
        let before = ratings[id] ?? 0
        let beforeLikes = likes[id]
        let target = before == 1 ? 0 : 1
        // Optimistic update, like the website.
        ratings[id] = target
        if let count = beforeLikes { likes[id] = count - (before == 1 ? 1 : 0) + (target == 1 ? 1 : 0) }
        do {
            let result = try await SlopAPI.shared.rate(videoID: id, value: target)
            ratings[id] = result.rating
            if let count = result.likes { likes[id] = count }
            return result.rating == 1 ? "Liked" : "Like removed"
        } catch {
            ratings[id] = before
            likes[id] = beforeLikes
            if case SlopError.http(401, _) = error { return "Your session expired. Sign in again from the Account tab." }
            return error.localizedDescription
        }
    }
}

/// Minimal Keychain wrapper for one string per account name.
enum Keychain {
    private static let service = "SlopTV"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        delete(account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
