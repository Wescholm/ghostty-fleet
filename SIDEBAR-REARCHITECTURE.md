# Sidebar re-architecture — in-app sessions

> Status: **Steps 0–8 landed & verified** (in-app sessions are the live default; native window
> tabbing is off by default; IPC-over-sessions / G1 reaches background sessions; per-session bell
> attribution / G2 done; per-session lifecycle status dot + Claude Code hooks done; multi-session
> restoration / Step 8 — quit→relaunch restores all sessions in one window; undo/redo / Step 7 —
> closing a session is undoable, process and scrollback intact). Remaining tail is cleanup/polish —
> see **Next steps** below. This is the architecture direction for the sidebar fork.
> Companion docs: `ENHANCEMENTS.md` (today's sidebar features), `SIDEBAR-FORK-REPORT.md` (rebase/toolchain),
> `VALIDATION.md` (how the UI is verified).
>
> **Baseline: macOS 26+.** The macOS app's deployment target was raised from 13.0 to 26.0 (all three
> app configs), which unlocks the Observation framework's `@Observable` and Liquid Glass / macOS-26
> APIs without availability guards. Consequence: the obsoleted `openAppWhenRun` (<26) fallback was
> removed from `NewTerminalIntent` (the only App Intent that still carried it). The Zig core's
> `osVersionMin` (`src/build/Config.zig`) is still 13.0.0 — harmless (the app gates at 26 via
> `LSMinimumSystemVersion`); raise it for consistency whenever a full `make build` is next run.

## Next steps (remaining work)

Steps 0–8 are done; the core in-app-sessions feature set works. What's left is **cleanup + polish**,
not core function. A full audit ran 2026-06-24 (**`AUDIT-REPORT.md`**); its close/quit data-loss cluster
(H3/H4/H5), the `FleetDisableNativeTabs` chokepoint default (M3), and the shared new-tab routing (M4) are
**fixed** — remaining audit items are folded into "Audit follow-ups" below. Roughly in priority order:

- [x] **Step 9 — audit native-tab code (done; decision: keep the flag, delete nothing).** A verified
      multi-agent audit (2026-06-24) classified every native-tab reference by origin × reachability. Key
      finding: the native-tab bodies (`closeTab`/`closeOtherTabs`/`closeTabsOnTheRight` + their
      `*Immediately` helpers and `tabGroup`/`UndoState` undo; the static `newTab` body + New-Tab undo;
      `onGotoTab`/`onMoveTab` native paths; `addTabbedWindowSafely`; `TabGroupCloseCoordinator`;
      `TabTitleEditor`; the window-style tab plumbing) are **upstream-verbatim** — the fork's footprint is
      only thin *prepended* flag-guards. Deleting them would *grow* the diff from upstream (against the
      stability pillar) and break the documented `FleetDisableNativeTabs=false` fallback, and they
      self-neutralise with the flag on (no `NSWindowTabGroup` ever forms → every branch guard-returns).
      **Decision: keep the flag as the fallback, delete nothing.** The audit's two flag-on defect
      candidates: `move_tab` (⌃⇧PageUp/Down) was a real no-op for sessions — **fixed** (emitter +
      `onMoveTab` session branch, parity with goto_tab/M5; commit `c696559c0`); the `validateMenuItem`
      "Close Tabs to the Right" force-disable was a **false positive** (that AppKit item only lives in the
      native tab context menu — `isTabContextMenu` — which never forms with the flag on, so it is never
      shown). The aggressive deletion (remove the flag + delete the upstream native-tab code across ~8
      files, rewriting upstream callers) is the `planFlagPermanent` path — deferred unless upstream itself
      drops native tabbing. See `AUDIT-REPORT.md` for the full dual-path plan.
- [ ] **Step 10 — drop the moot native-tab menu items** (Show All Tabs, Merge All Windows) — Scope
      decision 3; the sidebar replaces them.
- [ ] **Step 11 — full UI pass + `make test`.** Exercise switch/IME, off-screen keep-alive, restoration
      round-trip, fullscreen/traffic-lights, and the status/undo flows end-to-end.
