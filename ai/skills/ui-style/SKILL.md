---
name: ui-style
description: Anthony's personal UI style for web pages, Claude artifacts and native macOS apps (SwiftUI, AppKit, Hermes). Load before designing or styling any page or app interface, so it gets this look instead of a default template look. Not for terminal output. Do NOT use it when the working directory is under ~/projects/work/ (those projects follow their own design); add further excluded folders to this sentence.
user-invocable: true
disable-model-invocation: false
---

# UI style — "Technical", version 1

Plain on purpose. An ornamental version (border bands, gold leaf, pink and
green) is deferred until it is researched from real examples; see **Later**.
Until then, use exactly what is here and do not add decoration.

Chosen interactively on 2026-11-12 from `.cc/misc/style-lab.html` (direction C).
`.cc/misc/style-lab-2.html` holds the ornament experiments that were set aside.

## Principles

1. **Labels and indent, not boxes.** A section is a caps mono label, then its
   content indented 16px. No card around a section, no divider lines between
   sections. A border is for things you act on (inputs, buttons, a toast).
2. **Comfortable density.** Title, then a one-line muted summary under it. 20px
   between sections, 2px between rows of a list. Tables are aligned columns with
   no grid lines.
3. **Gray carries everything; color means status.** Green good, amber warning,
   red bad. Always pair the color with a word or symbol, never color alone.
   No brand or accent hue.
4. **One emphasis per screen.** One primary button, filled with the text color.
   Every other button is outlined.
5. **Numbers are mono and tabular,** so columns of times and counts line up.
6. **Motion is for state, not entrance.** At most a 150ms fade or slide when
   something changes. Nothing animates on load. No animated counters.
7. **Plain copy.** Sentence-case headings, short labels, real content. No filler
   or lorem, no marketing voice.
8. **Light and dark are equal.** Design and check both, every time.

## Never do

These are what make a page read as AI-generated:

- Gradient backgrounds, glow, glassmorphism or blur.
- Purple or indigo accents.
- A centered hero over three equal feature cards.
- Cards inside cards, or a card around every section.
- Drop shadows. Use a 1px border where an edge is needed.
- An icon on every label, or emoji used as icons.
- Large radius everywhere. The radius is 4px.
- Several "wow" effects. This style has none.

## Tokens

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#fbfcfd` | `#0f1216` | page or window |
| `fg` | `#111418` | `#e6e9ed` | text, primary button fill |
| `muted` | `#5b6470` | `#8b95a1` | labels, summaries, numbers, idle |
| `line` | `#dde1e6` | `#262c33` | quiet edges |
| `line-strong` | `#b8c0ca` | `#3d4650` | input and secondary-button borders |
| `field` | `#ffffff` | `#161a1f` | input background |
| `raised` | `#f1f3f5` | `#181c22` | toast, popover |
| `ok` | `#1a7f37` | `#3fb950` | good status |
| `warn` | `#9a6700` | `#d29922` | warning status |
| `bad` | `#cf222e` | `#f85149` | failure, destructive (also bold) |

| Type role | Face | Size / weight | Notes |
|---|---|---|---|
| Body | IBM Plex Sans | 15px / 400, line height 1.55 | fallback `system-ui` |
| Title | IBM Plex Sans | 22px / 600 | one per screen |
| Label | IBM Plex Mono | 12px / 600, caps, 0.02em tracking | `muted` color |
| Number | IBM Plex Mono | inherit, tabular | `muted` unless it is the point |

Radius 4px (toast 8px). Focus ring: 2px `fg` outline, 1px offset.

## Web

```html
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">
```

```css
:root {
  --bg:#fbfcfd; --fg:#111418; --muted:#5b6470; --line:#dde1e6; --line-strong:#b8c0ca;
  --field:#ffffff; --raised:#f1f3f5; --ok:#1a7f37; --warn:#9a6700; --bad:#cf222e;
  --sans:"IBM Plex Sans", system-ui, sans-serif; --mono:"IBM Plex Mono", ui-monospace, monospace;
  --radius:4px;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg:#0f1216; --fg:#e6e9ed; --muted:#8b95a1; --line:#262c33; --line-strong:#3d4650;
  --field:#161a1f; --raised:#181c22; --ok:#3fb950; --warn:#d29922; --bad:#f85149;
} }
:root[data-theme="dark"] {
  --bg:#0f1216; --fg:#e6e9ed; --muted:#8b95a1; --line:#262c33; --line-strong:#3d4650;
  --field:#161a1f; --raised:#181c22; --ok:#3fb950; --warn:#d29922; --bad:#f85149;
}

body   { background:var(--bg); color:var(--fg); font:15px/1.55 var(--sans); }
h1     { font-size:22px; font-weight:600; margin:0; }
.sub   { color:var(--muted); margin:4px 0 22px; }
.label { font:600 12px var(--mono); letter-spacing:.02em; text-transform:uppercase; color:var(--muted); margin:20px 0 6px; }
.indent{ padding-left:16px; }
.num   { font-family:var(--mono); font-variant-numeric:tabular-nums; color:var(--muted); }
.rows  { display:grid; grid-template-columns:max-content max-content 1fr; column-gap:28px; row-gap:2px; }
.ok { color:var(--ok); }  .warn { color:var(--warn); }  .bad { color:var(--bad); font-weight:600; }  .idle { color:var(--muted); }
a      { color:var(--fg); text-decoration-color:var(--line-strong); text-underline-offset:3px; }
input  { font:inherit; color:var(--fg); background:var(--field); border:1px solid var(--line-strong);
         border-radius:var(--radius); padding:7px 10px; }
button { font:inherit; font-weight:500; border-radius:var(--radius); padding:7px 14px; cursor:pointer; }
.primary   { background:var(--fg); color:var(--bg); border:1px solid var(--fg); }
.secondary { background:transparent; color:var(--fg); border:1px solid var(--line-strong); }
:focus-visible { outline:2px solid var(--fg); outline-offset:1px; }
.toast { display:flex; gap:12px; max-width:360px; background:var(--raised); border:1px solid var(--line);
         border-radius:8px; padding:12px 14px; }
```

When a page is a Claude artifact, the artifact contract still applies (title,
CDN rules, phone width). This skill decides only the look.

## Native (SwiftUI / AppKit)

- **Color:** put each token in the asset catalog with Any and Dark
  appearances, or build a dynamic `NSColor(name:dynamicProvider:)`. Never
  hard-code one mode.
- **Type:** bundle IBM Plex Sans and Mono when the app ships fonts. Otherwise
  use `.system(size: 15)` for body and `.system(size: 12, design: .monospaced)`
  for labels and numbers, with `.monospacedDigit()` on number columns.
- **Layout:** the same 16pt indent, 20pt section gap and one primary button.
  Use plain `List`/`Table` styles with no alternating rows or separators where
  the platform allows it.
- **Notifications:** title is the source ("Server check"), body is one sentence
  saying what is true.

## Check before calling it done

1. Render it in both themes. For web, headless Brave:
   `"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" --headless=new --screenshot=OUT.png --window-size=1240,1400 file://PAGE`
   Then set `data-theme="dark"` on `<html>` (in a copy of the page) and render it again.
2. Look at the screenshot against **Principles** and **Never do**, one by one.
3. Check that each status still reads without its color.

## Later

- Ornament layer: research real Art Nouveau, Rococo, illuminated-manuscript and
  Art Deco examples (images, not memory), then decide whether a single border
  band, gold-leaf headings and a pink/gold/green palette join this style.
  Status colors must stay separate from any decorative green or gold.
