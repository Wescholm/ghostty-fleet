# Liquid Glass (macOS 26+)

Apple's Liquid Glass material: apply it to custom views, contain/morph multiple glass shapes, and use the glass button styles. Standard SwiftUI controls already use it; these APIs let custom components adopt it.

> Fetch tip: the human doc pages are a JS app (empty when fetched). For live detail, fetch the **DocC JSON** endpoint (`.../tutorials/data/documentation/swiftui/<symbol>.json`), not the HTML.

## Contents

- [Applying Liquid Glass to custom views](#applying-liquid-glass-to-custom-views)
- [glassEffect(_:in:)](#glasseffect(_:in:))
- [glassEffectID(_:in:)](#glasseffectid(_:in:))
- [glassEffectTransition(_:)](#glasseffecttransition(_:))
- [glassEffectUnion(id:namespace:)](#glasseffectunion(id:namespace:))
- [GlassEffectContainer](#glasseffectcontainer)
- [Glass](#glass)
- [DefaultGlassEffectShape](#defaultglasseffectshape)
- [GlassEffectTransition](#glasseffecttransition)
- [GlassButtonStyle](#glassbuttonstyle)
- [GlassProminentButtonStyle](#glassprominentbuttonstyle)
- [glass](#glass)
- [glassProminent](#glassprominent)

---

## Applying Liquid Glass to custom views

[Apple docs](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/applying-liquid-glass-to-custom-views.json)

_Article_

Configure, combine, and morph views using Liquid Glass effects.


## Overview

Interfaces across Apple platforms feature a new dynamic material called Liquid Glass, which combines the optical properties of glass with a sense of fluidity. Liquid Glass is a material that blurs content behind it, reflects color and light of surrounding content, and reacts to touch and pointer interactions in real time. Standard components in SwiftUI use Liquid Glass. Adopt Liquid Glass on custom components to move, combine, and morph them into one another with unique animations and transitions.

To learn about Liquid Glass and more, see Landmarks: Building an app with Liquid Glass.


## Apply and configure Liquid Glass effects

Use the glassEffect(_:in:) modifier to add Liquid Glass effects to a view. By default, the modifier uses the regular variant of Glass and applies the given effect within a Capsule shape behind the view’s content.

Configure the effect to customize your components in a variety of ways:

- Use different shapes to have a consistent look and feel across custom components in your app. For example, use a rounded rectangle if you’re applying the effect to larger components that would look odd as a Capsule or Circle.

- Assign a tint color to suggest prominence.

- Add interactive(_:) to custom components to make them react to touch and pointer interactions. This applies the same responsive and fluid reactions that glass provides to standard buttons.

In the examples below, observe how to apply Liquid Glass effects to a view, use an alternate shape with a specific corner radius, and create a tinted view that responds to interactivity:

```swift
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()

Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect(in: .rect(cornerRadius: 16.0))

Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect(.regular.tint(.orange).interactive())
```


## Combine multiple views with Liquid Glass containers

Use GlassEffectContainer when applying Liquid Glass effects on multiple views to achieve the best rendering performance. A container also allows views with Liquid Glass effects to blend their shapes together and to morph in and out of each other during transitions. Inside a container, each view with the glassEffect(_:in:) modifier renders with the effects behind it.

Customize the spacing on the container to control how the Liquid Glass effects behind views interact with one another. The larger the spacing value on the container, the sooner the Liquid Glass effects behind views blend together and merge the shapes during a transition. A spacing value on the container that’s larger than the spacing of an interior HStack, VStack, or other layout container causes Liquid Glass effects to blend together at rest because the views are too close to each other. Animating views in or out causes the shapes to morph apart or together as the space in the container changes.

The glassEffect(_:in:) modifier captures the content to send to the container to render. Apply the glassEffect(_:in:) modifier after other modifiers that affect the appearance of the view.

In the example below, two images are placed close to each other and the Liquid Glass effects begin to blend their shapes together. This creates a fluid animation as components move around each other within a container:

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "scribble.variable")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()

        Image(systemName: "eraser.fill")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()

            // An `offset` shows how Liquid Glass effects react to each other in a container.
            // Use animations and components appearing and disappearing to obtain effects that look purposeful.
            .offset(x: -40.0, y: 0.0)
    }
}
```

In some cases, you want the geometries of multiple views to contribute to a single Liquid Glass effect capsule, even when your content is at rest. Use the glassEffectUnion(id:namespace:) modifier to specify that a view contributes to a unified effect with a particular ID. This combines all effects with a similar shape, Liquid Glass effect, and ID into a single shape with the applied Liquid Glass material. This is especially useful when creating views dynamically, or with views that live outside of a layout container, like an HStack or VStack.

```swift
let symbolSet: [String] = ["cloud.bolt.rain.fill", "sun.rain.fill", "moon.stars.fill", "moon.fill"]

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(symbolSet.indices, id: \.self) { item in
            Image(systemName: symbolSet[item])
                .frame(width: 80.0, height: 80.0)
                .font(.system(size: 36))
                .glassEffect()
                .glassEffectUnion(id: item < 2 ? "1" : "2", namespace: namespace)
        }
    }
}
```


## Morph Liquid Glass effects during transitions

Morphing effects occur during transitions or animations between views with Liquid Glass effects. Coordinate transitions between views with effects in a container by using the glassEffectID(_:in:) modifier. GlassEffectTransition allows you to specify the type of transition to use when you want to add or remove effects within a container. For effects you want to add or remove that are positioned within the container’s assigned spacing, the default transition type is matchedGeometry.

If you prefer to have a simpler transition or to create a custom transition, use the materialize transition and withAnimation(_:_:). Use the materialize transition for effects you want to add or remove that are farther from each other than the container’s assigned spacing. To provide people with a consistent experience, use matchedGeometry and materialize transitions across your apps. The system applies more than opacity changes with the available transition types.

Associate each Liquid Glass effect with a unique identifier within a namespace that the Namespace property wrapper provides. These IDs ensure SwiftUI animates the same shapes correctly when a shape appears or disappears due to view hierarchy changes. SwiftUI uses the spacing provided to the effect container along with the geometry of the shapes themselves to determine when and which appropriate shapes to morph into and out of.

The glassEffectID(_:in:) and glassEffectTransition(_:) modifiers only affect their content during view hierarchy transitions or animations.

In the example below, the eraser image transitions into and out of the pencil image when the isExpanded variable changes. The GlassEffectContainer has a spacing value of 40.0, and the HStack within it has a spacing of 40.0. This morphs the eraser image into the pencil image when the eraser’s nearest edge is less than or equal to the container’s spacing.

```swift
@State private var isExpanded: Bool = false
@Namespace private var namespace

var body: some View {
    GlassEffectContainer(spacing: 40.0) {
        HStack(spacing: 40.0) {
            Image(systemName: "scribble.variable")
                .frame(width: 80.0, height: 80.0)
                .font(.system(size: 36))
                .glassEffect()
                .glassEffectID("pencil", in: namespace)

            if isExpanded {
                Image(systemName: "eraser.fill")
                    .frame(width: 80.0, height: 80.0)
                    .font(.system(size: 36))
                    .glassEffect()
                    .glassEffectID("eraser", in: namespace)
            }
        }
    }

    Button("Toggle") {
        withAnimation {
            isExpanded.toggle()
        }
    }
    .buttonStyle(.glass)
}
```


## Optimize performance when using Liquid Glass effects

Creating too many Liquid Glass effect containers and applying too many effects to views outside of containers can degrade performance. Limit the use of Liquid Glass effects onscreen at the same time. Additionally, optimize how your app spends rendering time as people use it. To learn how to improve the performance of your UI, see Explore UI animation hitches and the render loop and Optimize SwiftUI performance with Instruments.

---

## glassEffect(_:in:)

[Apple docs](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/view/glasseffect(_:in:).json)

_Instance Method_

Availability: macOS 26.0

Applies the Liquid Glass effect to a view.

Declaration:
```swift
nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View
```


## Discussion

When you use this effect, the system:

- Renders a shape anchored behind a view with the Liquid Glass material.

- Applies the foreground effects of Liquid Glass over a view.

For example, to add this effect to a Text:

```swift
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()
```

SwiftUI uses the regular variant by default along with a Capsule shape.

SwiftUI anchors the Liquid Glass to a view’s bounds. For the example above, the material fills the entirety of the Text frame, which includes the padding.

You typically use this modifier with a GlassEffectContainer to combine multiple Liquid Glass shapes into a single shape that can morph into one another.

---

## glassEffectID(_:in:)

[Apple docs](https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/view/glasseffectid(_:in:).json)

_Instance Method_

Availability: macOS 26.0

Associates an identity value to Liquid Glass effects defined within this view.

Declaration:
```swift
nonisolated func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View
```


## Discussion

You use this modifier with the glassEffect(_:in:) view modifier and a GlassEffectContainer view. When used together, SwiftUI uses the identifier to animate shapes to and from each other during transitions.

---

## glassEffectTransition(_:)

[Apple docs](https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/view/glasseffecttransition(_:).json)

_Instance Method_

Availability: macOS 26.0

Associates a glass effect transition with any glass effects defined within this view.

Declaration:
```swift
@MainActor @preconcurrency func glassEffectTransition(_ transition: GlassEffectTransition) -> some View
```


## Discussion

You use this modifier with the glassEffect(_:in:) view modifier and GlassEffectContainer view. When used together, SwiftUI will use the provided transition to apply changes to the glass effect when you add or remove views with these effects from the view hierarchy.

In the example below, the notepad image will transition into and out of the pencil image when the isExpanded variable changes.

```swift
var isExpanded: Bool
@Namespace private var namespace

var body: some View {
    GlassEffectContainer(spacing: 10.0) {
        HStack(spacing: 10.0) {
            Image(systemName: "pencil")
                .frame(width: 20.0, height: 20.0)
                .glassEffect()
                .glassEffectID("pencil", in: namespace)

                if isExpanded {
                    Image(systemName: "note")
                        .frame(width: 20.0, height: 20.0)
                        .glassEffect()
                        .glassEffectID("note", in: namespace)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
        }
    }
}
```

---

## glassEffectUnion(id:namespace:)

[Apple docs](https://developer.apple.com/documentation/swiftui/view/glasseffectunion(id:namespace:)) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/view/glasseffectunion(id:namespace:).json)

_Instance Method_

Availability: macOS 26.0

Associates any Liquid Glass effects defined within this view to a union with the provided identifier.

Declaration:
```swift
@MainActor @preconcurrency func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View
```


## Discussion

You may want the geometries of multiple views to contribute to a single Liquid Glass effect shape. In these cases, you can use a glassEffectUnion(id:namespace:) to specify that a view should contribute to a union of Liquid Glass effects with a particular identifier. All Liquid Glass effects with the same shape and Liquid Glass variant will be combined into a single shape.

---

## GlassEffectContainer

[Apple docs](https://developer.apple.com/documentation/swiftui/glasseffectcontainer) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/glasseffectcontainer.json)

_Structure_

Availability: macOS 26.0

A view that combines multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another.

Declaration:
```swift
@MainActor @preconcurrency struct GlassEffectContainer<Content> where Content : View
```


## Overview

Use a container with the glassEffect(_:in:) modifier. Each view with a Liquid Glass effect contributes a shape rendered with the effect to a set of shapes. SwiftUI renders the effects together, improving rendering performance and allowing the effects to interact with and morph into one another.

Configure how shapes interact with one another by customizing the default spacing value of the container. As shapes near one another, their paths start to blend into one another. The higher the spacing, the sooner blending begins as the shapes approach each other.

Topics:
**Initializers**: init(spacing:content:)

---

## Glass

[Apple docs](https://developer.apple.com/documentation/swiftui/glass) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/glass.json)

_Structure_

Availability: macOS 26.0

A structure that defines the configuration of the Liquid Glass material.

Declaration:
```swift
struct Glass
```


## Overview

You provide instances of a variant of Liquid Glass to the glassEffect(_:in:) view modifier:

```swift
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()
```

You can combine Liquid Glass effects using a GlassEffectContainer, which supports morphing views with this effect into each other based on the geometry of their associated views.

Topics:
**Instance Methods**: interactive(_:), tint(_:)
**Type Properties**: clear, identity, regular

---

## DefaultGlassEffectShape

[Apple docs](https://developer.apple.com/documentation/swiftui/defaultglasseffectshape) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/defaultglasseffectshape.json)

_Structure_

Availability: macOS 26.0

The default shape applied by glass effects, a capsule.

Declaration:
```swift
struct DefaultGlassEffectShape
```


## Overview

You do not use this type directly. Instead, SwiftUI creates this shape on your behalf as the default parameter of the glassEffect(_:in:) modifier.

Topics:
**Initializers**: init()

---

## GlassEffectTransition

[Apple docs](https://developer.apple.com/documentation/swiftui/glasseffecttransition) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/glasseffecttransition.json)

_Structure_

Availability: macOS 26.0

A structure that describes changes to apply when a glass effect is added or removed from the view hierarchy.

Declaration:
```swift
struct GlassEffectTransition
```

Topics:
**Type Properties**: identity, matchedGeometry, materialize

---

## GlassButtonStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/glassbuttonstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/glassbuttonstyle.json)

_Structure_

Availability: macOS 26.0

A button style that applies glass border artwork based on the button’s context.

Declaration:
```swift
nonisolated struct GlassButtonStyle
```


## Overview

You can also use glass to construct this style.

Topics:
**Initializers**: init(), init(_:)
**Instance Methods**: makeBody(configuration:)

---

## GlassProminentButtonStyle

[Apple docs](https://developer.apple.com/documentation/swiftui/glassprominentbuttonstyle) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/glassprominentbuttonstyle.json)

_Structure_

Availability: macOS 26.0

A button style that applies prominent glass border artwork based on the button’s context.

Declaration:
```swift
nonisolated struct GlassProminentButtonStyle
```


## Overview

You can also use glassProminent to construct this style.

Topics:
**Initializers**: init()
**Instance Methods**: makeBody(configuration:)

---

## glass

[Apple docs](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/primitivebuttonstyle/glass.json)

_Type Property_

Availability: macOS 26.0

A button style that applies a Liquid Glass effect based on the button’s context.

Declaration:
```swift
nonisolated static var glass: GlassButtonStyle { get }
```


## Discussion

In tvOS, this button style applies a Liquid Glass effect regardless of whether the button has focus.

To apply this style to a button, or to a view that contains buttons, use the buttonStyle(_:) modifier.

---

## glassProminent

[Apple docs](https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glassprominent) · [DocC JSON](https://developer.apple.com/tutorials/data/documentation/swiftui/primitivebuttonstyle/glassprominent.json)

_Type Property_

Availability: macOS 26.0

A button style that applies a prominent Liquid Glass effect based on the button’s context.

Declaration:
```swift
@MainActor @preconcurrency static var glassProminent: GlassProminentButtonStyle { get }
```


## Discussion

In tvOS, this button style applies a Liquid Glass effect regardless of whether the button has focus. This style is similar to the borderedProminent style.

To apply this style to a button, or to a view that contains buttons, use the buttonStyle(_:) modifier.

---