- [ ] **Title-layer unification.** Renaming the *active* session (sidebar / `ghosttyctl rename`) updates
      its card but **not** the window titlebar (titlebar reads `controller.titleOverride`; rename sets
      `session.titleOverride`). `promptTabTitle` (⌘⇧I) is the inverse. Unify so the window chrome tracks
      `activeSession.titleOverride`; folds together with the `promptRenameTab` per-session-prompt TODO.
- [ ] **`make test` codesign papercut.** The test-host app is built into DerivedData and sets its icon
      at launch → `com.apple.FinderInfo` detritus → next codesign fails ("resource fork… not allowed").
      Add `xattr -cr "<DerivedData>/…/Debug/Ghostty.app"` to the Makefile `test` target (the `app`/`dev`
      targets only clean `macos/build`). Manual fix today: `xattr -cr` that DerivedData copy.
- [ ] **Richer OSC-133 status signals** (non-agent fallback for `Session.status`): `.error` on a
      non-zero command exit, prompt-mark → `.idle` / running → `.running`.
- [ ] **Undo grouping for bulk close** (Close Other Tabs / Close Tabs to the Right): today each closed
      session registers its own undo (one ⌘Z per session). Group them so one undo restores the set.
- [ ] **Raise the Zig core's `osVersionMin`** (`src/build/Config.zig`) to 26.0.0 on the next full
      `make build` (cosmetic; the app already gates at 26 via `LSMinimumSystemVersion`).
- [ ] **Confirm two keybinds with a physical keypress.** `⌘⇧Z` redo and `⌃⇧PageUp/Down` `move_tab`
      (session reorder, Step 9) couldn't be driven through peekaboo / AppleScript synthetic events. The
      redo *action* (menu) works, and `Cmd+T` fires fine via the same synthetic pipeline, so this is a
      special-key delivery (harness) artifact, not an app bug. Both are correct by construction (`move_tab`
      mirrors goto_tab/M5 and uses the unit-tested `moveSession`); verify each once by hand.

### Audit follow-ups (2026-06-24 — see `AUDIT-REPORT.md` for full detail)

Nearly all of the audit's verified findings landed in the fix batch (commits `3f0f48289..eac89cd98`,
pushed to `origin/dev`). Status:

- [x] **H3/H4/H5 — close/quit data-loss cluster.** Session-aware confirm (`anySessionNeedsConfirmQuit`),
      close-window undo restores *all* sessions, bulk-close IBActions route to `closeSession`, last-session
      close → `performClose`. (`3f0f48289`, `963e566b3`.)
- [x] **M3 — `FleetDisableNativeTabs` chokepoint default.** One shared `BaseTerminalController.nativeTabsDisabled`
      (`?? true`) accessor replaces all three reads incl. the load-bearing `NSWindow+Extension` chokepoint. (`3f0f48289`.)
- [x] **M4 — shared new-tab routing.** Static `TerminalController.newTab` → `newSession` (covers
      `AppDelegate.newTab` + `NewTerminalIntent`). (`963e566b3`.)
- [x] **H2 — IPC stale-socket race.** Probe-connect before unlink; `stop()` only unlinks if we still own the
      inode. *(H1 "ghosttyctl hangs" was a verified **false positive** — it returns in ~10 ms; do not chase
      it.)* (`3f34d58cf`.)
- [x] **M1 — background session surface death.** `ghosttyDidCloseSurface` searches every session's tree,
      removes the node, and drops the session when its tree empties. (`a2632639a`.)
- [x] **M5 — keyboard session switching.** `onGotoTab` (+ the App-level `gotoTab` handler) routes
      `goto_tab` to `selectSession` when the flag is on. (`bfb38b73e`.)
- [x] **M6 — occlusion-gate the sidebar pollers.** The refresh / CPU / git timers suspend on
      `didChangeOcclusionState` and re-arm + refresh on becoming visible. (`c2a8083d4`.)
