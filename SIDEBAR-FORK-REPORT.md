# Ghostty sidebar fork — rebase + build report

**Date:** 2026-06-17 · **Machine:** macOS 26.5 (Tahoe), Apple Silicon · **Repo:** `~/ghostty-sidebar`

## TL;DR

Tom Reinert's `tomreinert/ghostty` left-sidebar-tabs fork was **rebased onto current upstream
Ghostty** (1,021 commits newer than the fork's base), **polished**, and **verified to build and
run**. The hard part was a macOS-26.5-vs-Zig-0.15.2 toolchain incompatibility (independent of the
fork) that needed a custom build path — now fully automated in `build-macos.sh`.

```
git log --oneline:
  786dff263  build: local toolchain workaround for macOS 26.5 + Zig 0.15.2   (droppable)
  d8bc9888b  refactor(sidebar): remove unused NotificationStore
  0f6d7f332  perf(sidebar): read git branch off the main thread; safer tab reorder
  43ba7be2c  feat(macos): add left sidebar tab UI, rebased onto upstream
  e8e7fea10  (upstream/main) Update VOUCHED list (#13033)
```

## See it right now

```sh
open ~/ghostty-sidebar/macos/build/Debug/Ghostty.app
```
The app is already built. Left sidebar replaces the native tab bar; each row shows
title / directory / git-branch / status, with attention dots. The `ghosttyctl` CLI
(`~/ghostty-sidebar/cli/ghosttyctl`) drives it: `rename`, `notify`, `set-status`, `clear-status`.

## Rebuild after edits or a future rebase

```sh
cd ~/ghostty-sidebar && ./build-macos.sh
```
One command. It is idempotent and self-contained (recreates the overlay SDK, applies the Zig std
patch if missing, downloads the Metal toolchain if missing, builds the xcframework, builds the app).

---

## 1. The rebase

- **Strategy:** the fork's net feature delta (18 files, +1,727/−10) was squash-applied onto current
  `upstream/main` via a 3-way cherry-pick, preserving Tom Reinert's authorship. The fork's own history
  included a "replace sidebar v1 with v2" commit, so replaying individual commits would have replayed
  throwaway code — squashing the final state was cleaner and conflict-minimal.
- **Conflicts:** exactly **one**, in `GhosttyPackage.swift` (upstream added `ghosttySelectionDidChange`
  where the fork added two notification names). Resolved by keeping all three. Every other file —
  including the "hot" ones the audit feared (`TerminalController`, `BaseTerminalController`,
  `TerminalWindow`) — auto-merged.
- **API verification:** 3 parallel review agents checked every upstream symbol the fork calls against
  current upstream. **No compile-breakers.** One flagged "misplaced `refreshAllSidebars()`" was checked
  against the fork's source and found to be a **false positive** — the merge matches the fork's intent.
- **Proof:** the full macOS app compiles and links cleanly (`** BUILD SUCCEEDED **`).

## 2. Polish (3 commits on top of the rebase)

| Commit | Change | Why |
|---|---|---|
| `0f6d7f332` | Git-branch reads moved to a detached background poll (cached per-pwd, re-publishes only on change). `refresh()` no longer does file I/O on the main thread. | Audit flagged a 0.5s timer doing synchronous `.git/HEAD` reads on the main thread — UI stutter risk on slow/network dirs. |
| `0f6d7f332` | `moveTab` uses `addTabbedWindowSafely` (upstream's guarded variant). | Parity/robustness with the rest of the macOS app. |
| `d8bc9888b` | Deleted `NotificationStore.swift`. | Confirmed **zero references** anywhere — dead second source of truth behind the stale-attention-dot fragility. Live path is `SidebarTabManager.attentionWindows`. |

## 3. The toolchain wall (and how it's solved)

**Problem:** Ghostty 1.3.x pins **Zig 0.15.2**, whose Mach-O linker **cannot link against the macOS
26.5 (Tahoe) SDK's `libSystem.tbd`** (fails on `__availability_version_check` et al.). This breaks the
Zig build runner, host helper exes, and dylibs. *Pristine upstream Ghostty fails identically here* — it
is not a fork issue.

**Solution (all in `build-macos.sh`, commit `786dff263` + an out-of-repo Zig std patch):**
1. **Zig std patch** — `~/.zig-0.15.2/lib/std/zig/system/darwin.zig` `getSdk()` honors `$SDKROOT` so the
   SDK is found without a working `xcrun`.
2. **Bundled-stub linking** — run `zig build` with `DEVELOPER_DIR=/nonexistent` so Zig links every
   native binary against its *bundled* libSystem stub (which its linker can parse).
3. **Overlay SDK** — `SDKROOT` points at a symlink-farm of the real SDK with `libSystem.tbd` swapped for
   the bundled (parseable) one, so dynamic-lib links resolve while compiles get real headers/frameworks.
4. **Real Xcode for tool steps** — `libtool`/`ranlib`/`metal`/`metallib`/`lipo`/`xcodebuild` steps pin
   `DEVELOPER_DIR` back to real Xcode (they need the real toolchain; they don't link libSystem).
5. **Metal Toolchain** — auto-downloaded (Xcode 26.5 ships it as a separate ~700MB component).
6. **App build** — `xcodebuild` builds `Ghostty.app` with real Xcode (its real `ld` handles the 26.5 SDK
   fine). Build arm64-only (`-arch arm64`); the xcframework is native/arm64.

**This whole section disappears the day you move to a Zig that links the macOS 26 SDK natively** — then
`zig build` works directly and commit `786dff263` can be dropped.

## 4. Runtime verification (done)

- App launches and stays alive (no crash) — all fork subsystems initialized.
- IPC socket `/tmp/ghostty-501.sock` created with `0600` perms (matches the security audit).
- `ghosttyctl list` returned live tab metadata:
  `{"tabs":[{"is_active":true,"pwd":"/Users/nikita","title":"…","tab_id":"D5D700D7-…"}],"ok":true}`

## 5. Maintaining this going forward

- **To re-rebase onto newer upstream:** `git fetch upstream && git rebase upstream/main` (or cherry-pick
  the 3 feature/polish commits onto a fresh `upstream/main`). Expect possible conflicts only in the ~3
  hot files (`TerminalController.swift`, `BaseTerminalController.swift`, `TerminalWindow.swift`); the new
  files (`Sidebar/`, `IPC/`, `cli/`) don't conflict. Then `./build-macos.sh`.
- **The `build:` commit** (`786dff263`) is intentionally separate so you can `git rebase --onto` to drop
  it once Zig catches up to the SDK.
- **Security posture** (from the audit): no network egress, no shell-out, no telemetry; the only caveat
  is the unauthenticated local IPC socket (UI-spoofing only, same-uid). Fine for a single-user Mac.

## 6. Known follow-ups (not done — low priority)

- `controllerForSurfaceId` only resolves the *focused* surface, so IPC `tab_id` targeting can't address a
  background split within a tab (behavioral, not a bug).
- The "View" menu lookup for the Tab Color submenu is English-only (pre-existing; silently no-ops under
  other locales).
