# Ghostty-Fleet — Full Audit (2026-06-24)

Produced by a multi-agent audit workflow (stability/build/test + 10 parallel deep-review dimensions →
adversarial verification → synthesis), plus a deep-research pass over Apple's developer docs. A transient
server-side rate limit (from running two large workflows at once) killed the first verify/synth pass; it
was re-run on resume. The maintainer (Claude) then **independently re-verified the headline findings at
runtime** — corrections below take precedence over the raw report further down.

---

## ⚠️ Maintainer verification & corrections — read first

The workflow flagged the IPC layer as the top risk (2 HIGH). Runtime verification revises that:

- **H1 — "`ghosttyctl` hangs forever after every command": ❌ FALSE POSITIVE.** Disproven empirically:
  `time ./cli/ghosttyctl list` returns in **~10 ms with valid JSON**, and it was used successfully dozens
  of times this session. This machine's `nc -U` closes on stdin-EOF, so there is no hang. The audit's
  repro used a *mimic* server, not the real `nc`/server pair. **No action needed.**

- **H2 — "Stale-socket race orphans the live IPC listener": ✅ CONFIRMED, but MEDIUM (recoverable race).**
  Verified live: `lsof` shows the process LISTENing on `/tmp/ghostty-<uid>.sock`, yet a direct `connect()`
  to that path returns **ECONNREFUSED** — an orphaned listener on an unlinked inode. **However**, it is
  triggered only by *overlapping* quit/relaunch (which this session's heavy `make run`/`open`/quit cycling
  caused); a **clean single relaunch fully restores IPC** (`ghosttyctl list` → valid JSON). So it is a real
  bug worth hardening (liveness-probe before `unlink`+`bind`; own-inode check in `stop()`), but **not** a
  steady-state break — severity **MEDIUM**, not HIGH.

- **M3 — "`FleetDisableNativeTabs` default inconsistent across read sites": ✅ CONFIRMED (and important).**
  `AppDelegate.swift:209` and `TerminalController.swift:1435` use `object(forKey:) as? Bool ?? true`
  (default **on**), but the load-bearing chokepoint `NSWindow+Extension.swift:56` uses
  `UserDefaults.standard.bool(forKey:)` (default **false** when unset), and the key is never registered.
  So on a fresh default, `addTabbedWindowSafely` does **not** block native tabbing for non-Cmd+T entry
  points (new_tab keybind, AppleScript, `NewTerminalIntent .tab`). Earlier session testing masked this by
  always having the flag effectively set for the Cmd+T path. **Real; fix to one shared `?? true` accessor.**

**Corrected severity tally:** **0 CRITICAL · 3 HIGH · ~9 MEDIUM · 41 LOW/INFO.**
The genuine HIGH-severity cluster is **close/quit data-loss** (H3, H4, H5) — closing a multi-session window
or the last session can kill background agents with no confirmation and no/partial undo. These are real,
match the repo's own `SIDEBAR-REARCHITECTURE.md` "Next steps", and should be the first fixes. (H1 removed;
H2 → MEDIUM; H6 was only a companion note to H3/H4/H5.) Everything else below is code-reading verified by
the workflow's adversarial pass; the build/test/stability baseline (251 tests pass, no crashes) is solid.

---

## Apple best-practices cross-reference

From a deep-research pass over **primary Apple docs** (NSWindowRestoration; `NSWindow.OcclusionState`;
Energy Efficiency Guide *Work When Visible* / *Minimize Timer Usage*; *Migrating to the Observable macro* +
WWDC23 "Discover Observation"; `UndoManager`; Metal Best Practices *Drawables*). Note: the research's
*verifier* votes were rate-limited (abstained), so claims are **sourced-but-unvoted** — they are, however,
standard and well-known Apple guidance, cross-checked against the code below.

| Area | Apple guidance (cited) | Fork status |
|---|---|---|
| **Window restoration** | `NSWindowRestoration`/`restorationClass`, secure coding | ✅ **Aligned** — `TerminalWindowRestoration` + `CodableBridge` (NSSecureCoding); versioned v8 multi-session state. |
| **Occlusion / off-screen Metal** | `occlusionState` is **window-level only** (the `.visible` bit covers the whole window, not sub-views); track sub-view visibility manually; *halt work when not visible*; don't hold drawables off-screen | ✅ **Aligned & validated** — the fork's manual per-session `ghostty_surface_set_occlusion` is exactly what Apple's model *requires* (window occlusion can't distinguish sessions). ⚠️ **Gap (= M6):** the sidebar's 0.5s/1s/1s pollers do **not** pause when the window is occluded — directly contrary to *Work When Visible*. |
| **Observation vs Combine** | `@Observable` updates a view only for properties its body actually reads (finer-grained than `ObservableObject`/`@Published`, which invalidate on any change); recommended for view-models; macOS 14+ | ⚠️ **Partial divergence** — `Session` is `@Observable` ✅, but `SidebarTabManager` is `ObservableObject` + a 0.5s poll that rebuilds & republishes the whole `tabs` array. More Apple-idiomatic + cheaper: drive the sidebar from `@Observable`/observation, event-driven (= L4/L11). |
| **NSUndoManager** | holds the target **unowned/weak** (caller keeps it alive); group related ops; wire via `windowWillReturnUndoManager` | ✅ **Aligned** — `ExpiringUndoManager` weak target; closures retain the captured tree; `windowWillReturnUndoManager` → AppDelegate manager. ⚠️ bulk-close grouping is the known gap (= L28). |
| **Timers / polling & `proc_pidinfo`** | timers are energy-expensive (idle wakes); prefer event-driven; minimize/coalesce; `pti_total_user/_system` are **Mach absolute-time units** → convert via `mach_timebase_info` | ⚠️ **Biggest divergence** — three always-on pollers (= M6/L9/L11). ✅ the Mach-unit conversion is **correct** (the Apple-Silicon CPU fix landed this session). |

