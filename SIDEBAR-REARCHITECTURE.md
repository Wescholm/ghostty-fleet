# Sidebar re-architecture — in-app sessions

> Status: **decided, Step 0 landed.** This is the architecture direction for the sidebar fork.
> Companion docs: `ENHANCEMENTS.md` (today's sidebar features), `SIDEBAR-FORK-REPORT.md` (rebase/toolchain),
> `VALIDATION.md` (how the UI is verified).

## Vision

Make running **many parallel Claude Code / agent sessions** in Ghostty genuinely comfortable —
**like [cmux](https://github.com/manaflow-ai/cmux), but lightweight, high-performance, and stable.**

cmux is a *separate* native Swift/AppKit app that embeds **libghostty** as a rendering library (the way
apps embed WebKit) and re-implements the whole terminal-app shell around it (vertical tabs, splits,
embedded browser, socket API). This fork makes the opposite bet: **don't build a new app on libghostty —
*be Ghostty*, minimally patched.** We inherit the entire mature, GPU-fast, battle-tested Ghostty app and
its config/keybind ecosystem for free, and add only the agent-session sidebar (+ the `ghosttyctl` IPC we
already have). That is inherently more lightweight and stable than re-deriving a terminal — *provided we
don't fight the framework.*

### The three pillars → architecture mandate

| Pillar | What it demands | Architecture consequence |
|---|---|---|
| **Stable** | no self-inflicted bug treadmills; stay close to upstream | drop native window tabbing (deletes the macOS-26 tab-bar bug class); smallest possible diff from upstream so rebases stay trivial |
| **High-performance** | many sessions, only one visible | reuse Ghostty's GPU renderer untouched; **per-session occlusion** so hidden sessions draw nothing; single-container view swap, not N live Metal layers compositing |
| **Lightweight** | minimal new surface; no bloat | reuse `SplitTree`/`SurfaceView`/`TerminalController`; add only a `Session` type + the sidebar; **do not** re-implement the app shell or adopt `NavigationSplitView` |

## The problem with today's architecture

The sidebar is layered on top of **native macOS window tabbing**: each session is a separate `NSWindow`
in an `NSWindowTabGroup`, `SidebarTabManager` builds its cards by reading `window.tabbedWindows`, and the
fork then tries to **hide AppKit's tab UI** so only the sidebar shows. That fights the framework and keeps
generating bugs:

- macOS 26 renders the window tab bar as an **`NSToolbar`/`NSToolbarView`**; the fork's hider only catches
  the old `NSTabBar` class, so on Tahoe the native tab bar leaks through next to the sidebar.
- AppKit offers **no supported "keep the tab group, hide its bar" lever** (`NSWindowTabGroup.isTabBarVisible`
  is get-only); the only writable lever removes tabbing wholesale. Today's suppression is private
  view-hierarchy surgery against the Liquid-Glass titlebar region Apple just redesigned.
- Pristine upstream Ghostty hits the **identical** bugs (#9597, #12949, #7563, #9072, #8723, #9600) — it's
  an OS-vs-custom-chrome problem, not a fork defect, and it recurs every macOS release.
- Knock-on fragility: the hidden-titlebar `tabbingMode` dance, the traffic-lights/fullscreen entanglement,
  and per-window sidebar duplication all exist only because the sidebar rides on native tabbing.

## Decision

**Re-architect to in-app sessions, keep the AppKit shell.**

One `NSWindow` (one `TerminalController`) owns an ordered **`[Session]`** + `activeSessionIndex`. Each
`Session` is one `SplitTree<SurfaceView>` (so splits within a session still work). The sidebar switches the
active session; only the active session's surfaces are mounted/visible, with off-screen sessions kept alive
via explicit per-session `ghostty_surface_set_occlusion`. **Native window tabbing is disabled**
(`NSWindow.allowsAutomaticWindowTabbing = false`). The existing **AppKit `NSSplitView` +
`NSHostingView<SidebarView>`** shell is kept — we do **not** migrate to SwiftUI `NavigationSplitView`.

This is triple-confirmed by research:

- **Feasibility (Ghostty code):** `SurfaceView` owns its libghostty surface for its *object* lifetime (not
  view-hierarchy membership), and hidden surfaces keep running because occlusion is explicit; libghostty is
  target-agnostic ("new tab" is a Swift-side convention). Verified **feasible, high confidence.**
- **Peer apps:** Zed disables native tabbing (PR #26600); WezTerm/Kitty/Warp/iTerm2/VS Code all do in-app
  sessions; cmux embeds libghostty with fully in-app sessions. Upstream Ghostty intends to drop native tabs
  (#10711) — so this converges *toward* upstream.
- **Apple guidance:** the HIG says *prefer a split view / in-window panes over new windows*; native tabbing
  isn't deprecated but is de-emphasized; and Apple's own recommended AppKit-interop pattern (WWDC22-10075)
  is *a SwiftUI sidebar hosted in an `NSSplitView`* — i.e. the fork's existing shell.

### Why not the alternatives

- **A — keep native tabs, harden suppression:** fails *stable* — a perpetual treadmill of private-hierarchy
  surgery in the highest-churn upstream files (`Window Styles/*`), re-broken each macOS release.
- **C — `NavigationSplitView` SwiftUI rewrite:** fails *lightweight* — it still needs B's full session
  refactor underneath, discards the working AppKit shell, and on the Xcode-26 SDK makes the sidebar a
  *floating Liquid-Glass panel that refracts/insets the detail* — bad over an opaque Metal terminal
  (re-importing the exact chrome-bug class we're removing). It also rebuilds the detail per selection.
- **D — hybrid (B + native tabbing for multi-window grouping):** a strict superset of B whose headline
  benefit is self-contradictory (it only avoids the treadmill if it accepts an un-suppressed native tab bar).
- **cmux-style re-derivation on libghostty:** fails *lightweight + stable* — a whole new app shell to build
  and maintain against a less-mature embedding API. The fork sidesteps this by being Ghostty.

## Core design

### Session model

- `Session`: wraps one `SplitTree<SurfaceView>` + per-session metadata (title/override, color, status, the
  surface-UUID-keyed git/activity state we already track).
- `BaseTerminalController` generalizes from a single `@Published surfaceTree` to an ordered `[Session]` +
  `activeSessionIndex`, with a computed `activeSurfaceTree` bridging the existing `TerminalView` mount.
  `focusedSurface` stays driven by the active session (command palette / window title already key off it).
- `SidebarTabManager` becomes `@Observable @MainActor`, holding `[Session]` + `selectedSessionID` + the live
  NSView store. It **stops** reading `window.tabbedWindows` / calling `makeKeyAndOrderFront`; selection just
  sets `selectedSessionID`.

### Keep-alive content host (the performance crux)

Apple's `NavigationSplitView`/Landmarks pattern *rebuilds the detail per selection* — fatal for a live
terminal surface (`dismantleNSView` would kill the shell). So the content area is a **constant host**:

- Retain **all** session surfaces in the long-lived `@Observable` store keyed by session id; create each
  surface exactly once on session-create, free only on session-close.
- Swap the visible session by toggling **`isHidden`/subview order** in a single container `NSView` (or
  `opacity`/`zIndex` if done in SwiftUI) — **never** `if`/conditional/rebuild.
- Drive hidden sessions to **stop drawing** via per-session `ghostty_surface_set_occlusion` (replaces the
  window-level occlusion sync) → only the visible session uses the GPU. Validate this holds at ~20–30
  sessions.
- On switch: **mount-then-focus** (the existing `moveFocus` retry only loops while `window == nil`, which is
  the permanent state of an unmounted view — it will not save you; sequence focus explicitly).

### Session status model + Claude Code hook integration

Custom card logic is a first-class goal — and in-app sessions make it easier (the `Session` *is* the source
of truth; no side-tables keyed off window identity). Generalize today's two dots into an explicit
`Session.status`, fed by layered signals (authoritative source wins; heuristics are automatic fallback):

| State | Meaning | Authoritative source | Automatic fallback |
|---|---|---|---|
| **running** | agent/command actively working | agent pushes via IPC | CPU busy (existing poll) / OSC 133 command-start |
| **waiting** | blocked on the user (question/approval) | **agent pushes via IPC** | running process + low CPU + stdin-blocked heuristic |
| **idle** | shell at prompt, nothing running | OSC 133 command-end | low CPU, no running command |
| **done / attention** | finished / needs you | agent IPC + bell/notify | bell (existing attention) |
| **error** | last command failed | OSC 133 exit code ≠ 0 | — |

The card (SwiftUI `SidebarTabCard`) renders the state however we like (color, icon, spinner, label).

The reliable "waiting for input" signal is **the agent reporting it**, which the fork is uniquely
positioned for because it already has the `ghosttyctl` IPC + `TabMetadataStore`. Wire **Claude Code hooks →
`ghosttyctl`** (event-driven → lightweight + accurate → stable):

- **Notification** hook (needs permission/input) → `ghosttyctl set-status state waiting`
- **Stop** hook (finished) → `ghosttyctl set-status state done` (+ optional `notify`)
- tool start/stop → `running` / back to `waiting`/`idle`

Ship a ready-made hook snippet so a Claude Code user gets live "running / waiting / done" per session out of
the box, with the CPU/OSC-133 heuristics as fallback for non-reporting sessions. This is the differentiator
over cmux: deep, agent-aware, per-session state because the fork owns both the cards and the IPC.

## Migration plan

- **Step 0 — de-risk (done & validated):** the `FleetDisableNativeTabs` flag disables native tabbing
  in **two** places — `NSWindow.allowsAutomaticWindowTabbing = false` (automatic tabs) **and**
  short-circuiting `addTabbedWindowSafely` to return `false` (Ghostty's *explicit* tabbing chokepoint).
  `allowsAutomaticWindowTabbing` alone is **not** enough — Ghostty tabs explicitly via
  `addTabbedWindow`, so the first attempt still formed a tab group; gating the chokepoint fixed it.
  Verified at runtime in the transparent style: with the flag on, Cmd+T opens a **standalone window**,
  no `NSWindowTabGroup` forms, and the macOS-26 `NSToolbar` tab strip is gone (AX shows one sidebar
  card and no "tab bar" element). Validates the thesis before the refactor.
- **Step 1:** introduce the `Session` model (wrap one `SplitTree<SurfaceView>` + metadata) without removing
  `surfaceTree` yet.
- **Step 2:** generalize `BaseTerminalController` to `[Session]` + `activeSessionIndex` + `activeSurfaceTree`.
- **Step 3:** implement session switching (mount active tree, per-session occlusion, mount-then-focus).
- **Step 4:** reimplement tab lifecycle (new/close/goto/move) as `[Session]` array ops; `newWindow` stays a
  real window; Cmd+T → new in-app session.
- **Step 5:** rewrite `SidebarTabManager` to read `controller.sessions` (delete the `tabbedWindows` /
  `refreshAllSidebars` machinery); add the `Session.status` model here.
- **Step 6:** migrate IPC resolvers to iterate `controller.sessions`; replace `handleTabFocus`'s
  `makeKeyAndOrderFront` with a `selectSession()` API (`GHOSTTY_TAB_ID` is already a per-surface UUID).
- **Step 7:** reimplement undo/redo in terms of `(controller, sessionIndex)` (net-new code).
- **Step 8:** new single-window multi-session `TerminalRestorableState` (serialize the array of
  `SplitTree`s + `activeSessionIndex`); bump the format version and raise `minimumVersion` to **reject
  pre-rework state once** (one-time reset, no migration — Scope decision 2).
- **Step 9:** audit the long tail of native-tab references (AppDelegate hide-others / Show-All-Tabs,
  AppleScript, `Fullscreen.swift`, `TabTitleEditor`, `TabGroupCloseCoordinator`, `NSWindow+Extension`).
- **Step 10:** remove/disable the dropped native-tab menu items (Show All Tabs, Merge All Windows,
  move/drag between windows) — out of scope under single-window (Scope decision 3); the sidebar
  replaces them.
- **Step 11:** verify with `make test` + the `peekaboo-fork-ui` skill (switch focus/IME, off-screen sessions
  stay live, restoration round-trips N sessions, fullscreen/traffic-lights no longer touch tab chrome);
  remove the dead suppression code.

## Risks

- **First-responder / IME on switch** is the main depth-risk — sequence mount-then-focus explicitly.
- **Per-session occlusion** is mandatory (window-level occlusion would mark all sessions visible).
- **Restoration** is net-new code (array of trees + version bump); getting backward-compat wrong loses
  users' windows on upgrade.
- **Undo/redo** is deeply tab-group-entangled — a from-scratch rewrite with subtle ordering bugs.
- **Rebase cost** rises in `BaseTerminalController`/`TerminalController`; mitigated long-term because upstream
  intends the same direction and the high-churn `Window Styles/*` suppression hacks shrink.
- **Lost OS niceties** (Show All Tabs, native drag) must be hand-built or consciously dropped.

## Scope decisions (resolved)

1. **Single window.** No multiple real windows and no "move session to another window" (for now): one
   `NSWindow` / one `TerminalController` / N sessions. This simplifies undo, restoration, and IPC (no
   cross-window or tab-group machinery to reimplement). `Cmd+T` *and* `Cmd+N` both create a new
   in-app session.
2. **Restoration: one-time reset on upgrade** — do *not* migrate old per-window/tab-group state. The
   old model doesn't map onto single-window/N-sessions, and migration code is one-time cost plus
   long-tail risk. Bump the restorable `minimumVersion` to reject pre-rework state once; the new
   single-window/N-session format restores reliably afterward.
3. **Drop the native-tab niceties.** Under single-window scope, "move/drag between windows" and "Merge
   All Windows" are moot, and "Show All Tabs" is replaced by the sidebar itself (which already has
   drag-reorder). Remove/disable their menu items; nothing to reimplement.

## Step 0 — how to run the validation

Off by default (no behavior change). To validate the thesis:

```sh
# persistent toggle
defaults write com.wescholm.ghostty-fleet FleetDisableNativeTabs -bool YES
open macos/build/Debug/Ghostty.app
# or, one-off via launch arg (NSUserDefaults argument domain)
open macos/build/Debug/Ghostty.app --args -FleetDisableNativeTabs YES
```

With the flag on, no `NSWindowTabGroup` can form, so the macOS-26 `NSToolbar` tab strip never appears and the
suppression code path is dead. (Interim: Cmd+T opens a new window rather than an in-app session — that lands
in Step 4.)

The flag gates two code paths: `NSWindow.allowsAutomaticWindowTabbing = false` in
`AppDelegate.applicationWillFinishLaunching` (blocks *automatic* tabbing) and an early `return false` in
`NSWindow.addTabbedWindowSafely` (blocks Ghostty's *explicit* tabbing — the load-bearing one; automatic-only
was insufficient). Both read `UserDefaults.standard.bool(forKey: "FleetDisableNativeTabs")`.
