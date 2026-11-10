# Proposal: device sign-in for TV / limited-input apps

**For:** whoever operates tv.slop.cc
**From:** the unofficial [Slop TV for Apple TV](../README.md) app
**Status:** request for a new endpoint

## What this asks for

A way for an app on a device **with no web browser** (Apple TV, and later Android TV, Roku, consoles) to sign a user in — including via **Sign in with X** — and receive **its own session**, without the user typing a password or copying cookies.

This is the [OAuth 2.0 Device Authorization Grant (RFC 8628)](https://datatracker.ietf.org/doc/html/rfc8628): the pattern every streaming app uses on TV. The user approves on their phone (where the X app is already installed and signed in); the TV polls and gets a session back.

## Why the existing sign-in can't be used from a TV

tvOS has **no web browser and no web view** (`WKWebView` and `ASWebAuthenticationSession` don't exist on tvOS). So the current flows don't work there:

- **Sign in with X** (`POST /api/sign-in/pending` → `{href}` → browser navigates to X → redirect back sets the cookie): the TV has nothing that can open `href`, complete the X redirect, or receive the cookie.
- **Email code** (`sendSignInCode` / `verifySignInCode`): needs the Turnstile/CAPTCHA widget, which again needs a browser.

Today the app works around this by asking the user to sign in **in a desktop browser** and paste their `Cookie` header into a one-time page the Apple TV serves on the LAN (see [README → Liking films](../README.md#liking-films)). It works, but it's clunky and asks the user to handle their own session cookie by hand. A device flow replaces it cleanly.

Note: the cookie can't simply be handed over from the **phone** after X auth, which is why this needs server support. The phone completes OAuth in its own browser, the session cookie is `HttpOnly` (JS can't read it to forward it), and an `https://tv.slop.cc` page can't POST to the TV's plain-`http` LAN address (mixed content). The session has to be minted **for the TV**, which only the server can do.

## Proposed flow

Three endpoints under the existing `/api/sign-in/` namespace. Names/shapes are a suggestion — match them to your contract conventions.

### 1. Start — `POST /api/sign-in/device/start`

The TV calls this with no credentials.

```jsonc
// Request
{ "client": "appletv" }           // optional label for the approval screen

// Response
{
  "deviceCode": "…",              // secret; TV keeps it, never shown to the user
  "userCode": "KXTZ-QRDP",        // short, human-typeable; shown on the TV
  "verificationUri": "https://tv.slop.cc/link",
  "verificationUriComplete": "https://tv.slop.cc/link?code=KXTZ-QRDP",
  "expiresInMs": 600000,          // ~10 min
  "intervalMs": 3000              // how often the TV may poll
}
```

The TV shows `userCode` and a QR code of `verificationUriComplete`.

### 2. Approve — the phone

`verificationUriComplete` opens in the phone's **normal browser**, which **already supports Sign in with X and opens the X app** — this is the whole point, and it needs nothing new from you beyond binding an approved sign-in to the pending `userCode`:

1. Phone opens `/link?code=KXTZ-QRDP`.
2. If not signed in, the user signs in — **including the existing Sign in with X**, which deep-links to the X app as it does today.
3. The page shows: *"Allow **Slop TV on Apple TV** to sign in as @handle?"* with Allow / Deny, so approval is explicit and the client is named.
4. On Allow, the server marks that `userCode` approved for this user.

### 3. Poll — `POST /api/sign-in/device/poll`

The TV polls no faster than `intervalMs`:

```jsonc
// Request
{ "deviceCode": "…" }

// Response — still waiting
{ "status": "pending" }

// Response — approved
{ "status": "approved", "cookieWrites": [ /* same shape as verifySignInCode */ ] }

// Terminal
{ "status": "denied" }
{ "status": "expired" }
```

Reusing the **`cookieWrites`** array that `verifySignInCode` already returns means the TV installs the session exactly as the email-code flow does — no new session concept, just a new way to authorize one.

Standard RFC 8628 error cases to cover: `slow_down` (TV polled too fast → raise its interval), `expired` (code aged out), `denied`.

## Implementation notes

The design above is the *what*. These are the details an implementer (or an AI pair) will otherwise have to invent — written so you can build without guessing. The one thing this document **cannot** contain is your own code; see the integration checklist last.

### Pending-authorization record

One row/document per `device/start` call. Suggested fields:

| Field | Notes |
|---|---|
| `id` | Internal key. |
| `deviceCodeHash` | Store a **hash** of `deviceCode` (e.g. SHA-256), not the value — it's a bearer secret, like a session token. Poll looks up by hashing the presented code. |
| `userCode` | Stored as shown (uppercase, no separator) and looked up case-insensitively; the `/link` page finds the record by this. |
| `clientLabel` | From `start` request, shown on the approval screen ("Slop TV on Apple TV"). Treat as untrusted — escape it, cap length. |
| `status` | `pending` → `approved` \| `denied` \| `expired` \| `consumed`. |
| `userId` | Null until approved; set to the approver's user on Allow. |
| `createdAt`, `expiresAt` | ~10 min TTL. Expired records are terminal; sweep or lazily expire on read. |
| `lastPolledAt` | To enforce `slow_down`. |

### Code generation

- `deviceCode`: ≥128 bits from a CSPRNG, URL-safe. The only secret here.
- `userCode`: short and human-typeable — e.g. 8 chars from a reduced alphabet (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, no `0/O/1/I`), shown grouped as `KXTZ-QRDP`. Low entropy is fine **because** it's useless without a logged-in human tapping Allow in the 10-min window; still, rate-limit `/link` lookups and consider locking a record after a few failed code entries.

### The `/link` approval page

- Requires a signed-in session. If the user isn't signed in, run your **existing** sign-in first (email code or Sign in with X — unchanged), then return to the approval screen with the `code` preserved.
- The Allow/Deny action is a state-changing POST → protect it with your normal **CSRF** defense, same as your other forms.
- On Allow, write `userId` and set `status = approved`. On Deny, `status = denied`.
- `verificationUriComplete` (`/link?code=…`) pre-fills the code so the QR path is one tap; `/link` with no code shows a field to type `userCode` (for users who'd rather type than scan).

### Poll semantics

- Look up by `deviceCodeHash`. Unknown/expired → `expired`. `pending`/`denied` → return as-is.
- On `approved`: mint the session exactly as your existing sign-in does, return the `cookieWrites`, and set `status = consumed` atomically so a second poll can't re-mint. (Return `approved` only on the poll that consumes it; subsequent polls get `expired`.)
- `slow_down`: if a poll arrives sooner than `intervalMs` after `lastPolledAt`, return a `slow_down`-style refusal and have the TV add to its interval (the app already backs off).

### Integration checklist (needs your code, not this doc)

The device flow is a new *trigger and delivery* wrapper around sign-in you already have. To build it, put these in front of whoever implements (including if that's Claude):

1. **`verifySignInCode`** — specifically how it produces the `cookieWrites` array and what's in it. `device/poll` returns the identical shape; the app installs it the same way.
2. **The X OAuth callback / web sign-in handler** — how a completed sign-in becomes a session for a user. The `/link` page reuses this verbatim; only the "then mark this `userCode` approved" step is new.
3. **Your typed contract** (`sloptv-contract`, versioning, refusal codes) — add the three methods there so inputs are validated like the rest of the API. Reuse existing refusals where they fit (`LINK_CONSUMED`, `INTENT_USED`, `INTENT_EXPIRED`, `RATE_LIMITED`).

With those three in context, the endpoints are a few hundred lines. Without them, they can't be built correctly — the session minting is the whole point and only you have it.

## Security notes

- `deviceCode` is the secret and lives only on the TV; `userCode` is low-entropy and only meaningful during the short window with explicit human approval, so guessing it is useless without a logged-in approver.
- The approval screen **must** name the client and require a tap, so a phished `userCode` can't be auto-approved.
- One-time: a `deviceCode` yields a session once, then is consumed (your contract already has `LINK_CONSUMED` / `INTENT_USED` refusals that fit).
- Scope, rate-limiting, and session lifetime are yours to set; the TV only needs whatever a normal web session gets for reading `/api/me`, `/api/videos/{id}/social`, and `/api/videos/{id}/rating`.

## What the app does once this exists

Replaces the paste-the-cookie screen with: show `userCode` + QR → poll → install `cookieWrites` in the Keychain. The relevant code is isolated in [`SlopTV/Core/Account.swift`](../SlopTV/Core/Account.swift) and [`SlopTV/Core/LinkServer.swift`](../SlopTV/Core/LinkServer.swift) (the latter — the LAN handoff page — goes away entirely). Happy to adapt to whatever shape you land on.