**Two best-practice themes for hardening:** (1) the sidebar is more poll-heavy than Apple recommends —
coalesce/lengthen timers, **pause them while the window is occluded** (`windowDidChangeOcclusionState`),
and lean toward `@Observable`/event-driven; (2) everything else (restoration, the manual per-session
occlusion model, undo semantics, the CPU-unit fix) is well-aligned with documented Apple guidance.

---

*The raw multi-agent audit report follows verbatim. Where it lists H1/H2 as HIGH IPC risks, the
"Maintainer verification" section above supersedes it (H1 false; H2 = MEDIUM, recoverable; M3 confirmed).*

---

# Ghostty-Fleet Audit Report

## Executive summary

The fork is in good overall health: it **builds and tests clean** (`make test` → `** TEST SUCCEEDED **`, 251 cases, 0 failures, after one known codesign-detritus retry), with **no app crashes** this session (the only `.ghosttycrash` envelopes are Xcode `#Preview` crashes, matching the documented backlog). Fork-specific coverage is real — multi-session v8 restoration is exercised by `restoreTerminalV8MultiSession()`.

The risk is concentrated in the **in-app sessions migration** (`SIDEBAR-REARCHITECTURE.md` Steps 0–8). Several control-flow paths were re-routed to the session model for the *active* session only, leaving background sessions — the exact parallel-agent workload this fork exists for — silently mishandled. The **IPC layer** (the G1 "agent status from hooks" feature) is the most broken area in practice.

Severity counts (verified): **0 CRITICAL, 6 HIGH, 8 MEDIUM**, plus a long LOW/INFO tail. 1 candidate finding was refuted during verification.

**Top risks (fix first):**
1. **`ghosttyctl` hangs after every command** (HIGH, IPC) — `nc -U` never sees EOF; every Claude Code hook blocks until timeout, defeating the core use case.
2. **Stale-socket race orphans the live IPC listener** (HIGH, IPC) — observed live: a server is LISTENing yet every `connect()` returns ECONNREFUSED. IPC silently dead after a relaunch.
3. **Close/quit confirmations + close-window undo only inspect the active session** (HIGH) — closing a multi-session window kills background agents with no prompt and undo restores only the active one: silent data loss of parallel sessions.
4. **`close_tab` / menu "Close Tab" tears down the whole window** under the default flag (HIGH) — guard keyed on the now-absent native tab group.
5. **Closing the last session bypasses confirmation and undo** (HIGH) — `window.close()` skips `windowShouldClose`.
6. **Background session's surface death is never handled** (MEDIUM) — dead surface / zombie session leak that the user can't cleanly dismiss.

## Stability, build & tests

- **Build:** PASS. `make build` / xcodebuild Debug, macOS arm64.
- **Tests:** PASS. `make test` SUCCEEDED on retry; 251 cases, 0 failures, 0 unexpected. First run failed only at CodeSign on the DerivedData test-host with the **known custom-icon detritus papercut** ("resource fork, Finder information, or similar detritus not allowed"); `xattr -cr` on the DerivedData + `macos/build` apps cleared it. The single "Executed 0 tests" line is the empty `GhosttyUITests` bundle.
- **Fork coverage confirmed:** `TerminalRestorableTests/restoreTerminalV8MultiSession()` (multi-session restoration, Step 8), plus `SplitTreeTests`, `ConfigTests`, `SurfaceView_SearchStateTests`, `TerminalViewContainerTests`.
- **Crashes:** none from the shipping app. The two most recent `~/.local/state/ghostty/crash/*.ghosttycrash` envelopes (inner timestamps 2026-06-24T13:06:28Z, 2026-06-18T21:01:50Z) both list `__preview.dylib` + Xcode `libLogRedirect.dylib` — Xcode `#Preview` crashes, not the app. The crash-file mtimes reflect the handler finalizing earlier crashes. `/usr/bin/log` (scoped to the fork image path) over the last 30m showed only benign LaunchServices timeout lines.