- [x] **M7 — `ghosttyctl` JSON escaping.** `json_escape` now covers C0 controls (`python3 json.dumps` with
      a bash fallback). (`95315ba2f`.)
- [x] **Tests.** `effectiveStatus` precedence, `SessionStatus` contract, `TabMetadataStore` (`dac41d518`);
      session index-math extracted into pure `SessionIndexMath` + `SessionIndexMathTests` (M2, `eac89cd98`);
      pre-v8 `sessions == nil` back-compat assertion. (~260 tests, all passing.)
- [x] **Docs sweep.** AGENTS.md "In flight" callout, README dot legend + `ghosttyctl state`,
      SIDEBAR-FORK-REPORT.md, stale code comments, test counts. (`d26434d05`.)
- [x] **Tail hardening.** `selectSession` async-focus generation token (L1), `ClosedSession.leftNeighborId`
      anchored to a neighbor's identity (L5), `gitInfoCache` prune (L8), `FD_CLOEXEC` on the IPC fds (L13).
      (`dde1321cc`.)

**Deferred — lower value / higher risk (revisit later, not blocking):**

- [ ] **L4/L11 — `@Observable`/event-driven sidebar** instead of the 0.5 s republish-everything poll
      (Apple Observation guidance). A larger refactor; M6 occlusion-gating already removed the energy
      concern, so this is now an optimization, not a correctness fix.
- [ ] **L27 — IPC dispatch/resolver test seam.** Verb dispatch + `resolveTarget`/`resolve(surfaceId:)`
      are still only coverable end-to-end; a pure, unit-testable seam needs a small refactor.
- [ ] **L16 — restoration downgrade path.** A v8→v7 writer that keeps the active tree top-level so an
      older build could still open the active session. Rare (downgrade-after-upgrade); deferred.

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

**Shipped** as `cli/claude-hooks.example.json` (`ghosttyctl state running|waiting|done`), so a Claude Code
user gets live "running / waiting / done" per session out of the box, with the CPU heuristic as fallback
for non-reporting sessions (OSC-133 still a future source). This is the differentiator over cmux: deep,
agent-aware, per-session state because the fork owns both the cards and the IPC. (Note: lifecycle state
uses the dedicated `tab.set-state` verb / `Session.status`, **not** the key/value `tab.set-status` store.)

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
- **Step 3 (done):** `selectSession(at:)` — mount the active tree, occlude the outgoing session's
  surfaces, mount-then-focus. Hardened per adversarial review: rebinds the title listener via
  `focusedSurfaceDidChange(to:)`, resigns the outgoing first responder via `moveFocus(to:from:)`,
  re-syncs focus after the async settles, and re-applies the color scheme to the newly mounted surfaces.
- **Step 4 (done):** `newSession(baseConfig:)` creates a fresh surface + Session and switches to it;
  `closeSession(at:)` (switches to a sibling *before* the active tree empties — E1 guard; closes the
  window when the last session goes) and `moveSession(from:to:)` round out the `[Session]` array ops.
  Cmd+T (and Cmd+N) now route to `newSession` when the flag is on.
