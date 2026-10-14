# Changelog

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