**Note:** the codesign-detritus retry is a recurring papercut. `make app`/`dev` already auto-`xattr -cr` the build product, but the **DerivedData test-host** is not covered — worth folding into `make test` so CI/local test runs don't fail on the first attempt.

## Findings by severity

### HIGH

#### H1. `ghosttyctl` hangs forever after every command (IPC)
- **Area:** ipc · **File:** `cli/ghosttyctl:71`
- **What/why:** `send_request()` does `printf '%s\n' "$json" | nc -U "$SOCKET_PATH"`. The server (`GhosttyIPCServer.swift` `processRequest`, 218–247) replies with one JSON line and **keeps the connection open**, never closing it. macOS `nc` does not support `-q`/`-N` (both rejected on this machine), and `-w` doesn't terminate a session with data flowing — so `nc` prints the reply then blocks indefinitely. Every subcommand (list/current/rename/state/set-status/focus/notify) hangs the caller after emitting output. The documented Claude Code hooks (`cli/claude-hooks.example.json`: `ghosttyctl state running` on UserPromptSubmit, etc.) hang on every prompt/stop, blocking the agent until hook timeout — **directly defeating the G1 use case**.
- **Fix:** Make request/response one-shot. Robust: replace `nc -U` with a tiny stdin-feeding client that reads one line and exits (here-doc Python: connect, `sendall(json+"\n")`, `readline`, print). Belt-and-suspenders: have the server `shutdown(client.fd, SHUT_WR)`/close after replying so `nc` sees EOF, and add a `-w 2` backstop.
- **Confidence:** high. **Repro:** verified against a mimic server that replies-then-keeps-open — reply printed, `nc` still running at 4s, killed via `alarm` (exit 142).

#### H2. Stale-socket race orphans the live IPC listener (IPC)
- **Area:** ipc · **File:** `macos/Sources/Features/Terminal/IPC/GhosttyIPCServer.swift:54`
- **What/why:** `start()` unconditionally `unlink(socketPath)` then `bind()` with **no liveness check**; `stop()` (line 138) also unconditionally unlinks. With a fixed per-uid path `/tmp/ghostty-<uid>.sock`, a second instance (or a `make dev` relaunch overlapping the old quit, which only sleeps ~1s) unlinks the path the first instance is actively listening on and binds a **new inode**. The path then resolves to a dead/replaced inode while the original process still LISTENs on the now-unlinked original inode → all `connect()` return ECONNREFUSED even though a server is "running".
- **Observed live:** pid 31053 holds fd 5 LISTENing (`lsof` confirms), the binary contains current IPC code, yet python AF_UNIX and `nc` connects all return "Connection refused" (5/5), and `ghosttyctl list` returns empty + exit 0 (silent failure). Socket mtime (21:46) was 14 min after process launch (21:32) — the socket file was replaced under the live listener.
- **Fix:** Before unlinking, `connect()`-probe the existing path; if it succeeds, another instance owns it → bail (single-instance) or pick an alternate path. Only unlink when the probe fails. In `stop()`, only unlink if we still own the inode (compare `st_ino`/`st_dev` to the bound inode, or guard behind a flag set on successful bind). Consider per-PID names (`/tmp/ghostty-<uid>-<pid>.sock`) + a well-known symlink.
- **Confidence:** high.

#### H3. Close/quit confirmations + close-window undo ignore background sessions
- **Area:** controller-integration · **File:** `macos/Sources/Features/Terminal/TerminalController.swift:1531-1554`
- **What/why:** Every "running process" confirmation tests the **mounted** `surfaceTree` (active session) only: `closeWindow` (1538–1544), `closeAllWindows` (1001–1008), `closeTab` confirm (1452), and `BaseTerminalController.windowCanBeClosedWithoutConfirmation` (1449–1462) used by the red-X (`windowShouldClose`) and by the Quit flow (`AppDelegate.swift:1376`). A background session running an agent triggers **no** confirmation when the active session is idle. Worse, the close-window undo state (`undoState`, 1090–1100) captures only the active `surfaceTree`, so closing a multi-session window destroys all background sessions with no prompt **and** undo restores only the active one — **silent data loss of exactly the parallel-agent sessions this fork manages**. (OS app-quit/relaunch restoration is session-aware via v8 state; loss is limited to interactive close-window/close-all/quit and undo.)
- **Fix:** Make all close/quit confirmation checks iterate `sessions.flatMap(\.surfaceTree)` (or add `anySessionNeedsConfirmQuit`). Make close-window undo capture every session's tree + `activeSessionIndex` (reuse the v8 `SessionState` snapshot path). Surface a confirmation mentioning background sessions.
- **Confidence:** high. **Repro:** 2 sessions, `sleep 9999` in session 2, switch to idle session 1, close window/Cmd-Q → no confirmation, process killed; Cmd+Z restores only session 1.