- **Step 5 (core done & verified):** `SidebarTabManager` was rewritten to build its cards from
  `controller.sessions` (the `tabbedWindows` / `refreshAllSidebars` / `window: NSWindow` machinery is
  gone; `TabItem.id` is now the `Session`'s `UUID`); it observes the controller via
  `objectWillChange`, and sidebar selection → `selectSession`, close → `closeSession`, drag-reorder →
  `moveSession`. `FleetDisableNativeTabs` is **flipped on by default**. The `Session.status` model
  exists. **Verified e2e** (peekaboo-fork-ui): Cmd+T makes an in-app session, switching both
  directions works, the off-screen session stays live (keep-alive), and no native tab bar / no crash.
  **`Session.status` rendering — done & verified:** the card shows one **status dot** colored by the
  session's effective state (`SidebarTabManager.effectiveStatus` merges agent-reported `Session.status`
  with the bell/notify attention flag and the CPU "working" heuristic; precedence **attention > error >
  waiting > running > done > idle**; idle = no dot). Colors: orange/red/yellow/green/blue
  (`SidebarTabCard.statusColor`). Fed by a new IPC verb `tab.set-state` → `Session.status`, exposed as
  `ghosttyctl state <idle|running|waiting|done|attention|error>`, with a ready-made Claude Code hooks
  snippet at `cli/claude-hooks.example.json` (UserPromptSubmit→running, Notification→waiting,
  Stop→done; each hook inherits `GHOSTTY_TAB_ID` so it targets its own session, background included).
  Verified e2e: each state renders the right color on the right (incl. background) card, idle shows no
  dot, CPU activity overrides a stale done/idle to running. **Future:** richer OSC-133 signals (error
  on non-zero exit, prompt-mark idle/running) as an additional non-agent source.
  **Still pending in Step 5's scope:** nothing — the two review-mandated
  wirings are now **done**: IPC-over-sessions (G1, see Step 6) and per-session **bell attribution**
  (G2) — the sidebar drives attention from the per-surface `.ghosttyBellDidRing` notification (which
  carries the originating surface) instead of the controller-level `.terminalWindowBellDidChange`
  aggregate, whose `surfaceValuesPublisher` only watches the *mounted* tree and so never saw a
  background session's bell. Verified e2e: a delayed BEL armed in a session that's then backgrounded
  rings while occluded and lights the orange dot on **its** card (not the active one), and the dot
  clears when the session is visited. Gated on `bell-features` containing `attention` (unchanged).
  Desktop notifications + IPC notify already carried the surface, so they were per-session correct.
- **Step 6 / G1 (done & verified):** `GhosttyIPCServer` resolution now searches every session's tree,
  not just the mounted one, so `ghosttyctl` reaches **background** sessions. Concretely: `resolve(surfaceId:)`
  / `resolveTarget(params:)` iterate `controller.sessions[].surfaceTree`; `tab.list` emits one entry **per
  session** (so background sessions are discoverable, not one-per-window); `tab.focus` calls
  `selectSession()` (switches the in-app session, not just `makeKeyAndOrderFront`); `tab.rename` sets the
  *session's* `titleOverride`; and `tab.set-status`/`clear-status` key `TabMetadataStore` by **session id**
  (so status follows the session across surface swaps/splits). `tab.notify` posts the originating *surface*
  so the sidebar attributes attention to the owning session (the old window-object path was the G1 TODO).
  `SidebarTabManager` reads status by session id and clears attention for whatever session becomes active
  (so an IPC `focus` that bypasses `selectTab` can't leave a stale dot). **Verified e2e** (peekaboo-fork-ui,
  3 sessions): `list` shows all sessions; set-status / rename / notify / focus all land on the correct
  *background* card; per-session keep-alive holds (each session keeps its own scrollback across switches);
  no crash. **Known follow-up (not G1):** renaming the *active* session updates its card but not the window
  titlebar — the titlebar still reads `controller.titleOverride` while sidebar + IPC rename set
  `session.titleOverride`. This is a pre-existing title-layer split (the Cmd+Shift+I `promptTabTitle` dialog
  is the inverse: it updates the titlebar but not the card). Unify the title layer so the window chrome
  tracks `activeSession.titleOverride` — folds together with the `promptRenameTab` per-session-prompt TODO.
