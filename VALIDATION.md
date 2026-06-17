# Validation report — `sidebar-enhancements`

Validated 2026-06-17 via the **Xcode MCP bridge** (`xcrun mcpbridge`, Xcode 26.5) against the
live project — real build, real SwiftUI preview rendering, and the Swift REPL. This closes the
gap from the overnight run, where the live UI couldn't be observed headlessly.

## Result: PASS

| Check | Tool | Result |
|---|---|---|
| App builds | `BuildProject` | ✅ built successfully, 0 errors |
| Navigator issues | `XcodeListNavigatorIssues` | ✅ only 2 pre-existing benign warnings (ImGui dSYM in `libghostty-internal-fat.a`); nothing from these changes |
| Sidebar UI — dark | `RenderPreview` | ✅ every indicator state correct (see `docs/validation/sidebar-dark.png`) |
| Sidebar UI — light | `RenderPreview` (Light Appearance) | ✅ theme adapts correctly (see `docs/validation/sidebar-light.png`) |
| Git-porcelain parser | `ExecuteSnippet` (REPL) | ✅ all edge cases correct |

## Visual validation (the key gap, now closed)

A DEBUG-only `#Preview` (committed) renders `SidebarView` with mock tabs in every state. Xcode
rendered it and the snapshots were inspected directly:

| Tab (mock) | Renders | Verifies |
|---|---|---|
| `api-server` | selected highlight · 🟢 working dot · `main ●`(dirty) | selected + working + dirty |
| `Claude: refactor auth flow` | blue strip · 🟠 attention dot · `feature/auth ↑2` | attention beats working · ahead |
| `npm test — watch` | green strip · 🟢 working dot · `fix/flaky-spec ↓1` | working · behind |
| `idle shell` | no dots · `main` | idle |
| `deploy` | `release/v2 ● ↑1 ↓3` · `🌐 :3000` | dirty + ahead/behind + status together |
| `no-git scratch` | branch row omitted | nil branch handled |

Both light and dark appearances render cleanly (theme derives from system colors and adapts).

## Logic validation (git parser edge cases, via Swift REPL)

```
[clean main even]      branch=main       dirty=false ahead=0 behind=0
[ahead2 behind3 dirty] branch=feature/x  dirty=true  ahead=2 behind=3
[detached HEAD]        branch=nil        dirty=false ahead=0 behind=0
[no upstream]          branch=solo       dirty=false ahead=0 behind=0
[clean no upstream]    branch=main       dirty=false ahead=0 behind=0
```
Confirms detached-HEAD → nil branch, ahead/behind extraction, no-upstream → 0/0, and dirty
detection (incl. untracked `?` lines). The ahead/behind *formatting* (`↑2`, `↓1`, `↑1 ↓3`) is
confirmed visually in the renders above.

## A bug this caught (validation working as intended)

The first `BuildProject` failed with `Argument 'selected' must precede argument 'working'` in the
new `#Preview` — a real argument-order mistake of mine, buried under ~18 spurious SourceKit
"cannot find type" live-index diagnostics. The actual compiler cut through the noise; fixed and
rebuilt green. (Lesson: trust the build, not the live SourceKit index, for a freshly-edited
multi-file module.)

## Not done (deliberate, low-risk follow-ups)

- **Committed unit test for the parser.** There's a `GhosttyTests` target (229 tests). A durable
  test would mean extracting the pure parse into an `internal` function + a test file — a small
  refactor of a shipped feature. Validated via REPL instead to avoid changing the feature
  unattended; easy to add on request.
- **Live end-to-end** (real CPU → green dot, real `git` → dirty in a running window) still benefits
  from a real launch; the preview validates rendering, the REPL validates logic, and the earlier
  session validated the live IPC (`tab.focus`, socket).

## How to reproduce

Open `macos/Ghostty.xcodeproj` in Xcode, open `SidebarView.swift`, and use the preview canvas — or
via the bridge: `RenderPreview` on `Ghostty/Sources/Features/Terminal/Sidebar/SidebarView.swift`.