#### H4. Menu "Close Tab" / `close_tab` keybind closes the entire window
- **Area:** controller-integration · **File:** `macos/Sources/Features/Terminal/TerminalController.swift:1445-1463`
- **What/why:** `closeTab` was not migrated to the session model. It guards `window.tabGroup?.windows.count ?? 0 > 1`; with native tabbing disabled (default `FleetDisableNativeTabs`) there is no tab group, the guard fails, and it calls `closeWindow(sender)` — tearing down the whole window and **every** in-app session. Reachable from File > Close Tab (`MainMenu.xib:201-206`) and the `close_tab` keybind (`GHOSTTY_ACTION_CLOSE_TAB` → `onCloseTab` 1717–1721 → `closeTab(self)`).
- **Fix:** Mirror the `closeSurface` override: when `sessions.count > 1`, call `closeSession(at: activeSessionIndex)`; only fall back to native `closeWindow` when native tabs are actually enabled and a tab group exists.
- **Confidence:** high. **Repro:** 3 sessions, select middle, Cmd+Opt+W (or File > Close Tab) → entire window closes.

#### H5. Closing the last session bypasses confirmation and undo
- **Area:** controller-integration · **File:** `macos/Sources/Features/Terminal/BaseTerminalController.swift:391-398`
- **What/why:** `closeSession(at:)` handles the last session with `guard sessions.count > 1 else { window?.close(); return }`. `NSWindow.close()` (unlike `performClose`) does **not** invoke `windowShouldClose`, so the running-process alert is bypassed and **no undo is registered** on this branch. The sidebar reaches this directly: `SidebarTabManager.closeTab` (461–464), `closeOtherTabs` (478–489), `closeTabsToTheRight` (500–507), plus the card 'X' (`SidebarView.swift:133`) and "Close Tab" context item (132). Closing the final session running an agent destroys it with no prompt and no undo. The method's doc comment falsely claims it "Registers an undo" unconditionally.
- **Fix:** Route the last-session case through the confirming + undo-registering window close (e.g. `closeWindow(nil)`), ideally via an overridable hook so `TerminalController` runs its confirm/undo-aware close. Honor `needsConfirmQuit`. Fix the doc comment.
- **Confidence:** high.

#### H6. (companion to H3/H4/H5) — see note
The three controller-integration HIGHs (H3/H4/H5) plus the related LOW "Close Other/Right are no-ops" share one root cause: **the close/navigation IBActions and confirmation checks were not migrated off the native `tabGroup` model.** They are listed separately because each is independently reachable and independently fixable, but a single migration pass (route all close/goto IBActions through the session API when the flag is on; make all confirmation checks session-aware) resolves the cluster.

### MEDIUM

#### M1. Background session's surface death is never handled — zombie session leak
- **Area:** sessions-core · **File:** `macos/Sources/Features/Terminal/BaseTerminalController.swift:847-853`
- **What/why:** `ghosttyDidCloseSurface` (the only handler for the global libghostty close-surface request, fired for any surface whose process exits) guards `guard let node = surfaceTree.root?.node(view: target) else { return }`, which matches only the **mounted (active)** tree. A surface in a **background** session is in no mounted tree, so every controller drops the notification — the dead surface is never removed. The background session keeps a surface whose pty has exited; its card lingers and can't auto-close (manual `closeSession` would still register an undo retaining an already-dead tree). The active path (`closeSurface(node:)` → `closeSession`) doesn't cover this.
- **Fix:** In `ghosttyDidCloseSurface`, if `target` isn't in the mounted tree, search other sessions, remove that node from the owning session's tree, and if the tree becomes empty remove the session (fix `activeSessionIndex`, optional undo). Add a unit test that exits the process in a background session.
- **Confidence:** high. **Repro:** background session A, `exit` in its shell → card lingers with a dead pty.

#### M2. Session-API index math is untested and only partially testable
- **Area:** tests-coverage · **File:** `macos/Sources/Features/Terminal/BaseTerminalController.swift:391-524`
- **What/why:** `closeSession` neighbor pick + active-index fixup, `restoreClosedSession` insert/bump, `moveSession` move-by-identity, `restoreSessions` clamp. The arithmetic was traced and is **correct**, but there are **no tests** and the methods are welded to live side effects (occlusion calls, real `SurfaceView`, `window.close()`, `undoManager`), so the math can't be unit-tested without a live app or a refactor.
- **Fix:** Extract pure static helpers (`neighborIndexAfterClosing`, `activeIndexAfterRemoval`, `activeIndexAfterInsert`, `movedActiveIndex`, `clampedActiveIndex`) and test them in `SessionIndexMathTests.swift`. Converts an inspection-only claim into a regression guard.
- **Confidence:** high.

