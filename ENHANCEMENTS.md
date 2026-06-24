# Sidebar enhancements

Built on top of the rebased + polished `sidebar` branch. Five focused improvements that
turn the sidebar into an at-a-glance **dashboard for many parallel Claude Code sessions**.

## Sidebar legend (what the dots/marks mean)

A single **status dot** after the title encodes the session's lifecycle state (color = state):

| Dot | State | Source |
|---|---|---|
| 🟠 orange | **Attention** | bell / desktop notification / `ghosttyctl notify` |
| 🔴 red | **Error** | agent-reported (`ghosttyctl state error`) |
| 🟡 yellow | **Waiting** — blocked on you (e.g. an agent asking) | agent-reported (`ghosttyctl state waiting`) |
| 🟢 green | **Running/working** | agent-reported (`ghosttyctl state running`) *or* the foreground process is using CPU |
| 🔵 blue | **Done** | agent-reported (`ghosttyctl state done`) |
| (none) | **Idle** | shell at the prompt, nothing reported |

Precedence: **attention > error > waiting > running > done > idle** — CPU activity counts as *running* and
outranks a stale *done*/*idle*, but an agent's *error*/*waiting* outranks CPU. The lifecycle state is fed
by `ghosttyctl state …` (built for Claude Code hooks — see `cli/claude-hooks.example.json`), falling back
to the CPU heuristic when nothing reports.

| Mark | Meaning |
|---|---|
| ● small gray dot (after branch) | **Dirty** — uncommitted changes in the working tree |
| `↑2 ↓1` (after branch) | **Ahead/behind** the upstream branch |

## The five changes

1. **Worktree-aware git status** — `feat(sidebar): worktree-aware git status`
   Replaced direct `.git/HEAD` parsing (which returns *no branch* inside a git worktree —
   exactly the per-worktree-session workflow this fork is for) with one off-main
   `git status --porcelain=v2 --branch` per directory. Now shows the branch for worktrees
   and submodules, a dirty dot, and ↑/↓ upstream divergence. Read-only, non-interactive
   (`GIT_OPTIONAL_LOCKS=0`, `GIT_TERMINAL_PROMPT=0`).

2. **Per-session "working" indicator** — `feat(sidebar): per-session "working" indicator`
   Samples each tab's foreground-process CPU via `proc_pidinfo` once a second; a green dot
   means it's actively computing. Across 10 parallel Claude Code sessions you can see which
   are churning vs idle/waiting without clicking through them. A 2.5s grace period keeps the
   dot steady when Claude briefly idles between tool calls.

3. **IPC: focus + full-tree resolution + richer list** — `feat(ipc): tab.focus, …`
   - `ghosttyctl focus [tab_id]` brings a tab to the front — e.g. a Claude Code `Stop` hook
     can pop the session that just finished to the foreground.
   - `tab_id` is now resolved across the whole split tree (not just the focused surface), so
     IPC can target a tab whose matching surface is a background split.
   - `tab.list` / `tab.current` now include `foreground_pid`.

4. **Locale-proof Tab Color menu** — `fix(menu): anchor Tab Color submenu to the outlet`
   No longer finds the "View" menu by its English title (which silently no-opped under other
   system locales); anchors to the wired menu item instead.

5. **Activity hysteresis** — folded into (2): the grace period that prevents green-dot flicker.

6. **Window controls in the hidden titlebar** — `feat(window): keep traffic lights in hidden style`
   With `macos-titlebar-style = hidden` (the clean sidebar-only look) upstream Ghostty also hides the
   close/minimize/zoom buttons. The fork keeps them — floating top-left over the sidebar — and insets
   the sidebar's first card below them (`HiddenTitlebarTerminalWindow` +
   `TerminalController.sidebarTopInset` → `SidebarView.topInset`), so you get the edge-to-edge look
   *and* working window controls.

## ghosttyctl quick reference (new)

```sh
ghosttyctl focus <tab_id>     # bring that tab to the front
ghosttyctl list               # now includes "foreground_pid"
```
Example — a Claude Code hook that surfaces its session on stop:
```sh
# in a Stop hook
ghosttyctl notify "Claude finished"        # orange attention dot + macOS banner
# or jump straight to it:
ghosttyctl focus "$GHOSTTY_TAB_ID"
```

## Build

Same as the base branch: `./build-macos.sh` (or incremental `xcodebuild` if the
`GhosttyKit.xcframework` is already present). No new build requirements.

## Commits

```
fix(menu): anchor Tab Color submenu to the outlet, not the English title
feat(ipc): tab.focus, full-tree surface resolution, foreground_pid in list
feat(sidebar): per-session "working" indicator via CPU activity
feat(sidebar): worktree-aware git status — dirty + ahead/behind
```
(plus an activity-hysteresis follow-up). Each was built green individually.
