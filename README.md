<p align="center"><img src="docs/banner.png" alt="Slop TV for Apple TV" width="720"></p>

# Slop TV for Apple TV

An **unofficial**, open-source Apple TV app for watching AI-generated films from [tv.slop.cc](https://tv.slop.cc) on your TV, laid out like a streaming service.

Built with SwiftUI and AVKit. No dependencies and no tracking. You only need an account to like films.

> **Not affiliated with tv.slop.cc.** This is a fan-made client. All videos, posters and creator names come from the site and belong to their creators. See [How playback works](#how-playback-works) before relying on it.

## Features

- **Home**: a full-screen billboard of whatever is on the Slop TV channel right now, then rows for Fresh off the Cannon, Discover, Music Videos, Episodes, Originals, Restyles, Drips and Sloptoberfest. Rows load more as you scroll.
- **Live**: the 24/7 Slop TV channel with a countdown and what's up next. **Watch Live** plays in sync with the broadcast schedule and moves from slot to slot on its own.
- **Browse**: a full-screen grid with the site's category filters, sorted by Newest or Discover.
- **Detail pages**: title, creator, duration, views, likes, tier, and a "More Like This" row.
- **👍 Like films**, from the player's control bar while a film plays or from its page. Likes count on tv.slop.cc. Requires [linking your account](#liking-films).
- **Native player**: Apple's standard player, with the Siri Remote, scrubbing, the info panel with title and artwork, and adaptive HLS streaming.
- Dark theme matching the site, a layered parallax app icon, and Top Shelf art.

## Requirements

| | |
|---|---|
| Mac | macOS with **Xcode 16 or later** |
| Apple TV | **tvOS 18 or later** (Apple TV HD or any Apple TV 4K) |
| To install on a real Apple TV | An Apple ID signed into Xcode. A free account works; a paid Apple Developer Program membership lasts longer (see below). |

The app isn't on the App Store. You build it from source and install it with Xcode, which takes about 10 minutes the first time.

## Quick start: run it in the simulator

No signing or Apple TV needed.

```sh
git clone https://github.com/zeroxoneb/sloptv-appletv.git
cd sloptv-appletv
open SlopTV.xcodeproj
```

1. If Xcode asks, install the **tvOS** platform (or go to Xcode → Settings → Components → tvOS).
2. In the run destination menu at the top of the window, pick an **Apple TV** simulator.
3. Press **⌘R**.

In the simulator, the arrow keys move focus, **Return** selects and **Esc** is the Back/Menu button. **I/O → Show Apple TV Remote** gives you an on-screen Siri Remote.

## Install on your Apple TV

### 1. Add your signing details

Create a file called `Signing.local.xcconfig` in the project folder. It's git-ignored, so your details stay out of the repo.

```
DEVELOPMENT_TEAM = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.yourname.sloptv
```

- **DEVELOPMENT_TEAM**: your Team ID. With a paid account it's on [developer.apple.com/account](https://developer.apple.com/account) under *Membership details*. With a free account, open Xcode → Settings → Accounts, select your Apple ID, and copy the Team ID shown for your "Personal Team".
- **PRODUCT_BUNDLE_IDENTIFIER**: any reverse-DNS string that nobody else has registered.

You can also skip the file: select the **SlopTV** target → **Signing & Capabilities** and pick your team there.

### 2. Pair your Apple TV with Xcode (first time only)

1. Put the Apple TV and your Mac on the same network.
2. On the Apple TV, open **Settings → Remotes and Devices → Remote App and Devices** and leave that screen open.
3. In Xcode, open **Window → Devices and Simulators** (⇧⌘2). The Apple TV shows up under *Discovered*. Click **Pair** and enter the code from the TV.
4. If asked, turn on **Settings → Privacy & Security → Developer Mode** on the Apple TV and restart it.

### 3. Build and run

Pick your Apple TV as the run destination and press **⌘R**. The app installs, launches, and stays on your Apple TV home screen.

**How long the install lasts:** with a paid developer account, about a year. With a free account, **7 days**. Either way, run it from Xcode again to renew it.

### Command line (optional)

```sh
# Simulator
xcodebuild -project SlopTV.xcodeproj -scheme SlopTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' build

# Device
xcodebuild -project SlopTV.xcodeproj -scheme SlopTV \
  -destination 'generic/platform=tvOS' -allowProvisioningUpdates build
```

Run the UI tests (they play the live channel in the simulator and press Back on a virtual Siri Remote):

```sh
xcodebuild test -project SlopTV.xcodeproj -scheme SlopTV \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)'
```

If `xcodebuild` complains about Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app` once.

## Using the app

| Where | Siri Remote |
|---|---|
| Rows and grid | Swipe to move, click to open a film |
| Film page | **Play** starts it; swipe down for More Like This |
| Player | Click or swipe down for the controls and info panel; **Back** returns to where you were (press it again if the controls are showing) |
| Player, to like | Swipe down to show the controls, then select **👍 Like** at the right of the control bar |
| Live channel | Follows the broadcast, so seeking is off; **Back** returns to the app |

## Liking films

Browsing and watching don't need an account. To 👍 films, link your tv.slop.cc account.

The Apple TV can't show tv.slop.cc's sign-in: it needs a browser CAPTCHA or an X login, and tvOS has no browser. Instead, the app borrows the session from a browser where you're already signed in:

1. On the Apple TV, open the **Account** tab and select **Sign In**. It shows a local address such as `http://192.168.1.20:8723/k3m9xq2p`, plus a QR code.
2. On a computer on the **same network**, sign in at [tv.slop.cc](https://tv.slop.cc), then open that address.
3. Follow the steps on the page: open developer tools → **Network**, reload tv.slop.cc, click the first request, and copy the value of the **Cookie** request header.
4. Paste it and click **Send to Apple TV**. The TV checks the session with tv.slop.cc and switches to *Signed in*.

Then, while a film plays, swipe down on the remote and select **👍 Like** in the control bar. Select it again to remove your like. Film pages have a 👍 button next to **Play** that shows the like count.

**Security and privacy:**
- The cookie only travels from your computer to your Apple TV over your local network, and is stored in the Apple TV's **Keychain**. It's never sent anywhere except tv.slop.cc.
- The sign-in page only exists while the Sign In screen is open, and only at its random one-time address.
- It's a plain HTTP page on your LAN, so only do this on a network you trust. Treat the cookie like a password: anyone with it can act as you on tv.slop.cc.
- **Sign Out of This Apple TV** forgets the session on the TV only. Signing out on the website ends the session everywhere, after which the TV asks you to sign in again.
- The first time, tvOS may ask permission for Slop TV to use the local network. Allow it, or the page won't load.

**A smoother sign-in, if the site adds it:** the cookie-paste step exists only because tv.slop.cc has no sign-in flow for browserless devices. A one-tap *Sign in with X* on your phone (the way TVs normally sign in) would need a small server-side addition. [`docs/device-sign-in-proposal.md`](docs/device-sign-in-proposal.md) is a ready-to-send spec for it — hand it to whoever runs the site.

## How playback works

tv.slop.cc doesn't publish an API for apps. Browsing uses the same public JSON endpoints as the website:

| Endpoint | Used for |
|---|---|
| `GET /api/browse/fresh?chip=…&after=…` | Newest films, by category |
| `GET /api/browse/discover?chip=…&seed=…&after=…` | Discover rows |
| `GET /api/live/now` | The live channel's current slot and schedule |
| `POST /api/play/{id}` | A short-lived HLS stream URL for one film |
| `GET /api/me` | Whether the linked session is signed in |
| `GET /api/videos/{id}/social` | Your rating and the like count for a film |
| `POST /api/videos/{id}/rating` | `{"value": 1}` to like, `0` to remove the like |

`/api/play` only answers requests that come from the website. To get a stream, the app does what a visit with **Safari** would: it loads the film's page to get a session cookie, then requests the stream with the headers a browser sends from that page (`User-Agent`, `Origin`, `Referer`, `Sec-Fetch-*`).

This works as of November 2026, but:

- **It can stop working at any time** if the site changes how it checks requests. If you see *"Couldn't play this video"* while browsing still works, that's almost certainly why. The code to update is `SlopAPI.playbackURL(for:)` in [`SlopTV/Core/SlopAPI.swift`](SlopTV/Core/SlopAPI.swift).
- It's intended for **personal viewing**. Please be a good citizen: don't use this code to bulk-download or mirror the site, and respect the creators and the site's terms.
- If tv.slop.cc ever offers an official app API, this project should switch to it.

## Customizing

- **Home rows**: edit `ShelfSpec.home` in [`SlopTV/Core/Models.swift`](SlopTV/Core/Models.swift). Categories match the site's filters: `all`, `music`, `episodes`, `originals`, `restyles`, `drips`, `sloptoberfest`.
- **Colors**: [`SlopTV/Views/Theme.swift`](SlopTV/Views/Theme.swift).
- **Icon and Top Shelf art**: edit and run `swift scripts/make_icons.swift`.
- **Debug launch arguments**: in debug builds, `-autoplayLive` opens the live channel at startup and `-signIn` opens the Sign In screen. Both are in the shared scheme but turned off: Product → Scheme → Edit Scheme → Run → Arguments.

## Project layout

```
SlopTV/
  SlopTVApp.swift            App entry point and tab bar (Home / Live / Browse / Account)
  Core/
    Models.swift             API models and the list of home rows
    Models+Observable.swift  Paginated row model, home screen model
    SlopAPI.swift            tv.slop.cc client: feeds, live schedule, playback, likes
    Account.swift            Linked session (Keychain), likes store
    LinkServer.swift         Local sign-in page served while Sign In is open
  Views/
    HomeView.swift           Billboard and rows
    LiveView.swift           Live channel screen and synced live player
    BrowseView.swift         Category grid
    DetailView.swift         Film page
    Playback.swift           Full-screen player (AVPlayerViewController) with 👍 in the control bar
    AccountView.swift        Account tab, Sign In screen with QR code
    PosterCard.swift         Focusable poster card and row
    Theme.swift              Colors and shared UI pieces
  Assets.xcassets            App icon, Top Shelf images, accent color
SlopTVUITests/               UI test: Back closes the player and returns to the app
scripts/make_icons.swift     Generates the icon and Top Shelf art
Signing.xcconfig             Signing defaults (put yours in Signing.local.xcconfig)
```

## Troubleshooting

| Problem | Fix |
|---|---|
| *"Couldn't play this video"* | See [How playback works](#how-playback-works). If one film fails and others play, that film may have been removed. |
| Sign-in page won't load | The computer must be on the same network as the Apple TV, and Slop TV needs local-network permission (Settings → Privacy & Security → Local Network on the Apple TV). Keep the Sign In screen open. |
| *"That session isn't signed in"* | Sign in on tv.slop.cc first, reload, and copy the **Cookie** header from the request again (the whole value). |
| 👍 says *"Sign in from the Account tab"* or *"session expired"* | Link your account (see [Liking films](#liking-films)). Sessions end when you sign out on the website. |
| *"Too many plays just now"* | The site limits how many films you can start in a short time. Wait a minute. |
| Signing error / "No account for team" | Check `DEVELOPMENT_TEAM` in `Signing.local.xcconfig`, and that your Apple ID is added under Xcode → Settings → Accounts. |
| "Bundle identifier is not available" | Change `PRODUCT_BUNDLE_IDENTIFIER` to something unique. |
| Apple TV not listed in Xcode | Same network for both; keep the *Remote App and Devices* screen open while pairing. |
| App stopped opening after a week | Free-account installs expire after 7 days. Run it from Xcode again. |

## Contributing

Issues and pull requests are welcome. Ideas: search, creator pages, a Top Shelf extension with live content, subtitles (the site has some WebVTT captions), 👎 and Save, and the Following feed for linked accounts.

## License

[MIT](LICENSE). The license covers this app's source code only, not any content from tv.slop.cc.
