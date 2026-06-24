---
name: swiftui-components
description: Build custom SwiftUI components for macOS — custom views, view modifiers, the Layout protocol, state/data flow, style protocols, AppKit bridging (NSViewRepresentable/NSHostingView), and the Liquid Glass material. Use this whenever the work touches SwiftUI: writing or reviewing a `View`/`ViewModifier`, designing a reusable control, wiring `@State`/`@Binding`/`@Observable`/`@Environment`/`PreferenceKey`, implementing a custom `Layout`, theming a control with a style protocol, adopting Liquid Glass (`.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`), or embedding AppKit (`NSView`/`NSViewController`) inside SwiftUI or hosting SwiftUI inside an AppKit app. Reach for it even when the user just says "SwiftUI view", "modifier", "binding", "layout", "glass effect", or names a SwiftUI type.
---

# SwiftUI Components (macOS)

Knowledge for building **custom, reusable SwiftUI components** on Apple platforms, with a macOS/AppKit bias (intended for an app whose core surface is AppKit and whose chrome/settings are SwiftUI — e.g. a terminal app).

This skill bundles curated reference for the topics you actually compose with, plus a full index of every macOS-available SwiftUI symbol for the long tail. Lead with the mental model below; open a reference file when you need the exact API.

## Mental model — what's different about SwiftUI

Internalize these or the code fights you:

- **Views are values, not objects.** A `View` is a lightweight struct describing UI; SwiftUI creates and discards them constantly. Never put mutable component state in stored `var`s on the struct — it won't survive a re-render. Put it behind a property wrapper (`@State`, `@StateObject`, `@Observable`).
- **`body` is a pure function of state.** SwiftUI recomputes `body` whenever a dependency changes and diffs the result. Keep `body` cheap and side-effect-free; do work in `.task`/`.onChange`/actions, not in `body`.
- **Identity drives lifetime and animation.** Structural identity (position in the view tree) and explicit `.id(_:)` decide whether SwiftUI reuses or recreates state. Reusing a view preserves its `@State`; a new identity resets it. Most "my state randomly resets / animation jumps" bugs are identity bugs.
- **Compose, don't configure.** Prefer small views combined with `@ViewBuilder` over one view with many Boolean flags. This is the core idiom — see `references/custom-views-modifiers.md`.

## Choosing the right tool

| You want to… | Reach for | Reference |
|---|---|---|
| Package reusable UI | a custom `View` + `@ViewBuilder` | custom-views-modifiers.md |
| Package reusable *behavior/styling* applied to any view | a `ViewModifier` + a `View` extension | custom-views-modifiers.md |
| Make a control themeable (light/dark/brand variants) | a **style protocol** (`makeBody` + `Configuration`) | styling-protocols.md |
| Arrange children with custom geometry | the `Layout` protocol (not nested stacks + `GeometryReader`) | custom-layout.md |
| Move data through the tree | the right property wrapper (see Data flow) | state-and-data-flow.md |
| Put an `NSView`/`NSViewController` in SwiftUI, or SwiftUI in AppKit | `NSViewRepresentable` / `NSHostingView` | appkit-bridging.md |
| Adopt the Liquid Glass material on custom views/controls | `.glassEffect(_:in:)`, `GlassEffectContainer`, `.buttonStyle(.glass)` | liquid-glass.md |

## Data flow — pick by ownership, not habit

This is the single most common source of bugs. Choose by *who owns the truth*:

- **`@State`** — this view owns a small, private, value-typed piece of truth. Pair with `@Binding` to lend write access to a child.
- **`@Binding`** — a child borrows read/write access to state owned by an ancestor. A custom control almost always exposes its value as a `@Binding`.
- **`@Observable` (Observation framework) + plain `let`/`@State`** — reference-type model objects. `@Observable` (macro) replaces the old `ObservableObject`/`@Published`; SwiftUI tracks exactly the properties a view reads, so it's both simpler and more efficient. Use `@State` to *own* an `@Observable` model, `@Bindable` to get bindings into it. (`@Observable` lives in the `Observation` module, not SwiftUI — `import Observation`.)
- **`@Environment` / `EnvironmentKey`** — inject cross-cutting dependencies (theme, services) without threading them through every initializer. Define an `EnvironmentKey`, extend `EnvironmentValues`, set with `.environment(...)`. This is the idiomatic way to make a component configurable from above.
- **`PreferenceKey` + `.onPreferenceChange`** — pass data *up* the tree (child → ancestor), e.g. a child reporting its measured size. The mirror image of `@Environment`.
- **`@FocusState`** — manage keyboard focus for custom controls.

Legacy: `@ObservedObject`/`@StateObject`/`@EnvironmentObject` are the pre-`@Observable` equivalents — recognize them in existing code, prefer `@Observable` in new code. All are in `references/state-and-data-flow.md`.

## Patterns you'll reuse