#### M3. `FleetDisableNativeTabs` default is inconsistent across read sites
- **Area:** build-flags · **File:** `macos/Sources/Helpers/Extensions/NSWindow+Extension.swift:56`
- **What/why:** Three read sites, two defaults, never registered in `register(defaults:)`. The two gates default to ON: `AppDelegate.swift:209` and `TerminalController.swift:1435` both `... as? Bool ?? true`. But the **real chokepoint** `NSWindow+Extension.swift:56` uses `UserDefaults.standard.bool(...)`, which returns **false** when the key is absent. So out of the box (key unset = documented default), `addTabbedWindowSafely` does **not** short-circuit and forms a real `NSWindowTabGroup`. Cmd+T is masked (routes to `newSession`), but any path reaching `addNewTab()` (a `new_tab` keybind, tab-bar "+", Dock "New Tab", `NewTerminalIntent .tab`) still creates a native tab group on defaults — exactly the macOS-26 tab-bar bug class the flag exists to kill. The comment at 51–55 calls this "the real chokepoint", making the wrong default load-bearing.
- **Fix:** Change line 56 to `... .object(forKey:) as? Bool ?? true`. Better: centralize the flag in one accessor used by all three sites (also resolves the suite mismatch in the LOW table).
- **Confidence:** high.

#### M4. `AppDelegate.newTab` and `NewTerminalIntent(.tab)` bypass the session model
- **Area:** build-flags · **File:** `macos/Sources/App/macOS/AppDelegate.swift:977`
- **What/why:** Only the instance IBAction `newTab(_:)` was migrated. `AppDelegate.newTab` (977–982, the menu handler when no `TerminalController` is in the responder chain) and `NewTerminalIntent` with `.tab` (`NewTerminalIntent.swift:118-122`) both call the **static** `TerminalController.newTab` → `addNewTab()` → `addTabbedWindowSafely`. With the flag at its intended default these should make an in-app session but instead hit the wrongly-defaulted chokepoint (M3) → native tab group. Inconsistent with Cmd+T.
- **Fix:** When the flag is on, route both to `newSession()` on the resolved controller (mirroring `.splitLeft/.splitRight` → `controller.newSplit`). Share one helper across all "new tab" entry points.
- **Confidence:** high.

#### M5. `goto_tab` keybind handler (`onGotoTab`) is dead under the default flag
- **Area:** stale-code · **File:** `macos/Sources/Features/Terminal/TerminalController.swift:1665-1715`
- **What/why:** `onGotoTab` bails at 1676 `guard let tabGroup = ... else { return }`. With native tabs off, no tab group ever forms → the whole handler is a no-op. Still observed (registered 105–106) and the Zig core still emits `goto_tab`, so `keybind = ctrl+1=goto_tab:1` (and next/prev/last) gets silence. Tab navigation was never re-routed to `selectSession` (grep confirms `selectSession` has no keybind callers — only sidebar click + IPC focus). Dead code that masks a missing feature: **keyboard session switching**.
- **Fix:** Re-route `onGotoTab` to `selectSession(at:)` when the flag is on (1-indexed N → N-1; PREVIOUS/NEXT/LAST wrap over `sessions.count`); keep the native branch behind the else.
- **Confidence:** high.

#### M6. All three sidebar polling timers run at full rate for hidden windows
- **Area:** performance · **File:** `macos/Sources/Features/Terminal/Sidebar/SidebarTabManager.swift:94-96, 189-191, 276-291`
- **What/why:** Each `TerminalController` owns a `SidebarTabManager` running a 0.5s refresh, a 1s CPU timer, and a 1s git-poll task. None consult window occlusion/visibility or app-active state, so a fully-occluded / minimized / other-Space window keeps refreshing, sampling CPU, and spawning git subprocesses. With W windows this multiplies all polling by W. The occlusion signal is already available (`windowDidChangeOcclusionState` → `syncSurfaceTreeOcclusionState`) but unused by the pollers.
- **Fix:** Observe `NSWindow.didChangeOcclusionStateNotification` (+ `NSApplication.didResignActive`); suspend/throttle timers + git task while occluded; re-arm + one immediate refresh on becoming visible.
- **Confidence:** high. (The LOW "per-repo git status every second" is the subset of this scoped to git spawns.)

