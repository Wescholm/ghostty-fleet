---
name: peekaboo-fork-ui
description: >-
  Observe or drive the running Ghostty Fleet fork's macOS UI with peekaboo — the left vertical
  sidebar, its tab cards (title / directory / git branch / status dots), the menu bar, and windows.
  Use this whenever you need to check that the sidebar renders, assert a card's title/dir/branch/dot
  state, exercise drag-reorder or the context menu, read or click the app's menu bar, screenshot the
  running fork, or drive any of its UI. ESPECIALLY reach for it the moment peekaboo's `see` / `image`
  / `capture` time out or report "window off-screen" on the fork — they do not work here, and this
  skill is the AX + `screencapture` path that does. Triggers: "test/verify the sidebar", "screenshot
  the fork app", "is the sidebar showing X", "click the tab card", "open the context menu", "read the
  menu bar", or any live macOS UI inspection of the fork.
---

# Peekaboo for the Ghostty Fleet UI

Use peekaboo to **observe and drive the running fork's macOS UI** — the vertical sidebar, tab cards,
menu bar, windows. This skill exists because peekaboo's pixel-capture tools fail on this fork in a
non-obvious way, and there's a reliable path around it.

## The one thing to know: AX works, screenshots don't

peekaboo has two tool families, and they behave very differently on this app:

- **Accessibility (AX) / AppKit** — `list`, `inspect-ui`, `menu`, `app`, `window`, `click`,
  `perform-action`, `type`, `press`, `dialog`. These read the accessibility tree / drive AppKit and
  **work reliably on the fork regardless of which display the window is on.**
- **ScreenCaptureKit pixel capture** — `image`, `see`, `capture`. These **fail on the fork**, two
  ways: a `SCShareableContent` timeout (the fork exposes ~14 windows — the quick terminal plus
  accessory surfaces — that bog down enumeration) and a `window off-screen` rejection when the
  window sits on a secondary display (negative coordinates). Every `--capture-engine`
  (cg/classic/modern/sckit) hits this — it's a window-resolution problem, not an engine one.

So **read/assert with AX, and grab pixels with `screencapture -l <window-id>`** — that captures by
CoreGraphics window id directly (any display, on- or off-screen, no enumeration). Don't reach for
`peekaboo see`/`image` here; you'll just burn time on timeouts.

## Always target the fork by PID

A release Ghostty (`/Applications/Ghostty.app`) may also be running as a process named `ghostty`.
Scope every command to the fork so you never read or drive the wrong app (same reason `make quit`
scopes to the fork's absolute path — see CLAUDE.md):

```bash
PID=$(pgrep -f "ghostty-sidebar/macos/build/Debug/Ghostty.app/Contents/MacOS/ghostty")
```

Then pass `--app PID:$PID` (or `--pid $PID`) to every peekaboo command below.

## Recipes

**Read / assert the sidebar — no screenshot, deterministic:**
```bash
peekaboo inspect-ui --app-target "PID:$PID"    # AX tree: sidebar list, card title, dir, child elements
```
> ⚠️ `inspect-ui` is the odd one out: it takes **`--app-target "PID:$PID"`** (with the literal `PID:`
> prefix), *not* the `--app PID:$PID` that `list`/`click`/`menu`/`type` use. A bare `--app` errors
> "Unknown option"; a bare numeric `--app-target 1234` errors "Application not found". You can also
> target by bundle id: `--app-target com.wescholm.ghostty-fleet`.
Prefer this for assertions ("does the card show branch X / the dirty dot") — it returns text, so
it's stable and diffable, unlike eyeballing pixels. Also available as the `mcp__peekaboo__inspect_ui`
MCP tool. If a long sidebar (this fork is built for *many* parallel sessions) gets truncated, raise
the AX traversal limits: `--max-elements` / `--max-depth` / `--max-children` (or set
`PEEKABOO_AX_MAX_ELEMENTS` / `PEEKABOO_AX_MAX_DEPTH` / `PEEKABOO_AX_MAX_CHILDREN`).

**`inspect_ui` also reads the terminal's *content*** — the focused surface's AX value carries the
on-screen text (prompt, command output). That's the reliable way to confirm *which session is
active* after a switch: echo a unique marker into a session (e.g. `echo SESSION-A`), switch away and
back, and assert the marker is present in the AX value — no screenshot, no flaky pixel diff. This is
how the in-app-session switch + keep-alive was verified end-to-end.

**Capture pixels (when you actually need an image):**
```bash
peekaboo list windows --app PID:$PID --include-details ids,bounds   # find the window id
screencapture -o -x -l <window-id> /tmp/fork.png                    # NOT peekaboo image/see
```

**Drive the UI (AX — no synthetic mouse, no screenshot):**
```bash
peekaboo inspect-ui --app-target "PID:$PID"          # get element ids first (note --app-target)
peekaboo click --on <id> --app PID:$PID              # click by element id, or:
peekaboo perform-action --on <id> --action AXPress   # AXShowMenu opens a card's context menu
peekaboo type "echo hi" --return --app PID:$PID      # types into the focused terminal surface
```
`type` (background delivery) lands in the *active session's* focused surface — handy to write a unique
marker into a session, switch away/back, and assert keep-alive via the terminal-content AX value.
`perform-action` invokes the accessibility action directly, so it works even when the window is
off-screen or unfocused — handy for exercising the sidebar (select a tab, open the context menu).

**Prefer element-id clicks (`--on <id>`) over coordinate clicks.** If you must click by point,
peekaboo's `click` coordinates are **window-relative**, not screen-global — a card click computed
against screen geometry will miss (this bit the Step 5 verification: a coord meant for the first card
landed outside its tappable area). Pass `--global-coords` to interpret the point as screen
coordinates, or just click by element id and sidestep the whole class of error.

**Read / click the menu bar:**
```bash
peekaboo menu list  --app PID:$PID                          # full menu structure (AX)
peekaboo menu click --app PID:$PID --path "File > New Tab"  # new in-app session (File, not Shell)
```
(Note: the fork's menu bar title + items still read "Ghostty", not "Ghostty Fleet" — see the
"Distinct name" note in CLAUDE.md. The Dock / ⌘-Tab / Finder read "Ghostty Fleet".)

## Launch / quit

Prefer the Makefile — `make dev` / `make run` / `make quit` build, scope to the fork's path, and
prune stale copies. `peekaboo app launch/quit` works but does none of that, and a broad quit risks a
release Ghostty hosting your session.

## Going deeper

`peekaboo learn` prints a ~1700-line built-in guide (kept in sync with the installed binary), and
`peekaboo <command> -h` documents each command's flags. Consult those rather than guessing —
peekaboo is broad (browser, agent, spaces, dock, dialogs…), but only the AX subset above is relevant
to this fork.