**Custom modifier + ergonomic extension** (so callers write `.card()`, not `.modifier(Card())`):
```swift
struct Card: ViewModifier {
    func body(content: Content) -> some View {
        content.padding().background(.quaternary, in: .rect(cornerRadius: 8))
    }
}
extension View { func card() -> some View { modifier(Card()) } }
```

**Custom style via a style protocol** (themeable control):
```swift
struct LinkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? .secondary : .tint)
    }
}
// usage: .buttonStyle(LinkButton())
```

**Custom layout** (when stacks can't express it):
```swift
struct Flow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { /* … */ }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) { /* … */ }
}
```

**Configurable component via the environment:**
```swift
struct ThemeKey: EnvironmentKey { static let defaultValue = Theme.default }
extension EnvironmentValues { var theme: Theme {
    get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue } } }
// component reads: @Environment(\.theme) private var theme
```

## Liquid Glass (macOS 26+)

Liquid Glass is the current system material. Standard SwiftUI controls adopt it automatically; for **custom** components you opt in explicitly:

- `.glassEffect(_ glass: Glass = .regular, in shape: some Shape = …)` applies the material to any view.
- Wrap multiple glass views in a `GlassEffectContainer` so the system can blend and morph their shapes together (better rendering and transitions) instead of treating each in isolation.
- `.glassEffectID(_:in:)` + a `Namespace` drives morph transitions between glass shapes; `.glassEffectUnion(id:namespace:)` merges shapes.
- Buttons: `.buttonStyle(.glass)` / `.glassProminent`.

Don't hand-roll blur/vibrancy for this — use the material so it stays consistent with the platform. Full APIs and examples in `references/liquid-glass.md`.

## Pitfalls

- **Mutable stored properties on a `View`** — silently lost on re-render. Use a wrapper.
- **`@StateObject` vs `@ObservedObject`** — own a reference model with `@StateObject` (created once); use `@ObservedObject` only when an owner passes it in. Mixing these up causes models to be recreated or to leak.
- **Heavy work in `body`** — runs on every dependency change. Move it out.
- **`GeometryReader` for layout you could express with `Layout`** — `GeometryReader` greedily fills space and often breaks sizing; prefer the `Layout` protocol or `ViewThatFits` for real layout logic.
- **Fighting identity** — if state resets or animations jump, audit `.id(_:)`, `ForEach` ids, and whether you're conditionally swapping view types.

## macOS / AppKit bridging (the Ghostty case)

When the real surface is AppKit (custom `NSView`, Metal rendering, `NSEvent` key handling) and SwiftUI is the chrome:

- **`NSViewRepresentable` / `NSViewControllerRepresentable`** — wrap an `NSView`/`NSViewController` as a SwiftUI `View`. Implement `makeNSView`, `updateNSView`, and use a `Coordinator` for delegate/target-action callbacks back into SwiftUI state. `updateNSView` runs on every SwiftUI update — make it idempotent and cheap.
- **`NSHostingController` / `NSHostingView`** — the reverse: host SwiftUI inside an AppKit window/view hierarchy. Watch sizing — see `NSHostingSizingOptions`.
- Keep the AppKit ↔ SwiftUI boundary thin and one-directional where possible: SwiftUI state in, callbacks out via the Coordinator. Details and signatures in `references/appkit-bridging.md`.

## Reference files

Open the one that matches the task (each has a table of contents):

- **references/custom-views-modifiers.md** — `View`, `@ViewBuilder`, `ViewModifier`, composition primitives.
- **references/custom-layout.md** — `Layout`, size negotiation, alignment guides, geometry.
- **references/state-and-data-flow.md** — every property wrapper + `PreferenceKey`/`EnvironmentKey`.
- **references/styling-protocols.md** — the `makeBody`+`Configuration` style pattern across controls.
- **references/appkit-bridging.md** — `NSViewRepresentable`, `NSHostingView`, coordinators.
- **references/liquid-glass.md** — `.glassEffect`, `GlassEffectContainer`, glass button styles (macOS 26+).
- **references/api-index.md** — every macOS-available SwiftUI symbol → doc URL, for anything not bundled above (includes all view/control types like `Button`, `List`, `Table`, `NavigationStack`, …).

## Looking up the long tail

For any symbol not in the bundled references, find it in `references/api-index.md`, then fetch its content live. **Important:** the human doc page (`developer.apple.com/documentation/swiftui/<symbol>`) is a JavaScript app and returns *empty* when fetched — fetch the **DocC JSON** endpoint instead:

```
https://developer.apple.com/tutorials/data/documentation/swiftui/<symbol>.json
```

Members extend the parent slug, e.g. `.../swiftui/view/padding(_:).json` or `.../swiftui/view/glasseffect(_:in:).json`. All slugs are lowercase. This is the reliable way to pull current, authoritative API detail when network is available.
