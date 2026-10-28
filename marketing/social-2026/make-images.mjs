// Renders the 10 campaign cards (1200×1200 PNG) with headless Chrome.
// Usage: node marketing/social-2026/make-images.mjs
import { writeFileSync, mkdirSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const docs = resolve(here, "../../docs");
const out = join(here, "images");
const tmp = join(here, ".html");
mkdirSync(out, { recursive: true });
mkdirSync(tmp, { recursive: true });
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

const strip = (via, call, host, path, dest) =>
  `<li class="strip" data-via="${via}"><span class="call">${call}</span><span class="route"><b>${host}</b><span>${path}</span></span><span class="dest">→ ${dest}</span><span class="via">${via.toUpperCase()}</span></li>`;
const strips = (...items) => `<ul class="strips">${items.join("")}</ul>`;

const tile = (key, name, sub, color, { selected = false, pin = false } = {}) =>
  `<div class="tile${selected ? " sel" : ""}"><div class="av" style="--c:${color}">${name[0]}</div><div class="tn">${name}</div><div class="ts">${sub}</div><kbd>${key}</kbd>${pin ? '<span class="pin">📌</span>' : ""}</div>`;
const picker = (site, from, tiles, footer = "") =>
  `<div class="picker"><div class="ph"><b>${site}</b><span>from ${from}</span></div><div class="tiles">${tiles.join("")}</div>${footer}</div>`;

const keyRow = (keys, text) => `<li><span class="keys">${keys.map((k) => `<kbd>${k}</kbd>`).join("")}</span><span>${text}</span></li>`;

const cards = [
  {
    label: "Link router for macOS",
    title: "Every link, <em>cleared</em> for the right browser.",
    body: strips(
      strip("app", "LNR", "linear.app", "/acme/issue/ENG-142", "Linear"),
      strip("tab", "DOC", "docs.google.com", "/document/d/1x…", "open tab"),
      strip("rule", "GHB", "github.com", "/acme/api/pull/88", "Chrome · Work"),
      strip("ask", "HNW", "news.ycombinator.com", "/item?id=4…", "your pick"),
    ),
  },
  {
    label: "Chrome profiles",
    title: "Work and personal, <em>kept apart.</em>",
    body: picker("calendar.google.com", "Slack", [
      tile("1", "Work", "Chrome", "#2f9e6a", { selected: true }),
      tile("2", "Personal", "Chrome", "#8b6cf0"),
      tile("3", "Safari", "Safari", "#3b82f6"),
      tile("4", "Firefox", "Firefox", "#e5534b"),
    ]),
    note: "Every profile in Chrome, Brave, Edge and Vivaldi is its own choice, with its account picture.",
  },
  {
    label: "Rules",
    title: "Set it <em>once.</em> Never think about it again.",
    body: strips(
      strip("rule", "GHB", "github.com", "/acme/…", "Chrome · Work"),
      strip("rule", "GHB", "github.com", "/you/…", "Chrome · Personal"),
      strip("rule", "SLK", "any link", " from Slack", "Chrome · Work"),
      strip("rule", "CMD", "⌘-click", " anywhere", "Safari"),
    ),
    note: "Domain, path, full URL, source app, keys held. Wildcards and regex too.",
  },
  {
    label: "Desktop apps",
    title: "Linear links open <em>in Linear.</em>",
    body: strips(
      strip("app", "LNR", "linear.app", "/acme/issue/ENG-142", "Linear"),
      strip("app", "NTN", "notion.so", "/acme/Roadmap-9f…", "Notion"),
      strip("app", "FIG", "figma.com", "/design/k3x…", "Figma"),
      strip("app", "ZOM", "zoom.us", "/j/8812…", "Zoom"),
      strip("app", "SPT", "open.spotify.com", "/track/4u…", "Spotify"),
    ),
  },
  {
    label: "Open tabs",
    title: "Already open? <em>That tab</em> comes forward.",
    body: strips(
      strip("tab", "DOC", "docs.google.com", "/d/1x…?utm_source=slack", "open tab"),
      strip("tab", "PRS", "www.github.com", "/acme/api/pull/88/#files", "open tab"),
    ),
    note: "Ignores http vs https, www., trailing slashes, #anchors and utm_* tracking. Safari and Chromium browsers.",
  },
  {
    label: "The picker",
    title: "Choose a browser <em>without the mouse.</em>",
    body: `<ul class="keymap">${[
      keyRow(["1", "–", "9"], "open in that browser"),
      keyRow(["C"], "first letter jumps to Chrome"),
      keyRow(["⇧"], "hold to open in the background"),
      keyRow(["⌘"], "hold to save as this site's rule"),
      keyRow(["⌘", "C"], "copy the link and close"),
      keyRow(["esc"], "cancel"),
    ].join("")}</ul>`,
  },
  {
    label: "Hold ⌘",
    title: "Pick once. <em>It's a rule now.</em>",
    body: picker(
      "figma.com",
      "Linear",
      [
        tile("1", "Figma", "App", "#8b6cf0"),
        tile("2", "Work", "Chrome", "#2f9e6a", { selected: true, pin: true }),
        tile("3", "Personal", "Chrome", "#3b82f6"),
        tile("4", "Safari", "Safari", "#e5534b"),
      ],
      `<div class="pf">📌 Always open <b>figma.com</b> with the one you pick</div>`,
    ),
    note: "History remembers your usual choice per domain, so the picker preselects it.",
  },
  {
    label: "Screen sharing",
    title: "Presenting? Send <em>every link</em> to one browser.",
    body: `<div class="timer"><div class="tl">Send all links to</div><div class="tb">Chrome · Work</div><div class="tc">59:42</div><div class="tbtn">Stop</div></div>`,
    note: "One click in the menu bar, for an hour. No personal tabs on the shared screen.",
  },
  {
    label: "How a link is routed",
    title: "Five checks, <em>in this order.</em>",
    body: `<ol class="seq">${[
      ["Desktop app", "Linear, Notion, Figma, Zoom, Spotify"],
      ["Open tab", "bring the existing tab forward"],
      ["Your rules", "first match wins"],
      ["Default", "primary, only running, or last used"],
      ["Picker", "at your cursor, usual choice preselected"],
    ]
      .map(([h, p]) => `<li><b>${h}</b><span>${p}</span></li>`)
      .join("")}</ol>`,
  },
  {
    label: "Free · open source",
    title: "Up and running <em>in a minute.</em>",
    body: `<div class="term"><div class="dots"><i></i><i></i><i></i></div><code><span>$</span> brew install --cask hakubo/tap/trafficcontrol</code></div>
      <ul class="checks"><li>Free and open source</li><li>Updates itself</li><li>No accounts, no tracking. Settings stay on your Mac</li></ul>`,
  },
];

const css = `
@font-face { font-family: BSD; font-weight: 800; src: url(${docs}/fonts/BigShouldersDisplay-800.woff2); }
@font-face { font-family: AH; font-weight: 400; src: url(${docs}/fonts/AtkinsonHyperlegible-400.woff2); }
@font-face { font-family: AH; font-weight: 700; src: url(${docs}/fonts/AtkinsonHyperlegible-700.woff2); }
@font-face { font-family: PM; font-weight: 400; src: url(${docs}/fonts/IBMPlexMono-400.woff2); }
@font-face { font-family: PM; font-weight: 500; src: url(${docs}/fonts/IBMPlexMono-500.woff2); }
:root { --amber: #ffb547; --ink: #e8eef7; --soft: #9ba8c0; --scope: #0b1428; --ring: #22355c; --strip: #f7edd6; --edge: #e0cfa8; }
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { width: 1200px; height: 1200px; overflow: hidden; }
body { background: radial-gradient(circle at 85% 12%, #16264a 0, var(--scope) 55%); color: var(--ink); font: 400 28px/1.4 AH; padding: 84px 84px 72px; display: flex; flex-direction: column; gap: 40px; position: relative; }
body::before { content: ""; position: absolute; right: -260px; top: -260px; width: 820px; height: 820px; border-radius: 50%;
  background: repeating-radial-gradient(circle, transparent 0 118px, var(--ring) 118px 120px); opacity: .55; }
.top { display: flex; justify-content: space-between; font: 500 20px/1 PM; letter-spacing: .14em; text-transform: uppercase; color: var(--soft); position: relative; }
.top .k { color: var(--amber); }
h1 { font: 800 112px/.9 BSD; text-transform: uppercase; letter-spacing: .005em; max-width: 15ch; position: relative; text-wrap: balance; }
h1 em { font-style: normal; color: var(--amber); }
.body { flex: 1; display: flex; flex-direction: column; justify-content: center; gap: 26px; position: relative; }
.note { font-size: 26px; color: var(--soft); max-width: 40ch; }
.foot { display: flex; align-items: center; gap: 18px; font: 500 22px/1 PM; color: var(--soft); position: relative; }
.foot img { width: 56px; height: 56px; }
.foot b { font: 800 34px/1 BSD; letter-spacing: .03em; text-transform: uppercase; color: var(--ink); }
.foot .url { margin-left: auto; color: var(--ink); }
.strips { list-style: none; display: flex; flex-direction: column; gap: 12px; }
.strip { display: grid; grid-template-columns: 96px minmax(0,1fr) auto auto; align-items: center; background: var(--strip); border: 1px solid var(--edge);
  border-left: 12px solid var(--tag); border-radius: 6px; font: 400 25px/1.3 PM; color: #0e1a33; min-height: 74px; }
.strip > * { padding: 14px 18px; min-width: 0; }
.strip .call { font-weight: 500; border-right: 1px solid var(--edge); letter-spacing: .04em; }
.strip .route { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.strip .route b { font-weight: 500; } .strip .route span { color: #4a5672; }
.strip .dest { font-weight: 500; white-space: nowrap; }
.strip .via { font-size: 19px; letter-spacing: .1em; font-weight: 500; color: var(--tag-ink); }
.strip[data-via="app"] { --tag: #8b6cf0; --tag-ink: #7457d6; }
.strip[data-via="tab"] { --tag: #e5534b; --tag-ink: #c2413a; }
.strip[data-via="rule"] { --tag: #2f9e6a; --tag-ink: #237c52; }
.strip[data-via="ask"] { --tag: #f5a524; --tag-ink: #a95b06; }
kbd { display: inline-grid; place-items: center; min-width: 58px; height: 58px; padding: 0 14px; font: 500 26px/1 PM; color: var(--ink);
  background: #13213f; border: 1px solid #2c4170; border-bottom-width: 4px; border-radius: 10px; }
.picker { background: rgba(232,238,247,.96); color: #0e1a33; border-radius: 26px; padding: 28px; box-shadow: 0 40px 80px -30px #000; display: flex; flex-direction: column; gap: 22px; }
.ph { display: flex; justify-content: space-between; font: 400 24px/1 PM; color: #4a5672; } .ph b { color: #0e1a33; font-weight: 500; }
.tiles { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; }
.tile { position: relative; display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 22px 10px 18px; border-radius: 18px; background: #fff; border: 2px solid #d2d9e4; }
.tile.sel { border-color: var(--amber); box-shadow: 0 0 0 4px rgba(255,181,71,.35); }
.av { width: 84px; height: 84px; border-radius: 50%; background: var(--c); color: #fff; display: grid; place-items: center; font: 800 46px/1 BSD; }
.tn { font: 700 26px/1.1 AH; } .ts { font: 400 19px/1 PM; color: #4a5672; }
.tile kbd { min-width: 40px; height: 40px; font-size: 20px; color: #0e1a33; background: #edf1f6; border-color: #d2d9e4; }
.pin { position: absolute; top: 10px; right: 12px; font-size: 26px; }
.pf { font-size: 24px; text-align: center; color: #4a5672; } .pf b { color: #0e1a33; }
.keymap { list-style: none; display: flex; flex-direction: column; gap: 20px; }
.keymap li { display: grid; grid-template-columns: 300px 1fr; align-items: center; font-size: 32px; }
.keys { display: flex; gap: 10px; align-items: center; }
.timer { align-self: flex-start; background: #13213f; border: 1px solid #2c4170; border-radius: 26px; padding: 36px 44px; display: grid; grid-template-columns: 1fr auto; gap: 8px 48px; align-items: center; min-width: 760px; }
.tl { font: 500 22px/1 PM; letter-spacing: .12em; text-transform: uppercase; color: var(--soft); grid-column: 1 / 3; }
.tb { font: 700 46px/1.2 AH; } .tc { font: 500 72px/1 PM; color: var(--amber); grid-row: 2 / 4; grid-column: 2; }
.tbtn { justify-self: start; font: 700 26px/1 AH; background: #e5534b; color: #fff; padding: 14px 28px; border-radius: 12px; }
.seq { list-style: none; counter-reset: s; display: flex; flex-direction: column; gap: 18px; }
.seq li { counter-increment: s; display: grid; grid-template-columns: 70px 260px 1fr; align-items: center; font-size: 30px; }
.seq li::before { content: counter(s); width: 54px; height: 54px; border-radius: 50%; border: 4px solid var(--ink); display: grid; place-items: center; font: 500 24px/1 PM; }
.seq li:last-child::before { border-color: var(--amber); color: var(--amber); }
.seq b { font-weight: 700; } .seq span { color: var(--soft); }
.term { background: #050b18; border: 1px solid #2c4170; border-radius: 20px; overflow: hidden; }
.dots { display: flex; gap: 10px; padding: 18px 22px; border-bottom: 1px solid #1c2d4f; } .dots i { width: 16px; height: 16px; border-radius: 50%; background: #2c4170; }
.term code { display: block; padding: 32px 30px; font: 400 31px/1.3 PM; } .term code span { color: var(--amber); }
.checks { list-style: none; display: flex; flex-direction: column; gap: 14px; font-size: 32px; }
.checks li::before { content: "✓"; color: #6fd3a0; font-weight: 700; margin-right: 18px; }
`;

cards.forEach((c, i) => {
  const n = String(i + 1).padStart(2, "0");
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body>
<div class="top"><span class="k">${c.label}</span><span>TrafficControl · ${n}/10</span></div>
<h1>${c.title}</h1>
<div class="body">${c.body}${c.note ? `<p class="note">${c.note}</p>` : ""}</div>
<div class="foot"><img src="${docs}/icon.png" alt=""><b>TrafficControl</b><span>Free · macOS 14+</span><span class="url">hakubo.github.io/TrafficControl</span></div>
</body></html>`;
  const file = join(tmp, `${n}.html`);
  writeFileSync(file, html);
  execFileSync(chrome, [
    "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
    "--allow-file-access-from-files", "--virtual-time-budget=2000",
    "--window-size=1200,1200", `--screenshot=${join(out, `week-${n}.png`)}`, `file://${file}`,
  ], { stdio: "ignore" });
  console.log(`week-${n}.png`);
});
