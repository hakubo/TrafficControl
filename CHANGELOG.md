# Changelog

## 0.3.0

- A fresh look. The picker shows the link's site and the app it came from above larger browser tiles,
  with keycaps for each shortcut. Holding ⌘ pins the browser under the cursor and names the rule it
  will save, without the window jumping.
- The menu bar icon opens a popover instead of a menu: whether links are reaching TrafficControl,
  one-click "Send All Links To" with a countdown and Stop button, Open Link from Clipboard, your
  three most recent sites, and Settings, Updates and Quit.
- Settings → General opens with a status card: whether TrafficControl is your default browser, how
  many links it has opened and across how many sites. The sidebar groups panes and shows how many
  browsers and rules you have.
- Settings → Rules: the link tester sits above the rules, shows the browser a link would open in and
  highlights the rule that catches it. Create Rule only appears when no rule matches yet, and ⌥⏎ no
  longer adds a line break.
- Figma links (design, FigJam, Slides, prototypes…) open in the Figma desktop app.
- Settings → Apps options now read "Open always", "Open only if app is open" and "Never".
- Links that open in a Chrome (or other Chromium) profile reach the browser about twice as fast:
  TrafficControl starts the browser's executable directly instead of launching a new app instance.
- Checking a browser's open tabs takes two AppleScript round trips instead of two per window.
- Hold ⌘ while picking a browser to make it the rule for that site. The picker shows a pin and
  "Always open <site> with the one you pick" while ⌘ is down.
- `TIMING_LOGS=1 make app` builds a copy that logs how long each routing step takes.

## 0.2.0

- Send all links to one browser or profile for an hour from the menu bar ("Send All Links To"),
  handy during screen shares. Holding the picker key still shows the picker. Relaunching clears it.
- New menu bar icon: a control tower instead of the generic branch symbol.
- Picker: ⇧ + a number opens that choice in the background again. Moving the mouse no longer changes
  which browser Return opens; hover gets its own lighter highlight. Hover the link to see the full
  address. The key hint shows for the first few opens, then moves behind a ? icon. Tiles work with VoiceOver.
- Settings → General shows which browsers allow TrafficControl to check their open tabs, with a
  Set up now button to ask at a moment you choose and a link to the Automation settings.
- Settings tells you when Launch at login is waiting for your approval, and when Behaviour is
  "primary browser" but no primary browser is set.
- Rules: a regex that doesn't compile gets a red note, and a rule that an earlier rule already
  catches gets a hint. ⌫ deletes the selected rule. The rules list is resizable.
- Browsers installed while TrafficControl is running show up without a Refresh button.
- History records a link's path only when you pick a different browser for that path than the rest
  of the domain, so it no longer keeps usernames from every GitHub or LinkedIn link.
- Open Link from Clipboard no longer reads the clipboard every time the menu opens.
- The Settings window remembers its size and position and fits a 13-inch screen.
- A browser that denied Automation access isn't asked again on every click until relaunch.
- Respects Reduce Motion. Faster routing: regexes, icons and AppleScripts are cached, and history
  is saved in the background.
- The website loads its fonts itself and no longer loads the Buy Me a Coffee widget.

## 0.1.6

- Holding a key while clicking a link to get the picker now works reliably: TrafficControl looks at the
  keys you held when you clicked, not only when the link arrives, which is often after you let go.
- The key is now ⇧ Shift by default, and you can choose ⌥ Option or ⌘ Command instead
  (Settings → General). ⌥ was the default before, but some apps use ⌥-click themselves, such as Slack,
  which marks the message unread.
- New rule condition, Keys held: for example "Keys held include ⌘" → Safari. When such a rule
  matches, TrafficControl doesn't switch to an already open tab elsewhere.
- Right-clicking the top of the Settings window no longer shows an "Icon and Text / Icon Only / Text Only"
  menu that did nothing.

## 0.1.5

- Redesigned Settings window with a sidebar, like System Settings.
- Each Chrome profile is its own entry in the picker order, so you can place profiles of the same
  browser anywhere in the list.
- Recent Domains is now called History.
- If another app becomes your default browser, the menu bar icon gets an orange dot and its menu
  says links aren't reaching TrafficControl.
- Path rules are back to two plain conditions: Domain and Path. Create Rule makes
  "Domain is github.com, including subdomains" and "Path is /buffer, including sub-paths".
  Rules made with the Link condition in 0.1.4 are converted automatically.
- Clearer option names: "is, including subdomains" for domains and "is, including sub-paths" for paths,
  instead of "is or is under".

## 0.1.4

- Rules can target a path: a rule for `github.com/buffer` sends that page and everything below it
  (`github.com/buffer/api/pull/1`) to one browser or profile, while `github.com/hakubo` goes to another.
  New rules start with a Link condition that takes a domain or a domain plus path; you can paste a full URL.
- A new path rule goes above broader rules that would otherwise catch its links first.
- Recent Domains lists the paths you open on each domain, with where they went and a button to make a rule.
- The picker remembers your choice per path, so github.com/buffer and github.com/hakubo can each have their own.
- Type a link into the tester under Rules and use Create Rule to make a rule for its domain or one of its paths.

## 0.1.3

- Opening Settings while it's already open now brings the window to the front, also when it's minimized
  or on another desktop. While Settings is open, TrafficControl shows in the Dock and in ⌘-Tab.
- Copy, paste, select all and undo work in Settings' text fields, and ⌘W closes the window.

## 0.1.2

- Automatic updates: TrafficControl checks for new versions daily and installs them for you.
  Use Check for Updates… in the menu bar, or turn it off in Settings → General.
  This is the last version you need to install by hand.
- Install with Homebrew: `brew install --cask hakubo/tap/trafficcontrol`.

## 0.1.1

- New app icon: a control tower with an amber-lit cab over a radar sweep.
- Settings → General has an About section with the version number, links to the website and GitHub,
  and a Buy Me a Coffee button. The menu bar menu has a Buy Me a Coffee item too.

## 0.1.0

First release.

- Browser picker at the mouse pointer, with keyboard shortcuts.
- Rules on domain, URL, path and source app, with wildcards and regex.
- Chrome profiles, plus Brave, Edge, Vivaldi and Chromium profiles.
- Linear, Notion, Zoom and Spotify links open in their desktop apps.
- Switches to a tab that already shows the link instead of opening a duplicate.
- Recent domains list that turns a domain into a rule with one click.
