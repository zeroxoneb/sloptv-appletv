import Foundation
import Network

/// A tiny HTTP server the Apple TV runs on your local network while the Sign In screen is open.
/// You open its address on a computer, paste your tv.slop.cc cookies, and the TV signs in.
///
/// Only the path with the random one-time code is served, and the server stops as soon as you
/// leave the Sign In screen.
final class LinkServer: @unchecked Sendable {
    typealias Handler = @Sendable (String) async -> Result<String?, Error>

    let code: String
    private(set) var port: UInt16 = 0
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "LinkServer")
    private let onCookie: Handler

    init(onCookie: @escaping Handler) {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        code = String((0..<8).map { _ in alphabet.randomElement()! })
        self.onCookie = onCookie
    }

    /// Starts listening and returns the URL to open, e.g. `http://192.168.1.20:8723/k3m9xq2p`.
    func start() async throws -> URL {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: 8723)
        } catch {
            listener = try NWListener(using: .tcp) // port taken: let the system pick one
        }
        listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
        self.listener = listener

        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            // Resume exactly once: the handler removes itself on the first final state.
            listener.stateUpdateHandler = { [unowned listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    cont.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        self.port = port
        guard let ip = Self.localIPv4() else {
            throw AccountError("This Apple TV isn't connected to a local network.")
        }
        return URL(string: "http://\(ip):\(port)/\(code)")!
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    deinit { stop() }

    // MARK: HTTP

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self else { return conn.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.count > 128 * 1024 || error != nil { return conn.cancel() }

            guard let request = Request(buffer) else {
                if done { conn.cancel() } else { self.receive(conn, buffer: buffer) }
                return
            }
            Task { await self.respond(to: request, on: conn) }
        }
    }

    private func respond(to request: Request, on conn: NWConnection) async {
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        guard path == "/\(code)" else {
            return send(conn, status: "404 Not Found", html: Page.message(title: "Not found",
                body: "Open the exact address shown on your Apple TV."))
        }
        switch request.method {
        case "GET":
            send(conn, status: "200 OK", html: Page.form(code: code))
        case "POST":
            let cookie = Self.formValue("cookie", in: request.body) ?? ""
            switch await onCookie(cookie) {
            case let .success(name):
                send(conn, status: "200 OK", html: Page.message(
                    title: "You're signed in",
                    body: "Your Apple TV is signed in\(name.map { " as \(Page.escape($0))" } ?? ""). You can close this page."))
            case let .failure(error):
                send(conn, status: "400 Bad Request", html: Page.form(code: code, error: error.localizedDescription))
            }
        default:
            send(conn, status: "405 Method Not Allowed", html: Page.message(title: "Not allowed", body: ""))
        }
    }

    private func send(_ conn: NWConnection, status: String, html: String) {
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func formValue(_ name: String, in body: Data) -> String? {
        guard let text = String(data: body, encoding: .utf8) else { return nil }
        for pair in text.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.first == name else { continue }
            let raw = kv.count > 1 ? kv[1] : ""
            return raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        }
        return nil
    }

    private struct Request {
        let method: String
        let path: String
        let body: Data

        /// Parses a complete request, or returns nil if more bytes are needed.
        init?(_ data: Data) {
            guard let split = data.range(of: Data("\r\n\r\n".utf8)),
                  let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return nil }
            let lines = head.components(separatedBy: "\r\n")
            let parts = lines.first?.split(separator: " ") ?? []
            guard parts.count >= 2 else { return nil }
            let length = lines.dropFirst().compactMap { line -> Int? in
                let kv = line.split(separator: ":", maxSplits: 1)
                guard kv.count == 2, kv[0].lowercased() == "content-length" else { return nil }
                return Int(kv[1].trimmingCharacters(in: .whitespaces))
            }.first ?? 0
            let body = data[split.upperBound...]
            guard body.count >= length else { return nil }
            method = String(parts[0])
            path = String(parts[1])
            self.body = Data(body.prefix(length))
        }
    }

    /// The Apple TV's IPv4 address on Ethernet or Wi-Fi.
    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            candidates.append((String(cString: ifa.ifa_name), String(cString: host)))
        }
        return (candidates.first { $0.name.hasPrefix("en") } ?? candidates.first)?.ip
    }
}

/// HTML for the handoff page.
private enum Page {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func shell(_ title: String, _ content: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(title) · Slop TV</title>
        <style>
          :root { color-scheme: dark; }
          body { margin: 0; background: #0b0b0a; color: #efede6; font: 16px/1.5 -apple-system, system-ui, sans-serif; }
          main { max-width: 640px; margin: 0 auto; padding: 40px 20px; }
          h1 { font-size: 28px; margin: 0 0 8px; } h1 b { color: #ff6a4d; }
          ol { padding-left: 22px; } li { margin: 6px 0; }
          code, kbd { background: #1d1d1a; border: 1px solid #2b2a27; border-radius: 6px; padding: 1px 6px; font-size: 14px; }
          textarea { width: 100%; box-sizing: border-box; min-height: 140px; background: #151513; color: inherit;
                     border: 1px solid #2b2a27; border-radius: 10px; padding: 12px; font: 13px ui-monospace, monospace; }
          button { margin-top: 14px; background: #ff6a4d; color: #0b0b0a; border: 0; border-radius: 999px;
                   padding: 12px 28px; font-weight: 700; font-size: 16px; cursor: pointer; }
          .err { background: #3a1610; border: 1px solid #ff6a4d; border-radius: 10px; padding: 12px 14px; }
          .muted { color: #a09e95; font-size: 14px; }
        </style></head><body><main>\(content)</main></body></html>
        """
    }

    static func message(title: String, body: String) -> String {
        shell(title, "<h1>\(escape(title))</h1><p>\(body)</p>")
    }

    static func form(code: String, error: String? = nil) -> String {
        shell("Sign in", """
        <h1>Sign in to <b>Slop TV</b> on Apple TV</h1>
        \(error.map { "<p class=\"err\">\(escape($0))</p>" } ?? "")
        <p>Your Apple TV can't show tv.slop.cc's sign-in, so it borrows the session from a browser you're already signed in with.</p>
        <ol>
          <li>In a desktop browser, open <a href="https://tv.slop.cc" target="_blank" rel="noreferrer" style="color:#ff8a70">tv.slop.cc</a> and sign in.</li>
          <li>Open developer tools (<kbd>⌥⌘I</kbd> on Mac, <kbd>F12</kbd> on Windows) and go to the <b>Network</b> tab.</li>
          <li>Reload the page and click the first request (<code>tv.slop.cc</code>).</li>
          <li>Under <b>Request Headers</b>, copy the whole value of <code>Cookie</code> and paste it below.</li>
        </ol>
        <form method="post" action="/\(code)">
          <textarea name="cookie" placeholder="name=value; name2=value2; …" required autofocus></textarea>
          <button type="submit">Send to Apple TV</button>
        </form>
        <p class="muted">The cookie only goes to your Apple TV over your local network and is stored in its Keychain.
        Treat it like a password: anyone with it can act as you on tv.slop.cc. Signing out on the TV forgets it;
        signing out on the website ends the session everywhere.</p>
        """)
    }
}