- **Step 7 (done & verified):** closing an in-app session is now undoable. `closeSession(at:)`
  snapshots the closing session (tree + status + title + color + index + wasActive + focused surface)
  and registers an undo on the shared `ExpiringUndoManager`; the undo closure *retains the surfaceTree*,
  so the session's surfaces stay alive (occluded) until the undo is invoked or expires
  (`undo-timeout`, default 5s) — making a close fully reversible **with its running process and
  scrollback**, after which the surfaces are released and the ptys die. `restoreClosedSession` re-inserts
  the session at its index (re-selecting + refocusing if it was active) and registers the matching redo;
  redo re-closes (re-registering undo), so the chain holds across cycles. Because close is reversible,
  no running-process confirmation prompt is needed. Also routed `TerminalController.closeSurface`: when
  the active session is the root being closed and there is >1 session, it closes **that session** (not
  the window) — so Cmd+W (close_surface) now closes the active tab, undoably; the last session still
  closes the window. Verified e2e: Cmd+W close → undo restores the live session (a unique echo marker
  came back) → redo re-closes → undo again, marker still live; menu Undo/Redo + Cmd+Z work and
  `canUndo`/`canRedo` are correct. (Note: the Undo/Redo *menu items* have no key equivalent; Cmd+Z /
  Cmd+Shift+T undo and Cmd+Shift+Z redo come from libghostty's default keybinds. The Cmd+Shift+Z redo
  keybind didn't reproduce through the test harness's synthetic events — undo keybinds and the redo
  *action* itself all work — likely a synthetic-event artifact, not app logic.)
- **Step 8 (done & verified):** `TerminalRestorableState.InternalState` now carries an optional
  `sessions: [SessionState]` (each = `SplitTree` + `status` + `titleOverride` + `tabColor`) +
  `activeSessionIndex`; the format version is bumped 7→**8**. On encode the top-level `surfaceTree` is
  left empty (every tree, incl. the active one, lives in `sessions`) so the active session's surfaces
  aren't decoded twice. `restoreWindow` rebuilds all sessions into **one** window via the new
  `BaseTerminalController.restoreSessions(_:activeIndex:)` (mounts the active session, occludes the
  rest); a pre-v8 archive (no `sessions` key) falls back to the unchanged single-tree path.
  **Deviation from Scope decision 2 (deliberate, strictly better):** `minimumVersion` is kept at **5**,
  *not* raised — so no forced one-time reset. Pre-v8 archives still restore (a single window → one
  session) via the legacy path, which is unchanged code (no migration risk); only the new v8 format
  carries multiple sessions. This avoids losing users' windows on upgrade. Verified e2e: 3 renamed
  sessions with distinct status dots survive quit→relaunch in one window (titles, status, active
  session, pwd all restored; scrollback is not — Ghostty restores structure, not content). Also fixed:
  the `GhosttyTests` target's deployment target was still 15.5 (left behind by the 26.0 app bump),
  which had made the whole test suite uncompilable — now 26.0, and `make test` runs again.
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
   > **Superseded by the Step 8 implementation:** in practice `minimumVersion` was kept at 5, *not*
   > raised — pre-v8 archives restore cleanly as a single-session window through the **unchanged**
   > legacy path (no migration code, so no long-tail risk), and only the new v8 format carries N
   > sessions. This is strictly better than a reset (no window loss on upgrade) at no added risk.
3. **Drop the native-tab niceties.** Under single-window scope, "move/drag between windows" and "Merge
   All Windows" are moot, and "Show All Tabs" is replaced by the sidebar itself (which already has
   drag-reorder). Remove/disable their menu items; nothing to reimplement.

## The `FleetDisableNativeTabs` flag (now default-on)

The flag is **on by default** (`UserDefaults.standard.object(forKey:) as? Bool ?? true`), so the
in-app-sessions path is what ships: no `NSWindowTabGroup` can form, the macOS-26 `NSToolbar` tab strip
never appears, the suppression code path is dead, and Cmd+T/Cmd+N create an in-app session.

To **fall back to native window tabbing** (e.g. to reproduce the old tab-bar behavior) set it false:

```sh
defaults write com.wescholm.ghostty-fleet FleetDisableNativeTabs -bool NO
# or one-off via launch arg (NSUserDefaults argument domain):
open macos/build/Debug/Ghostty.app --args -FleetDisableNativeTabs NO
```

The flag gates two code paths: `NSWindow.allowsAutomaticWindowTabbing = false` in
`AppDelegate.applicationWillFinishLaunching` (blocks *automatic* tabbing) and an early `return false` in
`NSWindow.addTabbedWindowSafely` (blocks Ghostty's *explicit* tabbing — the load-bearing one; automatic-only
was insufficient — this catch was the key "verify, don't assume" moment of Step 0).
