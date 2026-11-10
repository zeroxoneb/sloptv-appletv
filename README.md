<p align="center"><img src="docs/banner.png" alt="Slop TV for Apple TV" width="720"></p>

# Slop TV for Apple TV

An **unofficial**, open-source Apple TV app for watching AI-generated films from [tv.slop.cc](https://tv.slop.cc) on your TV, laid out like a streaming service.

Built with SwiftUI and AVKit. No dependencies, no account, no tracking.

> **Not affiliated with tv.slop.cc.** This is a fan-made client. All videos, posters and creator names come from the site and belong to their creators. See [How playback works](#how-playback-works) before relying on it.

## Features

- **Home**: a full-screen billboard of whatever is on the Slop TV channel right now, then rows for Fresh off the Cannon, Discover, Music Videos, Episodes, Originals, Restyles, Drips and Sloptoberfest. Rows load more as you scroll.
- **Live**: the 24/7 Slop TV channel with a countdown and what's up next. **Watch Live** plays in sync with the broadcast schedule and moves from slot to slot on its own.
- **Browse**: a full-screen grid with the site's category filters, sorted by Newest or Discover.
- **Detail pages**: title, creator, duration, views, likes, tier, and a "More Like This" row.
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

If `xcodebuild` complains about Command Line Tools, run `sudo xcode-select -s /Applications/Xcode.app` once.

## Using the app

| Where | Siri Remote |
|---|---|
| Rows and grid | Swipe to move, click to open a film |
| Film page | **Play** starts it; swipe down for More Like This |
| Player | Click or swipe down for the controls and info panel; **Back** closes |
| Live channel | Follows the broadcast, so seeking is off; **Back** leaves |

## How playback works

tv.slop.cc doesn't publish an API for apps. Browsing uses the same public JSON endpoints as the website:

| Endpoint | Used for |
|---|---|
| `GET /api/browse/fresh?chip=…&after=…` | Newest films, by category |
| `GET /api/browse/discover?chip=…&seed=…&after=…` | Discover rows |
| `GET /api/live/now` | The live channel's current slot and schedule |
| `POST /api/play/{id}` | A short-lived HLS stream URL for one film |

`/api/play` only answers requests that come from the website. To get a stream, the app does what a visit with **Safari** would: it loads the film's page to get a session cookie, then requests the stream with the headers a browser sends from that page (`User-Agent`, `Origin`, `Referer`, `Sec-Fetch-*`).

This works as of November 2026, but:

- **It can stop working at any time** if the site changes how it checks requests. If you see *"Couldn't play this video"* while browsing still works, that's almost certainly why. The code to update is `SlopAPI.playbackURL(for:)` in [`SlopTV/Core/SlopAPI.swift`](SlopTV/Core/SlopAPI.swift).
- It's intended for **personal viewing**. Please be a good citizen: don't use this code to bulk-download or mirror the site, and respect the creators and the site's terms.
- If tv.slop.cc ever offers an official app API, this project should switch to it.

## Customizing

- **Home rows**: edit `ShelfSpec.home` in [`SlopTV/Core/Models.swift`](SlopTV/Core/Models.swift). Categories match the site's filters: `all`, `music`, `episodes`, `originals`, `restyles`, `drips`, `sloptoberfest`.
- **Colors**: [`SlopTV/Views/Theme.swift`](SlopTV/Views/Theme.swift).
- **Icon and Top Shelf art**: edit and run `swift scripts/make_icons.swift`.
- **Testing playback quickly**: in debug builds, the launch argument `-autoplayLive` opens the live channel at startup. It's in the shared scheme but turned off: Product → Scheme → Edit Scheme → Run → Arguments.

## Project layout

```
SlopTV/
  SlopTVApp.swift            App entry point and tab bar (Home / Live / Browse)
  Core/
    Models.swift             API models and the list of home rows
    Models+Observable.swift  Paginated row model, home screen model
    SlopAPI.swift            tv.slop.cc client: feeds, live schedule, playback
  Views/
    HomeView.swift           Billboard and rows
    LiveView.swift           Live channel screen and synced live player
    BrowseView.swift         Category grid
    DetailView.swift         Film page
    PlayerScreen.swift       On-demand player (AVPlayerViewController)
    PosterCard.swift         Focusable poster card and row
    Theme.swift              Colors and shared UI pieces
  Assets.xcassets            App icon, Top Shelf images, accent color
scripts/make_icons.swift     Generates the icon and Top Shelf art
Signing.xcconfig             Signing defaults (put yours in Signing.local.xcconfig)
```

## Troubleshooting

| Problem | Fix |
|---|---|
| *"Couldn't play this video"* | See [How playback works](#how-playback-works). If one film fails and others play, that film may have been removed. |
| *"Too many plays just now"* | The site limits how many films you can start in a short time. Wait a minute. |
| Signing error / "No account for team" | Check `DEVELOPMENT_TEAM` in `Signing.local.xcconfig`, and that your Apple ID is added under Xcode → Settings → Accounts. |
| "Bundle identifier is not available" | Change `PRODUCT_BUNDLE_IDENTIFIER` to something unique. |
| Apple TV not listed in Xcode | Same network for both; keep the *Remote App and Devices* screen open while pairing. |
| App stopped opening after a week | Free-account installs expire after 7 days. Run it from Xcode again. |

## Contributing

Issues and pull requests are welcome. Ideas: search, creator pages, a Top Shelf extension with live content, subtitles (the site has some WebVTT captions), and sign-in for the Following feed.

## License

[MIT](LICENSE). The license covers this app's source code only, not any content from tv.slop.cc.