#### M7. `json_escape` doesn't escape JSON control chars → server rejects the request
- **Area:** ipc · **File:** `cli/ghosttyctl:43`
- **What/why:** `json_escape()` only escapes `\ " \n \r \t`. Other C0 controls (VT 0x0B, FF 0x0C, ESC 0x1B — routine in terminal titles/agent output/pasted text passed to `rename`/`set-status`) are emitted raw. RFC 8259 requires escaping them, so `JSONSerialization` on the server fails and `processRequest` returns `{"ok":false,"error":"invalid request..."}` (`GhosttyIPCServer.swift:221`); the command silently no-ops. NUL is additionally truncated by bash. Correctness/robustness, **not** injection (the strict parser can't be coerced into anything dangerous).
- **Fix:** Escape all C0 controls. Simplest: build the payload with a real encoder (`python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))'` or `jq -Rs`). If staying in bash, `\u00XX`-escape every byte < 0x20 not already handled.
- **Confidence:** high. **Repro:** verified — Swift `JSONSerialization` rejects raw 0x0B/0x0C/0x1B/0x07; the `\u`-escaped variant parses.

#### M8. Docs over/under-claim migration status (AGENTS.md + README)
Two MEDIUM doc-accuracy findings that will actively mislead an agent:
- **`AGENTS.md:12-27`** — the "In flight" callout lists shipped features (IPC-over-sessions, per-session bell/status, undo, restoration) as "Still in progress" and says "Step 0 landed", contradicting `SIDEBAR-REARCHITECTURE.md:3` ("Steps 0–8 landed & verified") and the code (`GhosttyIPCServer.resolve` iterates `controller.sessions` 443–453; `closeSession`/`restoreClosedSession`/`registerUndo`; v8 `restoreSessions`). **Fix:** rewrite the callout to "Steps 0–8 done & verified; remaining = Next-steps cleanup/polish."
- **`README.md:24-25`** — the public dot legend still describes the **obsolete two-dot model** and never mentions the five-color lifecycle status (`SidebarView.statusColor` + `SidebarTabManager.effectiveStatus`) or the `ghosttyctl state` verb. **Fix:** update legend to the single-lifecycle-dot model (attention > error > waiting > running > done > idle) and add `state` to the CLI section. `ENHANCEMENTS.md`/`AGENTS.md` already document it correctly — README is the outlier.
- **Confidence:** high.

### LOW / INFO (compact)

| # | Sev | Area | File | Issue |
|---|---|---|---|---|
| L1 | low | sessions-core | BaseTerminalController.swift:353-362 | Unguarded async focus hop in `selectSession`; rapid switching can flicker focus to a now-background surface. Add a generation token / cancel prior `DispatchWorkItem`. |
| L2 | low | controller-integration | TerminalController.swift:1465-1524 | Menu "Close Other Tabs" / "Close Tabs to the Right" are silent no-ops in session mode (operate on `window.tabGroup`); sidebar context-menu versions work. Route IBActions to the session-aware `SidebarTabManager` methods. |
| L3 | low | sidebar | SidebarView.swift:95-98 | Abandoned/cancelled drag leaves source card stuck at 0.4 opacity (`draggingTabID` cleared only in `performDrop`). Reset on failure paths + make the dim self-healing. |
| L4 | low | sessions-core | SidebarTabManager.swift | Session @Observable status/title/color mutations don't notify the sidebar — UI relies on the 0.5s poll. Drive from observation or post a refresh notification. |
| L5 | low | sessions-core | BaseTerminalController.swift | `ClosedSession.index` goes stale after reorder → undo can restore at the wrong position. Anchor restore to a neighbor's identity. |
| L6 | low | sessions-core | BaseTerminalController.swift | Cmd+T / `newSession` is not undoable (inconsistent with native newTab/newWindow). Register undo/redo. |
| L7 | low | sidebar | SidebarTabManager.swift | `displayTitle` `dropFirst(3)` for a 2-char bell prefix eats the first title char. Use `dropFirst(2)` / `"\u{1F514} ".count`. |
| L8 | low | sidebar | SidebarTabManager.swift | `gitInfoCache` never pruned, grows unbounded. Filter to `currentPwds()` in `applyGitInfo`. |
| L9 | low | sidebar | SidebarTabManager.swift | Git poll spawns one `/usr/bin/git` per distinct pwd every second forever. Lengthen interval / back off / FSEvents-trigger. (Subset of M6.) |
| L10 | low | sidebar | SidebarTabManager.swift | Global key-window observers (`object: nil`) make every window's sidebar rebuild on any window's key transition. Scope to `controller?.window`. |
| L11 | low | performance | SidebarTabManager.swift | 0.5s refresh rebuilds the whole tabs array every tick even when unchanged. Lengthen interval / add a dirty signal. |
| L12 | low | ipc | ghosttyctl | Socket-existence pre-check is a TOCTOU; `-S` accepts any actor's socket at the path. Drop pre-check; verify uid ownership; prefer `$XDG_RUNTIME_DIR`/0700 dir. |
| L13 | low | ipc | GhosttyIPCServer.swift | Server + client fds lack `FD_CLOEXEC` (IPC listener can leak into spawned shells). Set close-on-exec after `socket()`/`accept()`. |
| L14 | low | ipc | GhosttyIPCServer.swift | `sendJSON` write loop treats transient EAGAIN as fatal → response dropped. Retry on EAGAIN/EINTR. |
| L15 | low | restoration | TerminalRestorable.swift | Stale per-session status restored verbatim → misleading dot after restart. Drop `status` from `SessionState` or normalize transient states to `.idle` on restore. |
| L16 | low | restoration | TerminalRestorable.swift | v8 archive read by a v7 binary silently loses all surfaces (downgrade data loss). Keep active tree in top-level `surfaceTree` for older readers, or document. |
| L17 | low | restoration | BaseTerminalController.swift | Corrupt archive with empty active-session tree closes the window though background sessions already spawned ptys. Pick first non-empty session as active defensively. |
| L18 | low | build-flags | AppDelegate.swift | Stale comment "Off by default" contradicts ON-by-default code. Fix wording. |
| L19 | low | build-flags | AppDelegate.swift | Flag registered/read across mismatched suites (`UserDefaults.ghostty` vs `.standard`). Pick one store / single accessor. |
| L20 | low | build-flags | NewTerminalIntent.swift | Loses `supportedModes` + `openAppWhenRun` if built with compiler < 6.2. Add `#else` fallback or scope the guarantee to the pinned toolchain. |
| L21 | low | stale-code | TerminalController.swift | `relabelTabs` keyEquivalent block dead under the flag (paired with `onGotoTab`). Fold into session path when fixing M5. |
| L22 | low | stale-code | TerminalController.swift | `disableNativeTabs` flag read duplicated inline in 3 places. Single static accessor. |
| L23 | low | tests-coverage | SidebarTabManager.swift:383-391 | `effectiveStatus` (the "orange beats green" precedence policy) is pure/static yet has **zero tests**. Add `SidebarStatusTests`. |
| L24 | low | tests-coverage | Session.swift:13-31 | `SessionStatus` rawValue/`CaseIterable` is the IPC + disk wire contract, untested. Pin rawValues + `allCases`. |
| L25 | low | tests-coverage | TabMetadataStore.swift:25-46 | set/clear/sort/auto-prune untested. Add `TabMetadataStoreTests` (unique UUID per test + `defer removeAll`). |
| L26 | low | tests-coverage | TerminalRestorableState+InteralState.swift:29-36 | Pre-v8 `sessions == nil` back-compat decode path not explicitly asserted. Add `#expect(v5.sessions == nil)` + an empty-sessions-falls-back-to-legacy test. |
| L27 | low | tests-coverage | GhosttyIPCServer.swift | Request dispatch / param resolution / error messages untestable (private + NSApp/SurfaceView-coupled). Extract `handle(method:params:resolver:)` + a resolver protocol. |
| L28 | low | stability | SidebarTabManager.swift | "Close Others"/"Close to the Right" register N separate undos — one Cmd+Z restores only one tab. Wrap in an undo group. |
| L29 | low | docs | SIDEBAR-FORK-REPORT.md:102 | "no shell-out" is false (`runGit` execs `/usr/bin/git`). Correct the security-posture line. |
| L30 | low | docs | SIDEBAR-FORK-REPORT.md:104-109 | "Known follow-ups" both resolved (`controllerForSurfaceId` removed; Tab Color menu locale-proofed). Delete/annotate Section 6. |
| L31 | low | docs | Session.swift:38-39 | Doc says type "not yet referenced by the controller or the sidebar" — false (43 refs in BaseTerminalController). Update to present tense. |
| L32 | low | docs | BaseTerminalController.swift | Stale "Always 0 until Step 3" / "Not yet wired — Step 5" comments. Refresh. |
| L33 | low | docs | AGENTS.md:145,159 | IPC verb list omits `tab.set-state`; `ghosttyctl state` value list drops `attention`. Add both. |
| L34 | low | docs | ENHANCEMENTS.md | References non-existent branch `sidebar-enhancements`. Drop/reword. |
| L35 | low | docs | VALIDATION.md / AGENTS.md | "229 tests" stale (~247/251); VALIDATION.md validates the pre-rearchitecture sidebar. Update count + scope note. |
| I1 | info | sidebar | SidebarTabManager.swift | CPU working-dot keyed by focused surface id → within-session focus changes flicker the dot. Key by foreground PID or aggregate per-session. |
| I2 | info | sidebar | SidebarView.swift | Drag-reorder drop position asymmetric (down: after target; up: before) vs always-top indicator. Account for removal direction. |
| I3 | info | restoration | TerminalRestorable.swift | Window-level `tabColor` restore is vestigial vs per-session colors. Drop or comment. |
| I4 | info | build-flags | project.pbxproj | Deployment-target values inconsistent (project-level 13.1 vs app 26.0). Optional cleanup. |
| I5 | info | stability | SidebarTabManager.swift | `git status` subprocess in the activity poll has no timeout — a hung git on a network FS can leak processes (off-main, no UI hang). Add a 3s watchdog. |
| I6 | info | stability | BaseTerminalController.swift | `selectSession` resets color-scheme cache to nil on every switch (redundant `set_color_scheme`). Track applied scheme per session. Low value. |
| I7 | info | stale-code | TerminalController.swift / Helpers | Native-tab IBActions/undo helpers + upstream native-tab helpers (`TabGroupCloseCoordinator`, `TabTitleEditor`, `ScriptTab/Window`) are inert under the flag but **RISKY/flag-reactivated or upstream-pristine** — do **not** delete piecemeal; remove only as one atomic change when the flag is retired. |

## Hardening plan / recommendations

Prioritized; deduped against `SIDEBAR-REARCHITECTURE.md`'s existing Next steps (Step 9 dead-code removal, Step 10 menu items, Step 11 full UI pass, title-layer unification). Items below are **not** already covered there unless noted.

**P0 — fix the IPC layer (the G1 feature is currently broken end-to-end).** Not in the rearchitecture Next steps.
1. **H1**: make `ghosttyctl` request/response one-shot (replace `nc -U` with a one-line reader; have the server `shutdown(SHUT_WR)`/close after replying). Without this, every documented Claude Code hook hangs.
2. **H2**: add a liveness probe before unlink + own-inode check in `stop()` (or per-PID socket names). Otherwise `make dev` relaunches silently kill IPC.
3. **M7**: replace hand-rolled `json_escape` with a real encoder. Add **L23/L24/L25/L27** tests + the `handle()` refactor so this layer is regression-guarded and the G1 "resolve a background session's surface" invariant is pinned.

**P1 — make close/quit session-aware (data-loss class).** Partially overlaps Step 10 (menu items) but the *confirmation/undo correctness* is not called out there.
4. **H3 + H4 + H5 + L2**: one migration pass — route all close IBActions (`closeTab`, `closeOther`, `closeRight`) and the last-session `closeSession` branch through the session API + a confirm/undo-aware hook; make every `needsConfirmQuit` check iterate `sessions.flatMap(\.surfaceTree)`; make close-window undo snapshot all sessions (reuse the v8 `SessionState` path).
5. **M1**: handle background-session surface death in `ghosttyDidCloseSurface`.
6. **M5 + L21**: re-route `onGotoTab` to `selectSession` (keyboard session switching — a missing feature, beyond Step 9's "remove dead code").

**P2 — flag correctness + steady-state cost.**
7. **M3 + M4 + L19 + L22**: single `nativeTabsDisabled` accessor (`?? true`) used by **all** read sites incl. the chokepoint, registered in one suite. Closes the macOS-26 tab-bar bug class for the non-Cmd+T entry points.
8. **M6 + L9 + L11 + L10 + I5**: occlusion-gate the three sidebar pollers; lengthen intervals; scope key-window observers to the owning window; add a git watchdog. Directly serves the "many parallel sessions" workload.

**P3 — tests + docs.**
9. **M2 + L23–L27**: extract pure index-math/dispatch helpers and add the unit suites — converts inspection-only correctness claims into guards (complements Step 11's UI pass).
10. **M8 + L29–L35**: a single docs sweep — fix the AGENTS.md "In flight" callout, README dot legend + `state` verb, the stale SIDEBAR-FORK-REPORT follow-ups/security line, and the test count. This is the cheapest high-value item: the stale docs will mislead the next agent about which features exist.
11. **Build hygiene:** fold `xattr -cr` of the DerivedData test-host into `make test` so the codesign-detritus retry stops biting.

## What's solid

Credit where due — these areas were reviewed and found clean:

- **Multi-session restoration (Step 8).** The v8 `TerminalRestorableState` (`SessionState`/`sessions`/`activeSessionIndex`, version 8) is implemented and covered by a passing round-trip test (`restoreTerminalV8MultiSession`). Optionals are deliberately used for pre-v8 back-compat (the only gap is an explicit *assertion* of that, L26).
- **Session index arithmetic.** All four mutators (`closeSession` neighbor/fixup, `restoreClosedSession` insert/bump, `moveSession` by-identity, `restoreSessions` clamp) were traced and are **correct** — the finding is the missing test seam (M2), not a bug.
- **IPC-over-sessions resolution (G1).** `GhosttyIPCServer.resolve`/`resolveTarget` walk every session's whole `surfaceTree`, correctly reaching background sessions' surfaces — the earlier focused-only limitation is genuinely fixed (refuting the stale `controllerForSurfaceId` follow-up).
- **`effectiveStatus` precedence.** The "orange beats green" status policy is implemented correctly (verified by inspection); it just needs tests (L23).
- **git shell-out hardening.** `runGit` uses a fixed absolute path + fixed argv, `GIT_OPTIONAL_LOCKS=0` / `GIT_TERMINAL_PROMPT=0`, no shell interpolation, off-main at `.utility` — low-risk and won't jank the UI (the issue is steady-state cost/occlusion, not safety).
- **Polling threading.** The pollers are correctly off the main thread; the active-session focus path is corrected by FIFO ordering even in the L1 race (visible artifact is only a transient flicker, never corruption).
- **No injection surface in IPC.** The strict server-side `JSONSerialization` parser cannot be coerced into anything dangerous; M7 is a correctness/robustness bug, not a security hole.
- **Build & test health.** Clean build, 251 passing tests, no app crashes — a solid baseline for the hardening work above.

*One candidate finding was refuted during verification.*