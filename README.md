# TrafficControl

A macOS menu bar app that sits in front of your browsers, in the spirit of [Choosy](https://choosy.app).
Make it your default browser. When you click a link anywhere, it either sends the link
straight to the right browser based on your rules, or shows a picker so you can choose one.

**[Download](https://github.com/hakubo/TrafficControl/releases/latest/download/TrafficControl.dmg)** ·
[Website](https://hakubo.github.io/TrafficControl/) · macOS 14+, Apple Silicon and Intel

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask hakubo/tap/trafficcontrol
```

Or by hand:

1. Download `TrafficControl.dmg` from the [latest release](https://github.com/hakubo/TrafficControl/releases/latest),
   open it and drag TrafficControl into Applications.
2. Releases aren't notarized by Apple yet, so macOS blocks the first launch. Open the app once, then go to
   **System Settings → Privacy & Security** and click **Open Anyway**, or run
   `xattr -dr com.apple.quarantine /Applications/TrafficControl.app`.
3. In TrafficControl's Settings, click **Make Default** and confirm the macOS prompt.

TrafficControl updates itself: it checks daily and installs new versions (from 0.1.2 on).

## Features

- **Browser picker** opens at the mouse pointer and leaves the app you clicked in frontmost.
  - `1`–`9` or click: open in that browser
  - first letter of a browser's name: jump to it (opens right away if no other browser shares the letter)
  - `←` `→` / `Tab` then `⏎`: open the selected browser
  - hold `⇧` while choosing: open in the background
  - hold `⌘` while choosing: always open this site there (saved as a rule; the picker shows a pin while `⌘` is down)
  - `⌘C`: copy the link and close; `Esc` or a click outside: cancel
- **Browser profiles** for Chrome and other Chromium browsers (Chrome Beta/Dev/Canary, Chromium, Brave, Edge, Vivaldi).
  A browser with more than one profile shows one picker entry per profile, with the profile's account picture.
  Rules and the primary browser can target a specific profile. Profiles are read from the browser's
  `Local State` file on every click, so new ones appear straight away. A rule pointing at a deleted
  profile is skipped, because Chrome would otherwise create a new, empty profile with that name.
- **Open in desktop apps**: web links that a desktop app can show are handed to that app, by default
  only while it is running (configurable per app: when running, when installed, never). This happens before rules.
  - Linear: workspace pages on linear.app (issues, projects, views, documents…) → `linear://…`, fragment kept
  - Notion: pages on notion.so → `notion://…`
  - Zoom: meeting links `zoom.us/j/…` → `zoommtg://…`
  - Spotify: tracks, albums, artists, playlists, podcasts → `spotify:…`

  When the picker shows such a link, the app is offered as the first choice.
- **Rules**, checked top to bottom, first match wins. A rule's conditions can look at:
  - domain (`is, including subdomains`) and path (`is, including sub-paths`), so `github.com` + `/buffer`
    can go to your work profile and `github.com` + `/hakubo` to your personal one
  - full URL
  - source app (bundle ID or name, e.g. links clicked in Slack)
  - match types: is, contains, begins with, ends with, wildcard (`*`, `?`), regex
  - match **all** or **any** condition; action is *open in browser X* or *show the picker*
  - a live tester in the Rules tab shows which rule a URL would hit
- **Switch to an open tab** instead of opening a duplicate: in Safari and Chromium browsers (Chrome, Brave, Edge,
  Vivaldi, Chromium), TrafficControl asks the running browsers for their tabs over AppleScript and focuses a match.
  Matching ignores http/https, `www.`, a trailing slash, the `#fragment` and tracking parameters (`utm_*`, `fbclid`…).
  Looks in any running browser by default, or only in the browser the link would open in; holding the picker key skips it.
  macOS asks once per browser for permission; without it links just open normally. Chrome's AppleScript doesn't
  say which profile a window belongs to, so a tab open in another profile counts as open. Firefox can't be supported
  (no AppleScript access to tabs).
- **History**: every link that gets opened records its domain (minus `www.`) and where it went:
  which browser, which profile or desktop app. The picker preselects what you usually choose for that domain.
  In Settings → Rules → *History*, click ＋ next to a domain to turn it into a rule using that usual
  choice, or open it to see the breakdown and pick a different target. Domains a rule already covers are
  marked ✓. Kept in `history.json` next to the settings (last 500 domains); can be turned off or cleared.
- **When no rule matches**: always ask, use the primary browser, use the only running
  browser, or use the most recently active running browser. The picker is the fallback.
- Hold **⇧ Shift** (or ⌥ Option or ⌘ Command, your choice) while clicking a link to skip rules and get the picker.
- Rules can also check which keys you hold: for example, ⌘-click sends links to Safari.
- Reorder browsers, and hide browsers or individual profiles from the picker.
- Launch at login, hide the menu bar icon, open the link on the clipboard.

Settings live in `~/Library/Application Support/TrafficControl/settings.json`.

## Building

Needs macOS 14+ and Swift 6. The Command Line Tools are enough; Xcode is not required.

```sh
make app       # builds build/TrafficControl.app (universal, ad-hoc signed)
make package   # dist/TrafficControl.dmg + .zip + SHA256SUMS.txt
make install   # copies the app to ~/Applications and registers it with Launch Services
make run       # install + launch
make test      # unit tests
make icon      # redraws Resources/AppIcon.icns and docs/icon.png from scripts/make-icon.swift
```

## Releasing

Each release also publishes `appcast.xml`, the feed the app's updater ([Sparkle](https://sparkle-project.org))
reads from `releases/latest/download/appcast.xml`. Updates are signed with an EdDSA key: the public half is
`SUPublicEDKey` in `Resources/Info.plist`, the private half lives in your login keychain and in the
`SPARKLE_PRIVATE_KEY` repository secret. Keep a backup of it; without it, installed copies can't be updated.
The Homebrew cask lives in [hakubo/homebrew-tap](https://github.com/hakubo/homebrew-tap) and always points at
the latest release, so it needs no changes per release.

Add a `## <version>` section to `CHANGELOG.md` (it becomes the release notes), bump
`CFBundleShortVersionString` in `Resources/Info.plist`, then push a version tag. GitHub Actions builds,
packages and publishes the release:

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The landing page in `docs/` is published to GitHub Pages whenever it changes on `main`.
Its download button always points at the latest release.

Releases are ad-hoc signed, so users have to approve the first launch. To ship signed and notarized builds,
add these repository secrets (needs an Apple Developer account): `DEVELOPER_ID_P12` (base64 of the exported
Developer ID Application certificate), `DEVELOPER_ID_P12_PASSWORD`, `SIGN_IDENTITY`, `APPLE_ID`,
`APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`. See `.github/workflows/release.yml`.

Signing with the hardened runtime (as `scripts/package.sh` does with a Developer ID) needs the
`com.apple.security.automation.apple-events` entitlement in `Resources/TrafficControl.entitlements`, or
switching to open tabs stops working.

On first launch, click **Make Default** in Settings (or use the menu bar item) and confirm the
macOS prompt.

## Layout

- `Sources/TrafficControlCore`: rule matching, routing decisions and settings persistence. No AppKit, fully unit tested.
- `Sources/TrafficControl`: the app: link handling (`AppDelegate`, `LinkRouter`), browser discovery (`BrowserManager`),
  the picker panel (`Picker.swift`) and Settings UI (`SettingsView.swift`).
- `Resources/Info.plist`: declares the http/https URL schemes and HTML document types that make macOS list TrafficControl as a browser.

## Not yet built

- Firefox and Safari profiles (Chromium-based browsers only for now)
- An app icon (`Resources/AppIcon.icns` is picked up automatically if present)
- Rewriting URLs before opening them (stripping tracking parameters, unwrapping redirect links)

## Looking for more?

TrafficControl is a simple version of [Choosy](https://choosy.app). If you want something more robust,
with more options, Choosy might be a better choice.

## Support

TrafficControl is free. If it saves you some tab juggling, you can
[buy me a coffee](https://buymeacoffee.com/jakubolek).
